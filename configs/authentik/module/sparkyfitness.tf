# Emit the user's Authentik group names as a `groups` claim in the
# id_token and userinfo response. Consumed by SparkyFitness's
# `SPARKY_FITNESS_OIDC_ADMIN_GROUP=admins` logic — anyone in the
# `admins` group is promoted to app admin on first login.
#
# Same expression as the Open WebUI mapping but kept as its own
# resource so lifecycle is per-app (Authentik keys mappings by `name`,
# so duplicate `scope_name = "groups"` is harmless).
resource "authentik_property_mapping_provider_scope" "sparkyfitness_groups" {
  name       = "SparkyFitness: groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in request.user.groups.all()]}"
}

resource "random_id" "sparkyfitness_client_id" {
  byte_length = 20
}

# SparkyFitness is a confidential client. `random_password` keeps the
# secret in Terraform state so it can be surfaced as a sensitive output
# for one-time paste into the SOPS-encrypted app secret.
resource "random_password" "sparkyfitness_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "sparkyfitness" {
  name               = "SparkyFitness"
  client_id          = random_id.sparkyfitness_client_id.hex
  client_secret      = random_password.sparkyfitness_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  # Callback path per Better Auth SSO plugin
  # (SparkyFitnessServer/auth.ts: `basePath: '/api/auth'` +
  # `SSO callback paths are /sso/callback/[providerId]`). `providerId`
  # comes from SPARKY_FITNESS_OIDC_PROVIDER_SLUG in the app env — the
  # trailing `authentik` segment of the URL below must equal
  # `config.oidc.providerSlug` in the app's HelmRelease values, or the
  # authorize step returns "redirect_uri mismatch".
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://fitness.homelab.blacksd.tech/api/auth/sso/callback/authentik"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.sparkyfitness_groups.id,
  ]

  # Match users by verified email; keeps the OIDC subject stable across
  # username changes.
  sub_mode                   = "user_email"
  include_claims_in_id_token = true

  # Authentik 2026.5 defaults grant_types to an empty list on
  # API-created providers regardless of client_type. Without this, the
  # authorize endpoint rejects every request with "Invalid grant_type
  # for provider". Same workaround as the other providers in this
  # module.
  grant_types = [
    "authorization_code",
    "refresh_token",
  ]

  # RS256-sign id_tokens against the stock self-signed cert so the JWKS
  # endpoint publishes a verification key.
  signing_key = data.authentik_certificate_key_pair.default.id
}

# Slug is intentionally one word (not `sparky-fitness`) to match
# upstream's own naming: the product calls itself "SparkyFitness"
# everywhere (env-var prefix SPARKY_FITNESS_*, GHCR chart path
# codewithcj/charts/sparkyfitness). The slug is load-bearing on the
# discovery URL — /application/o/sparkyfitness/.well-known/... — so
# changing it later is a coordinated update across Authentik, the
# HelmRelease patch's issuerUrl, and the redirect URI above.
resource "authentik_application" "sparkyfitness" {
  name              = "SparkyFitness"
  slug              = "sparkyfitness"
  protocol_provider = authentik_provider_oauth2.sparkyfitness.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". Admin promotion within SparkyFitness comes
# from group-claim inspection at the app layer
# (SPARKY_FITNESS_OIDC_ADMIN_GROUP=admins); no separate binding for
# `admins` is needed here because `admins` is a subset of `grownups`
# by household convention.
resource "authentik_policy_binding" "sparkyfitness_grownups" {
  target = authentik_application.sparkyfitness.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output — same shape as the other OIDC
# apps. Consume with:
#   terragrunt output -json sparkyfitness | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>. discovery_url is present because SparkyFitness's
# helm patch takes an issuer URL (not a discovery URL) so the field is
# informational — paste `client_id` / `client_secret` into
# apps/sparkyfitness/overlays/understairs/secrets.sops.yaml.
output "sparkyfitness" {
  description = "Authentik OIDC client for SparkyFitness. Read with `terragrunt output -json sparkyfitness` and paste client_id / client_secret into apps/sparkyfitness/overlays/understairs/secrets.sops.yaml."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.sparkyfitness.client_id
    client_secret = authentik_provider_oauth2.sparkyfitness.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.sparkyfitness.slug,
    )
  }
}

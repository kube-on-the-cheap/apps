# Emit the user's Authentik group names as a `groups` claim in the
# id_token and userinfo response. Consumed by Mealie's
# `OIDC_USER_GROUP=grownups` (access gate) and `OIDC_ADMIN_GROUP=admins`
# (role sync). Same expression as the SparkyFitness / Open WebUI
# mappings but kept as its own resource so lifecycle is per-app
# (Authentik keys mappings by `name`, so duplicate `scope_name = "groups"`
# is harmless).
resource "authentik_property_mapping_provider_scope" "mealie_groups" {
  name       = "Mealie: groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in request.user.groups.all()]}"
}

resource "random_id" "mealie_client_id" {
  byte_length = 20
}

# Mealie is a confidential client. `random_password` keeps the secret
# in Terraform state so it can be surfaced as a sensitive output for
# one-time paste into the SOPS-encrypted app secret.
resource "random_password" "mealie_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "mealie" {
  name               = "Mealie"
  client_id          = random_id.mealie_client_id.hex
  client_secret      = random_password.mealie_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  # Callback path is Mealie's SPA login page, NOT the backend
  # `/api/auth/oauth/callback` endpoint. Verified against
  # `mealie/routes/auth/auth.py` at v3.25.1: Mealie computes
  # `redirect_url = URLPath("/login").make_absolute_url(base)` and
  # passes that to the OIDC library. The Vue SPA at /login reads the
  # authorization code from the URL query string and posts it to
  # /api/auth/oauth/callback client-side.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://recipes.homelab.blacksd.tech/login"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.mealie_groups.id,
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

# Slug is intentionally one word — matches upstream Mealie's own naming
# (product is "Mealie", not "Meal-ie"). The slug is load-bearing on the
# discovery URL: /application/o/mealie/.well-known/... — changing it
# later is a coordinated update across Authentik, the HelmRelease
# patch's OIDC_CONFIGURATION_URL, and the redirect URI above.
resource "authentik_application" "mealie" {
  name              = "Mealie"
  slug              = "mealie"
  protocol_provider = authentik_provider_oauth2.mealie.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". Admin promotion within Mealie comes from
# group-claim inspection at the app layer (OIDC_ADMIN_GROUP=admins);
# Authentik emits the full group list in the `groups` claim regardless
# of policy bindings, so users in `admins` (a subset of `grownups` by
# household convention) get promoted automatically without a separate
# binding.
resource "authentik_policy_binding" "mealie_grownups" {
  target = authentik_application.mealie.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output — same shape as the other OIDC
# apps. Consume with:
#   terragrunt output -json mealie | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>. discovery_url is the value that goes into the
# HelmRelease patch's OIDC_CONFIGURATION_URL env var.
output "mealie" {
  description = "Authentik OIDC client for Mealie. Read with `terragrunt output -json mealie` and paste client_id / client_secret into apps/mealie/overlays/understairs/secrets.sops.yaml. discovery_url is the value for OIDC_CONFIGURATION_URL in helmrelease.patch.yaml."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.mealie.client_id
    client_secret = authentik_provider_oauth2.mealie.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.mealie.slug,
    )
  }
}

resource "random_id" "linkwarden_client_id" {
  byte_length = 20
}

# Linkwarden is a confidential client. `random_password` keeps the
# secret in Terraform state so it can be surfaced as a sensitive output
# for one-time paste into the SOPS-encrypted app secret.
resource "random_password" "linkwarden_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "linkwarden" {
  name               = "Linkwarden"
  client_id          = random_id.linkwarden_client_id.hex
  client_secret      = random_password.linkwarden_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  # NextAuth's generic OIDC provider is hardcoded to the slug `oidc`,
  # so the callback path is /api/auth/callback/oidc (verified against
  # apps/web/pages/api/v1/auth/[...nextauth].ts at Linkwarden v2.16.0).
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://bookmarks.homelab.blacksd.tech/api/auth/callback/oidc"
      redirect_uri_type = "authorization"
    },
  ]

  # Only the three standard scopes — no offline_access (Linkwarden
  # doesn't request it) and no groups (no role-based admin distinction
  # to sync; access is enforced by the policy binding below).
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
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

resource "authentik_application" "linkwarden" {
  name              = "Linkwarden"
  slug              = "linkwarden"
  protocol_provider = authentik_provider_oauth2.linkwarden.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". No separate `admins` binding — Linkwarden
# has no in-app role distinction to sync.
resource "authentik_policy_binding" "linkwarden_grownups" {
  target = authentik_application.linkwarden.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output — same shape as open_webui / reactive_resume.
# Consume with:
#   terragrunt output -json linkwarden | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>.
output "linkwarden" {
  description = "Authentik OIDC client for Linkwarden. Read with `terragrunt output -json linkwarden` and pipe fields into apps/linkwarden/overlays/understairs/secrets.sops.yaml (OIDC_CLIENT_ID, OIDC_CLIENT_SECRET) plus the deployment env (OIDC_WELLKNOWN_URL from discovery_url)."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.linkwarden.client_id
    client_secret = authentik_provider_oauth2.linkwarden.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.linkwarden.slug,
    )
  }
}

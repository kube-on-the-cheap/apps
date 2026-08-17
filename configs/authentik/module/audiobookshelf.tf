resource "random_id" "audiobookshelf_client_id" {
  byte_length = 20
}

# Audiobookshelf is a confidential client. `random_password` keeps
# the secret in Terraform state so it can be surfaced as a sensitive
# output for one-time paste into Audiobookshelf's Settings →
# Authentication UI (there is no env-var or config-file mechanism to
# ship OIDC settings declaratively for this app).
resource "random_password" "audiobookshelf_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "audiobookshelf" {
  name               = "Audiobookshelf"
  client_id          = random_id.audiobookshelf_client_id.hex
  client_secret      = random_password.audiobookshelf_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  # Two redirect URIs required: the web UI uses /auth/openid/callback,
  # the mobile app (iOS/Android) uses /auth/openid/mobile-redirect.
  # Both are strict matches per Audiobookshelf's OIDC guide.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://audiobooks.homelab.blacksd.tech/auth/openid/callback"
      redirect_uri_type = "authorization"
    },
    {
      matching_mode     = "strict"
      url               = "https://audiobooks.homelab.blacksd.tech/auth/openid/mobile-redirect"
      redirect_uri_type = "authorization"
    },
  ]

  # Standard scopes only — Audiobookshelf doesn't sync OIDC groups
  # to its admin role, so no `groups` claim needed. Admin promotion
  # is manual per-user in Settings → Users after first login.
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
  ]

  # Match users by verified email; keeps the OIDC subject stable
  # across username changes.
  sub_mode                   = "user_email"
  include_claims_in_id_token = true

  # Authentik 2026.5 defaults grant_types to an empty list on
  # API-created providers regardless of client_type. Without this,
  # the authorize endpoint rejects every request with "Invalid
  # grant_type for provider". Same workaround as the other providers
  # in this module.
  grant_types = [
    "authorization_code",
    "refresh_token",
  ]

  # RS256-sign id_tokens against the stock self-signed cert so the
  # JWKS endpoint publishes a verification key.
  signing_key = data.authentik_certificate_key_pair.default.id
}

resource "authentik_application" "audiobookshelf" {
  name              = "Audiobookshelf"
  slug              = "audiobookshelf"
  protocol_provider = authentik_provider_oauth2.audiobookshelf.id
}

# Grant the `grownups` Authentik group access. No separate `admins`
# binding — Audiobookshelf has no in-app role sync from OIDC, so the
# admin/user distinction is managed inside the app after first login.
resource "authentik_policy_binding" "audiobookshelf_grownups" {
  target = authentik_application.audiobookshelf.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output — same shape as the other OIDC
# apps. Consume with:
#   terragrunt output -json audiobookshelf | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>. discovery_url is present here (unlike the
# NetBox output) because it's pasted into Audiobookshelf's Settings
# UI — the app auto-populates the endpoint URLs from it.
output "audiobookshelf" {
  description = "Authentik OIDC client for Audiobookshelf. Read with `terragrunt output -json audiobookshelf` and paste client_id, client_secret, discovery_url into Audiobookshelf → Settings → Authentication → OpenID Connect."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.audiobookshelf.client_id
    client_secret = authentik_provider_oauth2.audiobookshelf.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.audiobookshelf.slug,
    )
  }
}

# Authentik 2026.x stopped auto-advertising offline_access in
# scopes_supported. Reactive Resume's OAuth client library requests
# offline_access to obtain a refresh token; without it, the authorize
# endpoint rejects the request. A per-provider mapping is registered so
# the scope shows up in the discovery document.
#
# Kept separate from the identical Vaultwarden/Grimmory mappings so the
# three providers can be modified independently; Authentik keys
# mappings by `name`, not `scope_name`, so the duplicate scope name is
# fine.
resource "authentik_property_mapping_provider_scope" "reactive_resume_offline_access" {
  name       = "Reactive Resume: offline_access"
  scope_name = "offline_access"
  expression = "return {}"
}

resource "random_id" "reactive_resume_client_id" {
  byte_length = 20
}

# Reactive Resume is a confidential client and authenticates to the
# token endpoint with a client_secret. `random_password` keeps the
# value in Terraform state so it can be surfaced as a sensitive output
# for one-time paste into the SOPS-encrypted app secret.
resource "random_password" "reactive_resume_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "reactive_resume" {
  name               = "Reactive Resume"
  client_id          = random_id.reactive_resume_client_id.hex
  client_secret      = random_password.reactive_resume_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://cv.homelab.blacksd.tech/api/auth/oauth2/callback/custom"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.reactive_resume_offline_access.id,
  ]

  # Match users by verified email; keeps the OIDC subject stable across
  # username changes. Same rationale as the Vaultwarden provider.
  sub_mode                   = "user_email"
  include_claims_in_id_token = true

  # Authentik 2026.5 defaults grant_types to an empty list on
  # API-created providers regardless of client_type. Without this, the
  # authorize endpoint rejects every request with "Invalid grant_type
  # for provider". Same workaround as the Vaultwarden/Grimmory
  # providers.
  grant_types = [
    "authorization_code",
    "refresh_token",
  ]

  # RS256-sign id_tokens against the stock self-signed cert so the JWKS
  # endpoint publishes a verification key.
  signing_key = data.authentik_certificate_key_pair.default.id
}

resource "authentik_application" "reactive_resume" {
  name              = "Reactive Resume"
  slug              = "reactive-resume"
  protocol_provider = authentik_provider_oauth2.reactive_resume.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". Explicit request from the user: this
# application is grownups-only.
resource "authentik_policy_binding" "reactive_resume_grownups" {
  target = authentik_application.reactive_resume.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# One consolidated object output per OIDC client. Everything the app
# needs (client_id, client_secret, discovery_url) is namespaced under a
# single output so the reader is `terragrunt output -json reactive_resume
# | jq -r '.<field>'` regardless of which field they want. The whole
# object is marked sensitive because it carries the client_secret;
# Terraform will refuse to print any of the fields without `-json` /
# `-raw <path>`, which matches how the values get consumed (piped into
# `sops --encrypt`, never eyeballed).
output "reactive_resume" {
  description = "Authentik OIDC client for Reactive Resume. Read with `terragrunt output -json reactive_resume` and pipe fields into apps/reactive-resume/overlays/understairs/secrets.sops.yaml (OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET) plus the deployment env (OAUTH_DISCOVERY_URL)."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.reactive_resume.client_id
    client_secret = authentik_provider_oauth2.reactive_resume.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.reactive_resume.slug,
    )
  }
}

# Authentik 2026.x stopped auto-advertising offline_access in
# scopes_supported. Open WebUI's OAuth client library requests
# offline_access to obtain a refresh token; without it, the authorize
# endpoint rejects the request. A per-provider mapping is registered so
# the scope shows up in the discovery document.
#
# Kept separate from the identical Vaultwarden/Grimmory/Reactive Resume
# mappings so each provider can be modified independently; Authentik
# keys mappings by `name`, not `scope_name`, so the duplicate scope
# name is fine.
resource "authentik_property_mapping_provider_scope" "open_webui_offline_access" {
  name       = "Open WebUI: offline_access"
  scope_name = "offline_access"
  expression = "return {}"
}

# Emit the user's Authentik group names as a `groups` claim in the
# id_token and userinfo response. Consumed by Open WebUI's
# `ENABLE_OAUTH_ROLE_MANAGEMENT=true` logic — anyone in the `admins`
# group becomes an OWUI admin, anyone in `grownups` becomes a regular
# OWUI user. Anyone with a populated `groups` claim that matches
# neither list is rejected at the app layer with HTTP 403
# (belt-and-braces on top of the policy binding below).
#
# Same expression as Grimmory's mapping but kept as its own resource
# so lifecycle is per-app (mappings are keyed by `name`, so duplicate
# `scope_name = "groups"` is harmless).
resource "authentik_property_mapping_provider_scope" "open_webui_groups" {
  name       = "Open WebUI: groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in request.user.groups.all()]}"
}

resource "random_id" "open_webui_client_id" {
  byte_length = 20
}

# Open WebUI is a confidential client. `random_password` keeps the
# secret in Terraform state so it can be surfaced as a sensitive output
# for one-time paste into the SOPS-encrypted app secret.
resource "random_password" "open_webui_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "open_webui" {
  name               = "Open WebUI"
  client_id          = random_id.open_webui_client_id.hex
  client_secret      = random_password.open_webui_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://ai.homelab.blacksd.tech/oauth/oidc/login/callback"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.open_webui_offline_access.id,
    authentik_property_mapping_provider_scope.open_webui_groups.id,
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

resource "authentik_application" "open_webui" {
  name              = "Open WebUI"
  slug              = "open-webui"
  protocol_provider = authentik_provider_oauth2.open_webui.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". Admin promotion within Open WebUI comes
# from group-claim inspection at the app layer (OAUTH_ADMIN_ROLES=admins);
# no separate binding for `admins` is needed here because `admins` is a
# subset of `grownups` by household convention.
resource "authentik_policy_binding" "open_webui_grownups" {
  target = authentik_application.open_webui.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output per client — matches the shape
# introduced with reactive_resume. Consume with:
#   terragrunt output -json open_webui | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>.
output "open_webui" {
  description = "Authentik OIDC client for Open WebUI. Read with `terragrunt output -json open_webui` and pipe fields into apps/open-webui/overlays/understairs/secrets.sops.yaml (OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET) plus the deployment env (OPENID_PROVIDER_URL)."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.open_webui.client_id
    client_secret = authentik_provider_oauth2.open_webui.client_secret
    discovery_url = format(
      "%s/application/o/%s/.well-known/openid-configuration",
      trimsuffix(var.authentik_url, "/"),
      authentik_application.open_webui.slug,
    )
  }
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

# Custom scope that flattens the user's Authentik groups into a `groups`
# claim — same shape as the Zitadel module's setGroupsClaim action.
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "Grimmory: groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in request.user.groups.all()]}"
}

# Authentik 2026.x stopped auto-advertising offline_access in
# scopes_supported. The OIDC spec defines offline_access as the standard
# way to request refresh tokens, and Grimmory's client builds it into the
# default authorization request. Without an explicit scope mapping the
# authorize endpoint rejects the entire request as "otherwise malformed".
# The expression is a no-op (returns {}); the side effect is that the
# scope is registered and the discovery doc lists it.
resource "authentik_property_mapping_provider_scope" "offline_access" {
  name       = "Grimmory: offline_access"
  scope_name = "offline_access"
  expression = "return {}"
}

resource "random_id" "grimmory_client_id" {
  byte_length = 20
}

resource "authentik_provider_oauth2" "grimmory" {
  name               = "Grimmory"
  client_id          = random_id.grimmory_client_id.hex
  client_type        = "public"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://library.homelab.blacksd.tech/oauth2-callback"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.groups.id,
    authentik_property_mapping_provider_scope.offline_access.id,
  ]

  sub_mode                   = "user_username"
  include_claims_in_id_token = true
  logout_uri                 = "https://library.homelab.blacksd.tech/api/v1/auth/oidc/backchannel-logout"
  logout_method              = "backchannel"

  # Authentik 2026.5 defaults grant_types to an empty list on API-created
  # providers regardless of client_type. Without this, the authorize
  # endpoint rejects every request with "Invalid grant_type for provider"
  # → "The request is otherwise malformed". The Terraform provider docs
  # don't list this field but the schema accepts it.
  grant_types = [
    "authorization_code",
    "refresh_token",
  ]

  # Without a signing_key, the JWKS endpoint publishes no keys and the
  # provider falls back to HMAC-with-client-secret signing — which can't
  # work for a public PKCE client. Wire the stock self-signed cert so
  # id_tokens are RS256-signed and the JWKS endpoint actually exposes
  # the public key for clients to validate against.
  signing_key = data.authentik_certificate_key_pair.default.id
}

resource "authentik_application" "grimmory" {
  name              = "Grimmory"
  slug              = "grimmory"
  protocol_provider = authentik_provider_oauth2.grimmory.id
}

# Grant the household-wide `family` group access to the Grimmory
# application. Without an explicit policy binding, Authentik defaults
# to denying every user with a "Request has been denied" error page.
#
# `authentik_policy_binding` supports either a `policy`, `user`, or
# `group` target — we use `group` and leave `policy` unset. Semantics:
# "member of this group ⇒ policy passes."
resource "authentik_policy_binding" "grimmory_family" {
  target = authentik_application.grimmory.uuid
  group  = authentik_group.family.id
  order  = 0
}

output "grimmory_client_id" {
  description = "Client ID for the Authentik-side Grimmory OIDC application. Read with `terragrunt output -raw grimmory_client_id`. Not wired into Grimmory yet — the app continues using the Zitadel client until a separate apps-repo PR cuts it over."
  value       = authentik_provider_oauth2.grimmory.client_id
  sensitive   = true
}

output "grimmory_issuer_url" {
  description = "OIDC issuer URL for the Authentik-side Grimmory application. Paste into Grimmory Settings → OIDC alongside `grimmory_client_id`. The discovery document lives at `<issuer>/.well-known/openid-configuration`. Read with `terragrunt output -raw grimmory_issuer_url`."
  value       = format("%s/application/o/%s/", trimsuffix(var.authentik_url, "/"), authentik_application.grimmory.slug)
}

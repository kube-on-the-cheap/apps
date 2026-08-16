# Emit the user's Authentik group names as a `groups` claim in the
# id_token and userinfo response. Consumed by NetBox's custom
# SOCIAL_AUTH_PIPELINE step (`_map_netbox_roles` in the overlay's
# oidc-config.yaml) — anyone in `admins` gets is_staff + is_superuser,
# anyone else in `grownups` is a regular user, and users in neither
# are rejected by the policy binding below.
#
# Same expression as the Open WebUI mapping but kept as its own resource
# so lifecycle is per-app (mappings are keyed by `name`, so duplicate
# `scope_name = "groups"` is harmless).
resource "authentik_property_mapping_provider_scope" "netbox_groups" {
  name       = "NetBox: groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in request.user.groups.all()]}"
}

resource "random_id" "netbox_client_id" {
  byte_length = 20
}

# NetBox is a confidential client. `random_password` keeps the
# secret in Terraform state so it can be surfaced as a sensitive output
# for one-time paste into the SOPS-encrypted app secret.
resource "random_password" "netbox_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "netbox" {
  name               = "NetBox"
  client_id          = random_id.netbox_client_id.hex
  client_secret      = random_password.netbox_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id

  # python-social-auth's default callback route is
  # /oauth/complete/<backend_name>/ with a trailing slash. NetBox uses
  # `oidc` as the backend name because the Django backend module is
  # social_core.backends.open_id_connect.OpenIdConnectAuth, whose
  # name attribute is 'oidc'.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://netbox.homelab.blacksd.tech/oauth/complete/oidc/"
      redirect_uri_type = "authorization"
    },
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.email.id,
    authentik_property_mapping_provider_scope.netbox_groups.id,
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

resource "authentik_application" "netbox" {
  name              = "NetBox"
  slug              = "netbox"
  protocol_provider = authentik_provider_oauth2.netbox.id
}

# Grant the `grownups` Authentik group access. Without an explicit
# policy binding, Authentik defaults to denying every user with
# "Request has been denied". Admin promotion within NetBox comes
# from group-claim inspection in the custom social-auth pipeline
# step; no separate binding for `admins` is needed here because
# `admins` is a subset of `grownups` by household convention.
resource "authentik_policy_binding" "netbox_grownups" {
  target = authentik_application.netbox.uuid
  group  = authentik_group.grownups.id
  order  = 0
}

# Single consolidated object output — same shape as open_webui /
# reactive_resume / linkwarden. Consume with:
#   terragrunt output -json netbox | jq -r '.<field>'
# The whole object is marked sensitive because it carries the
# client_secret; Terraform will refuse to print the fields without
# -json / -raw <path>.
output "netbox" {
  description = "Authentik OIDC client for NetBox. Read with `terragrunt output -json netbox` and pipe fields into apps/netbox/overlays/understairs/secrets.sops.yaml (OIDC_CLIENT_ID, OIDC_CLIENT_SECRET). The issuer URL is hardcoded in the extraConfig ConfigMap (see oidc-config.yaml)."
  sensitive   = true
  value = {
    client_id     = authentik_provider_oauth2.netbox.client_id
    client_secret = authentik_provider_oauth2.netbox.client_secret
  }
}

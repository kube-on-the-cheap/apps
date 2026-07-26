resource "zitadel_application_oidc" "grimmory" {
  project_id = zitadel_project.homelab.id
  org_id     = local.org_id
  name       = "Grimmory"

  redirect_uris             = ["https://library.homelab.blacksd.tech/oauth2-callback"]
  post_logout_redirect_uris = ["https://library.homelab.blacksd.tech/"]
  response_types            = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types = [
    "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
    "OIDC_GRANT_TYPE_REFRESH_TOKEN",
  ]
  app_type                    = "OIDC_APP_TYPE_WEB"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_NONE"
  version                     = "OIDC_VERSION_1_0"
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = false
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  dev_mode                    = false
  clock_skew                  = "0s"
}

output "grimmory_client_id" {
  description = "Client ID for the Grimmory OIDC application. Paste into Grimmory Settings → OIDC. Marked sensitive because the Zitadel provider schema flags `client_id` as sensitive; read with `terragrunt output -raw grimmory_client_id`."
  value       = zitadel_application_oidc.grimmory.client_id
  sensitive   = true
}

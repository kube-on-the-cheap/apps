resource "zitadel_idp_google" "google" {
  name                = "Google"
  client_id           = var.google_client_id
  client_secret       = var.google_client_secret
  scopes              = ["openid", "profile", "email"]
  is_linking_allowed  = true
  is_creation_allowed = false
  is_auto_creation    = false
  is_auto_update      = true
  auto_linking        = "AUTO_LINKING_OPTION_EMAIL"
}

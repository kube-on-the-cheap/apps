resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  provider_type       = "google"
  consumer_key        = var.google_client_id
  consumer_secret     = var.google_client_secret
  authentication_flow = data.authentik_flow.source_authentication.id
  enrollment_flow     = data.authentik_flow.source_enrollment.id
  user_matching_mode  = "email_link"

  # Authentik auto-fills these for provider_type = "google" on first apply.
  # Declaring them explicitly stops every subsequent plan from showing them
  # as drift back to null.
  authorization_url = "https://accounts.google.com/o/oauth2/v2/auth"
  access_token_url  = "https://oauth2.googleapis.com/token"
  profile_url       = "https://openidconnect.googleapis.com/v1/userinfo"
  oidc_jwks_url     = "https://www.googleapis.com/oauth2/v3/certs"

  # Without this, the source exists but the identification stage doesn't render
  # the per-source button. This is Authentik's equivalent of wiring
  # zitadel_default_login_policy.idps in the Zitadel module.
  promoted = true
}

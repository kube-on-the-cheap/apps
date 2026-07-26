resource "zitadel_default_login_policy" "default" {
  # Values captured from the live instance default via terragrunt import.
  # Changing any of these alters login behavior for every org on this instance.
  user_login                    = true
  allow_register                = false
  allow_external_idp            = true
  force_mfa                     = false
  force_mfa_local_only          = false
  passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED"
  hide_password_reset           = false
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "12h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "18h0m0s"
  ignore_unknown_usernames      = false
  default_redirect_uri          = ""

  # Other imported optional fields.
  allow_domain_discovery   = true
  disable_login_with_email = false
  disable_login_with_phone = false
  second_factors = [
    "SECOND_FACTOR_TYPE_OTP",
    "SECOND_FACTOR_TYPE_U2F",
  ]
  multi_factors = [
    "MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION",
  ]

  # IdP wiring — the reason this resource exists in Terraform.
  idps = [zitadel_idp_google.google.id]
}

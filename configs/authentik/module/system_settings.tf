# Global system settings for Authentik.
#
# The most operationally-relevant setting here is `default_token_duration`,
# which caps the lifetime of API tokens / app passwords created via the
# self-service "App password" or "Token" flow in the user profile UI.
#
# Ships defaulted to `minutes=30`, which is fine for interactive
# short-lived tokens but painful for anything long-running (Terraform
# runs, cron-driven scripts, CI). We bump it to a week — long enough
# to survive typical operational cadences, short enough that a leaked
# token isn't a permanent risk.
#
# The per-user override attribute `goauthentik.io/user/token-maximum-lifetime`
# (see akadmin.tf and users.tf for wiring) can extend this further on
# a per-user basis — the human/service account that owns the Terraform
# token gets a year, everyone else stays at the global default.
#
# Duration values are Python timedelta kwargs strings, e.g.:
#   minutes=30, hours=1, days=7, weeks=1, weeks=52
resource "authentik_system_settings" "default" {
  default_token_duration = "weeks=1"
}

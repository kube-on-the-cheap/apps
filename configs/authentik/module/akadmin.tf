# Break-glass posture for the pre-created `akadmin` user.
#
# Authentik ships with a built-in `akadmin` user in the `authentik Admins`
# group. Left at defaults, that user has the same email as the human
# admin (marco.bulgarini@gmail.com), which:
#
#   1. Creates a conflict on downstream apps that provision users on
#      first OIDC login and enforce a UNIQUE constraint on email. Grimmory
#      hit this exactly: signing in as `akadmin` triggered a duplicate-
#      email row insert against its `users` table because `marco` was
#      already there.
#
#   2. Encourages using `akadmin` as a day-to-day identity, which
#      conflates admin power with the human identity used across apps.
#      The recommended posture is that `akadmin` is break-glass only —
#      strong password, no email, used only when superuser access
#      through the normal identity (marco) is unavailable.
#
# This resource pins the *identity* posture declaratively (username,
# email cleared, still a superuser via `authentik Admins`).
#
# ---
#
# WHY PASSWORD MANAGEMENT IS NOT HERE
#
# The `authentik_user` resource in terraform-provider-authentik does NOT
# support password updates on existing users. The provider source
# (pkg/provider/resource_user.go: resourceUserSetPassword) explicitly
# guards the write with:
#
#     if !d.IsNewResource() {
#         return nil
#     }
#
# So the password only ships on resource CREATE. On UPDATE (which is
# our case — akadmin exists in Authentik and we import it into state),
# the provider silently no-ops. Terraform records the intent in state,
# but Authentik never sees it. The account continues to accept only
# the pre-existing password.
#
# WORKAROUND: rotate the password manually.
#
#   1. Log in as a different superuser (marco, if you've promoted the
#      `admins` group; otherwise use the current akadmin password).
#   2. Open Directory → Users → akadmin → three-dot menu → Set password.
#   3. Paste a strong value from your password manager.
#   4. Store the new value in Vaultwarden under "Authentik akadmin
#      (break-glass)".
#
# The `lifecycle.ignore_changes = [password]` block below suppresses
# drift alerts if a future provider version starts reading the password
# hash into state (unlikely — passwords aren't reversible — but cheap
# defense).

# Data lookup for the pre-existing built-in Admins group. Not managed by
# our Terraform (it's created by Authentik at install time), but we need
# its ID to keep akadmin in it so it retains superuser rights.
data "authentik_group" "builtin_admins" {
  name = "authentik Admins"
}

# Import the pre-existing akadmin user (pk=6) into state. The pk was
# discovered via `GET /api/v3/core/users/?search=akadmin` at the time
# this file was written; if the value ever drifts, run:
#
#   curl -H "Authorization: Bearer $TOKEN" \
#     https://login.cloud.blacksd.tech/api/v3/core/users/?search=akadmin \
#     | jq '.results[0].pk'
#
# and update the id below. The import block is idempotent — leaving it
# in place after the first successful apply is safe.
import {
  to = authentik_user.akadmin
  id = "6"
}

resource "authentik_user" "akadmin" {
  username = "akadmin"
  name     = "authentik Default Admin"
  # Email intentionally blank: prevents email collisions on downstream
  # apps that provision users on first OIDC sign-in. akadmin should
  # never be used as a human identity, so it doesn't need an email.
  # Uses "" (not null) — the provider treats null as "unmanaged/don't
  # touch", which leaves whatever email is already there. Explicit ""
  # forces a PATCH that clears the field.
  email  = ""
  type   = "internal"
  groups = [data.authentik_group.builtin_admins.id]

  # akadmin owns the API token that Terraform uses to talk to Authentik.
  # The global `default_token_duration` (set in system_settings.tf) caps
  # token lifetime at weeks=1 for regular users — too short for the
  # Terraform-owning identity, which we want to regenerate at most once
  # a year. This per-user override lifts akadmin's cap to weeks=52.
  #
  # Format is Python timedelta kwargs (weeks, days, hours, minutes).
  # See https://docs.goauthentik.io/users-sources/user/user_ref/ for
  # the full attribute reference.
  attributes = jsonencode({
    "goauthentik.io/user/token-maximum-lifetime" = "weeks=52"
  })

  lifecycle {
    # See the header comment: passwords are managed manually via the
    # Authentik UI because the terraform provider silently drops
    # password updates on existing users.
    ignore_changes = [password]
  }
}

# `nonsensitive(var.users)` is required because Terraform rejects sensitive
# values in for_each arguments — usernames (the keys) end up in resource
# addresses, which Terraform considers structurally non-secret. The values
# (names, emails) remain treated as sensitive through `each.value.*`.
resource "random_password" "user_initial" {
  for_each = nonsensitive(var.users)

  length           = 32
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}<>?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "zitadel_human_user" "users" {
  for_each = nonsensitive(var.users)

  org_id     = local.org_id
  user_name  = each.key
  first_name = each.value.first_name
  last_name  = each.value.last_name
  email      = each.value.email

  display_name       = coalesce(each.value.display_name, format("%s %s", each.value.first_name, each.value.last_name))
  nick_name          = each.value.nick_name
  preferred_language = each.value.preferred_language

  initial_password             = random_password.user_initial[each.key].result
  initial_skip_password_change = true
  is_email_verified            = true

  lifecycle {
    ignore_changes = [initial_password]
  }
}

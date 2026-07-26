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

locals {
  user_group_ids = nonsensitive({
    for username in keys(var.users) :
    username => compact([
      contains(var.family, username) ? authentik_group.family.id : null,
      contains(var.admins, username) ? authentik_group.admins.id : null,
      contains(var.grownups, username) ? authentik_group.grownups.id : null,
      contains(var.kids, username) ? authentik_group.kids.id : null,
    ])
  })
}

resource "authentik_user" "users" {
  for_each = nonsensitive(var.users)

  username = each.key
  name     = coalesce(each.value.display_name, format("%s %s", each.value.first_name, each.value.last_name))
  email    = each.value.email
  type     = "internal"
  groups   = local.user_group_ids[each.key]
  password = random_password.user_initial[each.key].result

  lifecycle {
    ignore_changes = [password]
  }
}

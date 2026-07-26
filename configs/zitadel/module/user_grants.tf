locals {
  # Zitadel enforces one user_grant per (user, project) with multiple role_keys
  # inside it — not one grant per (user, role). For each user in var.users, we
  # aggregate every role they appear in across the four group lists.
  homelab_user_role_keys = nonsensitive({
    for username in keys(var.users) :
    username => compact([
      contains(var.users_group, username) ? zitadel_project_role.users.role_key : null,
      contains(var.admins, username) ? zitadel_project_role.admins.role_key : null,
      contains(var.grownups, username) ? zitadel_project_role.grownups.role_key : null,
      contains(var.kids, username) ? zitadel_project_role.kids.role_key : null,
    ])
    if length(compact([
      contains(var.users_group, username) ? "u" : null,
      contains(var.admins, username) ? "a" : null,
      contains(var.grownups, username) ? "g" : null,
      contains(var.kids, username) ? "k" : null,
    ])) > 0
  })
}

resource "zitadel_user_grant" "homelab" {
  for_each = local.homelab_user_role_keys

  org_id     = local.org_id
  project_id = zitadel_project.homelab.id
  user_id    = zitadel_human_user.users[each.key].id
  role_keys  = each.value
}

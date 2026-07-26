# Family = grownups ∪ kids. The catch-all "everyone in the household"
# group used for shared-family apps (library, media, etc.). Named
# `family` (was `users` originally) to match the age-partitioned
# `grownups`/`kids` naming; the previous `users` name was too generic
# and easy to confuse with Authentik's own user objects.
resource "authentik_group" "family" {
  name = "family"
}

# Rename tracking: the group was called `users` in the initial version
# of this module. Terraform sees the change from resource address
# `authentik_group.users` to `authentik_group.family` as a
# destroy-and-recreate by default (which would wipe all memberships,
# then re-add). The `moved` block below tells Terraform to treat this
# as an in-place rename — the underlying Authentik group UUID stays
# the same, so memberships are preserved. Safe to delete this block
# after the first successful apply that processes it.
moved {
  from = authentik_group.users
  to   = authentik_group.family
}

resource "authentik_group" "admins" {
  name         = "admins"
  is_superuser = true
}

resource "authentik_group" "grownups" {
  name = "grownups"
}

resource "authentik_group" "kids" {
  name = "kids"
}

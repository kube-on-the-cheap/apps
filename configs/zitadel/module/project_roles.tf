resource "zitadel_project_role" "users" {
  org_id       = local.org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "users"
  display_name = "Users"
  group        = "homelab"
}

resource "zitadel_project_role" "admins" {
  org_id       = local.org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "admins"
  display_name = "Admins"
  group        = "homelab"
}

resource "zitadel_project_role" "grownups" {
  org_id       = local.org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "grownups"
  display_name = "Grownups"
  group        = "homelab"
}

resource "zitadel_project_role" "kids" {
  org_id       = local.org_id
  project_id   = zitadel_project.homelab.id
  role_key     = "kids"
  display_name = "Kids"
  group        = "homelab"
}

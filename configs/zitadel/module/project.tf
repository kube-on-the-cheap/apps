resource "zitadel_project" "homelab" {
  name                   = "Homelab"
  org_id                 = local.org_id
  project_role_assertion = true
  project_role_check     = false
  has_project_check      = false
}

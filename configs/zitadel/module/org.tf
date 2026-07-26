data "zitadel_orgs" "default" {
}

locals {
  org_id = one(data.zitadel_orgs.default.ids)
}

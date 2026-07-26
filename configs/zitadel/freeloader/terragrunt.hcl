terraform {
  source = "../module"
}

include "general" {
  path = find_in_parent_folders("general.include.hcl")
}

remote_state {
  backend = "gcs"
  config = {
    bucket   = "kube-on-the-cheap-3st1qzzy"
    prefix   = "blacksd/zitadel/terraform.tfstate"
    project  = "kube-on-the-cheap"
    location = "europe-west3"
  }
}

locals {
  google_oauth = yamldecode(sops_decrypt_file("./google-oauth.sops.yaml"))
  users_data   = yamldecode(sops_decrypt_file("./users.sops.yaml"))
}

inputs = {
  zitadel_domain           = "auth.cloud.blacksd.tech"
  zitadel_jwt_profile_json = sops_decrypt_file("./zitadel-key.sops.json")
  google_client_id         = local.google_oauth.client_id
  google_client_secret     = local.google_oauth.client_secret
  users                    = local.users_data.users
  users_group              = try(local.users_data.groups.users, [])
  admins                   = try(local.users_data.groups.admins, [])
  grownups                 = try(local.users_data.groups.grownups, [])
  kids                     = try(local.users_data.groups.kids, [])
}

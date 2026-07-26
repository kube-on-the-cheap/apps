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
    prefix   = "blacksd/authentik/terraform.tfstate"
    project  = "kube-on-the-cheap"
    location = "europe-west3"
  }
}

locals {
  google_oauth    = yamldecode(sops_decrypt_file("./google-oauth.sops.yaml"))
  users_data      = yamldecode(sops_decrypt_file("./users.sops.yaml"))
  authentik_token = yamldecode(sops_decrypt_file("./authentik-token.sops.yaml")).token
}

inputs = {
  authentik_url        = "https://login.cloud.blacksd.tech"
  authentik_token      = local.authentik_token
  google_client_id     = local.google_oauth.client_id
  google_client_secret = local.google_oauth.client_secret
  users                = local.users_data.users
  family               = try(local.users_data.groups.family, [])
  admins               = try(local.users_data.groups.admins, [])
  grownups             = try(local.users_data.groups.grownups, [])
  kids                 = try(local.users_data.groups.kids, [])
}

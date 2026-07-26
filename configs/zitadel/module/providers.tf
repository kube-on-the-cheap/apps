terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  backend "gcs" {}
}

provider "zitadel" {
  domain           = var.zitadel_domain
  jwt_profile_json = var.zitadel_jwt_profile_json
}

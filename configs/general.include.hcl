locals {
  project_details = {
    name       = "Kube, on the cheap"
    short_form = "kube-on-the-cheap"
  }
  gcp = {
    region     = "europe-west3"
    project_id = local.project_details.short_form
  }
  state_bucket = "kube-on-the-cheap-3st1qzzy"
  domain_name  = "blacksd.tech"
}

inputs = {
  domain_name       = local.domain_name
  cloud_domain_name = "cloud.${local.domain_name}"
}

terraform_version_constraint  = "~> 1.10.0"
terragrunt_version_constraint = "~> 0.71.0"

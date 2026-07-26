variable "zitadel_domain" {
  description = "Hostname of the self-hosted Zitadel instance."
  type        = string
  default     = "auth.cloud.blacksd.tech"
}

variable "zitadel_jwt_profile_json" {
  description = "Service-account JSON key (whole document, inline) for the Terraform machine user. Provided by Terragrunt via SOPS decrypt of zitadel-key.sops.json."
  type        = string
  sensitive   = true
}

variable "google_client_id" {
  description = "Client ID of the Google OAuth web-application client used for the Google IdP. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Client secret of the Google OAuth web-application client used for the Google IdP. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml."
  type        = string
  sensitive   = true
}

variable "users" {
  description = "Map of Zitadel human users keyed by username. Provided by Terragrunt via SOPS decrypt of users.sops.yaml."
  sensitive   = true
  type = map(object({
    first_name         = string
    last_name          = string
    email              = string
    display_name       = optional(string)
    nick_name          = optional(string)
    preferred_language = optional(string)
  }))
}

variable "users_group" {
  description = "Usernames who get the 'users' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.users`)."
  sensitive   = true
  type        = list(string)
  default     = []
}

variable "admins" {
  description = "Usernames who get the 'admins' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.admins`)."
  sensitive   = true
  type        = list(string)
  default     = []
}

variable "grownups" {
  description = "Usernames who get the 'grownups' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.grownups`)."
  sensitive   = true
  type        = list(string)
  default     = []
}

variable "kids" {
  description = "Usernames who get the 'kids' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.kids`)."
  sensitive   = true
  type        = list(string)
  default     = []
}

variable "authentik_url" {
  description = "Base URL of the Authentik instance."
  type        = string
  default     = "https://auth.cloud.blacksd.tech"
}

variable "authentik_token" {
  description = "API token for the Terraform-owned admin user. Provided by Terragrunt via SOPS decrypt of authentik-token.sops.yaml."
  type        = string
  sensitive   = true
}

variable "google_client_id" {
  description = "Client ID of the Google OAuth client used for the Google source. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Client secret of the Google OAuth client used for the Google source. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml."
  type        = string
  sensitive   = true
}

variable "users" {
  description = "Map of Authentik human users keyed by username. Provided by Terragrunt via SOPS decrypt of users.sops.yaml. `nick_name` and `preferred_language` are accepted to match the Zitadel module's variable shape (the SOPS file is bit-for-bit reusable) but are silently ignored — Authentik's `authentik_user` resource has no equivalent fields."
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

variable "family" {
  description = "Usernames who get added to the 'family' Authentik group (kids ∪ grownups — the household-wide catch-all used for shared apps like the library). Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.family`)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "admins" {
  description = "Usernames who get added to the 'admins' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.admins`)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "grownups" {
  description = "Usernames who get added to the 'grownups' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.grownups`)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "kids" {
  description = "Usernames who get added to the 'kids' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.kids`)."
  type        = list(string)
  default     = []
  sensitive   = true
}

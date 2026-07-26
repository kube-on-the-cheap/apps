# zitadel

Terraform module for managing the self-hosted Zitadel instance at
`auth.cloud.blacksd.tech`.

## What this manages

Provider configuration, default-organization discovery, and a placeholder
for future per-client OIDC application resources. No Zitadel resources
are defined in this module today; per-client files (e.g., `grimmory.tf`)
land here in follow-up specs and reference `local.org_id`.

## One-time bootstrap

1. Log into the Zitadel Console at `https://auth.cloud.blacksd.tech`.
2. Create a Service User in the default organization with
   **Access Token Type = JWT**.
3. Grant the Service User `IAM_OWNER` at the org level.
4. Generate a JSON key for the Service User — the Console downloads
   it once.
5. Move the downloaded file to
   `configs/blacksd/zitadel/zitadel-key.sops.json`, then encrypt:
   ```bash
   cd configs/blacksd/zitadel
   sops --encrypt --in-place zitadel-key.sops.json
   ```
6. Verify round-trip:
   ```bash
   sops -d zitadel-key.sops.json | jq -r .type   # → serviceaccount
   ```

The repo-root `.sops.yaml` rule
(`path_regex: \.sops(?:\.(?:yaml|json))?$`) matches the file
automatically.

## Day-to-day workflow

```bash
devbox shell
cd configs/blacksd/zitadel
terragrunt init    # first run only
terragrunt plan
terragrunt apply
```

## Adding a new OIDC client

New per-client resources land as sibling `.tf` files inside
`modules/zitadel/` (e.g., `modules/zitadel/grimmory.tf`) in their own
follow-up specs. Reference `local.org_id` for the org context.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_zitadel"></a> [zitadel](#requirement\_zitadel) | ~> 2.12 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_zitadel"></a> [zitadel](#provider\_zitadel) | 2.12.8 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [random_password.user_initial](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [zitadel_action.set_groups_claim](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/action) | resource |
| [zitadel_application_oidc.grimmory](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/application_oidc) | resource |
| [zitadel_default_login_policy.default](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/default_login_policy) | resource |
| [zitadel_human_user.users](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/human_user) | resource |
| [zitadel_idp_google.google](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/idp_google) | resource |
| [zitadel_project.homelab](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project) | resource |
| [zitadel_project_role.admins](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project_role) | resource |
| [zitadel_project_role.grownups](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project_role) | resource |
| [zitadel_project_role.kids](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project_role) | resource |
| [zitadel_project_role.users](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project_role) | resource |
| [zitadel_trigger_actions.customise_token](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/trigger_actions) | resource |
| [zitadel_user_grant.homelab](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/user_grant) | resource |
| [zitadel_orgs.default](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/data-sources/orgs) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admins"></a> [admins](#input\_admins) | Usernames who get the 'admins' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.admins`). | `list(string)` | `[]` | no |
| <a name="input_google_client_id"></a> [google\_client\_id](#input\_google\_client\_id) | Client ID of the Google OAuth web-application client used for the Google IdP. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml. | `string` | n/a | yes |
| <a name="input_google_client_secret"></a> [google\_client\_secret](#input\_google\_client\_secret) | Client secret of the Google OAuth web-application client used for the Google IdP. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml. | `string` | n/a | yes |
| <a name="input_grownups"></a> [grownups](#input\_grownups) | Usernames who get the 'grownups' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.grownups`). | `list(string)` | `[]` | no |
| <a name="input_kids"></a> [kids](#input\_kids) | Usernames who get the 'kids' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.kids`). | `list(string)` | `[]` | no |
| <a name="input_users"></a> [users](#input\_users) | Map of Zitadel human users keyed by username. Provided by Terragrunt via SOPS decrypt of users.sops.yaml. | <pre>map(object({<br/>    first_name         = string<br/>    last_name          = string<br/>    email              = string<br/>    display_name       = optional(string)<br/>    nick_name          = optional(string)<br/>    preferred_language = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_users_group"></a> [users\_group](#input\_users\_group) | Usernames who get the 'users' role on the Homelab project. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.users`). | `list(string)` | `[]` | no |
| <a name="input_zitadel_domain"></a> [zitadel\_domain](#input\_zitadel\_domain) | Hostname of the self-hosted Zitadel instance. | `string` | `"auth.cloud.blacksd.tech"` | no |
| <a name="input_zitadel_jwt_profile_json"></a> [zitadel\_jwt\_profile\_json](#input\_zitadel\_jwt\_profile\_json) | Service-account JSON key (whole document, inline) for the Terraform machine user. Provided by Terragrunt via SOPS decrypt of zitadel-key.sops.json. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_grimmory_client_id"></a> [grimmory\_client\_id](#output\_grimmory\_client\_id) | Client ID for the Grimmory OIDC application. Paste into Grimmory Settings → OIDC. Marked sensitive because the Zitadel provider schema flags `client_id` as sensitive; read with `terragrunt output -raw grimmory_client_id`. |
<!-- END_TF_DOCS -->

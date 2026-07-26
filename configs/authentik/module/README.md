# authentik

Terraform module for managing the self-hosted Authentik instance at
`auth.cloud.blacksd.tech` (deployed on the freeloader cluster). Mirrors
`modules/zitadel/` — same users, same four group buckets, same Google
IdP, plus a parallel Grimmory OIDC client.

## What this manages

- Four `authentik_group` buckets (`users`, `admins`, `grownups`, `kids`).
- `authentik_user` entries from a SOPS-encrypted YAML roster, with
  group memberships derived from per-bucket username lists.
- `authentik_source_oauth` Google source with `user_matching_mode =
  "email_link"`.
- `authentik_provider_oauth2` + `authentik_application` for Grimmory
  (public PKCE client). The client ID is exposed as the
  `grimmory_client_id` output and is **not** wired into Grimmory's
  runtime yet — the app keeps using the Zitadel client until a separate
  apps-repo PR cuts it over.

No `groups` claim is emitted on the Grimmory id_token in this revision;
adding the property mapping is a follow-up spec.

## One-time bootstrap

1. Log into the Authentik admin UI at
   `https://auth.cloud.blacksd.tech/if/admin/` from a permitted source
   IP (admin route gated by the existing `authentik-admin-ip-filter`
   SecurityPolicy).
2. Create an Internal Service Account user named `terraform`, add it
   to the built-in `authentik Admins` group, then create an API token
   for it under Tokens & App passwords.
3. Save the token to
   `configs/blacksd/authentik/authentik-token.sops.yaml` as
   `token: <value>`, then `sops --encrypt --in-place
   authentik-token.sops.yaml`.
4. Copy `configs/blacksd/zitadel/users.sops.yaml` and
   `configs/blacksd/zitadel/google-oauth.sops.yaml` to
   `configs/blacksd/authentik/`. The repo-root `.sops.yaml` rule
   (`path_regex: \.sops(?:\.(?:yaml|json))?$`) matches the new paths
   automatically.
5. In the Google Cloud Console, add
   `https://auth.cloud.blacksd.tech/source/oauth/callback/google/`
   to the OAuth client's authorized redirect URIs (alongside the
   existing Zitadel callback).

## Day-to-day workflow

```bash
devbox shell
cd configs/blacksd/authentik
terragrunt init    # first run only
terragrunt plan
terragrunt apply
```

## Drifting `users.sops.yaml`

The Zitadel and Authentik config dirs each carry their own copy of
`users.sops.yaml`. Until one of the two IdPs is retired, edits to
either file must be propagated to the other by hand. This is explicit,
time-boxed tech debt.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_authentik"></a> [authentik](#requirement\_authentik) | ~> 2026.5 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_authentik"></a> [authentik](#provider\_authentik) | 2026.5.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [authentik_application.grimmory](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/application) | resource |
| [authentik_flow_stage_binding.authentication_identification](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/flow_stage_binding) | resource |
| [authentik_group.admins](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/group) | resource |
| [authentik_group.family](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/group) | resource |
| [authentik_group.grownups](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/group) | resource |
| [authentik_group.kids](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/group) | resource |
| [authentik_policy_binding.grimmory_family](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/policy_binding) | resource |
| [authentik_property_mapping_provider_scope.groups](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/property_mapping_provider_scope) | resource |
| [authentik_property_mapping_provider_scope.offline_access](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/property_mapping_provider_scope) | resource |
| [authentik_provider_oauth2.grimmory](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/provider_oauth2) | resource |
| [authentik_source_oauth.google](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/source_oauth) | resource |
| [authentik_stage_identification.identification](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/stage_identification) | resource |
| [authentik_stage_password.password](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/stage_password) | resource |
| [authentik_system_settings.default](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/system_settings) | resource |
| [authentik_user.akadmin](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/user) | resource |
| [authentik_user.users](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/user) | resource |
| [random_id.grimmory_client_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.user_initial](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [authentik_certificate_key_pair.default](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/certificate_key_pair) | data source |
| [authentik_flow.authentication](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/flow) | data source |
| [authentik_flow.authorization](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/flow) | data source |
| [authentik_flow.invalidation](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/flow) | data source |
| [authentik_flow.source_authentication](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/flow) | data source |
| [authentik_flow.source_enrollment](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/flow) | data source |
| [authentik_group.builtin_admins](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/group) | data source |
| [authentik_property_mapping_provider_scope.email](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/property_mapping_provider_scope) | data source |
| [authentik_property_mapping_provider_scope.openid](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/property_mapping_provider_scope) | data source |
| [authentik_property_mapping_provider_scope.profile](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/data-sources/property_mapping_provider_scope) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admins"></a> [admins](#input\_admins) | Usernames who get added to the 'admins' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.admins`). | `list(string)` | `[]` | no |
| <a name="input_authentik_token"></a> [authentik\_token](#input\_authentik\_token) | API token for the Terraform-owned admin user. Provided by Terragrunt via SOPS decrypt of authentik-token.sops.yaml. | `string` | n/a | yes |
| <a name="input_authentik_url"></a> [authentik\_url](#input\_authentik\_url) | Base URL of the Authentik instance. | `string` | `"https://auth.cloud.blacksd.tech"` | no |
| <a name="input_family"></a> [family](#input\_family) | Usernames who get added to the 'family' Authentik group (kids ∪ grownups — the household-wide catch-all used for shared apps like the library). Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.family`). | `list(string)` | `[]` | no |
| <a name="input_google_client_id"></a> [google\_client\_id](#input\_google\_client\_id) | Client ID of the Google OAuth client used for the Google source. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml. | `string` | n/a | yes |
| <a name="input_google_client_secret"></a> [google\_client\_secret](#input\_google\_client\_secret) | Client secret of the Google OAuth client used for the Google source. Provided by Terragrunt via SOPS decrypt of google-oauth.sops.yaml. | `string` | n/a | yes |
| <a name="input_grownups"></a> [grownups](#input\_grownups) | Usernames who get added to the 'grownups' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.grownups`). | `list(string)` | `[]` | no |
| <a name="input_kids"></a> [kids](#input\_kids) | Usernames who get added to the 'kids' Authentik group. Each must be a key in `users`. Provided by Terragrunt via SOPS decrypt of users.sops.yaml (`groups.kids`). | `list(string)` | `[]` | no |
| <a name="input_users"></a> [users](#input\_users) | Map of Authentik human users keyed by username. Provided by Terragrunt via SOPS decrypt of users.sops.yaml. `nick_name` and `preferred_language` are accepted to match the Zitadel module's variable shape (the SOPS file is bit-for-bit reusable) but are silently ignored — Authentik's `authentik_user` resource has no equivalent fields. | <pre>map(object({<br/>    first_name         = string<br/>    last_name          = string<br/>    email              = string<br/>    display_name       = optional(string)<br/>    nick_name          = optional(string)<br/>    preferred_language = optional(string)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_grimmory_client_id"></a> [grimmory\_client\_id](#output\_grimmory\_client\_id) | Client ID for the Authentik-side Grimmory OIDC application. Read with `terragrunt output -raw grimmory_client_id`. Not wired into Grimmory yet — the app continues using the Zitadel client until a separate apps-repo PR cuts it over. |
| <a name="output_grimmory_issuer_url"></a> [grimmory\_issuer\_url](#output\_grimmory\_issuer\_url) | OIDC issuer URL for the Authentik-side Grimmory application. Paste into Grimmory Settings → OIDC alongside `grimmory_client_id`. The discovery document lives at `<issuer>/.well-known/openid-configuration`. Read with `terragrunt output -raw grimmory_issuer_url`. |
<!-- END_TF_DOCS -->

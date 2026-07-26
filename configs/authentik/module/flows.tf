data "authentik_flow" "source_authentication" {
  slug = "default-source-authentication"
}

data "authentik_flow" "source_enrollment" {
  slug = "default-source-enrollment"
}

data "authentik_flow" "authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_flow" "authentication" {
  slug = "default-authentication-flow"
}

# The stock `default-authentication-identification` stage has the Google source
# pinned out of its `sources` list, so `promoted = true` on the source isn't
# enough — the per-source button never renders. We replace the binding on the
# default authentication flow with our own identification stage that explicitly
# lists the Google source. A password stage hangs off it so username-only
# login still works.

resource "authentik_stage_password" "password" {
  name     = "homelab-password"
  backends = ["authentik.core.auth.InbuiltBackend"]
}

resource "authentik_stage_identification" "identification" {
  name               = "homelab-identification"
  user_fields        = ["username", "email"]
  sources            = [authentik_source_oauth.google.uuid]
  password_stage     = authentik_stage_password.password.id
  show_source_labels = true
}

resource "authentik_flow_stage_binding" "authentication_identification" {
  target = data.authentik_flow.authentication.id
  stage  = authentik_stage_identification.identification.id
  order  = 0
}

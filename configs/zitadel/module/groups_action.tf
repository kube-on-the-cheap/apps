resource "zitadel_action" "set_groups_claim" {
  org_id          = local.org_id
  name            = "setGroupsClaim"
  timeout         = "10s"
  allowed_to_fail = false

  # The JS function name must match the resource name (Zitadel calls
  # the function whose name matches the action name).
  script = <<-EOJS
    function setGroupsClaim(ctx, api) {
      const grantList = ctx.v1.user.grants;
      const grants = (grantList && grantList.grants) || [];
      const groups = new Set();
      for (const g of grants) {
        for (const role of g.roles || []) {
          groups.add(role);
        }
      }
      api.v1.claims.setClaim('groups', Array.from(groups));
    }
  EOJS
}

resource "zitadel_trigger_actions" "customise_token" {
  org_id       = local.org_id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_USERINFO_CREATION"
  action_ids   = [zitadel_action.set_groups_claim.id]
}

# Extra NetBox configuration appended to configuration.py by the
# netbox-community/netbox-chart via extraConfig[].configMap.name.
# Named `.py` locally so pre-commit's check-yaml hook doesn't reject
# it; the overlay's configMapGenerator maps this file to the
# `oidc-config.yaml` ConfigMap key the chart mounts (Task 10 uses
# kustomize's `KEY=SOURCE` file syntax).

import os

REMOTE_AUTH_ENABLED = True
REMOTE_AUTH_BACKEND = 'social_core.backends.open_id_connect.OpenIdConnectAuth'

# Authentik issuer (no trailing slash; python-social-auth appends
# /.well-known/openid-configuration internally).
SOCIAL_AUTH_OIDC_OIDC_ENDPOINT = 'https://auth.cloud.blacksd.tech/application/o/netbox'

# Ask for `groups` on top of the standard scopes so _map_netbox_roles
# below can promote admins users to superuser.
SOCIAL_AUTH_OIDC_SCOPE = ['openid', 'email', 'profile', 'groups']

# Client id/secret come from environment variables injected via the
# chart's extraEnvs (backed by the SOPS-encrypted netbox-oidc Secret).
SOCIAL_AUTH_OIDC_KEY = os.environ.get('OIDC_CLIENT_ID')
SOCIAL_AUTH_OIDC_SECRET = os.environ.get('OIDC_CLIENT_SECRET')

# Custom pipeline step: map the OIDC `groups` claim onto Django
# is_staff / is_superuser. Runs after user creation, idempotent, and
# demotes users cleanly if they leave the admins group.
#
# The Authentik policy binding only allows `grownups` members through
# in the first place, so we don't need to reject unknown users here.
def _map_netbox_roles(strategy, details, backend, user=None, response=None, *args, **kwargs):
    if user is None or response is None:
        return
    groups = response.get('groups') or []
    is_admin = 'admins' in groups
    changed = False
    if user.is_staff != is_admin:
        user.is_staff = is_admin
        changed = True
    if user.is_superuser != is_admin:
        user.is_superuser = is_admin
        changed = True
    if changed:
        user.save(update_fields=['is_staff', 'is_superuser'])

SOCIAL_AUTH_PIPELINE = (
    'social_core.pipeline.social_auth.social_details',
    'social_core.pipeline.social_auth.social_uid',
    'social_core.pipeline.social_auth.auth_allowed',
    'social_core.pipeline.social_auth.social_user',
    'social_core.pipeline.user.get_username',
    'social_core.pipeline.user.create_user',
    'social_core.pipeline.social_auth.associate_user',
    'social_core.pipeline.social_auth.load_extra_data',
    'social_core.pipeline.user.user_details',
    # Fully-qualified name: extraConfig files are appended to
    # netbox/configuration.py, so _map_netbox_roles lives in the
    # `netbox.configuration` module at runtime.
    'netbox.configuration._map_netbox_roles',
)

# python-social-auth builds callback URLs from this. Chart's ingress
# is off (Envoy Gateway HTTPRoute in front of the Service) so we
# explicitly force https on redirects.
SOCIAL_AUTH_REDIRECT_IS_HTTPS = True

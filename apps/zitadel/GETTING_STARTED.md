# Zitadel Getting Started

## Initial Admin Access

Zitadel creates machine users during setup but no human admin with a password. You have two options:

### Option A: Create a New Admin User (Recommended)

```bash
# Get the IAM admin PAT
PAT=$(kubectl get secret iam-admin-pat -n zitadel -o jsonpath='{.data.pat}' | base64 -d)

# Create human user and grant IAM_OWNER
USER_ID=$(curl -s -X POST "https://auth.cloud.blacksd.tech/v2/users/human" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "profile": {"givenName": "Admin", "familyName": "User"},
    "email": {"email": "admin@cloud.blacksd.tech", "isVerified": true},
    "password": {"password": "CHANGE_ME_SecurePass123!", "changeRequired": true}
  }' | jq -r '.userId')

curl -X POST "https://auth.cloud.blacksd.tech/admin/v1/members" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d "{\"userId\": \"$USER_ID\", \"roles\": [\"IAM_OWNER\"]}"
```

### Option B: Set Password for Default ZITADEL Admin

```bash
PAT=$(kubectl get secret iam-admin-pat -n zitadel -o jsonpath='{.data.pat}' | base64 -d)

# Find the zitadel-admin user ID
USER_ID=$(curl -s "https://auth.cloud.blacksd.tech/v2/users?query.userNameQuery.userName=zitadel-admin" \
  -H "Authorization: Bearer $PAT" | jq -r '.result[0].userId')

# Set password
curl -X POST "https://auth.cloud.blacksd.tech/v2/users/$USER_ID/password" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"newPassword": {"password": "CHANGE_ME_SecurePass123!", "changeRequired": true}}'
```

## Login

Access the console at: https://auth.cloud.blacksd.tech/ui/console/

## Password Recovery

If you lose access to your admin account:

```bash
PAT=$(kubectl get secret iam-admin-pat -n zitadel -o jsonpath='{.data.pat}' | base64 -d)

# Find user ID by username
USER_ID=$(curl -s "https://auth.cloud.blacksd.tech/v2/users?queries.userNameQuery.userName=admin" \
  -H "Authorization: Bearer $PAT" | jq -r '.result[0].userId')

# Reset password
curl -X POST "https://auth.cloud.blacksd.tech/v2/users/$USER_ID/password" \
  -H "Authorization: Bearer $PAT" \
  -H "Content-Type: application/json" \
  -d '{"newPassword": {"password": "NEW_PASSWORD_HERE", "changeRequired": true}}'
```

## Service Accounts (Do Not Delete)

- **iam-admin**: Machine user for API access and recovery
- **login-client**: Required by the login UI service

## References

- [Zitadel Self-Hosting Guide](https://zitadel.com/docs/self-hosting/deploy/overview)
- [User Management API](https://zitadel.com/docs/apis/resources/user_service_v2/user-service-add-human-user)
- [IAM Members API](https://zitadel.com/docs/apis/resources/admin_service/admin-service-add-iam-member)
- [Custom Domain Configuration](https://zitadel.com/docs/self-hosting/manage/custom-domain)

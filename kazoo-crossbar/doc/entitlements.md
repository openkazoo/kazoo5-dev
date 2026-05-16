# Entitlements

## About Entitlements

Entitlements are the combination of [capabilities](./capabilities.md) and `enrollments` in the available capabilities.

At a high level, capabilities represent features or functionality that the cluster operator offers (like a custom UI app, an integration service, etc) that resellers, accounts, and/or users can enroll in to receive access to the capability.

For a capability to be accessible to a user or account, all ancestor resellers must have the capability enabled and be enrolled in the capability.

For instance, given a reseller tree of `Master` -> `Reseller A` -> `Account B` -> `User C`:

- If a capability is disabled in the top-level, it will not be visible to `A`, `B`, or `C`.
- If `A` has a capability enabled but is not enrolled, or has explicitly disabled the capability, `B` and `C` will not see the capability.
- If `B` has disabled a capability, `C` will not see the capability listed.

Another way to think of it is, enabled capabilities are inherited from the ancestor account and can be explicitly disabled. Enabled capabilities must also be enrolled in by the ancestor account (top-level account is implicitly enrolled in all enabled system capabilities). Users can only enroll in capabilities enabled and enrolled in by their account.

#### Schema

Entitlements recognize the capabilities the system or reseller offer and the enrollments of accounts in those capabilities



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`capabilities./[a-zA-Z0-9]{3,32}/` | List of capabilities allowed for an account or user | [#/definitions/capability](#capability) |   | `false` |  
`capabilities` |   | `object()` |   | `false` |  
`enrollments./[a-zA-Z0-9]{3,32}/` | Which capabilities an account or user are enrolled in | [#/definitions/enrollment](#enrollment) |   | `false` |  
`enrollments` |   | `object()` |   | `false` |  

### capability

Capabilities represent the additional features a cluster (or reseller) is providing descendant accounts


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`description` | Optional description of what the capability offers | `string()` |   | `false` |  
`enabled` | Is the capability currently offered | `boolean()` |   | `false` |  
`provided_by` | ID of the provider of the capability (reseller) or 'system' | `string()` |   | `false` |  

### enrollment

Enrollments represent the account's accepted capabilities from the cluster or reseller


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`enabled` | Whether the enrollment is enabled on the account | `boolean()` |   | `false` |  
`enrolled` | Timestamp, in gregorian seconds, when the enrollment was last toggled | `integer()` |   | `false` |  



## Fetch an account's entitlements

> GET /v2/accounts/{ACCOUNT_ID}/entitlements

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements
```
```json
{
  "data": {
    "capabilities": {
      "{CAPABILITY_ID}": {
        "description": "you really want this thing",
        "enabled": true,
        "name": "thing you want",
        "provided_by": "system"
      }
    },
    "enrollments": {}
  }
}
```

### Fetch an user's entitlements

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/entitlements

## (Un)Enroll an account in a capability

> POST /v2/accounts/{ACCOUNT_ID}/entitlements/enrollment

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements/enrollment \
    -d '{"data":{"capabilities":["{CAPABILITY_ID}"],"enabled":true}}'
```
```json Request JSON
{
  "data": {
    "capabilities": [
      "{CAPABILITY_ID}"
    ],
    "enabled": true
  }
}

```
```json Response JSON
{
  "data": {
    "enrollments": {
      "{CAPABILITY_ID}": {
        "enabled": true,
        "enrolled": {TIMESTAMP}
      }
    }
  },
  "status": "success"
}
```

Toggle the `enabled` flag to enroll (`true`) or unenroll (`false`).

### (Un)Enroll an descendant account

As a reseller with sub-accounts, it is possible to enroll your child accounts directly without requiring the account admin to do so.


> POST /v2/accounts/{RESELLER_ACCOUNT_ID}/entitlements/enrollment

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements/enrollment \
    -d '{"data":{"capabilities":["{CAPABILITY_ID}"],"enabled":true, "account_id":"{DESCENDANT_ID}"}}'
```
```json Request JSON
{
  "data": {
    "account_id": "{DESCENDANT_ID}",
    "capabilities": [
      "{CAPABILITY_ID}"
    ],
    "enabled": true
  }
}

```
```json Response JSON
{
  "data": {
    "enrollments": {
      "{CAPABILITY_ID}": {
        "enabled": true,
        "enrolled": {TIMESTAMP}
      }
    }
  },
  "status": "success"
}
```

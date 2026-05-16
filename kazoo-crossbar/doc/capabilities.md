# Capabilities

## About Capabilities

Capabilities describe what the cluster (or reseller) offers to its resellers, accounts and users.

These capabilities can then be enrolled in by sub-accounts and users, as appropriate. See [entitlements](./entitlements.md) for more.

#### Schema

Capabilities represent the additional features a cluster (or reseller) is providing descendant accounts



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`description` | Optional description of what the capability offers | `string()` |   | `false` |
`enabled` | Is the capability currently offered | `boolean()` |   | `false` |
`provided_by` | ID of the provider of the capability (reseller) or 'system' | `string()` |   | `false` |



## Update the system capabilities

This will create (if not existing yet) or replace the system capabilities with the request data

> POST /v2/accounts/capabilities

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/capabilities \
    -d '{"data":{"{CAPABILITY_ID}":{"description":"system capability you want to use","enabled":true,"name":"smoething you want"}}}
```

`{CAPABILITY_ID}` can be a UUID (recommended) or a friendlier name.

This API requires a super-duper admin API token to use

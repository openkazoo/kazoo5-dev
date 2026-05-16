# Entitlements

## About Entitlements

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



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/entitlements

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/entitlements/{APP_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements/{APP_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/entitlements/enrollment

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/entitlements/enrollment
```


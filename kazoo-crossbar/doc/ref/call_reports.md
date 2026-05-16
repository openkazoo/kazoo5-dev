# Call Reports

## About Call Reports

#### Schema

Schema for a call report



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`call_id` | Call ID for which the quality/issue report was submitted | `string()` |   | `true` | `supported`
`cdr_id` | CDR ID of the call for which the quality/issue report was submitted | `string()` |   | `false` | `supported`
`description` | Description of the issue/steps to reproduce/etc. that may be submitted by, for example, a user | `string()` |   | `false` | `supported`
`type` | Type of issue that was reported. Must be in the list of allowed types for call reports in system_config | `string()` |   | `true` | `supported`



## Create

> PUT /v2/accounts/{ACCOUNT_ID}/call_reports

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/call_reports
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/call_reports/allowed_types

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/call_reports/allowed_types
```


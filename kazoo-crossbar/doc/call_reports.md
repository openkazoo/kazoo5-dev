# Call Reports

## About Call Reports

Reports of quality or other issues for calls

#### Schema

Schema for a call report



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`call_id` | Call ID for which the quality/issue report was submitted | `string()` |   | `true` | `supported`
`cdr_id` | CDR ID of the call for which the quality/issue report was submitted | `string()` |   | `false` | `supported`
`description` | Description of the issue/steps to reproduce/etc. that may be submitted by, for example, a user | `string()` |   | `false` | `supported`
`type` | Type of issue that was reported. Must be in the list of allowed types for call reports in system_config | `string()` |   | `true` | `supported`



## Create a new call report

> PUT /v2/accounts/{ACCOUNT_ID}/call_reports

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -H "Content-Type: application/json" \
    -d '{"data":{"call_id":"0e03ab16-2684-40a0-951b-8ee0d6f3e214", "cdr_id":"202006-0e03ab16-2684-40a0-951b-8ee0d6f3e214", "description":"Sound quality was poor", "type":"audio_quality"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/call_reports
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_id": "0e03ab16-2684-40a0-951b-8ee0d6f3e214",
        "cdr_id": "202006-0e03ab16-2684-40a0-951b-8ee0d6f3e214",
        "description": "Sound quality was poor",
        "id": "{CALL_REPORT_ID}",
        "type": "audio_quality"
    },
    "node": "{NODE}",
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success",
    "timestamp": "{TIMESTAMP}",
    "version": "{VERSION}"
}
```

## Fetch the allowed types for the `type` property

The `id` properties of the response's `data` objects define the allowed values for the `type` property of a call report.

> GET /v2/accounts/{ACCOUNT_ID}/call_reports/allowed_types

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/call_reports/allowed_types
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "dropped_call",
            "name": "Dropped call"
        },
        {
            "id": "one_way_audio",
            "name": "One-way audio"
        },
        {
            "id": "broken_audio",
            "name": "Broken audio or bad sound"
        },
        {
            "id": "other",
            "name": "Other"
        }
    ],
    "node": "{NODE}"
    "request_id": "{REQUEST_ID}",
    "status": "success",
    "timestamp": "{TIMESTAMP}",
    "version": "{VERSION}"
}
```

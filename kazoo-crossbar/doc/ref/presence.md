# Presence

## About Presence

#### Schema

Change and request presence status



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` | Action to be executed on this request | [#/definitions/presence.action](#presenceaction) |   | `true` |  
`reset` | Deprecated way of running reset action | `boolean()` |   | `false` | `deprecated`
`state` | Desired state to be set on this request | [#/definitions/presence.state](#presencestate) |   | `false` |  

### presence.action

Action to be executed on this request


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` | Action to be executed on this request | `string('set' \| 'reset')` | `reset` | `true` | `supported`

### presence.state

Desired state to be set on this request


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`state` | Desired state to be set on this request | `string('early' \| 'confirmed' \| 'terminated')` |   | `true` | `supported`



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/presence

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/presence
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/presence

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/presence
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/presence/{EXTENSION}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/presence/{EXTENSION}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/presence/{EXTENSION}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/presence/{EXTENSION}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/presence/report-{REPORT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/presence/report-{REPORT_ID}
```


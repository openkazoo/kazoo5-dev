# Webhooks

## About Webhooks

#### Schema

Web Hooks are subscriptions to allowed events that, when the event occurs, the event data is sent to the URI set in the Web Hook document.



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`custom_data` | These properties will be added to the event and will overwrite existing values. | `object()` |   | `false` |  
`custom_request_headers` | Custom HTTP request headers to be included when sending the webhook request | `object()` |   | `false` |  
`enabled` | Is the webhook enabled and running | `boolean()` | `true` | `false` |  
`format` | What Body format to use when sending the webhook. only valid for 'post' & 'put' verbs | `string('form-data' \| 'json')` | `form-data` | `false` | `supported`
`hook` | The trigger event for a request being made to 'callback_uri'. | `string()` |   | `true` | `supported`
`http_verb` | What HTTP method to use when contacting the server | `string('get' \| 'post' \| 'put')` | `post` | `false` | `supported`
`include_internal_legs` | Whether to filter out call legs that are internal to the system (loopback) | `boolean()` | `true` | `false` |  
`include_subaccounts` | Should the webhook be fired for subaccount events. | `boolean()` |   | `false` | `supported`
`name` | A friendly name for the webhook | `string()` |   | `true` | `supported`
`retries` | Retry the request this many times (if it fails) | `integer(0..4)` | `2` | `false` | `supported`
`security_settings.sha256_key` | Secret key to create a SHA256 HMAC with, so receiver can validate the webhook came from the cluster | `string()` |   | `false` |  
`security_settings` | Security settings to harden webhook delivery | `object()` |   | `false` |  
`uri` | The 3rd party URI to call out to an event | `string(1..)` |   | `true` | `supported`
`version` | Whether to receive the full version of the event in the webhook payload | `string('v1' \| 'v2')` | `v1` | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/webhooks

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/webhooks

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks/samples

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/samples
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks/attempts

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/attempts
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}/attempts

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/{WEBHOOK_ID}/attempts
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/webhooks/samples/{SAMPLE_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/webhooks/samples/{SAMPLE_ID}
```


# External Numbers

## About External Numbers

#### Schema

Schema for an external number



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`name` | A friendly name for the external number | `string(1..128)` |   | `false` | `supported`
`number` | The external number | `string(1..30)` |   | `true` | `supported`



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/external_numbers

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/external_numbers

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify
```


# Lists

## About Lists

#### Schema

Schema for a match list



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`description` | A friendly list description | `string(1..128)` |   | `false` |  
`name` | A friendly match list name | `string(1..128)` |   | `true` |  
`org` | Full legal name of the organization | `string()` |   | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/lists

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/lists

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{LIST_ID}
```


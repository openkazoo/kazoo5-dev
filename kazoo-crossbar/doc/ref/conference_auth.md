# Conference Authentication

## About Conference Authentication

#### Schema

Schema for conference_auth



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`account_name` | The account name of the conference | `string(1..128)` |   | `true` |  
`conference_name` | Conference name | `string(1..128)` |   | `true` |  
`conference_pin` | Conference member pin number | `string()` |   | `true` |  



## Create

> PUT /v2/accounts/{ACCOUNT_ID}/conference_auth

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/conference_auth
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/conference_auth/{CONFERENCE_ID}

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/conference_auth/{CONFERENCE_ID}
```


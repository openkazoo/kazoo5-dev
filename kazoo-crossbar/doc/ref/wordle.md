# Wordle

## About Wordle

## Schema



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/wordle

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/wordle
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/wordle/{WORD_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/wordle/{WORD_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/wordle/{WORD_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/wordle/{WORD_ID}
```


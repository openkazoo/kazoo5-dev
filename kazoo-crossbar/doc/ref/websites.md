# Websites

## About Websites

#### Schema

Websites represent the website urls that can be added to a account and it's child accounts



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`account_wide` | Whether an website is visible to all accounts in the parent account | `boolean()` | `true` | `false` |  
`name` | A name for the website to be displayed | `string(1..128)` |   | `true` |  
`open_in_browser` | Whether a website should be opened in browser | `boolean()` | `false` | `false` |  
`users.[]` |   | `string()` |   | `false` |  
`users` | A list users who are assigned the website | `array(string())` | `[]` | `false` |  
`web_url` | Application api url | `string(7..)` |   | `true` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/websites

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/websites

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```


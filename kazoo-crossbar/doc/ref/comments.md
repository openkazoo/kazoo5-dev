# Comments

## About Comments

#### Schema

Schema for comments



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`comments` | The history of comments made on a object | `array([#/definitions/comment](#comment))` |   | `false` |  

### comment

Schema for a single comment


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`account_id` | Account ID of the commenter. | `string()` |   | `false` |  
`action_required` | Specified if an action is required by the user. | `boolean()` | `false` | `false` |  
`author` | Full name of the author | `string()` |   | `true` |  
`content` | Content of the comment | `string()` |   | `true` |  
`is_private` | Specified if this comment is private | `boolean()` | `false` | `false` |  
`timestamp` |   | `integer()` |   | `true` |  
`user_id` | User ID of the commenter | `string()` |   | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```


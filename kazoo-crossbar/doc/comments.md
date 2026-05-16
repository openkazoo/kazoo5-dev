# Comments

## About Comments

Allows you to add comments to "any" documents in Kazoo.

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

> DELETE /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

```json
{
    "data": [
    ],
    "status": "success"
}
```


## Fetch a Comment

> GET /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

```json
{
  "data": "{COMMENT}",
  "status": "success"
}
```


## Add a Comment

> PUT /v2/accounts/{ACCOUNT_ID}/comments

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"comments": [{COMMENT_3}]}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments
```

```json
{
    "data": {
        "comments": [
            "{COMMENT_1}",
            "{COMMENT_2}",
            "{COMMENT_3}"
        ]
    },
    "status": "success"
}
```


## Delete a Comment

> DELETE /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```

```json
{
    "data": {
        "comments": [
            "{COMMENT_1}",
            "{COMMENT_2}"
        ]
    },
    "status": "success"
}
```


## Fetch a Comment

> GET /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```

```json
{
    "data": {
        "comments": [
            "{COMMENT_1}",
            "{COMMENT_2}"
        ]
    },
    "status": "success"
}
```


## Update a Comment

> POST /v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": "{COMMENT}"}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/comments/{COMMENT_ID}
```

```json
{
    "data": "{COMMENT}",
    "status": "success"
}
```

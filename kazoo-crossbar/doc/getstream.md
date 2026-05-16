# Getstream

## About Getstream

Integration with getstream.io

## Schema

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/getstream/connect

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/getstream/connect
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
    "id": "{TOKEN_ID}",
    "token": "{TOKEN}",
    "api_key": "{API_KEY}"
  },
  "request_id": "{REQUEST_ID}",
  "revision": "{REVISION}",
  "status": "success"
}
```

## Fetch getstream enabled users in the account

Get the users who has the getstream feature enabled. For this kazoo will query the users who has pvt_chat.getstream.enabled parameter equal to true in user doc.

> GET /v2/accounts/{ACCOUNT_ID}/users/getstream

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/getstream
```

**Response**

```json
{
    "data": [
        {
            "id": "7b609e2e24b7c32f3a30dba972ecec9f",
            "features": [
                "vm_to_email",
                "getstream"
            ],
            "username": "navoda3633@2600hz.com",
            "email": "navoda3633@2600hz.com",
            "first_name": "Navoda 363",
            "last_name": "3",
            "priv_level": "user",
            "presence_id": "653"
        },
        {
            "id": "76c579d53b8c2e2c1c3102033775ce7c",
            "features": [
                "vm_to_email",
                "getstream"
            ],
            "username": "nginige1@2600hz.com",
            "email": "nginige1@2600hz.com",
            "first_name": "Navoda 363",
            "last_name": "1",
            "priv_level": "user",
            "presence_id": "651"
        }
    ],
    "revision": "4de2f80e8e81fba956e639d45171dfb7",
    "status": "success"
}
```

## Get status of getstream feature for an user

Get the getstream object a specific user.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream
```

**Response**

```json
{
    "data": {
        "enabled": true
    },
    "status": "success"
}
```

## Enable getstream feature for an user

This will enable the getstream feature for a specific user.

> PUT /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d {"data": {"nickname": "navoda"}} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream
```

**Response**

```json
{
    "data": {
        "nickname": "navoda",
        "enabled": true
    },
    "revision": "14-0ff6d7b0723fa8bfebd9c652cd2578f7",
    "status": "success"
}
```

## Update getstream for an user

This will update the getstream object of a user doc. This can be used to enable/disable getstream feature.

> PATCH /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d {"data": {"nickname": "navoda2","enabled": false}} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream
```

**Response**

```json
{
    "data": {
        "nickname": "navoda2",
        "enabled": false
    },
    "revision": "14-0ff6d7b0723fa8bfebd9c652cd2578f7",
    "status": "success"
}
```

## Disable getstream feature for an user

This will remove the pvt_chat.getstream object from user document disabling the getstream feature.

> DELETE /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/getstream
```

**Response**

```json
{
    "data": {
        "nickname": "navoda",
        "enabled": true
    },
    "revision": "1-fa91d3b20e63d1ef0c40dc4f19d15ff8",
    "status": "success"
}
```

### Prerequisites on getstream API

You just need to create a doc in `system_config` with the following id : `crossbar.getstream`

The structure required is :
```json
{
  "_id": "crossbar.getstream",
  "default": {
  "secret": "{SECRET}",
  "api_key": "{API_kEY}"
  }
}
```

`{SECRET}` and `{API_KEY}` will be provided by gestream or you can go on the user's overview in getstream to check these values.

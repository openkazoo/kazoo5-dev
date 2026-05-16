# Websites

## About Websites

Websites can be used with the comm.land. So an admin and users would be able to add custom websites with a logo. Admin can set websites as account wide or to specific users and users can add their own websites.

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`account_wide` | Whether an website is visible to all accounts in the parent account | `boolean()` | `true` | `false` |
`name` | A name for the website to be displayed | `string(1..128)` |   | `true` | `supported`
`open_in_browser` | Whether a website should be opened in browser | `boolean()` | `false` | `false` |
`users.[]` |   | `string()` |   | `false` |
`users` | A list users who are assigned the website | `array(string())` | `[]` | `false` |
`web_url` | Application api url | `string(7..)` |   | `true` |

## Fetch Available Website Bindings

List all available websites in an account.

> GET /v2/accounts/{ACCOUNT_ID}/websites

```shell
curl -v -X GET \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites
```

**Response**

```json
{
    "data": [
        {
            "id": "e4a04b3e0be66cace9d773c2b7931101",
            "name": "twitter",
            "web_url": "http://www.twitter.com",
            "account_wide": true,
            "users": []
        },
        {
            "id": "aeec180d6a0d1256cf37ecafb00915a4",
            "name": "test website",
            "web_url": "http://www.google.com",
            "account_wide": true,
            "users": []
        }
    ],
    "revision": "a813defba56966a02aa37dd3b9326ff9",
    "metadata": {},
    "status": "success"
}
```
## Fetch a website

Fetch a website using the id. If logo is to be fetched http header 'Accept' need to be set as with accepted content types. 
image/gif
image/jpg
image/jpeg
image/png

> GET /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X GET \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

**Response**

```json
{
    "data": {
        "name": "YouTube",
        "web_url": "http://www.youtube.com",
        "account_wide": true,
        "users": [],
        "id": "742d592f872c008698cb634885f73bb5"
    },
    "revision": "1-7a1609ecb150e6b069d5d55dc7086679",
    "metadata": {
        "id": "742d592f872c008698cb634885f73bb5",
        "created": 63837033818,
        "modified": 63837033818
    },
    "status": "success"
}
```

## Fetch available websites for a user

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/websites

Fetch available websites for a specific user. Those are the websites which set "account_wide" : true or user is specified in the website

```shell
curl -v -X GET \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/websites
```

**Response**

```json
{
    "data": [
        {
            "id": "e4a04b3e0be66cace9d773c2b7931101",
            "name": "twitter",
            "web_url": "http://www.twitter.com",
            "account_wide": true,
            "users": []
        },
        {
            "id": "aeec180d6a0d1256cf37ecafb00915a4",
            "name": "test website",
            "web_url": "http://www.google.com",
            "account_wide": true,
            "users": []
        }
    ],
    "revision": "36a61f70066521bcd1ba227f44acb621",
    "metadata": {},
    "status": "success"
}
```

## Create a new website

> PUT /v2/accounts/{ACCOUNT_ID}/websites

```shell
curl -v -X PUT \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -d {"data":{"name": "twitter","web_url": "http://www.twitter.com","account_wide": true,"users": []}} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites
```

**Response**

```json
{
    "data": {
        "name": "Amazon",
        "web_url": "http://www.amazon.com",
        "account_wide": true,
        "users": [],
        "id": "075fd00b30b28e4023cad20a5e44ba98"
    },
    "revision": "1-30cb71809be117e310eb176aeb60995b",
    "metadata": {
        "id": "075fd00b30b28e4023cad20a5e44ba98",
        "created": 63837577763,
        "modified": 63837577763
    },
    "status": "success"
}
```

## Add/update a website logo

Website logo can be added/updated in MIME types image/jpg, image/jpeg, image/png, image/gif and can add/update a logo using application/base64 content-type also

> POST /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    --data-binary "@/local/path/to/logo.png" \
    --header 'Content-Type: image/png' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```
**Response**
```json
{
    "data": {
        "web_url": "http://www.instagram.com.au",
        "name": "Instagram",
        "account_wide": true,
        "users": [],
        "id": "7b5670335c21409ba33d78bbbc708ff1"
    },
    "revision": "4-60b578b6dc2c051d1c06ca6efb62b772",
    "metadata": {
        "id": "7b5670335c21409ba33d78bbbc708ff1",
        "created": 63837101837,
        "modified": 63837580528
    },
    "status": "success"
}
```

## Update a website

> POST /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X POST \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -d {"data":{"name": "twitter","web_url": "http://www.twitter.com","account_wide": true,"users": []}} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

**Response**

```json
{
    "data": {
        "web_url": "http://www.instagram.com.au",
        "name": "Instagram",
        "account_wide": true,
        "users": [],
        "id": "7b5670335c21409ba33d78bbbc708ff1"
    },
    "revision": "4-60b578b6dc2c051d1c06ca6efb62b772",
    "metadata": {
        "id": "7b5670335c21409ba33d78bbbc708ff1",
        "created": 63837101837,
        "modified": 63837580528
    },
    "status": "success"
}
```

## Patch a website

> PATCH /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X PATCH \
    -H "Content-Type:application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -d {"data":{"web_url": "http://www.twitter.com","name": "Twitter US"}} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

**Response**

```json
{
    "data": {
        "web_url": "http://www.twitter.com",
        "users": [],
        "name": "Twitter US",
        "account_wide": true,
        "id": "e4a04b3e0be66cace9d773c2b7931101"
    },
    "revision": "2-c49d30317b4bdf967b756800193f1e43",
    "metadata": {
        "id": "e4a04b3e0be66cace9d773c2b7931101",
        "created": 63837158408,
        "modified": 63837580649
    },
    "status": "success"
}
```

## Remove a website

> DELETE /v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/websites/{WEBSITE_ID}
```

**Response**

```json
{
    "data": {
        "name": "Amazon",
        "web_url": "http://www.amazon.com",
        "account_wide": true,
        "users": [],
        "id": "075fd00b30b28e4023cad20a5e44ba98"
    },
    "revision": "1-30cb71809be117e310eb176aeb60995b",
    "metadata": {
        "id": "075fd00b30b28e4023cad20a5e44ba98",
        "created": 63837577763,
        "modified": 63837579123,
        "deleted": true
    },
    "status": "success"
}
```
# Commland

## About Commland

Provides an API that referrs the request to a core compatible version of comm.land desktop application. This API bypasses authentication as it is invoked prior to a client login.

## Schema

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/commland/compatibility

```shell
curl -v -X GET \
    http://{SERVER}:8000/v2/commland/compatibility
*   Trying {SERVER}:8000...
* Connected to {SERVER} ({SERVER_IP}) port 8000 (#0)
> GET /v2/commland/compatibility HTTP/1.1
> Host: {SERVER}:8000
> User-Agent: curl/7.74.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 302 Found
< access-control-allow-headers: content-type, depth, user-agent, x-http-method-override, x-file-size, x-requested-with, if-modified-since, x-file-name, cache-control, x-auth-token, x-kazoo-cluster-id, if-match, authorization
< access-control-allow-methods: OPTIONS, GET
< access-control-allow-origin: *
< access-control-expose-headers: content-type, x-auth-token, x-request-id, x-kazoo-cluster-id, location, etag
< access-control-max-age: 86400
< content-language: en
< content-length: 314
< content-type: application/json
< date: Mon, 11 Jul 2022 22:22:01 GMT
< location: https://packages.2600hz.com/commland/misc/compatibility/{COMPATIBILITY_HASH}
< server: Cowboy
< vary: accept-language, accept
< x-request-id: f7da98da675b0d35beb9fe953cba6ba1
<
* Connection #0 to host {SERVER} left intact
{
  "timestamp": "2022-07-11T22:22:01Z",
  "node": "qg1oaL-5Urqhl1DWLVLFxA",
  "request_id": "f7da98da675b0d35beb9fe953cba6ba1",
  "tokens": {
    "consumed": 0,
    "remaining": 100
  },
  "data": {
    "url": "https://packages.2600hz.com/commland/misc/compatibility/{COMPATIBILITY_HASH}"
  },
  "error": "302",
  "message": "redirect",
  "status": "error"
}
```

# Quickroutes

## About Quickroutes

Associates a number with a list of endpoints to dial, bypassing internal KAZOO call routing decisions.

For example, imagine a callflow for DID +12125551234 that does TTS(Hi there) -> User(UUID).

If a quickroute is created for +12125551234 to route a KAZOO device's ID, the caller would not hear the TTS played, and the device would immediately start ringing.

Quickroutes bypass all routing and account limiting so should only be in place for good reasons.

At the moment, quickroutes are only configurable via internal AMQP payloads and not API-controlled. However, the API can return existing quickroutes.

## Schema



## Fetch existing quickroutes for an account

> GET /v2/accounts/{ACCOUNT_ID}/quickroutes

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/quickroutes
```

```json
{
  "data": {
    "{DID}": {
      "endpoints": [
        "{DEVICE_ID}",
        "{USER_ID}"
      ]
    }
  }
}
```

# Inbound Messaging

Currently an internal-only api for inbound s/mms hooks from Trunking IO.

Supports only `POST` to `/v2/` at present.

## About Inbound Messaging

See [TIO API Docs](https://gitlab.com/oomaforbin/onsip/trunkingio-sms/-/blob/main/docs/api/messages.md?ref_type=heads) for expected schema.

## Schema




## Examples

> POST /hooks/accounts/{ACCOUNT_ID}/messaging/{CARRIER}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/inbound_messaging/{CARRIER}
```

## Internal

configure Trunking IO s/mms DIDs to send hooks to a URL in the form:
http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/inbound_messaging/trunkingio

the account ID should always be the ID of the reseller account associated with the TIO account

### Authentication

cb_inbound_messaging allows the carrier module to handle authentication. For TrunkingIO, this is
hmac validation relying on a shared secret.

### Payload creation

cb_inbound_messaging expects carrier modules to have a callback returning (mostly) valid `kapps_im`. At least these fields:
```
"From"
"To"
"Body"
"Route-Type"
"Event-Category"
```
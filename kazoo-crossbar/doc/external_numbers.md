# External Numbers

## About External Numbers

External numbers is a collection of phone numbers that the account or reseller has attested they have control over but does not route to the cluster for call processing. Once an external number has been successfully verified it can be used as a known valid caller id for that account with [STIR/SHAKEN](https://en.wikipedia.org/wiki/STIR/SHAKEN "STIR/SHAKEN") compliance.

#### Schema

Schema for an external number



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`name` | A friendly name for the external number | `string(1..128)` |   | `false` | `supported`
`number` | The external number | `string(1..30)` |   | `true` | `supported`



## Fetch

List all external numbers on an account with the verification status.

> GET /v2/accounts/{ACCOUNT_ID}/external_numbers

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers
```
```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "c124b06cd3796d191528427405a32978",
            "name": "Alice's Cellphone Example",
            "number": "+15551231111",
            "verified": true
        },
        {
            "id": "e78376b2b371318b7e3356652c344718",
            "name": "Bob's Cellphone Example",
            "number": "+15551232222",
            "verified": false
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```


## Create a new external number

Creates a new, unverified, external number. The number must be unique among the existing assigned (routable) phone numbers as well as external numbers.

> PUT /v2/accounts/{ACCOUNT_ID}/external_numbers

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"number":"+15551233333", "name": "Satellite office legacy PBX"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers
```
```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "number": "+14158867900",
        "name": "Satellite office legacy PBX",
        "attestation": {},
        "id": "e78376b2b371318b7e3356652c344718"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch an external number

Fetch the details of an external number.

> GET /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}
```
```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "name": "Test",
        "number": "+15551231111",
        "attestation": {
            "date": 63788516002,
            "token": {
                "method": "cb_user_auth",
                "source": "127.0.0.1"
            },
            "account": {
                "id": "5a5cbbc0539ccaf1c681064935213a55",
                "name": "master-account"
            },
            "user": {
                "id": "1a2d89b89c1d4a0c5677465e6d99eb2e",
                "name": "Alice Nidifugous"
            }
        },
        "id": "c124b06cd3796d191528427405a32978",
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Remove an external number

Removes and external number from the account, if it is still being used as a caller id it will no longer be marked with 'A' level STIR/SHAKEN attestation.

> DELETE /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}
```

## Create a verification code

This will send a verification code using one of three methods (by default if none are specified it will use 'voice'). The available methods are:

1. `voice` This will call the external number and play the verification code to the the person that answers the call.
2. `sms` This will send the external number an SMS containing the verification code.
3. `ivr` This will call the external number and on answer request "If you would like to allow your caller identification to be used by other phones, press one now". Pressing one will immediately validate the number. This method does not require the user to submit a verification code to complete the validation.


**NOTE:**
There is an additional property `message` that can be used to override the default prompts on a per-verification request if required. If provided for methods `voice` or `ivr`, it will replace the corresponding prompts played to the user using the cluster's configured TTS engine to convert to audio, and if used with `sms` is the resulting body of the SMS. When providing the `message` parameter it is important to include the template placeholder `{{verify.code}}` at the location the verification code should be inserted. For example:
```
{"data":{"method":"voice", "message":"The FooBar phone company has requested to use your caller id, the verification code is {{verify.code}}. Thank you for your time."}}
```

> PUT /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"method":"voice"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify
```

The returned data is different depending on the method used.

#### Request a verification code: voice reply

When using the method `voice` the response will be the relevant parameters of the call placed to the external number or an API error if the call could not be started. The API will block until the call is progressing.

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "key_value_store": {},
        "account_db": "account%2F5a%2F5c%2Fbbc0539ccaf1c681064935213a55",
        "account_id": "5a5cbbc0539ccaf1c681064935213a55",
        "authorizing_id": "5a5cbbc0539ccaf1c681064935213a55",
        "authorizing_type": "account",
        "call_bridged": false,
        "call_direction": "outbound",
        "call_id": "8294ea4dc3e3b28486d05a4cfc2ee5a5a617",
        "callee_id_name": "",
        "callee_id_number": "5551231111",
        "caller_id_name": "master-account",
        "caller_id_number": "+14158867900",
        "custom_application_vars": {},
        "custom_channel_vars": {
            "resource_type": "offnet-termination",
            "resource_id": "2e6dcfb5e177e4f251da07b28d5d744e-did_us",
            "reseller_id": "5a5cbbc0539ccaf1c681064935213a55",
            "realm": "master.sip.2600hz.dev",
            "privacy_hide_number": false,
            "privacy_hide_name": false,
            "original_number": "+15551231111",
            "matched_number": "5551231111",
            "global_resource": "true",
            "fetch_id": "39b2d3af01a77febfd97e6b5ac40effc",
            "ecallmgr_node": "ecallmgr@2600hz.dev",
            "e164_origination": "+14158867900",
            "e164_destination": "+15551231111",
            "did_classifier": "did_us",
            "channel_authorized": "true",
            "call_interaction_is_root": false,
            "call_interaction_id": "63790409961-37b1ea24",
            "account_id": "5a5cbbc0539ccaf1c681064935213a55"
        },
        "custom_sip_headers": {},
        "fetch_id": "39b2d3af01a77febfd97e6b5ac40effc",
        "from": "sip:+14158867900@master.sip.2600hz.dev",
        "from_realm": "master.sip.2600hz.dev",
        "from_user": "sip:+14158867900",
        "is_recording": false,
        "is_call_forward": false,
        "is_transfer": false,
        "language": "en-us",
        "message_left": false,
        "request": "15551231111@sip.com",
        "request_realm": "sip.com",
        "request_user": "+15551231111",
        "resource_type": "offnet-termination",
        "to": "15551231111@sip.com",
        "to_realm": "sip.com",
        "to_user": "15551231111"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Request a verification code: sms reply

When using the method `sms` the response will be have an empty success reply if the SMS was published. The API will return immediately.

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Request a verification code: IVR reply

When using the method `ivr` the response will result in the updated external number object, if the user chooses to press one then the attestation parameter will be populated. The API will return when the user terminates the call or it times out.

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "name": "Test",
        "number": "+15551231111",
        "attestation": {
            "date": 63788516002,
            "token": {
                "method": "cb_user_auth",
                "source": "127.0.0.1"
            },
            "account": {
                "id": "5a5cbbc0539ccaf1c681064935213a55",
                "name": "master-account"
            },
            "user": {
                "id": "1a2d89b89c1d4a0c5677465e6d99eb2e",
                "name": "Alice Nidifugous"
            }
        },
        "id": "c124b06cd3796d191528427405a32978",
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Claim an external number

If a user has received an external number verification code they can submit it to claim and verify they have access to the number. If the code matches what is expected the updated document is returned otherwise an API error is provided.

**NOTE:**
If an auth-token is used belonging to the master account of the cluster this request can be issued without providing a code to mark a number as verified without requiring a valid verification code.

> POST /v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"code":"1234"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/external_numbers/{EXTERNAL_NUMBER_ID}/verify
```
```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "name": "Test",
        "number": "+15551231111",
        "attestation": {
            "date": 63788516002,
            "token": {
                "method": "cb_user_auth",
                "source": "127.0.0.1"
            },
            "account": {
                "id": "5a5cbbc0539ccaf1c681064935213a55",
                "name": "master-account"
            },
            "user": {
                "id": "1a2d89b89c1d4a0c5677465e6d99eb2e",
                "name": "Alice Nidifugous"
            }
        },
        "id": "c124b06cd3796d191528427405a32978",
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

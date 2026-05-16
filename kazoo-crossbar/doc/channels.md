# Call Channels

## About Call Channels

The Channels API allows queries to find active channels for an account, a user, or a device. Given a call-id for a channel, a limited set of commands are allowed to be executed against that channel (such as hangup, transfer, or play media).

NOTE: Konami is an outdated and unsupported 2600Hz module. If you need support on this module, please ensure you are signed up for Konami Pro.

## Fetch active channels system wide.

!!! note
    For super duper admin only. Be sure to set `system_config`->`crossbar.channels`->`system_wide_channels_list` flag to `true`

> GET /v2/channels

```shell
curl -v -X GET \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/channels
```

## Fetch active channels for an account

> GET /v2/accounts/{ACCOUNT_ID}/channels

```shell
curl -v -X GET \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "answered": true,
            "authorizing_id": "{AUTHORIZING_ID}",
            "authorizing_type": "device",
            "destination": "user_zu0bf7",
            "direction": "outbound",
            "other_leg": "{CALL_ID}",
            "owner_id": "{OWNER_ID}",
            "presence_id": "user_zu0bf7@account.realm.com",
            "timestamp": 63573977746,
            "username": "user_zu0bf7",
            "uuid": "{UUID}"
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch channels for a user or device

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/channels

For user with `{USER_ID}`:

```shell
curl -v -X GET \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/channels
```

For device with `{DEVICE_ID}`:

> GET /v2/accounts/{ACCOUNT_ID}/devices/{DEVICE_ID}/channels

```shell
curl -v -X GET \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/devices/{DEVICE_ID}/channels
```

## Fetch a channel's details

> GET /v2/accounts/{ACCOUNT_ID}/channels/{UUID}

```shell
curl -v -X GET \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels/{UUID}
```

## Execute an application against a Channel

!!! note
    This API requires Konami Pro to be running and metaflows to be enabled on the call

> POST /v2/accounts/{ACCOUNT_ID}/channels/{UUID}

```shell
curl -v -X POST \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"action": "transfer", "target": "2600", "takeback_dtmf": "*1", "moh": "media_id" }}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels/{UUID}
```

Available `action` values are `transfer`, `hangup`, `break`, `callflow`, `move` and `intercept`.

### Move

```shell
curl -v -x POST \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"action": "move", "owner_id": "{OWNER_ID}", "device_id": "{DEVICE_ID}", "auto_answer": true, "can_call_self": true, "dial_strategy": "simultaneous"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels/{UUID}
```

Key | Description | Type | Default | Required

--- | ----------- | ---- | ------- | --------
`auto_answer` | Whether to auto-answer the new leg | `boolean()` | `false` | `false`
`can_call_self` | Can intercept devices of the same targeted user | `boolean()` | `true` | `false`
`device_id` | Move the call to a specific device | `string()` |   | `false`
`dial_strategy` | How to ring the endpoints, if multiple | `string()` | `simultaneous` | `false`
`owner_id` | User ID to use for finding endpoints | `string()` |   | `false`
`timeout` | Endpoint(s) call leg timeout | `int()` |   | `false`

### Transfer

```shell
curl -v -X POST \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data":{"module":"transfer","data":{"target":"2600","Transfer-Type":"blind","leg":"bleg"}},"action":"metaflow"}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels/{UUID}
```

Key | Description | Type | Default
--- | ----------- | ---- | -------
`leg` | Defines which leg of the call to take action against | `string('self' | 'bleg')` | `self`
`target` | Extension/DID to transfer the `{UUID}` | `string()` |
`transfer-type` | What type of transfer to perform | `string('attended' | 'blind')` | `blind`
`moh` | Music on hold to play while transferring | `string()` |

## Put a feature (metaflow) on a channel

!!! note
    This API requires Konami Pro to be running and metaflows to be enabled on the call

> PUT /v2/accounts/{ACCOUNT_ID}/channels/{UUID}

```shell
curl -v -X PUT \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"action":"metaflow", "data": {"data": { "module": "hangup" }}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/channels/{UUID}
```

The Metaflow feature is a `metaflow` object which validates with its corresponding JSON schema.

### Reasoning

The `POST` action requires that every Metaflow action would have to be coded into the module.

### Benefits

The Metaflow feature allows adding new types of Metaflows without changing the code.
It also allows full Metaflows and not only single actions, i.e., the `children` node is also processed.

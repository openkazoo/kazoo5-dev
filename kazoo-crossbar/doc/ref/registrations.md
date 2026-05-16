# Registrations

## About Registrations

#### Schema

Device registration information



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`account_name` | Account Name | `string()` |   | `false` |  
`account_realm` | Account SIP realm | `string()` |   | `false` |  
`authorizing_id` | Registering Device ID | `string()` |   | `false` |  
`authorizing_type` | Type of registered endpoint | `string()` |   | `false` |  
`bridge_ruri` | SIP URI used for bridging to endpoint | `string()` |   | `false` |  
`call_id` | REGISTER Call-ID | `string()` |   | `true` |  
`contact` | SIP Contact header | `string()` |   | `false` |  
`contact_ip` | Contact IP | `string()` |   | `false` |  
`contact_port` | Contact port | `integer()` |   | `false` |  
`event_timestamp` | Timestamp of registration | `integer()` |   | `false` |  
`expires` | Seconds until registration expiration | `integer()` |   | `false` |  
`first_registration` | First-seen registration | `boolean()` |   | `false` |  
`from_host` | SIP From Header Realm | `string()` |   | `false` |  
`from_user` | SIP From Header Username | `string()` |   | `false` |  
`initial_registration` | Timestamp of first registration | `integer()` |   | `false` |  
`last_registration` | Timestamp of latest registration | `integer()` |   | `false` |  
`original_contact` | Orignal SIP Contact | `string()` |   | `false` |  
`presence_id` | Presence ID | `string()` |   | `false` |  
`proxy_ip` | Registrar Proxy IP | `string()` |   | `false` |  
`proxy_path` | Registrar Proxy path | `string()` |   | `false` |  
`proxy_port` | Registrar Proxy port | `integer()` |   | `false` |  
`proxy_protocol` | Registrar Proxy protocol | `string()` |   | `false` |  
`realm` | Account SIP Realm | `string()` |   | `false` |  
`register_overwrite_notify` | Whether to overwrite NOTIFY | `boolean()` |   | `false` |  
`registrar_node` | Registrar Node name | `string()` |   | `false` |  
`source_ip` | Device source IP | `string()` |   | `false` |  
`source_port` | Device source port | `integer()` |   | `false` |  
`suppress_unregister_notify` | Should suppress Unregister notification | `boolean()` |   | `false` |  
`to_host` | SIP To Host | `string()` |   | `false` |  
`to_user` | SIP To Username | `string()` |   | `false` |  
`user_agent` | SIP User-Agent | `string()` |   | `false` |  
`username` | Device username | `string()` |   | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/registrations

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/registrations
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/registrations

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/registrations
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/registrations/{USERNAME}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/registrations/{USERNAME}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/registrations/count

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/registrations/count
```


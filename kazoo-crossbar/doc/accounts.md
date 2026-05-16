# Accounts

## About Accounts

Accounts are the container for most things in Kazoo. They typically represent an office, business, family, etc. Kazoo arranges accounts into a tree structure, where parent accounts can access their sub accounts but not their ancestor accounts.

## About the Account Tree

Since accounts can be the child of 0 or more parent accounts, it is necessary to track each account's lineage. This is tracked in the account document (`_id` = ID of the account) in the `pvt_tree` array. The order of the list is from most-ancestral to parent.

So given `"pvt_tree":["1", "2", "3"]`, it can be determined that "3" is the parent account, "2" the grand-parent, and "1" is the great-grandparent. `"pvt_tree":[]` indicates the master (or Highlander) account; there should only be one!

#### Schema

Accounts represent tenants or customers on the system. Each account represents an individual dataset or sandbox that only one tenant can access. The data set is architecturally independent from other tenants.



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`addresses` | Account addresses | [#/definitions/addresses](#addresses) |   | `false` |  
`allowed_proxy_ips.[]` |   | `string()` |   | `false` |  
`allowed_proxy_ips` | Allowed proxy ips from which user can authenticate | `array(string())` |   | `false` |  
`announcement` | The announcement will be pop up when use log in to this account | `string()` |   | `false` |  
`blacklists.[]` |   | `string()` |   | `false` |  
`blacklists` | A list blacklist ids that apply to the account | `array(string())` |   | `false` |  
`call_failover` | The device call failover parameters, to replace the device with an extension/phone number when device is offline. | [#/definitions/call_failover](#call_failover) |   | `false` |  
`call_forward` | Call forward settings | [#/definitions/call_forward](#call_forward) |   | `false` |  
`call_limits` | Schema for call limits | [#/definitions/call_limits](#call_limits) |   | `false` |  
`call_recording.account` | endpoint recording settings | [#/definitions/call_recording](#call_recording) |   | `false` |  
`call_recording.endpoint` | endpoint recording settings | [#/definitions/call_recording](#call_recording) |   | `false` |  
`call_recording` | call recording configuration | `object()` |   | `false` |  
`call_restriction` | Account level call restrictions for each available number classification | `object()` | `{}` | `false` |  
`call_waiting` | Parameters for server-side call waiting | [#/definitions/call_waiting](#call_waiting) |   | `false` |  
`caller_id` | The account default caller ID parameters | [#/definitions/caller_id](#caller_id) |   | `false` |  
`caller_id_options` | custom properties for configuring caller_id | [#/definitions/caller_id_options](#caller_id_options) |   | `false` |  
`dial_plan` | A list of default rules used to modify dialed numbers | [#/definitions/dialplans](#dialplans) |   | `false` |  
`do_not_disturb.enabled` | The default value for do-not-disturb | `boolean()` |   | `false` |  
`do_not_disturb` |   | `object()` |   | `false` |  
`enabled` | Determines if the account is currently enabled | `boolean()` | `true` | `false` | `supported`
`flags.[]` |   | `string()` |   | `false` | `supported`
`flags` | Flags set by external applications | `array(string())` |   | `false` | `supported`
`formatters` | Schema for request formatters | [#/definitions/formatters](#formatters) |   | `false` |  
`language` | The language for this account | `string()` |   | `false` | `supported`
`metaflows` | Actions applied to a call outside of the normal callflow, initiated by the caller(s) | [#/definitions/metaflows](#metaflows) |   | `false` |  
`music_on_hold.media_id` | The ID of a media object that should be used as the default music on hold | `string(0..2048)` |   | `false` |  
`music_on_hold.options.[]` |   | `string('preserve-position' \| 'random-start')` |   | `false` |  
`music_on_hold.options` | Options for playing music on hold | `array(string('preserve-position' \| 'random-start'))` |   | `false` |  
`music_on_hold` | The default music on hold parameters | `object()` | `{}` | `false` |  
`name` | A friendly name for the account | `string(1..128)` |   | `true` | `supported`
`notifications.first_occurrence.sent_initial_call` | has the account made their first call | `boolean()` | `false` | `false` |  
`notifications.first_occurrence.sent_initial_registration` | has the account registered their first device | `boolean()` | `false` | `false` |  
`notifications.first_occurrence` | send emails on these account-firsts | `object()` |   | `false` |  
`notifications.low_balance.enabled` | should the account be checked for this alert | `boolean()` |   | `false` |  
`notifications.low_balance.last_notification` | Timestamp, in Gregorian seconds, of when the last low_balance alert was sent | `integer()` |   | `false` |  
`notifications.low_balance.sent_low_balance` | has the alert been sent (avoids duplication/spamming) | `boolean()` |   | `false` |  
`notifications.low_balance.threshold` | account balance to send alert on | `number()` |   | `false` |  
`notifications.low_balance` | Low balance settings | `object()` |   | `false` |  
`notifications.media_proxy.fail_alert_enabled` | should the account produce system alert when media failed to be uploaded | `boolean()` | `true` | `false` |  
`notifications.media_proxy.last_notification` | Timestamp, in Gregorian seconds, of when the last media upload fail alert was sent | `integer()` |   | `false` |  
`notifications.media_proxy` | Media proxy settings | `object()` |   | `false` |  
`notifications` | account notification settings | `object()` |   | `false` |  
`org` | Full legal name of the organization | `string()` |   | `false` |  
`preflow.always` | The ID of a callflow to always execute prior to processing the callflow with numbers/patterns matching the request | `string()` |   | `false` |  
`preflow` | Each property provides functionality that can be applied to calls using the callflow application | `object()` | `{}` | `false` |  
`realm` | The realm of the account, ie: 'account1.2600hz.com' | `string(4..253)` |   | `false` | `supported`
`ringtones.external` | The alert info SIP header added when the call is from internal sources | `string(0..256)` |   | `false` |  
`ringtones.internal` | The alert info SIP header added when the call is from external sources | `string(0..256)` |   | `false` |  
`ringtones` | Ringtone Parameters | `object()` | `{}` | `false` |  
`timezone` | The default account timezone | [#/definitions/timezone](#timezone) |   | `false` | `supported`
`topup.amount` | Amount to topup with | `number()` |   | `false` |  
`topup.threshold` | The account balance when topup occurs | `number()` |   | `false` |  
`topup` | Topup settings for the account | `object()` |   | `false` |  
`voicemail.notify.callback` | Schema for a callback options | [#/definitions/notify.callback](#notifycallback) |   | `false` |  
`voicemail.notify` |   | `object()` |   | `false` |  
`voicemail` |   | `object()` |   | `false` |  
`zones` | A priority ordered mapping of zones for the account | `object()` |   | `false` |  

### addresses

Account, user or device addresses


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`emergency.additional_information` | Additional location information. Example: Room 543 | `string()` |   | `false` |  
`emergency.callback_cid_number` | 10-digit DID used as caller ID to PSAP, overrides CID | `string(10)` |   | `false` |  
`emergency.country` | The country is identified by the two-letter ISO 3166 code. Example: US | `string()` |   | `true` |  
`emergency.county` | County, parish, gun (JP), district (IN). Example: King's County | `string()` |   | `false` |  
`emergency.delivery_method` | How the emergency call is routed by the destination handler (not applicable to all providers) | `string('direct' \| 'three_way' \| 'security_desk')` |   | `false` |  
`emergency.floor` | Floor. Example: 4 | `integer()` |   | `false` |  
`emergency.house_number` | House number, numeric part only. Example: 123 | `integer()` |   | `true` |  
`emergency.house_number_suffix` | House number suffix. Example: A, 1/2 | `string()` |   | `false` |  
`emergency.latitude` | The geo-position of a location, north or south of the equator, using WGS84 formatting | `string(0..11)` |   | `false` |  
`emergency.locality` | City, township, shi (JP). Example: New York | `string()` |   | `true` |  
`emergency.location_identifier` | United States unique 10-digit number known as an E911 location identifier (ELIN) | `integer()` |   | `false` |  
`emergency.longitude` | The geo-position of a location, east or west of the prime meridian, using WGS84 formatting | `string(0..11)` |   | `false` |  
`emergency.name` | Name (residence, business or office occupant). Example: Joe's Barbershop | `string()` |   | `true` |  
`emergency.postal_code` | Postal code. Example: 10027-0401 | `string()` |   | `true` |  
`emergency.region` | National subdivisions (state, region, province, prefecture). Example: New York | `string()` |   | `true` |  
`emergency.street` | Primary road or street. Example: Broadway | `string()` |   | `true` |  
`emergency.street_direction` | Leading street direction. Example: N, W | `string()` |   | `false` |  
`emergency.street_suffix` | Trailing street suffix. Example: SW | `string()` |   | `false` |  
`emergency.street_type` | Street type. Example: Avenue, Platz, Street | `string()` |   | `false` |  
`emergency` | Emergency address | `object()` |   | `false` |  

### call_failover

The device call failover parameters, to replace the device with an extension/phone number when device is offline.


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`direct_calls_only` | Determines if the calls that are not directly sent to the device should be forwarded | `boolean()` | `false` | `false` | `supported`
`enabled` | Determines if the call failover should be used when device is offline | `boolean()` | `false` | `false` |  
`ignore_early_media` | The option to determine if early media from the call forwarded number should ignored | `boolean()` | `true` | `false` |  
`keep_caller_id` | Determines if the caller id is kept when the call is forwarded, if not the devices caller id is used | `boolean()` | `true` | `false` | `supported`
`number` | The number to forward calls to | `string(0..35)` |   | `false` | `supported`
`require_keypress` | Determines if the callee is prompted to press 1 to accept the call | `boolean()` | `true` | `false` |  

### call_forward

Call Forward


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`busy` | Call Forward Properties | `object()` |   | `false` |  
`direct_calls_only` |   | `boolean()` | `false` | `false` |  
`enabled` |   | `boolean()` | `false` | `true` |  
`ignore_early_media` |   | `boolean()` | `true` | `false` |  
`keep_caller_id` |   | `boolean()` | `true` | `false` |  
`no_answer` | Call Forward Properties | `object()` |   | `false` |  
`number` |   | `string(0..35)` |   | `false` |  
`require_keypress` |   | `boolean()` | `true` | `false` |  
`selective.direct_calls_only` |   | `boolean()` | `false` | `false` |  
`selective.enabled` |   | `boolean()` | `false` | `false` |  
`selective.ignore_early_media` |   | `boolean()` | `true` | `false` |  
`selective.keep_caller_id` |   | `boolean()` | `true` | `false` |  
`selective.number` |   | `string(0..35)` |   | `false` |  
`selective.require_keypress` |   | `boolean()` | `true` | `false` |  
`selective.rules.[].direct_calls_only` |   | `boolean()` | `false` | `false` |  
`selective.rules.[].enabled` |   | `boolean()` | `false` | `false` |  
`selective.rules.[].ignore_early_media` |   | `boolean()` | `true` | `false` |  
`selective.rules.[].keep_caller_id` |   | `boolean()` | `true` | `false` |  
`selective.rules.[].match_list_id` |   | `string()` |   | `false` |  
`selective.rules.[].number` |   | `string(0..35)` |   | `false` |  
`selective.rules.[].require_keypress` |   | `boolean()` | `true` | `false` |  
`selective.rules` | Match list rules to check for call forwarding | `array(object())` |   | `false` |  
`selective` | Conditionally check match lists to determine if call forwarding should be used | `object()` |   | `false` |  
`substitute` | Determines if the call forwarding replaces the device | `boolean()` | `true` | `false` |  
`unconditional` | Call Forward Properties | `object()` |   | `false` |  

### call_forward_type

Call Forward Properties


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`direct_calls_only` |   | `boolean()` | `false` | `false` |  
`enabled` |   | `boolean()` | `false` | `true` |  
`ignore_early_media` |   | `boolean()` | `true` | `false` |  
`keep_caller_id` |   | `boolean()` | `true` | `false` |  
`number` |   | `string(0..35)` |   | `false` |  
`require_keypress` |   | `boolean()` | `true` | `false` |  

### call_limits

Schema for call limits


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`max_concurrent` | Maximum number of concurrent calls allowed per endpoint | `integer()` |   | `false` |  

### call_recording

endpoint recording settings


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`any` | settings for any calls to/from the endpoint | [#/definitions/call_recording.source](#call_recordingsource) |   | `false` |  
`inbound` | settings for inbound calls to the endpoint | [#/definitions/call_recording.source](#call_recordingsource) |   | `false` |  
`outbound` | settings for outbound calls from the endpoint | [#/definitions/call_recording.source](#call_recordingsource) |   | `false` |  

### call_recording.parameters


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`enabled` | is recording enabled | `boolean()` |   | `false` |  
`format` | What format to store the recording on disk | `string('mp3' \| 'wav')` |   | `false` |  
`record_min_sec` | The minimum length, in seconds, the recording must be to be considered successful. Otherwise it is deleted | `integer()` |   | `false` |  
`record_on_answer` | Recording should start on answer | `boolean()` |   | `false` |  
`record_on_bridge` | Recording should start on bridge | `boolean()` |   | `false` |  
`record_sample_rate` | What sampling rate to use on the recording | `integer()` |   | `false` |  
`should_announce_when_recording` | Whether or not a prompt should be played (after bridge) when the call is being recorded | `boolean()` |   | `false` |  
`should_record_feature_calls` | Toggles whether to start a recording for calls to feature codes | `boolean()` | `true` | `false` |  
`time_limit` | Time limit, in seconds, for the recording | `integer(5..10800)` |   | `false` |  
`url` | The URL to use when sending the recording for storage | `string(6..)` |   | `false` |  

### call_recording.source


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`any` | settings for calls from any network | [#/definitions/call_recording.parameters](#call_recordingparameters) |   | `false` |  
`offnet` | settings for calls from offnet networks | [#/definitions/call_recording.parameters](#call_recordingparameters) |   | `false` |  
`onnet` | settings for calls from onnet networks | [#/definitions/call_recording.parameters](#call_recordingparameters) |   | `false` |  

### call_waiting

Parameters for server-side call waiting


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`enabled` | Determines if server side call waiting is enabled/disabled | `boolean()` |   | `false` |  

### caller_id

Defines caller ID settings based on the type of call being made


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`asserted.name` | The asserted identity name for the object type | `string(0..35)` |   | `false` |  
`asserted.number` | The asserted identity number for the object type | `string(0..35)` |   | `false` |  
`asserted.realm` | The asserted identity realm for the object type | `string()` |   | `false` |  
`asserted` | Used to convey the proven identity of the originator of a request within a trusted network. | `object()` |   | `false` |  
`emergency.name` | The caller id name for the object type | `string(0..35)` |   | `false` |  
`emergency.number` | The caller id number for the object type | `string(0..35)` |   | `false` |  
`emergency` | The caller ID used when a resource is flagged as 'emergency' | `object()` |   | `false` |  
`external.name` | The caller id name for the object type | `string(0..35)` |   | `false` |  
`external.number` | The caller id number for the object type | `string(0..35)` |   | `false` |  
`external` | The default caller ID used when dialing external numbers | `object()` |   | `false` |  
`internal.name` | The caller id name for the object type | `string(0..35)` |   | `false` |  
`internal.number` | The caller id number for the object type | `string(0..35)` |   | `false` |  
`internal` | The default caller ID used when dialing internal extensions | `object()` |   | `false` |  

### caller_id_options

Caller ID options for endpoints


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`format./.+/.prefix` | Prefix to add to captured group of regex | `string()` |   | `false` |  
`format./.+/.regex` | Regexp to match normalized CID and use first capture group | `string()` |   | `false` |  
`format./.+/.suffix` | Prefix to add to captured group of regex | `string()` |   | `false` |  
`format./.+/` | Format to use for the CID classification | `object()` |   | `false` |  
`format.all.prefix` | Prefix to add to captured group of regex | `string()` |   | `false` |  
`format.all.regex` | Regexp to match normalized CID and use first capture group | `string()` |   | `false` |  
`format.all.suffix` | Prefix to add to captured group of regex | `string()` |   | `false` |  
`format.all` | Format to use for all CID formatting needs (vs per-classifier) | `object()` |   | `false` |  
`format` | Object for CID formatters based on number classifiers | `object()` |   | `false` |  
`ignore_completed_elsewhere` | Suppress the completed elsewhere cause | `boolean()` |   | `false` |  
`outbound_privacy` | Determines what appears as caller id for offnet outbound calls. Values: full - hides name and number; name - hides only name; number - hides only number; none - hides nothing | `string('full' \| 'name' \| 'number' \| 'none')` |   | `false` |  
`privacy_method` | Method to use for anonymizing CID | `string('sip' \| 'none' \| 'kazoo')` |   | `false` |  
`show_rate` | Whether to show the rate | `boolean()` |   | `false` |  
`type` | Caller ID on endpoint to choose | `string('internal' \| 'external' \| 'emergency')` |   | `false` |  

### dialplans

Permit local dialing by converting the dialed number to a routable form


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`system.[]` |   | `string()` |   | `false` |  
`system` | List of system dial plans | `array(string())` |   | `false` |  

### formatters

Schema for request formatters


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`^[[:alnum:]_]+$` | Key to match in the route request JSON | `array([#/definitions/formatters.format_options](#formattersformat_options)) | [#/definitions/formatters.format_options](#formattersformat_options)` |   | `false` |  

### formatters.format_options

Schema for formatter options


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`direction` | Only apply the formatter on the relevant request direction | `string('inbound' \| 'outbound' \| 'both')` |   | `false` |  
`match_invite_format` | Applicable on fields with SIP URIs. Will format the username portion to match the invite format of the outbound request. | `boolean()` |   | `false` |  
`prefix` | Prepends value against the result of a successful regex match | `string()` |   | `false` |  
`regex` | Matches against the value, with optional capture group | `string()` |   | `false` |  
`strip` | If set to true, the field will be stripped from the payload | `boolean()` |   | `false` |  
`suffix` | Appends value against the result of a successful regex match | `string()` |   | `false` |  
`value` | Replaces the current value with the static value defined | `string()` |   | `false` |  

### metaflow

A metaflow node defines a module to execute, data to provide to that module, and one or more children to branch to


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`children./.+/` | A metaflow node defines a module to execute, data to provide to that module, and one or more children to branch to | [#/definitions/metaflow](#metaflow) |   | `false` |  
`children` | Children metaflows | `object()` |   | `false` |  
`data` | The data/arguments of the metaflow module | `object()` | `{}` | `false` |  
`module` | The name of the metaflow module to execute at this node | `string(1..64)` |   | `true` |  

### metaflows

Actions applied to a call outside of the normal callflow, initiated by the caller(s)


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`binding_digit` | What DTMF will trigger the collection and analysis of the subsequent DTMF sequence | `string('1' \| '2' \| '3' \| '4' \| '5' \| '6' \| '7' \| '8' \| '9' \| '0' \| '*' \| '#')` | `*` | `false` |  
`digit_timeout` | How long to wait between DTMF presses before processing the collected sequence (milliseconds) | `integer(0..)` |   | `false` |  
`listen_on` | Which leg(s) of the call to listen for DTMF | `string('both' \| 'self' \| 'peer')` |   | `false` |  
`numbers./^[0-9]+$/` | A metaflow node defines a module to execute, data to provide to that module, and one or more children to branch to | [#/definitions/metaflow](#metaflow) |   | `false` |  
`numbers` | A list of static numbers with their flows | `object()` |   | `false` |  
`patterns./.+/` | A metaflow node defines a module to execute, data to provide to that module, and one or more children to branch to | [#/definitions/metaflow](#metaflow) |   | `false` |  
`patterns` | A list of patterns with their flows | `object()` |   | `false` |  

### notify.callback

Schema for a callback options


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`attempts` | How many attempts without answer will system do | `integer()` |   | `false` |  
`disabled` | Determines if the system will call to callback number | `boolean()` |   | `false` |  
`interval_s` | How long will system wait between call back notification attempts | `integer()` |   | `false` |  
`number` | Number for callback notifications about new messages | `string()` |   | `false` |  
`schedule` | Schedules interval between callbacks | `array(integer())` |   | `false` |  
`timeout_s` | How long will system wait for answer to callback | `integer()` |   | `false` |  

### timezone

The default timezone


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------



## Create New Account

> PUT /v2/accounts

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"name":"child account"}}' \
    http://{SERVER}:8000/v2/accounts
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Remove an account

> DELETE /v2/accounts/{ACCOUNT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch the account doc

> GET /v2/accounts/{ACCOUNT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Patch the account doc

> PATCH /v2/accounts/{ACCOUNT_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data":{"some_key":"some_value"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "some_key":"some_value",
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Change the account doc

> POST /v2/accounts/{ACCOUNT_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data": {"billing_mode": "manual","call_restriction": {},"caller_id": {},"created": 63621662701,"dial_plan": {},"enabled": true,"is_reseller": false,"language": "en-us","music_on_hold": {},"name": "child account","preflow": {},"realm": "aeac33.sip.2600hz.com","reseller_id": "undefined","ringtones": {},"some_key":"some_value","superduper_admin": false,"timezone": "America/Los_Angeles","wnm_allow_additions": false}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "some_key":"some_value",
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Create a new child account

Puts the created account under `{ACCOUNT_ID}`

> PUT /v2/accounts/{ACCOUNT_ID}

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"name":"child account"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{CHILD_ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch the parent account IDs

> GET /v2/accounts/{ACCOUNT_ID}/parents

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/parents
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{PARENT_ACCOUNT_ID}",
            "name": "{PARENT_ACCOUNT_NAME}"
        }
    ],
    "page_size": 1,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch an account's ancestor tree

> GET /v2/accounts/{ACCOUNT_ID}/tree

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/tree
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{PARENT_ACCOUNT_ID}",
            "name": "{PARENT_ACCOUNT_NAME}"
        }
    ],
    "page_size": 1,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch the account's API key

The API key is used by the `api_auth` API to obtain an `auth_token`. This is intended for use by applications talking to kazoo and provides a mechanism for authentication that does not require storing a username and password in the application. The API key can be obtained via the accounts API's endpoint `api_key`.

> GET /v2/accounts/{ACCOUNT_ID}/api_key

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
     http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/api_key
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "api_key": "{API_KEY}"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Re-create the account's API key

If you think that your account's API key might be exposed you can create a new one with the `api_key` endpoint. Issuing a `PUT` request to this endpoint will generate a new API key for the account and will return the new key in response.

!!! note The auth token included in the request must be for an admin of the account *or* the superduper dmin. Otherwise expect a 403 Forbidden error to the request.

> PUT /v2/accounts/{ACCOUNT_ID}/api_key

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
     http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/api_key
```

And the 201 Created response:

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "api_key": "{API_KEY}"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch sibling accounts

By default a user account under an admin/reseller account can view all the other accounts under that reseller. If you would like current account only will be able to query its child accounts' sibling and not other accounts then set `allow_sibling_listing` in `system_config/crossbar.accounts` to `false`. Admin account can unrestrictedly list siblings.

> GET /v2/accounts/{ACCOUNT_ID}/siblings

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/siblings
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "descendants_count": 1,
            "id": "{ACCOUNT_ID}",
            "name": "{ACCOUNT_NAME}",
            "realm": "{ACCOUNT_REALM}"
        }
    ],
    "page_size": 1,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "start_key": "",
    "status": "success"
}
```

## Fetch all descendants of an account

This will include children, grandchildren, etc

> GET /v2/accounts/{ACCOUNT_ID}/descendants

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/descendants
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CHILD_ACCOUNT}",
            "name": "{CHILD_NAME}",
            "realm": "{CHILD_REALM}",
            "tree": [
                "{ACCOUNT_ID}"
            ]
        }
    ],
    "page_size": 1,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "start_key": "",
    "status": "success"
}
```

## Fetch immediate children of an account

> GET /v2/accounts/{ACCOUNT_ID}/children

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/children
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CHILD_ACCOUNT}",
            "name": "{CHILD_NAME}",
            "realm": "{CHILD_REALM}",
            "tree": [
                "{ACCOUNT_ID}"
            ]
        }
    ],
    "page_size": 1,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "start_key": "",
    "status": "success"
}
```

## Demote a reseller

Requires superduper admin auth token

> DELETE /v2/accounts/{ACCOUNT_ID}/reseller

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/reseller
```

## Promote a reseller

Requires superduper admin auth token

> PUT /v2/accounts/{ACCOUNT_ID}/reseller

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/reseller
```


## Move an account

An account can only be moved by a "superduper_admin" or if enabled by anyone above the desired account.

!!! note
    Kazoo does NOT support moving accounts between reseller accounts.
    You can enable that feature by editing the document `crossbar.accounts` in your `system_config` database and set the value to `tree`.

The result of a successful `move` will have `{ACCOUNT_ID}` as a child of the `to` account ID passed in the request data.

Key | Value | Description
--- | ----- | -----------
`allow_move` | enum("tree", "superduper_admin") | Who can move a sub-account

> POST /v2/accounts/{ACCOUNT_ID}/move

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"to": "{ACCOUNT_ID_DESTINATION}"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/move
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "billing_mode": "manual",
        "call_restriction": {},
        "caller_id": {},
        "created": 63621662701,
        "dial_plan": {},
        "enabled": true,
        "id": "{ACCOUNT_ID}",
        "is_reseller": false,
        "language": "en-us",
        "music_on_hold": {},
        "name": "child account",
        "preflow": {},
        "realm": "aeac33.sip.2600hz.com",
        "reseller_id": "undefined",
        "ringtones": {},
        "superduper_admin": false,
        "timezone": "America/Los_Angeles",
        "wnm_allow_additions": false
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Call recording direction

`inbound` vs `outbound` is relative to the media server in KAZOO.

For instance, Alice places a call from her device to KAZOO - `inbound` call to KAZOO.

Bob receives a call from KAZOO on his device - `outbound` call from KAZOO.

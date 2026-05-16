# Users

## About Users

Users represent just that, your users of the system. You can assign multiple devices to a user, put the user in a callflow, and all devices will ring.

#### Schema

Schema for a user



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`addresses.vcard.[].address` |   | `string()` |   | `true` |  
`addresses.vcard.[].types.[]` |   | `string()` |   | `false` |  
`addresses.vcard.[].types` |   | `array(string())` |   | `false` |  
`addresses.vcard` | Addresses list to build user's vcard | `array(object())` |   | `false` |  
`addresses` | User addresses | `object()` |   | `false` |  
`allowed_proxy_ips.[]` |   | `string()` |   | `false` |  
`allowed_proxy_ips` | Allowed proxy ips from which user can authenticate | `array(string())` |   | `false` |  
`call_failover` | The device call failover parameters, to replace the device with an extension/phone number when device is offline. | [#/definitions/call_failover](#call_failover) |   | `false` |  
`call_forward` | Call forward settings | [#/definitions/call_forward](#call_forward) |   | `false` |  
`call_limits` | Schema for call limits | [#/definitions/call_limits](#call_limits) |   | `false` |  
`call_recording` | endpoint recording settings | [#/definitions/call_recording](#call_recording) |   | `false` |  
`call_restriction` | Device level call restrictions for each available number classification | `object()` | `{}` | `false` |  
`call_waiting` | Parameters for server-side call waiting | [#/definitions/call_waiting](#call_waiting) |   | `false` |  
`caller_id` | The device caller ID parameters | [#/definitions/caller_id](#caller_id) |   | `false` |  
`caller_id_options` | custom properties for configuring caller_id | [#/definitions/caller_id_options](#caller_id_options) |   | `false` |  
`contact_list.exclude` | If set to true the device is excluded from the contact list | `boolean()` |   | `false` | `supported`
`contact_list` | Contact List Parameters | `object()` | `{}` | `false` |  
`dial_plan` | A list of rules used to modify dialed numbers | [#/definitions/dialplans](#dialplans) |   | `false` |  
`directories` | Provides the mappings for what directory the user is a part of (the key), and what callflow (the value) to invoke if the user is selected by the caller. | `object()` |   | `false` |  
`do_not_disturb.enabled` | Is do-not-disturb enabled for this user? | `boolean()` |   | `false` |  
`do_not_disturb` | DND Parameters | `object()` |   | `false` |  
`email` | The email of the user | `string(3..254)` |   | `false` | `supported`
`enabled` | Determines if the user is currently enabled | `boolean()` | `true` | `false` | `supported`
`feature_level` | The user level for assigning feature sets | `string()` |   | `false` |  
`first_name` | The first name of the user | `string(1..128)` |   | `true` | `supported`
`flags.[]` |   | `string()` |   | `false` | `supported`
`flags` | Flags set by external applications | `array(string())` |   | `false` | `supported`
`formatters` | Schema for request formatters | `object()` |   | `false` |  
`hotdesk.enabled` | Determines if the user has hotdesking enabled | `boolean()` | `false` | `false` |  
`hotdesk.id` | The users hotdesk id | `string(0..15)` |   | `false` |  
`hotdesk.keep_logged_in_elsewhere` | Determines if user should be able to login to multiple phones simultaneously | `boolean()` | `false` | `false` |  
`hotdesk.pin` | The users hotdesk pin number | `string(4..15)` |   | `false` |  
`hotdesk.require_pin` | Determines if user requires a pin to change the hotdesk state | `boolean()` | `false` | `false` |  
`hotdesk` | The user hotdesk parameters | `object()` | `{}` | `false` |  
`language` | The language for this user | `string()` |   | `false` | `supported`
`last_name` | The last name of the user | `string(1..128)` |   | `true` | `supported`
`media` | Configure audio/video/etc media options for this user | [#/definitions/endpoint.media](#endpointmedia) |   | `false` |  
`metaflows` | The device metaflow parameters | [#/definitions/metaflows](#metaflows) |   | `false` |  
`music_on_hold.media_id` | The ID of a media object that should be used as the music on hold | `string(0..128)` |   | `false` |  
`music_on_hold.options.[]` |   | `string('preserve-position' \| 'random-start')` |   | `false` |  
`music_on_hold.options` | Options for playing music on hold | `array(string('preserve-position' \| 'random-start'))` |   | `false` |  
`music_on_hold` | The music on hold parameters used if not a property of the device owner | `object()` | `{}` | `false` |  
`password` | The GUI login password | `string()` |   | `false` | `supported`
`presence_id` | Static presence ID (used instead of SIP username) | `string()` |   | `false` | `supported`
`priv_level` | The privilege level of the user | `string('user' \| 'admin')` | `user` | `false` | `supported`
`profile` | User's profile data | [#/definitions/profile](#profile) |   | `false` |  
`pronounced_name.media_id` | The ID of a media object that should be used as the music on hold | `string(0..128)` |   | `false` |  
`pronounced_name` | Name pronounced by user to introduce himself to conference members | `object()` |   | `false` |  
`require_password_update` | UI flag that the user should update their password. | `boolean()` | `false` | `false` |  
`ringtones.external` | The alert info SIP header added when the call is from internal sources | `string(0..256)` |   | `false` |  
`ringtones.internal` | The alert info SIP header added when the call is from external sources | `string(0..256)` |   | `false` |  
`ringtones` | Ringtone Parameters | `object()` | `{}` | `false` |  
`scope_restrictions.[]` |   | `string()` |   | `false` |  
`scope_restrictions` | Scope restrictions applied to this user | `array(string())` |   | `false` |  
`timezone` | User's timezone | [#/definitions/timezone](#timezone) |   | `false` | `supported`
`username` | The GUI login username - alpha-numeric, dashes, at symbol, periods, plusses, and underscores allowed | `string(1..256)` |   | `false` | `supported`
`verified` | Determines if the user has been verified | `boolean()` | `false` | `false` |  
`vm_to_email_enabled` | Determines if the user would like voicemails emailed to them | `boolean()` | `true` | `false` |  
`voicemail.notify.callback` | Schema for a callback options | [#/definitions/notify.callback](#notifycallback) |   | `false` |  
`voicemail.notify` |   | `object()` |   | `false` |  
`voicemail` |   | `object()` |   | `false` |  

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

### codecs.audio

A list of audio codecs the endpoint supports


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------

### codecs.video

A list of video codecs the endpoint supports


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------

### dialplans

Permit local dialing by converting the dialed number to a routable form


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`system.[]` |   | `string()` |   | `false` |  
`system` | List of system dial plans | `array(string())` |   | `false` |  

### endpoint.media

Schema for endpoint media options


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`audio.codecs` | A list of audio codecs the endpoint supports | [#/definitions/codecs.audio](#codecsaudio) |   | `false` |  
`audio` | The audio media parameters | `object()` | `{}` | `false` |  
`bypass_media` | Default bypass media mode (The string type is deprecated, please use this as a boolean) | `boolean() | string('auto' \| 'false' \| 'true')` |   | `false` |  
`encryption.enforce_security` | Is Encryption Enabled? | `boolean()` | `false` | `false` |  
`encryption.methods.[]` |   | `string('zrtp' \| 'srtp')` |   | `false` |  
`encryption.methods` | Supported Encryption Types | `array(string('zrtp' \| 'srtp'))` | `[]` | `false` |  
`encryption` | Encryption Parameters | `object()` | `{}` | `false` |  
`fax_option` | Is T.38 Supported? | `boolean()` |   | `false` |  
`ignore_early_media` | The option to determine if early media from the endpoint should always be ignored | `boolean()` |   | `false` |  
`progress_timeout` | The progress timeout to apply to the endpoint (seconds) | `integer()` |   | `false` |  
`video.codecs` | A list of video codecs the endpoint supports | [#/definitions/codecs.video](#codecsvideo) |   | `false` |  
`video` | The video media parameters | `object()` | `{}` | `false` |  
`webrtc` | If true, forces a WebRTC compatible SDP on the INVITE | `boolean()` |   | `false` |  

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

### profile

Defines user extended properties


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`addresses.[].address` | To specify the address | `string()` |   | `false` |  
`addresses.[].types` | To specify types of the address | `array()` |   | `false` |  
`addresses` | To specify the components of the addresses | `array(object())` |   | `false` |  
`assistant` | To specify the user's assistant | `string()` |   | `false` |  
`birthday` | To specify the birth date of the user | `string()` |   | `false` |  
`nicknames.[]` |   | `string()` |   | `false` |  
`nicknames` | To specify the text corresponding to the nickname of the user | `array(string())` |   | `false` |  
`note` | To specify supplemental information or a comment that is associated with the user | `string()` |   | `false` |  
`role` | To specify the function or part played in a particular situation by the user | `string()` |   | `false` |  
`sort-string` | To specify the family name or given name text to be used for national-language-specific sorting of the FN and N types | `string()` |   | `false` |  
`title` | To specify the position or job of the user | `string()` |   | `false` |  

### timezone

The default timezone


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/users

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "email": "user1@account_realm.com",
            "features": [
                "caller_id",
                "vm_to_email"
            ],
            "first_name": "User",
            "id": "{USER_ID}",
            "last_name": "One",
            "priv_level": "admin",
            "timezone": "America/Los_Angeles",
            "username": "user1@account_realm.com"
        },
        {
            "email": "user2@account_realm.com",
            "features": [
                "caller_id",
                "vm_to_email"
            ],
            "first_name": "User",
            "id": "{USER_ID}",
            "last_name": "Two",
            "priv_level": "user",
            "timezone": "America/Los_Angeles",
            "username": "user2@account_realm.com"
        }
    ],
    "page_size": 2,
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Create a new user

> PUT /v2/accounts/{ACCOUNT_ID}/users

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -H "Content-Type: application/json" \
    -d '{"data":{"first_name":"User", "last_name":"Three"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": true,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Remove a user

This request will return the current JSON object of the now-deleted user.

> DELETE /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": false,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

### Enhanced User deletion

Defines DELETE user extended functionality

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`object_types` | List of object types owned by the user that should also be deleted as part of the user delete process. NOTE: If "phone_numbers" is included in the list, numbers assigned to callflows owned by the user will also be released. | `array(string('phone_numbers' | 'callflow' | 'vmbox' | 'device' | 'conference' | 'faxbox' | 'media')) | string('all')` |   | `false` |




When deleting a user, a list of `object_types` could be passed either within the request body or the query string.
If object_types are included in the request, along deleting the user, the objects owned by the user that are listed
will be deleted as well. See [#/definitions/users_delete](#users_delete) for more information.

If object_types were included in the request, the API response will include a `object_types` field in the response with
a list with the objects that were tried to be deleted with the response status for each request, something like:

`[{"type": {OBJECT_TYPE}, "id": {OBJECT_ID}, "status": {RESPONSE_STATUS}}, ...]`

If any of the requests to delete an object failed, the object response will have 2 extra fields: error_code, and error_msg.

`{"type": ..., "id": ..., "status": ..., "error_code": {ERROR_CODE}, "error_msg", {ERROR_MSG}}`

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"object_types": ["callflow", "vmbox"]}}'
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": false,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "object_types": [
            {
                "type": "vmbox",
                "id": "{VMBOX_ID}",
                "status": "success"
            },
            {
                "type": "callflow",
                "id": "{CALLFLOW_ID}",
                "status": "success"
            }
        ]
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Fetch a user

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": true,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Patch a user's doc

> PATCH /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"enabled":false}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": false,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Change the user doc

This requires posting the full user's document in the request body

**Sync**: See [the documentation on device sync](#sync) for more info on `check-sync`. One can add the field `"sync": true` to the JSON document in order to attempt a `check-sync` on every registered device this user has.

> POST /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"first_name":"User","last_name":"Three","call_restriction":{},"caller_id":{},"contact_list":{},"dial_plan":{},"enabled":false,"hotdesk":{"enabled":false,"keep_logged_in_elsewhere":false,"require_pin":false},"media":{"audio":{"codecs":["PCMU"]},"encryption":{"enforce_security":false,"methods":[]},"video":{"codecs":[]}},"music_on_hold":{},"priv_level":"user","profile":{},"require_password_update":false,"ringtones":{},"verified":false,"vm_to_email_enabled":true}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "call_restriction": {},
        "caller_id": {},
        "contact_list": {},
        "dial_plan": {},
        "enabled": false,
        "first_name": "User",
        "hotdesk": {
            "enabled": false,
            "keep_logged_in_elsewhere": false,
            "require_pin": false
        },
        "id": "{USER_ID}",
        "last_name": "Three",
        "media": {
            "audio": {
                "codecs": [
                    "PCMU"
                ]
            },
            "encryption": {
                "enforce_security": false,
                "methods": []
            },
            "video": {
                "codecs": []
            }
        },
        "music_on_hold": {},
        "priv_level": "user",
        "profile": {},
        "require_password_update": false,
        "ringtones": {},
        "verified": false,
        "vm_to_email_enabled": true
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Push payload to user's devices

See [pushes.md](./pushes.md) for information about this action.

## Fetch (or create) a vCard

[vCard](https://en.wikipedia.org/wiki/VCard) is a file format typically used in emails as a form of business card. Kazoo currently generates a 3.0 compatible vCard.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/vcard

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    -H "Accept: text/x-vcard"
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/vcard
BEGIN:VCARD
VERSION:3.0
FN:User Three
N:Three;User
END:VCARD
```

## Remove the photo from the user

> DELETE /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN} \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo
```

## Fetch the user's photo, if any

Set the `Accept` header to either `application/base64` or `application/octet-stream` to retrieve the picture's contents.

If the result is successful, you will want to pipe the response into a file.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo

```shell
curl -v -X GET \
    -H "Accept: application/base64" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo
[binary data]
```

## Create or change the user's photo

Use `application/octet-stream` as the content type.

> POST /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo

```shell
curl -v -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @/path/to/image.jpg \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/photo
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {},
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

## Quickcalls

See [the quickcall](quickcall.md) docs for how to perform this action.

## QR Codes

When an account is configured to use multi-factor authentication, and uses the included TOTP/HOTP provider, a user can generate their QR code for scanning into TOTP/HOTP applications like Google Authenticator.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/qrcode

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Accept: image/png" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/qrcode
```

## User Password Strength Compliance (Admins)

By default, KAZOO is not enforcing a secure password is used. This can be changed on a per-system configuration or per-account basis.

Enforcement is implemented as a list of regular expressions.

Each regular expression should use a capture group to return a match.

Failure of the regex to match against the password indicates the password will be rejected.

### Password strength configuration

There are a few places to configure to control the password strength enforcer:

- Enabling password strength enforcer:
    - Enabling globally:
        - `sup kapps_config set_boolean auth.password should_enforce_strength true`
    - Enabling per reseller/account:
        - `sup kapps_account_config set {RESELLER_OR_ACCOUNT_ID} auth.password should_enforce_strength true`
    - To disable use same command but set it to `false`
- Preventing setting the same old password:
    - If you need to force users to not use the same password again
    - Enabling globally:
        - `sup kapps_config set_boolean auth.password should_prevent_reuse true`
    - Enabling per reseller/account:
        - `sup kapps_account_config set {RESELLER_OR_ACCOUNT_ID} auth.password should_prevent_reuse true`
    - To disable use same command but set it to `false`
- Password strength regular expressions
    - This setting is JSON object you need to set this setting directly in CouchDB or use
      Erlang shell.     - Config key: `strength_regexes`
    - Config doc id:
        - For global: database `system_config` and doc id is `auth.password`
        - For per reseller/account: database is the reseller/account database and doc id
          is `configs_auth.password`

If you change the CouchDB doc directly don't forget to flush the cache or if you changed an account directly:

```
sup kapps_config flush auth.password
sup kapps_account_config flush {ACCOUNT_ID} auth.password
```

For more info please refer to [Kazoo Auth Password](../../../core/kazoo_auth/doc/password.md) documentation.

### Example of password enforcement API rejects insecure password

> POST /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"password":"bad"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}
```

Failed response:

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
      "password": {
        "insecure": {
          "message": "The provided password is non-compliant with your account's security level",
          "cause": "password",
          "details": [
             "at least one special character is required",
             "at least one digit is required",
             "at least one upper case character is required",
             "minimum password length is 10 characters"
                                                                          ]
        }
      }
    },
    "error": "validation failed",
    "status": "failed"
}
```

## Password expiration

For system operators who wish to enforce password rotation, password expiration can be configured.

In the `system_config/crossbar` doc, set the `password_expiry_s` key to the amount of time from when a password was set that the password should be considered expired.

When this key is undefined, no password exipration check is made.

When set to a number (like 31540000 for seconds in a year) KAZOO will check the user's doc for a pvt field with the password creation timestamp:
  a. If undefined (all user docs pre-password expiry, the password is considered expired
  b. If set, add UserPasswordTimestampS to ExpiryS and compare if less than now() (less than implies expired).

If the password is considered expired, auth attempts by the user will be denied. The user's password will need to be updated via POST to the users API by an admin of the account.

A password expiration timestamp (when the password will be considered expired) and an `is_expired_expired` boolean are included on the metadata of a user fetch now:

```json
{
  "metadata": {
    "created": {DOC_CREATED},
    "id": "{DOC_ID}",
    "is_password_expired": false,
    "modified": {DOC_MODIFIED},
    "password_expiration_timestamp": {TIMESTAMP + EXPIRY}
  }
}
```

### Legacy concerns

When fetching the user's doc, if the password is considered expired, `require_password_update` will also be set in the `data` object of the user (some UIs use this to force password resets while the user is logged in).

Going forward, UIs should create a password expiration policy (say warn the user starting 10 days before expiration and force a reset by the user 3 days before expiration) to enforce changing the password before the password expires.

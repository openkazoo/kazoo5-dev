# Pushes

## About Pushes

Allows payloads to be sent to iOS/Android devices via _pusher_ application.

#### Schema

Generic endpoint's push notifications



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`alert.body` | The body of the notification | `string()` |   | `false` |  
`alert.body_key` | The key for a localized notification body | `string()` |   | `false` |  
`alert.body_params.[]` |   | `string()` |   | `false` |  
`alert.body_params` | The array of values to replace placeholders in the localized body | `array(string())` |   | `false` |  
`alert.subtitle` | The subtitle of the notification | `string()` |   | `false` |  
`alert.title` | The title of the notification | `string()` |   | `false` |  
`alert.title_key` | The key for a localized notification title | `string()` |   | `false` |  
`alert.title_params.[]` |   | `string()` |   | `false` |  
`alert.title_params` | The array of values to replace placeholders in the localized title | `array(string())` |   | `false` |  
`alert` | Alert parameters | `object()` |   | `false` |  
`apns.alert.subtitle_key` | The key for a localized notification subtitle | `string()` |   | `false` |  
`apns.alert.subtitle_params.[]` |   | `string()` |   | `false` |  
`apns.alert.subtitle_params` | The array of values to replace placeholders in the localized subtitle | `array(string())` |   | `false` |  
`apns.alert` |   | `object()` |   | `false` |  
`apns.push_type` | The type of push notification | `string('alert' \| 'background' \| 'complication' \| 'fileprovider' \| 'location' \| 'mdm' \| 'voip')` |   | `false` |  
`apns.thread_id` | The app-specific identifier for grouping related notifications | `string()` |   | `false` |  
`apns.topic` | The topic for the notification | `string()` |   | `false` |  
`apns` | APNs parameters | `object()` |   | `false` |  
`badge` | The value to set the home screen app icon badge to. `0` removes the badge | `integer()` |   | `false` |  
`call_id` | (Legacy) The call ID for a call notification | `string(1..)` |   | `false` |  
`category` | The app-specific type of notification, which corresponds to a pre-registered `UNNotificationCategory` on iOS or an intent filter launched on click on Android | `string()` |   | `false` |  
`collapse_id` | Coalesce multiple notifications matching the same ID into one | `string()` |   | `false` |  
`content_available` | Specify `true` to deliver the notification as a silent background update on iOS | `boolean()` |   | `false` |  
`content_mutable` | Specify `true` to allow a notification service app extension on iOS to modify the notification's content before delivery | `boolean()` |   | `false` |  
`data` | The custom data to include in the notification | `object()` |   | `false` |  
`fcm` | FCM parameters | `object()` |   | `false` |  
`priority` | The priority of the notification | `string('low' \| 'normal' \| 'high')` | `high` | `false` |  
`sound` | The name of a sound file to play when the device receives the notification | `string()` |   | `false` |  
`ttl` | The duration (in seconds) for which notification delivery should be retried if it fails | `integer()` |   | `false` |  



## Push

> PUT /v2/accounts/{ACCOUNT_ID}/{ENDPOINT_TYPE}/{ENDPOINT_ID}/pushes

Where:

- `{ENDPOINT_TYPE}`: users | devices
- `{ENDPOINT_ID}`: {USER_ID} | {DEVICE_ID}

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {PAYLOAD}}'
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/{ENDPOINT_TYPE}/{ENDPOINT_ID}/pushes
```

Example: Push payload to {USER_ID}'s devices. {DEVICE_ID2} is not configured for push notifications.

```
$ curl -v -X PUT \
     -H "X-Auth-Token: {AUTH_TOKEN}" \
     -d '{"data": {"alert": {"title": "title", "body": "body"}}}'
     http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/pushes

{
  ...
  "data": {
    "results": [
      {
        "device_id": "{DEVICE_ID1}",
        "status": 200,
        "message": "Success"
      },
      {
        "device_id": "{DEVICE_ID2}",
        "status": 200,
        "message": "Not push device"
      }
    ]
  },
  ...
  "status": "success"
}
```

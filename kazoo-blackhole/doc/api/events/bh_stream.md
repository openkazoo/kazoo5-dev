# Overview

A developer can use Pivot (or Callflow) to start streaming an ongoing call's raw audio to their application over Websocket.
When this stream connection is successfully established, a `stream_start` event is fired.

If the stream stops, or the call is hangup or the connection failed to disconnected for any reason, a `stream_stop` event will be fired.

For receiving these events in real-time you can subscribe to Stream events.

## Subscription Bindings Overview

Blackhole Stream event support these bindings you can subscribe into:

- `stream.start.{CALL_ID}`: Subscribes to [Stream Start](#stream-start) event
- `stream.stop.{CALL_ID}`: Subscribes to [Stream Stop](#stream-stop) event
- `stream.*.{CALL_ID}`: Subscribes to both Stream Start and Stop events

For example for binding to Stream Start event:

- `stream.start.*`: binds to all calls (existing or future) in the account for stream_start event
- `stream.start.my-call-ID-123`: binds only for the Stream event in the existing call with ID `my-call-ID-123`

### Call specific or all call Stream events

When subscribing, replace `{Call-ID}` in the binding with the existing Call-ID to receive the event for that specific call
or replace `{CALL_ID}` with wild card `*` to receive the Stream event for any call in the account.

## Stream Start

Once the WebSocket is properly established between Pivot and your server, this event fires. The event includes
the unique ID generated for this stream and if configured, the custom name for the stream. If no name was given
Pivot will generate a unique name.

To subscribe use WebSocket message (here in this example subscribes to receive the event for all call):

```json
{
  "action": "subscribe",
  "auth_token": "{AUTH_TOKEN}",
  "request_id": "{REQUEST_ID}",
  "data": {
    "account_id": "{ACCOUNT_ID}",
    "binding": "stream.start.*"
  }
}
```

### Event Data Parameters

The subscribed events will send this event message with body with the following parameters:

| Parameter        | Description                                 |
|------------------|---------------------------------------------|
| `account_id`     | The unique ID of the account for the stream |
| `call_id`        | The unique ID of the call for the stream    |
| `event_category` | Always set to `pivot`                       |
| `event_name`     | Always set to `stream_start`                |
| `stream_id`      | The unique Id of the stream                 |
| `stream_name`    | The unique name of the stream               |
|------------------|---------------------------------------------|

Example event message:

```json
{
  "action": "event",
  "subscribed_key": "stream.start.*",
  "subscription_key": "pivot.stream.start.{ACCOUNT_ID}.*",
  "name": "stream_start",
  "routing_key": "pivot.stream.start.{ACCOUNT_ID}.{CALL_ID}",
  "data": {
    "node": "{NODE}",
    "msg_id": "{MSG_ID}",
    "account_id": "{ACCOUNT_ID}",
    "app_name": "{APP_NAME}",
    "app_version": "{APP_VERSION}",
    "call_id": "{CALL_ID}",
    "event_category": "pivot",
    "event_name": "stream_start",
    "stream_id": "{STREAM_ID}",
    "stream_name": "{STREAM_NAME}"
  }
}
```

## Stream Stop

`stream_stop` fires when the stream ends. This event may include the reason for the stop
and, if applicable, any error that caused the stream to end.

To subscribe use WebSocket message (here in this example subscribes to receive the event for all call):

```json
{
  "action": "subscribe",
  "auth_token": "{AUTH_TOKEN}",
  "request_id": "{REQUEST_ID}",
  "data": {
    "account_id": "{ACCOUNT_ID}",
    "binding": "stream.stop.*"
  }
}
```

### Event Data Parameters

The subscribed events will send this event message with body with the following parameters:

| Parameter        | Description                                                                                                                             |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `account_id`     | The unique ID of the account for the stream                                                                                             |
| `call_id`        | The unique ID of the call for the stream                                                                                                |
| `error_message`  | If present indicates the stream is ended because of an error encountered during the stream, the string value provides the error message |
| `event_category` | Always set to `pivot`                                                                                                                   |
| `event_name`     | Always set to `stream_stop`                                                                                                             |
| `reason`         | The reason the stream is stopped                                                                                                        |
| `stream_id`      | The unique Id of the stream, if it is known. May be missing if the stream failed before initialization                                  |
| `stream_name`    | The unique name of the stream, if it is known. May be missing if the stream failed before initialization                                |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|

Example of a normal ending of a stream:

```json
{
  "action": "event",
  "subscribed_key": "stream.stop.*",
  "subscription_key": "pivot.stream.stop.{ACCOUNT_ID}.*",
  "name": "stream_stop",
  "routing_key": "pivot.stream.stop.{ACCOUNT_ID}.{CALL_ID}",
  "data": {
    "node": "{NODE}",
    "msg_id": "{MSG_ID}",
    "app_name": "{APP_NAME}",
    "app_version": "{APP_VERSION}",
    "account_id": "{ACCOUNT_ID}",
    "app_name": "{APP_NAME}",
    "app_version": "{APP_VERSION}",
    "call_id": "{CALL_ID}",
    "event_category": "pivot",
    "event_name": "stream_stop",
    "reason": "hangup",
    "stream_id": "{STREAM_ID}",
    "stream_name": "{STREAM_NAME}"
  }
}
```

Example of an abnormal ending of a stream:

```json
{
  "action": "event",
  "subscribed_key": "stream.stop.*",
  "subscription_key": "pivot.stream.stop.{ACCOUNT_ID}.*",
  "name": "stream_stop",
  "routing_key": "pivot.stream.stop.{ACCOUNT_ID}.{CALL_ID}",
  "data": {
    "node": "{NODE}",
    "msg_id": "{MSG_ID}",
    "app_name": "{APP_NAME}",
    "app_version": "{APP_VERSION}",
    "account_id": "{ACCOUNT_ID}",
    "app_name": "{APP_NAME}",
    "app_version": "{APP_VERSION}",
    "call_id": "{CALL_ID}",
    "error_message": "max unidirectional limit reached",
    "event_category": "pivot",
    "event_name": "stream_stop",
    "reason": "error",
    "stream_id": "{STREAM_ID}",
    "stream_name": "{STREAM_NAME}"
  }
}
```

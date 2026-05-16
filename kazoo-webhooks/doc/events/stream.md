# Pivot Stream webhook event

A developer can use Pivot (or Callflow) to start streaming an ongoing call's raw audio to their application over Websocket.
When this stream connection is successfully established, a `stream_start` event is fired.

If the stream stops, or the call is hangup or the connection failed to disconnected for any reason, a `stream_stop` event will be fired.

You can use this webhook to invoking a HTTP request hook into your application when these events are fired.

## Webhook Modifiers

_None._

## Webhook Custom Data

Stream webhook has  custom data you may use when creating or updating a hook.

| Key    |  Description                                                                                                                                                                                                                                     |
|--------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `type` | The Stream type to receive. ossible values are:<br><dl><dt>`all`</dt><dd>Sends any Stream event</dd><dt>`stream_start`</dt><dd>Only send event when a stream starts</dd><dt>`stream_stop`</dt><dd>Only send event when a stream stopped</dd><dl> |
|--------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## Stream start hook event

Once the WebSocket is properly established between Pivot and your server, this event fires. The event includes
the unique ID generated for this stream and if configured, the custom name for the stream. If no name was given
Pivot will generate a unique name.

### Event Data Parameters

The subscribed events will send this event message with body with the following parameters:

| Parameter        | Description                                 |
|------------------|---------------------------------------------|
| `account_id`     | The unique ID of the account for the stream |
| `call_id`        | The unique ID of the call for the stream    |
| `event_name`     | Always set to `stream_start`                |
| `stream_id`      | The unique Id of the stream                 |
| `stream_name`    | The unique name of the stream               |
|------------------|---------------------------------------------|

## Stream Stop

`stream_stop` fires when the stream ends. This event may include the reason for the stop
and, if applicable, any error that caused the stream to end.

### Event Data Parameters

The subscribed events will send this event message with body with the following parameters:

| Parameter        | Description                                                                                                                             |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| `account_id`     | The unique ID of the account for the stream                                                                                             |
| `call_id`        | The unique ID of the call for the stream                                                                                                |
| `error_message`  | If present indicates the stream is ended because of an error encountered during the stream, the string value provides the error message |
| `event_name`     | Always set to `stream_stop`                                                                                                             |
| `reason`         | The reason the stream is stopped                                                                                                        |
| `stream_id`      | The unique Id of the stream, if it is known. May be missing if the stream failed before initialization                                  |
| `stream_name`    | The unique name of the stream, if it is known. May be missing if the stream failed before initialization                                |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|

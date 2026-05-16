# Pivot Stream Events

During a stream, Pivot will publish some events which your application can subscribe to, using either
a WebSocket, to receive them in real-time, or through invoking HTTP request to your application.

## Receiving Pivot stream events in real-time

Your application can subscribe to Blackhole Websocket event to receive [Pivot Stream](https://docs.2600hz.com/git/2600hz/kazoo-blackhole/doc/api/events/bh_stream.md) events
in near real-time.

## Receiving Pivot stream events via HTTP request

You can add a Webhook to your account using [Webhooks API](https://docs.2600hz.com/git/2600hz/kazoo-crossbar/doc/webhooks.md) to
receive [Pivot Stream](https://docs.2600hz.com/git/2600hz/kazoo-webhooks/doc/events/stream.md) events via HTTP request to your application.

### Internal Pivot stream event through AMQP messages

Your Kazoo Erlang/OTP application and bind to these AMQP messages.

All Pivot stream events are in the `Pivot` event category.

## Stream Start

Once the WebSocket is properly established between Pivot and your server, this event fires. The event includes
the unique ID generated for this stream and if configured, the custom name for the stream. If no name was given
Pivot will generate a unique name.

```json
{
  "Account-ID": "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Call-ID": "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-ID": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-Name": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Event-Cateogry": "pivot",
  "Event-Name": "stream_start"
}
```

## Stream Stop

`stream_stop` fires when the stream ends. This event may include the reason for
the stop, and if applicable, any error that caused the stream to end.

- `Stream-ID` or `Stream-Name` maybe not present if stream failed or stopped before initialization.
- Because of the asynchronous nature of stream, the `Reason` supplied for the stop can be incorrect.
This property is only for general information
- If `Error-Message` is present that means the stream is ended because of an error. The message
may be helpful determining why the stream failed.

Example of a normal ending of a stream:

```json
{
  "Account-ID": "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Call-ID": "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-ID": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-Name": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Reason": "hangup",
  "Event-Cateogry": "pivot",
  "Event-Name": "stream_stop",
}
```

Example of an abnormal ending of a stream:

```json
{
  "Account-ID": "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Call-ID": "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-ID": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Stream-Name": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Reason": "error",
  "Error-Message": "max unidirectional limit reached",
  "Event-Cateogry": "pivot",
  "Event-Name": "stream_stop",
}
```

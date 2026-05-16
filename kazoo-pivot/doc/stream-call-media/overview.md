# Stream Call Media

Pivot can stream ongoing call audio to your server over a WebSocket connection in near real-time.
This gives you ability to process the audio however your application needs, even send it to a
third party service. Stream is used for conversational IVRs, AI assistants, real-time voice
detection and call transcription, voicemail detection, fraud detection/prevention,
voice authentication, and more.

Stream can only be used for an _ongoing_ call.

<!--
TODO: improve this, add callflow stream doc and etc....
Stream provided by Pivot is a bit different from the one provided by [Callflow Stream](https://gothub.com/2600hz/kazoo-callflow/doc/stream.md)
or other ways available in 2600Hz.

something like: The main difference is on the message type, and your application being able to send media to be played back on the call.
-->

Pivot's stream has a different interface than the similar stream capability provided
by {% BRAND_NAME %} Callflow. This document and the documentation in this section
pertains only to Pivot's Stream and it's types. Pivot's stream is only
created using the [`<Stream>`](../twiml/stream.md) term.

During a stream, Pivot will send JSON messages containing call audio and
[other call events](./websocket-messages.md) to your server. [Raw streams](#raw-audio-streams)
which do not use the JSON message format are also available.

## Unidirectional Streams

This simpler type of stream sends the Call's audio over WebSocket, but does not allow your
application to send messages back to Pivot.

In a unidirectional stream, all WebSocket messages are sent in plaintext JSON, with the
audio itself encoded in Base64 included in [`media`](./websocket-messages.md#media-message) messages.

Any detected inbound DTMF (when the caller presses a touch-tone number)
are also be sent over the WebScoket in a [`dtmf`](./websocket-messages.md#dtmf-message) message.

Pivot starts a unidirectional stream when it encounters `<Start><Stream>` in a Pivot TwiML response.
Once the stream starts, Pivot immediately continues to process the XML. If there are no remaining
instructions in the document the call will end. ALways include additional instructions
after the stream begins.

<!-- TODO link to /channels API (and konami_pro stream action??) -->
You can stop the stream by using `<Stop><Stream>` Pivot TwiML or by API. The stream automatically
closes when the call ends or your application disconnects from the WebSocket.

<!-- TODO: there is no limitation on which track can be used in bi or uni directional, like _other_ services, /end-of-bragging -->
Pivot's streams have several different options for how call audio can me mixed and sent to your
server. You can always choose what audio to receive and how to receive it in both unidirectional
and bidirectional streams.
Pivot can attach up to 4 streams to a call.

<!-- TODO Provide some example apps? it wou;d be nice to create a repo with some code examples for pivot in general -->

Here is a sample unidirectional stream:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
      <Stream name="Example" url="wss://your_application/stream" />
  </Start>
  <Say>The stream has started.</Say>
</Response>
```

Here Pivot establishes the WebSocket connection to the specified URL, and streams the call's audio to your application and
uses TTS to say the specified string from `<Play>` verb and ends the call and stream afterwards.

## Raw Audio Streams

In a [`rawAudio`](../twiml/stream.md#rawaudio) stream, messages are sent as binary audio
without the extra JSON information. There will not be [`dtmf`](./websocket-messages.md#dtmf-message)
messages in a raw stream. Otherwise, raw streams are similar to Unidirectional Streams, including
that your application will be unable to send messages back to pivot.

For example, to start a Raw Audio stream:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
      <Stream name="Example" url="wss://your_application/stream" rawAudio="true" />
  </Start>
  <Say>The stream has started and your applications receives only the raw audio in binary format.</Say>
</Response>
```

## Bidirectional Streams

In bidirectional streams, your application can send audio streams back to Pivot which are played
on the call. This enables real-time interactivity with your application. For example, a
bidirectional stream can be used to connect a call to a conversational AI assistant.

Once the connection is established and Pivot is streaming, your application can use the
same WebSocket to send audio back to Pivot, which will be played on the call.

Any detected inbound DTMF (when the caller presses a touch-tone number)
will also be sent over WebSocket in [`dtmf`](./websocket-messages.md#dtmf-message) message.

Bidirectional stream are started using `<Connect><Stream>`. Once the connection is established,
Pivot will abandon the execution of the TwiML document and end the call when the stream ends or
a party hangs up. When your application disconnects from the WebSocket, Pivot will immediately
end the call.

A call can only have one Pivot bidirectional stream attached.

Example how to start a bidirectional stream:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
 <Connect>
     <Stream url="wss://your_application/ostream" />
 </Connect>
 <Say>This verb will never execute after a bidirectional stream.</Say>
</Response>
```

Here Pivot establishes the WebSocket connection to the specified URL, and streams the call's
audio to your application. Once the stream closes or the caller hangs up, Pivot will end the
call. The `<Say>` verb will never be executed by Pivot.

<!-- provide a link to an example application (receiveing side of stream not just XML) in the future -->

## Additional Resources

- [\<Stream> Pivot TwiML Reference](../twiml/stream.md)
- [Pivot Stream WebSocket Messages Reference](./websocket-messages.md)
<!-- - [Callflow Stream](http://github.com/2600hz/kazoo-callflow/doc/stream.md), alternative way to start a stream using onlt Callflow -->
- [Metaflow Stream Actions](http://github.com/2600hz/kazoo-konami-pro/doc/stream.md) allows you to control a stream via Channels API or Metaflow
<!-- link to a example websocket application on how to use pivot stream -->

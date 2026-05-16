# Pivot Stream WebSocket Messages

During both unidirectional and bidirectional Streams, Pivot may send plain text JSON messages over
the WebSocket. During a Bidirectional Stream, your server can optionally send plain text JSON
messages back to Pivot.

During a [`raw`](./overview.md#raw-audio-streams) Stream, Pivot will not send and cannot receive
these messages.


## WebSocket messages send by Pivot

When the WebSocket connection is established, Pivot will immediately send the
[`connected`](#connected-message) and [`start`](#start-message) messages to the server, in that order.

After those messages your application can expect to receive a stream of different messages:

- `media`: Includes the Base64 encoded audio of the call.
- `dtmf`: Any detected DTMF on the call.
- `stop`: Sent to notify your server immediately before Pivot ends a stream.
- `mark`: Only used during bidirectional streams, Pivot sends this message when [`media`](#send-a-playback-media-message) from your server finishes playback.

## Messages From Pivot

Except the `connected` message, every message to your server will
include these three fields and a fourth:

| Name             | Description                                                                                                    |
|------------------|----------------------------------------------------------------------------------------------------------------|
| `event`          | Indicates message type and content. I.E. a ['start'](#start-message) message's `event` field is always `start` |
| `sequenceNumber` | A number incrementing by one each time Pivot sends a message to track message order.                           |
| `streamSid`      | The unique ID for this steam which your server should use in replies.                                          |

The fourth field matches name of the `event`, and contains fields specific to that type of message.

### Connected message

This is the first message Pivot sends after connecting to your WebSocket Server,
and contains information about the connection.
It is sent only once.

| Name             | Description               |
|------------------|---------------------------|
| `event`          | Always set to `connected` |
| `protocol`       | Always set to `Call`      |
| `version`        | Always set to `1.0.0`     |

```json
{
  "event": "connected",
  "protocol": "Call",
  "version": "1.0.0"
}
```

### Start message

Immediately after `connected`, Pivot sends this message to provide information about the stream
and call that initiated it.
It is sent only once.


| Name                           | Description                                                                                                                                                             |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `event`                        | Always set to `start`                                                                                                                                                   |
| `sequenceNumber`               | A number incrementing by one each time Pivot sends a message to track message order.                                                                                    |
| `streamSid`                    | The unique ID for this steam which your server should use in replies.                                                                                                   |
| `start`                        |                                                                                                                                                                         |
| `start.accountSid`             | The unique ID of the account the call is associated with                                                                                                                |
| `start.streamSid`              | The unique ID of the stream                                                                                                                                             |
| `start.callSid`                | The unique ID of the incoming call                                                                                                                                      |
| `start.tracks`                 | Array of strings indicating the call's media flow for the stream, possible values are `inbound`, and `outbound`                                                         |
| `start.mediaFormat`            |                                                                                                                                                                         |
| `start.mediaFormat.encoding`   | The codec used for encoding for audio in [`media`](#media) messages, configured by [`<Stream>` `audioCodec`](../twiml/stream.md#audiocodec). Possible values are `audio/L16`, and `audio/x-mulaw` |
| `start.mediaFormat.sampleRate` | Sample rate for [audio](#media), configured by [`<Stream>` `sampleRate`](../twiml/stream.md#samplerate)                                                                 |
| `start.mediaFormat.channels`   | The number of channels in the stream's [audio](#media), configured by [`<Stream>` `track`](../twiml/stream.md#track)                                                    |
| `start.customParameters`       | The custom parameters as-is set by nesting in [`<Stream>`](../twiml/stream.md#sending-custom-parameters)                                                                |


```json
{
  "event": "start",
  "sequenceNumber": "1",
  "start": {
    "accountSid": "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "callSid": "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tracks": [ "inbound" ],
    "mediaFormat": {
        "encoding": "audio/L16",
        "sampleRate": 8000,
        "channels": 1
    },
    "customParameters": {
     "FirstName": "Jane",
     "LastName": "Doe",
     "RemoteParty": "Bob",
   },
  },
  "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

### Media message

This message contains the encoded call audio. Pivot sends multiple `media`
messages during the life of the stream as audio is sent and received in the
call.

| Name              | Description                                                                                                                                                        |
|-------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `event`           | Always set to `media`                                                                                                                                              |
| `sequenceNumber`  | A number incrementing by one each time Pivot sends a message to track message order                                                                                |
| `streamSid`       | The unique ID for this steam which your server should use in replies                                                                                               |
| `media`           |                                                                                                                                                                    |
| `media.track`     | Which audio track this media is from, set by `<Stream>` parameters, see see [`track`](../twiml/stream.md#track) and [`audioMix`](../twiml/stream.md#audiomix) `inbound`, `outbound` or `both`    |
| `media.chunk`     | A number, starting at 1 and incrementing every media message to track order                                                                                        |
| `media.timestamp` | The time in seconds since Pivot opened the connection to your server                                                                                                |
| `media.payload`   | A Base64 encoding of the raw audio. May include inbound, outbound, or both [tracks](../twiml/stream.md#track) on [one or two channels](../twiml/stream.md#audiomix) |


```json
{
 "event": "media",
 "sequenceNumber": "3",
 "media": {
   "track": "outbound",
   "chunk": "1",
   "timestamp": "5",
   "payload": "no+JhoaJjpz..."
 } ,
 "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

### Stop message

Sent at the end of stream, indicating the stream is ended before disconnecting.



| Name               | Description                                                                         |
|--------------------|-------------------------------------------------------------------------------------|
| `start.accountSid` | The unique ID of the account the call is associated with                            |
| `stop.callSid`     | The unique ID of the incoming call                                                  |


```json
{
 "event": "stop",
 "sequenceNumber": "5",
 "stop": {
    "accountSid": "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "callSid": "CAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  },
  "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

### DTMF message

Sent anytime the Pivot receives DTMF from the caller (inbound track).

| Name             | Description                                                                         |
|------------------|-------------------------------------------------------------------------------------|
| `event`          | Always set to `dtmf`                                                                |
| `sequenceNumber` | A number incrementing by one each time Pivot sends a message to track message order |
| `streamSid`      | The unique ID for this steam which your server should use in replies                |
| `dtmf.track`     | Always `inbound_track`, pivot does not send DTMF from the callee (outbound track)   |
| `dtmf.digit`     | The detected DTMF number as string                                                  |

```json
{
  "event": "dtmf",
  "streamSid":"MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "sequenceNumber":"5",
  "dtmf": {
      "track":"inbound_track",
      "digit": "1"
  }
}
```

### Mark message


Sent only on __bidirectional Pivot streams__, indicating the playback media you sent to Pivot is played on the call. See [Playing media on the call](#play-media-on-the-call).


This message will be sent either on:

- When the playback media is finished playing on the call
- Your server [cleared](#clear-the-buffered-media) the playback media buffer
- The stream is ended

| Name             | Description                                                                                              |
|------------------|----------------------------------------------------------------------------------------------------------|
| `event`          | Always set to `mark`                                                                                     |
| `sequenceNumber` | A number incrementing by one each time Pivot sends a message to track message order                      |
| `streamSid`      | The unique ID for this steam which your server should use in replies                                     |
| `mark.name`      | The mark name used by the `mark` message your server sent to Pivot (or set to `unknown` if not provided) |

```json
{
  "event": "mark",
  "sequenceNumber": "4",
  "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "mark": {
    "name": "my label"
  }
}
```

## Messages from your Server

During a bidirectional stream, your server can send messages back to Pivot. There are multiple
message types, but all of them are for sending audio and controlling playback on the call.

- `media`: Streams of the playback media. Audio from `media` messages is not played immediately.
Instead, it is buffered until Pivot receives a `mark` message.
- `mark`: When pivot receives this message, all buffered audio is played on the call.
- `clear`: Pivot discards all buffered audio when it receives a `clear` message.

On a unidirectional or `raw` stream, Pivot will ignore any messages it receives through the connection.

### Playing Call Media

To initiate playback, send a [`media`](#send-a-playback-media-message) message to Pivot.
Your server may break audio files up into as many separate `media` messages as needed to send
the complete file,
similar to how Pivot sends audio one chunk at a time to you during a stream. Pivot
will not immediately play audio received through `media` messages. Instead, it buffers audio
until it receives a [`mark`](#send-a-mark-message-to-play-the-media-on-the-call)
message. Once Pivot receives `mark`, it immediately plays the audio buffer to the call.

If you want to cancel the current buffered media for any reason, you may send a
[`clear`](#clear-the-buffered-media) message. Pivot will clear all buffered
media messages.

Once Pivot starts playback of your audio after receiving `mark`, it starts
a new audio buffer. Additional `media` messages will be on the new `buffer`,
and will not play until another `mark` message is received. If Pivot is still
playing audio from the first buffer when it receives the second `mark` message,
Pivot will wait until playback of the first buffer completes before playing audio
from the second buffer.

A `clear` message will only clear media from the current active buffer. Once a `mark`
is received and audio is queued for playback, it cannot be cleared. Additionally a
`clear` message will not cancel playback of audio currently being played on the call.
In other words, only `media` messages from after the most recent `mark` message received
by Pivot can be cleared.

### Send Media to Pivot's Buffer

<!-- TODO write this, add properties table -->

The first `media` message from your server __MUST__ include the audio encoding format.
Pivot will only begin buffering audio after the encoding is specified. Once Pivot
receives a `media` message with an `encoding`, messages without an `encoding` will be
buffered. Before then, these messages are ignored entirely.

After each `mark` message you send to Pivot, you must again specify the encoding
of the new media stream. Pivot supports `audio/mp3` and `audio/wav` encoding. The
actual raw audio data must be sent using Base64.

The `encoding` format cannot be changed within one buffer.

The sample rate of your media can be arbitrary. Pivot will resample if necessary.


| Name                    | Description                                                                                                      |
|-------------------------|------------------------------------------------------------------------------------------------------------------|
| `event`                 | Always use `media` when sending `media` messages                                                                 |
| `streamSid`             | The unique ID for this steam. Your server receives the `streamSid` in all of Pivot's messages (except `connect`) |
| `media.payload`         | Base64 audio of the media to be buffered                                                                         |
| `media.format.encoding` | The encoding format of the media, required in the first message. Values include: `audio/mp3` and `audio/wav`     |


Media message at the start of a new buffer:

```json
{
  "event": "media",
  "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "media": {
    "payload": "a3242sa...",
    "format": { "encoding": "audio/mp3" }
  }
}
```

Subsequent media messages before ending the buffer with `mark`:

```json
{
  "event": "media",
  "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "media": {
    "payload": "a3242sa..."
  }
}
```

### Mark Audio for Pivot Playback

When Pivot receives a mark message it closes the current audio buffer and
queues it for playback. If Pivot is not already playing media from your server,
audio from the current buffer is played immediately.

Once playback completes, Pivot sends back a `mark` message with the `name` specified
in your mark message. If you did not specify a `name`, Pivot will use `unknown` for the
name.

| Name        | Description                                                                                                      |
|-------------|------------------------------------------------------------------------------------------------------------------|
| `event`     | Always use `mark` when sending `mark` messages                                                                   |
| `streamSid` | The unique ID for this steam. Your server receives the `streamSid` in all of Pivot's messages (except `connect`) |
| `mark.name` | Optional, the name of the media. Pivot sends this back in a `mark` message once playback completes.              |

```json
{
 "event": "mark",
 "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
 "mark": {
   "name": "my label"
 }
}
```

### Clear the buffered media

Clears any buffered media.

When Pivot receives a `clear` message, any actively buffering media is deleted. Sending
a `clear` message after a `mark` message will not cancel playback, even if the audio is
not yet playing.


| Name        | Description                                                                                                      |
|-------------|------------------------------------------------------------------------------------------------------------------|
| `event`     | Always use `clear` when sending `clear` messages                                                                 |
| `streamSid` | The unique ID for this steam. Your server receives the `streamSid` in all of Pivot's messages (except `connect`) |

```json
{
 "event": "clear",
 "streamSid": "MZXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
}
```

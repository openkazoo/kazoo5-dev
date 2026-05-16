# \<Stream>

Stream an active call's audio from Pivot to your server through WebSockets in real time.


## Overview

`<Stream>` let you access the raw audio of a call, for further processing by your application.
The Audio is encoded in `audio/L16` (commonly known as 16 bit linear PCM) by default.


See [Stream Call Media](../stream-call-media/overview.md) to learn more about Pivot's messages
through the WebSocket. This page is reference for the `<Stream>` term.

Pivot TwiML supports multiple ways create a media stream:

1. Using `<Start><Stream>` to create a unidirectional Stream, which only sends audio to
your server without allowing your application to send messages back over WebSocket. The messages
are in JSON format with raw audio encoded as Base64. After the stream started, Pivot will immediately
continue to process the rest of TwiML document. If Stream is the last term, the call will end.
2. In unidirectional streams, it is possible to receive only raw Audio as binary, by setting
 `<Start><Stream rawAudio="true">`.
3. If your application needs to play media back on the call, `<Connect><Stream>` allows you
to create a bidirectional Stream. Here after the stream started, Pivot will abandon the execution of
the TwiML document and end the call when the stream ends or a party hangs up.


Here is a simple example of creating unidirectional stream:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
      <Stream name="Example" url="wss://your_application/stream" />
  </Start>
  <Say>The stream has started.</Say>
</Response>
```

This instructs Pivot to send the current call audio in near real-time to your WebSocket server
at `wss://your_application/stream` address.

Be sure to include other instructions after a unidirectional stream since pivot
immediately continues processing the rest of TwiML document. In this example,
`<Say>` will execute, then the call will end and the stream will close.

<!-- TODO link to /channels API (and konami_pro stream action??) -->

Unidirectional streams can be closed using `<Stop><Stream>`. All stream can be closed by API
and are always closed when a call ends.

This next example shows a bidirectional stream:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
 <Connect>
     <Stream url="wss://your_application/ostream" />
 </Connect>
 <Say>This verb will never execute after a bidirectional stream.</Say>
</Response>
```

<!-- TODO link to /channels API (and konami_pro stream action??) -->
In this example, the stream is started in bidirectional mode and your application can send playback media to Pivot
over same WebSocket connection to be played on the call. The only way to stop the stream is either using API, if
the call is hangup, or your WebSocket server disconnects.

## Attributes

`<Start><Stream>` noun has the following attributes:

| Name                          | Values Description                                                                                         | Default value            |
|-------------------------------|------------------------------------------------------------------------------------------------------------|--------------------------|
| [`url`](#url)                 | Optional, a relative, or absolute URL to stream the audio to                                               | Pivot TwiML document URL |
| [`audioCodec`](#audiocodec) | Specifies the audio encoding of the stream. Optional.                                                      | `pcm`                    |
| [`audioMix`](#audiomix)       | Specifies the audio channel of the stream. Optional.                                                       | `mono`                   |
| [`id`](#id)                   | Only used with `<Stop><Stream>`, identifies the attached stream to stop by its unique stream ID. Optional. | none                     |
| [`name`](#name)               | Your custom unique friendly name to identify the stream. Optional.                                         | Randomly generated       |
| [`rawAudio`](#rawaudio)       | Specifies to send the raw audio instead of encoded as Base64 in a JSON format. Optional.                   | `false`                  |
| [`sampleRate`](#samplerate)   | Specifies the audio sample rate of the stream. Optional.                                                   | `8000`                   |
| [`track`](#track)             | Specifies what side of the call's audio to stream. Optional.                                               | `inbound_track`          |


### `url`
<!-- HEY THIS SHOULD CHANGE WSS -->
This is the URL that Pivot uses to establish the WebSocket connection and stream the audio. This can be an absolute or relative URL.
The relative value will be relative to the current TwiML document being processed. If missing the current TwiML document URL will be used.

If relative or missing, a secure WebSocket URL (`wss`) will be assumed. We highly recommend using secure `wss` with absolute URLs.

Any string query and fragment will discarded from the URL. See [Sending Custom Parameters](#sending-custom-parameters) on how to include extra custom parameters instead.

### `audioCodec`

Specifies the audio codec you want to get in the stream. Default values is `pcm`.

Pivot supports to major audio codecs,
[PCM](https://en.wikipedia.org/wiki/Pulse-code_modulation) and
[G.711 μ-law](https://en.wikipedia.org/wiki/G.711#%CE%BC-law).

Possible `audioCodec` values are:

- `pcm`: This will set audio codec of the stream to PCM (also known as L16), you
  may choose the [sample rate](#samplerate) and [audio channels/mix](#audiomix)
  using attributes.
- `pcm16`: This is a shortcut for
  `audioCodec="pcm" sampleRate="24000" audioMix="mono"`, any extra `sampleRate`
  and `audioMix` attributes will be ignored. This settings is commonly used by
  AI and/or Machine Learning service providers.
- `g711_ulaw`: This sets the audio codec to G.711 μ-law (Commonly known as PCMU)
  and sets `sampleRate` to `8000` and `audioMix` to `mono`. Any `sampleRate` and
  `audioMix` attributes will be ignored.
- `pcmu`: Same as `g711_ulaw`

### `audioMix`

This attribute along with the[`track`](#track) attribute control how the audio that is being transmitted to your server is encoded.

This attribute will be ignored if [`audioCodec`](#audiocodec) is not `pcm`.

Available options are: `mono` and `stereo`.

When `mono`, the stream's audio is on a single channel, regardless of the value of [`track`](#track).

When `stereo`, the stream's audio will on 2 channels. The outbound track will be on the left channel,
and the inbound track will be on the right channel.



### `id`

Each stream will have a unique identifier, generated by 2600Hz. Pivot will provide this ID over WebSocket to your application
which then can be used to stop the stream.

<!-- TODO link to /channels API (and konami_pro stream action??) -->
This attribute is used with `<Stop><Stream>` or when using API to stop the stream.

When no `id` or [`name`](#name) is provided, `<Stop><Stream>` will stop all streams attached to the call.

See [When a stream stops](#when-a-stream-stops) for more detail.

### `name`

This is an optional attribute to give the stream a unique name. You may use this name or the stream [`id`](#id)
generated by 2600Hz to stop the stream.

The name must be unique on the current call.

If name is missing a random text will be generated and used. The name will be send over in `start` message.

When no `id` or [`name`](#name) is provided, `<stop><Stream>` will stop all streams attached to this call.

### `rawAudio`

Unidirectional streams created using `<Start><Stream>` can have this optional attribute to request that
Pivot send the raw call's audio in binary instead of encoding in Base64 format in a JSON format message.

This option only available in unidirectional streams and when used no
[`dtmf`](../stream-call-media/websocket-messages.md#dtmf-message) message will be sent.
See [Raw Audio Streams](../stream-call-media/overview.md#raw-audio-streams) for further information.

### `sampleRate`

Specifies what sample rate to use to encode the audio of the stream. The value must be divisible by `8000`,
like `8000`, `16000`.

This attribute will be ignored if [`audioCodec`](#audiocodec) is not `pcm`.

You may use short value of `8k` or `16k`. Defaults to `8000`.

### `track`

Specifies which track of the call to be streamed. Accepted values are: `inbound_track`, `outbound_track`
and `both_tracks`. Default is `inbound_track`.

Track is a property of the call, and means where the audio in a call originated from
{% BRAND_NAME %}'s perspective.

If the audio is from the caller, that audio is
_inbound_ into 2600Hz. If the 2600Hz is transmitting the audio to the caller (like when playing a beep, a media,
a TTS or the audio from the callee's device), then this is _outbound_ track.

When using `both_tracks` you will receive both inbound and outbound tracks.

When using both `track` and [`audioMix`](#audioMix), how the track sounds are combined depends on the `audioMix` value:

- `mono`: Th tracks are combined on one audio channel.
- `stereo`: Audio has 2 channels, with inbound track on the right channel and outbound track on the left channel.

## Nesting

`<Stream>` only accepts `Parameter` as nesting nouns.

`<Stream>` can only be nested under `<Start>`, `<Stop>` and `<Connect>`.

### Sending Custom Parameters

On stream start, it is possible to define some custom parameters to be send to your server over WebSocket.

For example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
      <Stream name="Example" url="wss://your_application/stream">
        <Parameter name="caller_name" value="Jane Doe" />
        <Parameter name="caller_number" value="+18005550199" />
      </Stream>
  </Start>
  <Say>The stream has started.</Say>
</Response>
```

## When a stream stops

There a few different ways a stream can be stopped:

<!-- TODO link to /channels API (and konami_pro stream action??) -->
1. An error occurs during start of stream, or while stream was in progress
2. The call a stream is on ends
3. Stop is requested via an API call
4. `<Stop><Stream>` is used in a unidirectional stream
4. Your application ends the WebSocket connection

When no `id` or [`name`](#name) is provided, `<stop><Stream>` will stop all streams attached to this call.

For example in a unidirectional stream, you may start and stop the stream by:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
      <Stream name="Example" url="wss://your_application/stream" />
  </Start>
  <Say>The stream has started.</Say>
  <Stop>
      <Stream name="Example" url="wss://your_application/stream" />
  </Stop>
  <Play>https://awesome.cool/happy.mp3</Play>
</Response>
```

Since processing of TwiML immediately continues after stream is started, the WebSocket will receive the audio for the `<Say>` verb
and not the audio from `<Play>` verb.

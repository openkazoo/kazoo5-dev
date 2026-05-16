# Pivot

## About Pivot

Execute an HTTP request to a web server about the call, expecting more callflow instructions in the response.

#### Schema

Validator for the Pivot callflow element



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`cdr_url` | Optional URL to send the CDR to at the end of the call | `string(7..)` |   | `false` |  
`custom_request_headers./^[x|X]-/` | Include a custom X- header | `string()` |   | `false` |  
`custom_request_headers` | Custom HTTP X- headers to be included on each Pivot request to the voice_url | `object()` |   | `false` |  
`debug` | Store debug logs related to processing this Pivot call | `boolean()` | `false` | `false` |  
`method` | What HTTP verb to send the request(s) with | `string('get' \| 'post' \| 'GET' \| 'POST')` | `get` | `false` |  
`req_body_format` | What format should the request body have when using POST | `string('form' \| 'json')` | `form` | `false` |  
`req_format` | What format of Pivot will the your server respond with | `string('kazoo' \| 'twiml')` | `kazoo` | `false` |  
`req_timeout_ms` | How long, in milliseconds, to wait for a Pivot response from the HTTP server | `integer(..5000)` |   | `false` |  
`serverless.flow_doc` | Execute this serverless Pivot flow without making a request to a server. It can be either a valid PivotML or valid Callflow object | `string(1..) | object()` |   | `true` |  
`serverless.flow_type` | Specifies the type of Pivot flow | `string('application/json' \| 'application/xml' \| 'text/xml')` |   | `true` |  
`serverless` | Use provided Pivot flow without requiring an external server to execute | `object()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`voice_url` | What URL to request the initial Pivot callflow | `string(7..)` |   | `false` |  






##### TwiML

TwiML support is limited at the moment; KAZOO JSON is highly encouraged.

!!! note
    `cdr_url` is only applicable when using the XML (TwiML) format. When using the kazoo format, control is handed off to the Callflows app, with the Pivot process ending (and nothing waiting for the CDR). Instead, please use [webhooks](/applications/webhooks/doc/README.md) (specifically the CHANNEL_DESTROY event) to receive CDRs.

## Handling failures

The Pivot request can fail for a number of reasons:

* DNS resolution of the web server fails
* Connection (TLS or clear) to the web server fails
* Response is not of a known `content-type`
* Response is not valid callflow JSON

The pivot callflow action waits until either
  1. The Pivot response is processed successfully, in which case the pivot callflow action exits quietly
  2. The Pivot response fails (for whatever reason), in which case the pivot callflow action goes to the default `_` child branch (if any).

In the example below, if an error occurs when getting a response from `{SERVER_URL}`, the caller will hear the media at `{MEDIA_ID}` played and the call will end.

```json
"flow": {
    "data": {
        "method": "GET",
        "req_timeout": "5",
        "req_format": "kazoo",
        "voice_url": "{SERVER_URL}"
    },
    "module": "pivot",
    "children": {
        "_": {
            "module": "play",
            "data": {
                "id": "{MEDIA_ID}"
            },
            "children": {}
        }
    }
}
```

## Basic Serverless feature

Often time you may just need to provide the PivotML to be executed without requiring the running up a web server. It is highly expected that you use regular native Callflow, but
it is understandable there may be a circumstances that you really need to use PivotML, e.g. for example as interim to convert your application from PivotML/TwiML to fully using Callflow.

Pivot features a very basic serverless functionality, you can just save the Pivot flow as data and Pivot will use that flow instead of making a HTTP request to voice URL.
You must provide a valid PivotML. The `flow_doc` may be valid Callflow Object too but it is __strongly__ suggested to actually create and use a normal Callflow doc for this propuse. Remember
that Pivot will return the flow back to Callflow application and will go down and using Callflow Object with serverless Pivot is useless.

You may use `serverless` field to add the Pivot flow:

```json
"flow": {
    "data": {
        "method": "GET",
        "req_timeout": "5",
        "req_format": "kazoo",
        "serverless": {
            "flow_doc": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response><Say>Hello world!</Say></Response>",
        },
        "voice_url": "{SERVER_URL}"
    },
    "module": "pivot"
}

```

The `serverless` field will accept these fields:

- `flow_doc`: __Required__, A valid PivotML as string or a valid Callflow Object as JSON (or string).
- `flow_type`: _Optional_, Specifies the type of serverless Pivot flow doc, defaults to try and detect the type based on provided flow doc

Using `serverless` field and `voice_url` is mutually exclusive, meaning you only can use either `serverless` or you can only use `voice_url`.

When serverless Pivot flow is set, the flow doc will be sent to Pivot application as-is, any further validations will be handled by Pivot application itself.

Using serverless, special care must be taken to use full URL anywhere that expects an action URL or any kind of URL, there is no `voice_url` in serverless
to use as base to resolve a relative URL.

Some PivotML verbs like `<Redirect>`, `<Dial>`, `<Record>` and `<Gather>` will execute a HTTP request to get more instructions to continue. These verbs will
not be executed a serverless fashion and you are expected to provide a valid and working full URL that returns more instructions. If there is no
URL provided in these verbs Pivot will end the call.

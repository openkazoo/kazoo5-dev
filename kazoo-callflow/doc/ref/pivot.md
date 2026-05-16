## Pivot

### About Pivot

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




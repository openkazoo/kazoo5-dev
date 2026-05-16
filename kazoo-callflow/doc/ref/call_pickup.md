## Call Pickup

### About Call Pickup

#### Schema

Validator for the call_pickup callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`target_call_id` | The existing call-id to connect to the caller | `string(1..)` |   | `false` |  




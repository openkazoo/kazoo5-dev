## Branch Variable

### About Branch Variable

#### Schema

Validator for the branch_variable callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | if using the doc scope, a doc id is required | `string()` |   | `false` |  
`scope` | specifies where the variable is defined | `string('account' \| 'custom_channel_vars' \| 'device' \| 'merged' \| 'user' \| 'doc')` | `custom_channel_vars` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`variable` | specifies the name or path to the variable that should be looked up | `string() | array(string())` |   | `true` |  




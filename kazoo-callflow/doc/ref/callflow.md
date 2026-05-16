## Callflow

### About Callflow

#### Schema

Validator for the callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`doc_id` | A document ID of an allowed document to store a callflow ID | `string()` |   | `false` |  
`flow` | A callflow node defines a module to execute, data to provide to that module, and zero or more children to branch to | [#/definitions/callflows.action](#callflowsaction) |   | `false` |  
`id` | The Callflow ID to branch to | `string()` |   | `false` |  
`path` | The name or path to the variable that should be looked up | `string() | array(string())` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  

### callflows.action

Call flows describe steps to take in order to process a phone call. They are trees of information related to a phone call such as "answer, play file, record file" etc. that are logically grouped together and ordered.


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`children./.+/` | Call flows describe steps to take in order to process a phone call. They are trees of information related to a phone call such as "answer, play file, record file" etc. that are logically grouped together and ordered. | [#/definitions/callflows.action](#callflowsaction) |   | `false` |  
`children` | Children callflows | `object()` |   | `false` |  
`data` | The data/arguments of the callflow module | `object()` | `{}` | `true` |  
`module` | The name of the callflow module to execute at this node | `string(1..64)` |   | `true` |  




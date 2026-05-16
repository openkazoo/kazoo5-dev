## Branch Variable

### About Branch Variable

Branch the callflow based on the configured variable (if it exists)

#### Schema

Validator for the branch_variable callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | if using the doc scope, a doc id is required | `string()` |   | `false` |  
`scope` | specifies where the variable is defined | `string('account' \| 'custom_channel_vars' \| 'device' \| 'merged' \| 'user' \| 'doc')` | `custom_channel_vars` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`variable` | specifies the name or path to the variable that should be looked up | `string() | array(string())` |   | `true` |  






### Usage / Example  

Example (specifying document id): 
```
{
  module: "branch_variable",
  data: {
    scope: "doc",
    id: "doc_id_xyz",
    variable: "path.to.field"
  },
  children: {
    true: {
      module: "tts",
      data: { text: "this will play if path.to.field is true" }
    },
    false: {
      module: "tts",
      data: { text: "this will play if path.to.field is false" }
    },
    _: {
      module: "tts",
      data: { text: "this will play if path.to.field is neither true or false. it can be undefined or any other value" }
    }
  }
}
```

Example (using "authorizing document"): 
```
{
  module: "branch_variable",
  data: {
    scope: "user",
    variable: "path.to.field"
  },
  children: {
    true: {
      module: "tts",
      data: { text: "this will play if path.to.field is true" }
    },
    false: {
      module: "tts",
      data: { text: "this will play if path.to.field is false" }
    },
    _: {
      module: "tts",
      data: { text: "this will play if path.to.field is neither true or false. it can be undefined or any other value" }
    }
  }
}
```




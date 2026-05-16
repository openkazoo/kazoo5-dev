## Callflow

### About Callflow

Branches the current call to another callflow.

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






### Usage / Example  

There are three separate use-cases for the `callflow` module:  
1. Redirect to another callflow by ID  
2. Lookup a path to an ID in another document and redirect to that callflow ID  
3. Provide an flow to branch to (with a fallback if that flow is never answered)  

#### Scenario 1  

> Redirect to another callflow by ID  

```
{
  module: "callflow",
  data: {
    id: "id_of_another_callflow"
  }
}
```


#### Scenario 2  

> Lookup a path to an ID in another document and redirect to that callflow ID    

A `user`'s document may look like:  
```
{
  id: "userid123",
  favorite_callflow_id: "callflowid123",
  ...(more info such as first_name, last_name, etc)
}
```

So the `callflow` module would look like:  
```
{
  module: "callflow",
  data: {
    doc_id: "userid123",
    path: "favorite_callflow_id"
  }
}
```
To access nested paths, two formats are supported `array` and `dot delimited string`.

```
{
  id: "userid123",
  "somekey": {
    favorite_callflow_id: "callflowid123",
  },
  ...(more info such as first_name, last_name, etc)
}
```

##### array

```
["somekey", "favorite_callflow_id"]
```

##### dot delimeted path

```
somekey.favorite_callflow_id
```

#### Scenario 3  

> provide a flow to branch to (with a fallback if that flow is never answered)  

```
{
  module: "callflow",
  data: {
    flow: {
      module: 'tts',
      data: {
        text: "This is said FIRST"
      },
      children: {
        _: {
          module: 'tts',
          data: {
            text: "This is said SECOND"
          }
        }
      }
    }
  },
  children: {
    _: {
      module: 'tts',
      data: {
        text: "This is said LAST"
      }
    }
  }
}
```

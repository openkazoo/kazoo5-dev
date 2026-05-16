# Fax Detect

Fax Detect allows the detection of an incoming fax and branches the callflow accordingly.

#### Schema

Validator for the fax_detect callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`duration` | How long, in seconds, to try detecting fax tones | `integer()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  






## Example

```
"data": {
    "duration": DURATION
}
```

The `DURATION` is the number of seconds the detection lasts, default is 3.
if the detection fails, it defaults to `voice`

## Branching

Fax detect action has 2 branch values for children: `ON_VOICE` and `ON_FAX`.

For example, a callflow for a user that would like to receive faxes:

```js
{"numbers":["{USER_DID}"]
 ,"name":"User A Callflow"
 ,"flow":{
   "module":"fax_detect"
   ,"data":{"duration":3}
   ,"children":{
     "ON_FAX":{
       "module":"faxbox"
       ,"data":{"id":"{FAXBOX_ID}"}
     }
     ,"ON_VOICE":{
       "module":"user"
       ,"data":{"id":"{USER_ID}"}
       ,"children":{
         "_":{
           "module":"voicemail"
           ,"data":{"id":"{VMBOX_ID}"}
         }
       }
     }
   }
 }
}
```

## Doorman

### About Doorman

1. Prompts the caller to record name and purpose for the call
2. Dials the configured device/user
3. Plays the caller's recording and prompts whether to
  a. accept the call
  b. accept and record the call
  c. send caller to voicemail
  d. hangup the call

#### Schema

Validator for the doorman callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`call_timeout` | How long to ring the callee | `integer()` | `30` | `false` |  
`caller_greeting` | Greeting played to caller to inform her/him about name/purpose recording | `string()` | `Hi. Please state your name after the tone.` | `false` |  
`caller_id_name` | Custom Caller ID Name to denote the doorman is calling | `string()` | `Doorman` | `false` |  
`failover_strategy` | The failover strategy to use if the callee does not answer or hangs up without choosing an option | `string('hangup' | 'voicemail')` | `hangup` | `false` |  
`id` | The KAZOO device or user ID | `string()` |   | `true` |  
`max_menu_attempts` | The max number of doorman menu repetitions in case of callee's wrong choice | `integer()` | `3` | `false` |  
`origin` | Read-only setting if the call is recorded | `string()` | `callflow : cf_doorman` | `false` |  
`recording_limit` | The caller's recording limit for name and reason for calling | `integer()` | `3` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`tones` | Ring tone to play to the caller after recording their name | `array([#/definitions/tone](#tone))` |   | `false` |  
`vmbox_id` | Voicemail box ID to send caller to if callee choses | `string()` |   | `false` |  

### tone

Validator for a teletone config


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`duration_off` | duration, in milliseconds, for tone to be off | `integer()` |   | `true` |  
`duration_on` | duration, in milliseconds, for the tone to be on | `integer()` |   | `true` |  
`frequencies` | list of Frequencies to play | `array(integer())` |   | `true` |  
`repeat` | How many times to loop the tones | `integer()` |   | `false` |  
`volume` | Volume, in dB. 0 = max, negative = quieter | `integer(..0)` |   | `false` |  




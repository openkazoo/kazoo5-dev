## Tones

### About Tones

#### Schema

Validator for the tones callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`tones` | list of tones to play to caller | `array([#/definitions/tone](#tone))` |   | `false` |  

### tone

Validator for a teletone config


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`duration_off` | duration, in milliseconds, for tone to be off | `integer()` |   | `true` |  
`duration_on` | duration, in milliseconds, for the tone to be on | `integer()` |   | `true` |  
`frequencies` | list of Frequencies to play | `array(integer())` |   | `true` |  
`repeat` | How many times to loop the tones | `integer()` |   | `false` |  
`volume` | Volume, in dB. 0 = max, negative = quieter | `integer(..0)` |   | `false` |  




## Detect Speech

### About Detect Speech

#### Schema

Validator for the detect_speech callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` | action | `string('start' | 'stop')` |   | `false` |  
`asr_engine` | asr engine name | `string()` |   | `false` |  
`asr_params` | asr engine params | `object()` |   | `false` |  
`asr_settings` | asr engine settings | `object()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  




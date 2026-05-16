## Call Forward

### About Call Forward

Configure call forwarding for your device from your phone!

#### Schema

Validator for the call_forward callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` | What action to perform on the caller's call forwarding | `string('activate' | 'deactivate' | 'update' | 'toggle' | 'menu')` |   | `false` |  
`menu_retries` | If the action is menu, how many retries to get a correct menu selection | `integer()` | `3` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  






### Actions

#### Activate

Support for NANPA `*72`. Enables call forwarding on the user (if the calling device is owned) or the calling device.

If the callflow is configured with a regex pattern with a capture group (like `^*72(\\d+)$`), and the caller includes the forwarding number in the request (by dialing `*723335557777` for instance), the endpoint will be updated automatically to forward calls to `333.555.7777`.

If no capture group digits are matched, the caller will be prompted to enter the number they wish to use for forwarding calls.

#### Deactivate

Support for NANPA `*73`. Disables call forwarding on the user (if the calling device is owned) of the calling device.

#### Update

Support for NANPA `*56`. If no capture group matched, prompts the caller for the new call forwarding number to use.

The state of call fowarding (enabled or not) is unchanged.

#### Toggle

Toggles the call forwarding `enabled` flag on the user (if the calling device is owned) or calling device. Toggling from a `disabled` state to `enabled`, if a forwarding number is defined already, the `enabled` setting is toggled to `true`. Otherwise, the `activate` or `deactivate` action is performed as appropriate.

#### Menu

The `menu` action provides the caller with a menu from which to choose to toggle if call forwarding is enabled or change the call forwarding number (effectively choosing from actions `toggle` or `update` from above).


## Table of scenarios and expected outcomes

| Scenario                                                      | *72 (Activate)                                                               | *73 (Deactivate)              | *74 (Toggle)                                                                | *56 (Update number)                                                     |
|---------------------------------------------------------------|------------------------------------------------------------------------------|-------------------------------|-----------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Call forwarding is disabled (or undefined) with no number set | Caller will be prompted to enter the cfwd number and cfwd will be activated  | Call forward remains disabled | Caller will be prompted to enter the cfwd number and cfwd will be activated | Caller will be prompted to enter the cfwd number, cfwd remains disabled |
| Call forwarding is enabled with a number set                  | Caller will be prompted to enter the new cfwd number, cfwd remains enabled   | Call forward is deactivated   | Call forward is deactivated                                                 | Caller will be prompted to enter the cfwd number, cfwd remains enabled  |
| Call forwarding is disabled with a number set                 | Caller will be prompted to enter the new cfwd number, cfwd will be activated | Call forward remains disabled | Cfwd is activated, number remains the same                                  | Caller will be prompted to enter the cfwd number, cfwd remains disabled |

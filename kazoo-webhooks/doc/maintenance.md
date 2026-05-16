# SUP-able functions

| Function | Arguments | Description |
| -------- | --------- | ----------- |
| `enable_account_hooks/1` | `(AccountId)` | |
| `enable_descendant_hooks/1` | `(AccountId)` | |
| `failure_status/0` |  | |
| `failure_status/1` | `(Account)` | |
| `flush_account_failures/1` | `(AccountId)` | |
| `flush_hook_failures/2` | `(AccountId,HookId)` | |
| `hooks_configured/0` |  | All webhooks that are active to fire HTTP events |
| `hooks_configured/1` | `(AccountId)` | All webhooks, within the account, that are active to fire HTTP events |
| `register_views/0` |  | |
| `reset_hook_definition/1` | `(Hook) | (_)` | |
| `reset_hook_definitions/0` |  | |
| `set_disable_threshold/1` | `(Count)` | |
| `set_disable_threshold/2` | `(Account,Count)` | |
| `set_failure_expiry/1` | `(Expires)` | |
| `set_failure_expiry/2` | `(Account,Expires)` | |
| `start_module/1` | `(ModuleBin)` | Force a webhook module to initialize and add AMQP bindings and responders |

## See what hooks are active

This will display all hooks, or only hooks for the account provided, that are currently being processed.

    sup webhooks_maintenance hooks_configured [{ACCOUNT_ID}]
    | URI                                           | VERB  | EVENT                | RETRIES    | ACCOUNT ID                       |
    | http://dev.null/calls/new.php                 | post  | CHANNEL_CREATE       | 3          | {ACCOUNT_ID}                     |
    | http://dev.null/calls/done.php                | post  | CHANNEL_DESTROY      | 3          | {ACCOUNT_ID}                     |

## Protect against abuse

### Set the Failure Expiry Timeout

Webhooks will track how many times a given hook has failed to fire to the configured URI. This expiry determines how long webhooks holds onto the failure before considering it irrelevant. The number of failures over a given time period will determine if a hook is auto-disabled.

* System-wide: `sup webhooks_maintenance set_failure_expiry {MILLISECONDS}`
* Account-specific: `sup webhooks_maintenance set_failure_expiry {ACCOUNT_ID} {MILLISECONDS}`

### Set the Auto-Disable Threshold

Set how many failures are considered too many and auto-disable a hook.

* System-wide: `sup webhooks_maintenance set_disable_threshold {COUNT}`
* Account-specific: `sup webhooks_maintenance set_disable_threshold {ACCOUNT_ID} {COUNT}`

### How it works

Once you've set the `expiry` and `threshold`, *webhooks* will check every `expiry` milliseconds for hook failure counts. If any hooks have a count over `threshold`, they will be auto-disabled.

For instance, using the defaults of `expiry = 60000` (one minute) and `threshold = 6`, if a hook fails to fire to the configured URI 6 times or more in the last minute, it will be auto-disabled until an API request to set "enabled" to `true` is performed.

### Monitor the situation

You can see the current failure counts for each hook:

    sup webhooks_maintenance failure_status [{ACCOUNT_ID}]
    | -------------------------------- | -------------------------------- | ----- |
    | Account                          | Hook                             | Count |
    | {ACCOUNT_ID}                     | {HOOK_ID}                        |     4 |
    | -------------------------------- | -------------------------------- | ----- |

### Re-enable hooks

If hooks are disabled in an account due to failures, an admin can bulk-update the hooks to be enabled again.

    sup webhooks_maintenance enable_account_hooks {ACCOUNT_ID}

Similarly, enable all hooks for an account and its descendants:

    sup webhooks_maintenance enable_descendant_hooks {ACCOUNT_ID}

Note: this will only enable those hooks which have been auto-disabled by the system, not manually disabled via API.

## Flush failure counts

Webhooks tracks the number of times a hook fails to be sent, auto-disabling the hook after a threshold is hit. You can reset those failure counts:

    sup webhooks_maintenance flush_account_failures {ACCOUNT_ID}
    sup webhooks_maintenance flush_hook_failures {ACCOUNT_ID} {HOOK_ID}

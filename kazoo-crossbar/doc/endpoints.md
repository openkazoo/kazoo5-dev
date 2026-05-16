# KAZOO Endpoints

When you see references to `endpoints` in KAZOO, it is typically something that exists outside of KAZOO that KAZOO wishes to send calls (or messages) to.

Concretely, an `endpoint` typically refers to a `device`, but can also mean a `user`, `group`, or even `account` (and is extendable to other entities.

In practice, each type of endpoint has rules that govern how call legs are generated; some are shared rules and some are specific to the endpoint type.

Let's take a look at some examples!

## Devices

Conceptually, this is what most folks probably think of when discussing "dialing an endpoint". The main parameters that govern call leg creation to devices are:

1. Having SIP credentials configured
2. Having `call_forward` settings enabled
  a. Having `call_forward.substitute=true`
3. Having `call_failover` settings enabled

Let's see how these parameters interact:

| Has SIP Creds? | Is device registered | call_forward.enabled | call_forward.substitute | Legs started                                      |
| -------------- | -------------------- | -------------------- | ----------------------- | ------------                                      |
| true           | false                | N/A                  | N/A                     | 1 - to call-failover number                       |
| true           | true                 | true                 | false                   | 2 - to call-forwarded number and SIP registration |
| true           | true                 | false                | false                   | 1 - to SIP registration                           |
| false          | N/A                  | true                 | ignored                 | 1 - to call-fowarded number                       |
| false          | N/A                  | false                | ignored                 | 0 - no destinations dialed                        |

## Users

Under normal circumstances, when dialing a `user`, KAZOO will find all devices owned by the user and follow the appropriate rules for those devices. Since a `user` won't have SIP credentials configured (at least KAZOO will not look for them), legs generated for the call to the `user` will be from the devices owned by the user or the `call_forward` settings.

## call_forward.substitute

Particular attention should be paid to `call_forward.substitute` as it affects all endpoints. When set to `true`, all leg creation will be overridden and *only* the call_forwarded leg will be created.

This is more relevant for users or groups where SIP credentials aren't also going to be considered. Setting `call_forward.substitute=true` on a user or group means skipping normal leg creation rules and creating *just* the leg specified by the endpoint's `call_forward` object.

To re-iterate, if a `user` sets the `call_forward.substitute` flag, KAZOO will not look for devices owned by the user; KAZOO will immediately create only a call leg based on the user's `call_forward` object. Same for any other entity.

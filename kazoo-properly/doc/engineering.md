# Engineering notes

## API modules

In `src/api` you'll find `pqc_{crossbar_module}` modules that map 1-1 to the `cb_{endpoint}` modules in Crossbar.

So API calls to `cb_devices` will be found in `pqc_cb_devices`.

See `pqc_cb_skels.erl.src` for a starter template.

### CRUD

For CRUD operations on an endpoint, see `src/pqc_cb_crud.erl` for making the requests.

The standard functions for CRUD in `pqc_cb_{module}` should be:

* `summary/2` - list the collection
* `create/3` - Create an entity
* `fetch/3` - Fetch an entity
* `update/3` - Update an entity (POST)
* `patch/3` - Patch an entity
* `delete/3` - Delete an entity

These are obviously the minimum arities to define; some may want to define alternative request headers, expectations, etc.

## Sequential tests

Sequential tests represent the "happy path" through an API's usage. These can be found in `src/tests/seq_{module}` and where `{module}` maps to the collection type.

So `seq_devices` will test the `cb_devices` endpoint using the `pqc_cb_devices` API module.

Each `seq` module should export at least `seq/0` to run during integration testing in CI.

Each `seq` module should export at least `cleanup/0` to ensure all settings, accounts, etc are removed. This generally means `seq` modules should name their accounts statically (`<<?MODULE_STRING>>` is a good choice!).

Per-ticket functions (like `seq_kzoo_12345/0`) can also be exported for specific testing locally.

See `seq_skels.erl.src` for a template.

## Property tests

Some APIs are tested using PropEr tests. These tests are found in `src/tests/pqc_{module}`. So stateful property testing of the `cb_phone_numbers` is done in `pqc_phone_numbers` using the API functions in `pqc_cb_phone_numbers` (among others).

Each module should export the expected PropEr statem callbacks.

## Local tests

These are tests that should be run within a KAZOO VM, as the tests might access the AMQP bus, direct CouchDB access, or function calls to KAZOO applications.

See `src/local/` for these tests to run.

## Utilities

There are several utility modules to use when needed:

* `pqc_httpd` - an HTTP server to receive requests from KAZOO (like storage)
* `pqc_sip_client` - a basic SIP client for talking to Kamailio
* `pqc_ws_client` - a basic websocket client for talking to Blackhole

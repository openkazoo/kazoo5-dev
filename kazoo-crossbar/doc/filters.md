# Query String Filters

## Overview

Query string filters allow the API results to be filtered by additional criteria to limit the result set. This is especially useful when querying a collection that could be massive (like CDRs) but you're only interested in results that match certain criteria.

## Available Filters

Filter | Operates On | Description
------ | ----------- | -----------
`filter_any_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is any of the values in `{VALUE}` JSON array.
`filter_array_intersect_all_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is an array has all values in `{VALUE}` JSON array
`filter_array_intersect_any_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is an array has any values in `{VALUE}` JSON array
`filter_array_intersect_none_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is an array has **none** of the values in `{VALUE}` JSON array
`filter_none_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is not any of the values in `{VALUE}` JSON array
`filter_not_{KEY}` | `{VALUE}` | Doc include if `{KEY}` is *not* `{VALUE}`
`filter_{KEY}` | `{VALUE}` | Doc included if `{KEY}` is `{VALUE}`
`has_key` | `{KEY}` | Doc included if `{KEY}` is present on the doc
`key_missing` | `{KEY}` | Doc included if `{KEY}` is *not* present on the doc
`has_value` | `{KEY}` | Doc included if `{KEY}` exists *and* the `{VALUE}` is non-empty
`missing_value` | `{KEY}` | Doc included if `{KEY}` is not present *or* the `{VALUE}` is empty
`created_from` | `{VALUE}` | Doc included if the created time is greater than or equal to `{VALUE}` (in Gregorian seconds)
`created_to` | `{VALUE}` | Doc included if the created time is less than or equal to `{VALUE}` (in Gregorian seconds)
`modified_from` | `{VALUE}` | Doc included if the last-modified time is greater than or equal to `{VALUE}` (in Gregorian seconds)
`modified_to` | `{VALUE}` | Doc included if the last-modified time is less than or equal to `{VALUE}` (in Gregorian seconds)

### Keys

Filters can be used on validated keys (those appearing in the schema) and on custom keys (those included by the caller).

`{KEY}` can be a dot-delimited string representing a JSON key path. So `filter_foo.bar.baz=1` would match a doc that had `{"foo":{"bar":{"baz":1}}}` in it.

## Array Value

Is the `{VALUE}` of any of the filters above is an array, you should use pass it as encoded JSON array value in query string. So `filter_array_intersect_all_numbers=["1000"]` would match a doc that have `{"numbers": ["1000"]}` in it.

### Multiple Filters

Filters can be chained together on a query string and will be applied as a boolean `AND` operation. For example, `?filter_foo=1&has_key=bar` will look for docs where `foo=1` and the key `bar` exists on the doc.

## Fetching Sparse Fieldsets

A client **MAY** request that an endpoint return only specific fields (of the document) in the response. This will only works the request is listing objects, like `/users`.

The value of `fields` parameters must be an encoded JSON array. Each element of the array can be dot-delimited string representing a JSON key path. If any of the requested fields are restricted (are private fields) then they would be ignored.

The `id` of documents (if any) will always be part of the response.

If `fields` parameter is empty, the server will treat the request as if no `fields` parameter is specified and will return the default response (i.e. the "listing" result, not the full document).

For example, endpoint `/callflows` which is lists callflows normally will return a response like this:

```json
{
    "data": [
        {
            "id": "532841b1d27c3f2f6ac792d304854fd",
            "name": "MainCallflow",
            "flags": [],
            "features": [],
            "featurecode": false,
            "modules": [
                "temporal_route",
                "callflow"
            ],
            "numbers": [
                "0",
                "+15554431234"
            ],
            "patterns": [],
            "type": "main"
        }
    ]
}
```

If you want to request the name of callflow (if any) and the `flow` object (from document), you may make a request like `?fields=["name","flow"]` which will return a list of all callflows with only `name` and `flow` (if they are defined):

```
{
    "data": [
        {
            "name": "Main",
            "flow": {...},
            "id": "id1"
        }
    ]
}
```

If you were to make this request without the `fields` querystring, you would not receive the `flow` field in your response (because the listing response does not include the `flow` field by default).

## Requesting Full Documents

A client **MAY** request that an endpoint return all public fields of the documents in the response using `full_docs=true` query string when the request is listing objects, like `/users`.

This feature is opt-in and can be enabled by system administrator in `system_configs/crossbar`.

* Set `allow_fetch_full_docs` to `true` for enabling this for all endpoints
* Set `{CB_MODULE_NAME}` to `true` under `allowed_modules_fetch_full_docs` to enable for specific endpoints.

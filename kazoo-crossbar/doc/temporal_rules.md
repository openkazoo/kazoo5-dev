# Temporal Rules

## About Temporal Rules

Temporal rules provide a flexible way to configure time-based Call routing, e.g. open hours, holidays, close hours, etc...

#### Schema

Schema for a temporal rules



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`cycle` | The recurrence cycle for this rule | `string('date' \| 'daily' \| 'weekly' \| 'monthly' \| 'yearly')` |   | `true` | `supported`
`days` | The occurance day(s) of the month (1-31) for this rule | `array(integer(1..31))` |   | `false` | `supported`
`enabled` | Whether the rule is enabled | `boolean()` |   | `false` |  
`end_date` | The date that any recurrence should be calculated as ending on | `integer()` |   | `false` | `supported`
`exclude.[]` |   | `string()` |   | `false` |  
`exclude` | Exclude specific dates (ISO8601 format) for recurring, non-linear rules, e.g: ["20210106", "20210206"] | `array(string())` |   | `false` |  
`flags.[]` |   | `string()` |   | `false` | `supported`
`flags` | Flags set by external applications | `array(string())` |   | `false` | `supported`
`interval` | The recurrence interval for this rule | `integer(1..)` | `1` | `false` | `supported`
`month` | The recurrence month for this rule | `integer(1..12)` |   | `false` | `supported`
`name` | A friendly name for the temporal rule | `string(1..128)` |   | `true` | `supported`
`ordinal` | The recurrence ordinal for this rule | `string('every' \| 'first' \| 'second' \| 'third' \| 'fourth' \| 'fifth' \| 'last')` |   | `false` | `supported`
`owner_id` | KAZOO User ID of the owner of this temporal rule | `string()` |   | `false` |  
`start_date` | The date that any recurrence should be calculated as starting on | `integer()` | `62586115200` | `false` | `supported`
`time_window_start` | Seconds from the start of a day to consider this rule valid | `integer(0..86400)` |   | `false` | `supported`
`time_window_stop` | Seconds from the start of a day to stop considering this rule valid | `integer(0..86400)` |   | `false` | `supported`
`wdays.[]` |   | `string('monday' \| 'tuesday' \| 'wednesday' \| 'wensday' \| 'thursday' \| 'friday' \| 'saturday' \| 'sunday')` |   | `false` | `supported`
`wdays` | The recurrence weekdays for this rule | `array(string('monday' \| 'tuesday' \| 'wednesday' \| 'wensday' \| 'thursday' \| 'friday' \| 'saturday' \| 'sunday'))` |   | `false` | `supported`



### Notes on fields

#### `enabled`

Unless you need to override a time of day rule (for example keep an office open longer) keep the property unset.

#### `start_date`

It is recommended that a start date always be set to some time in the past if this control is not required to ensure it takes effect on the next cycle.

Setting this property is especially important when using an interval other than 1. For example if the rule should be applied every other year and the start date is in 2010, then it will be active on 2010, 2012, 2014, etc. However, if the start date was in 2011 then it will be active on 2011, 2013, 2015, etc.

#### `ordinal`

Not all months have a fifth occurrence of a weekday; the rule is ignored if that is the case.

#### `cycle`

When `cycle` is `date`, the rule only considers `start_date` and matches it against the current day.

#### `days`

The `days` array is only valid when `cycle` is `yearly` or `monthly`.

#### `exclude`

The `exclude` array adds the ability to have a way to exclude an specific date, for example: If a recurring holiday is created for 'Christmas', but it is not intended to be applied for a specific year, the `exclude` field can be use to exclude that date instead of creating multiple rules for this.

Here is an example:

A recurring holiday for labor day (First Monday of September) is created, it should be used every year, but in 2022 that holiday is not going to be given to employees so it can be excluded. Instead of creating 2 new rules, one for 2021 and one starting 2023, the same rule can be used by excluding the date when this holiday happens on 2022, like the example below:


> PUT /v2/accounts/{ACCOUNT_ID}/temporal_rules

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data":{"name":"Labor Day","cycle":"yearly","interval":1,"month":9,"type":"main_holidays","ordinal":"first","wdays":["monday"],"exclude":["20220905"]}}'
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules
```
```json
{
    "version": "5.0.47",
    "timestamp": "2021-01-12T20:50:24Z",
    "node": "{NODE}",
    "request_id": "{REQUEST_ID}",
    "tokens": {
        "consumed": 1,
        "remaining": 100
    },
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "name": "Labor Day",
        "cycle": "yearly",
        "interval": 1,
        "month": 9,
        "type": "main_holidays",
        "ordinal": "first",
        "wdays": [
            "monday"
        ],
        "exclude":["20220905"],
        "start_date": 62586115200,
        "id": "{TEMPORAL_RULE_ID}"
    },
    "revision": "{REVISION}",
    "status": "success"
}
```

## Get a summary of created temporal rules

> GET /v2/accounts/{ACCOUNT_ID}/temporal_rules

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules
```
```json
{
   "auth_token":"{AUTH_TOKEN}",
   "status":"success",
   "request_id":"{REQUEST_ID}",
   "revision":"{REVISION}",
   "data":[
      {
         "id":"{TEMPORAL_RULE_ID}",
         "name":"Business Hours"
      },
      {
         "id":"{TEMPORAL_RULE_ID}",
         "name":"Holiday"
      }
   ]
}
```

## Create a new temporal rule

> PUT /v2/accounts/{ACCOUNT_ID}/temporal_rules

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data":{"time_window_start":0,"time_window_stop":86400,"days":[25],"name":"Christmas","cycle":"yearly","start_date":62586115200,"month":12,"ordinal":"every","interval":1}}'
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules
```
```json
{
   "auth_token":"{AUTH_TOKEN}",
   "status":"success",
   "request_id":"{REQUEST_ID}",
   "revision":"{REVISION}",
   "data":{
      "time_window_start":0,
      "time_window_stop":86400,
      "days":[25],
      "name":"Christmas",
      "cycle":"yearly",
      "start_date":62586115200,
      "month":12,
      "ordinal":"every",
      "interval":1
   }
}
```

## Fetch a temporal rule

> GET /v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}
```

### Evaluate a temporal rule

It can be helpful to test an existing rule and whether it will match, given a timestamp.

A querystring parameter, `timestamp`, can be included on the URL to to specify a time to evaluate the rule against. The API response will include a `metadata.rule_matches` boolean to indicate whether the rule matched the timestamp. The timestamp must be in Gregorian seconds in the timezone of the account.

For instance, fetching a rule that matches on [Tau Day](https://tauday.com/) with a timestamp for Pi day:

```shell
  curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}?timestamp=63846025766
```
```json
{
  "data": {
    "custom": "value",
    "cycle": "yearly",
    "days": [
      28
    ],
    "id": "{TEMPORAL_RULE_ID}",
    "interval": 1,
    "month": 6,
    "name": "Tau Day",
    "ordinal": "every",
    "start_date": 62586115200
  },
  "metadata": {
    "created": 63849751700,
    "id": "{TEMPORAL_RULE_ID}",
    "modified": 63849751700,
    "rule_matches": false
  },
  "revision": "{REVISION}",
  "status": "success"
}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/temporal_rules/{TEMPORAL_RULE_ID}
```

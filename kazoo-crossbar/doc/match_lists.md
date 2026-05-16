# Match Lists

## About Match Lists

Match lists encode rules to process to decide if criteria has been met.

Concretely, this means match lists can encode decision making for:
- Whether to branch a callflow
- Whether to set a specific caller ID
- Whether to allow call forwarding

#### Schema

Match lists - define a set of rules for matching against call properties, callflows, etc



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`name` | Friendly name for the match list | `string()` |   | `false` |  
`owner_id` | KAZOO User ID of the owner of this match list | `string()` |   | `false` |  
`rules` | Evaluated rules to determine if the match list has matched | `array([#/definitions/match_lists.rule](#match_listsrule))` |   | `true` |  

### match_lists.rule

Match list rule - express the logic of a match


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`name` | Friendly name of the rule | `string(3..255)` |   | `true` |  
`regex` | Regular expression to match with when type=regex | `string()` |   | `false` |  
`target` | The target field to match against - context-dependent | `string()` |   | `false` |  
`temporal_route_id` | When type=temporal_route, set this to the ID of the temporal route (or route set) to use | `string()` |   | `false` |  
`type` |   | `string('regex' \| 'temporal_route')` |   | `true` |  



## Fetch the listing of created match lists

> GET /v2/accounts/{ACCOUNT_ID}/match_lists

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": [],
  "metadata": {},
  "node": "{MD5_NODE}",
  "page_size": 1,
  "request_id": "{REQUEST_ID}",
  "revision": "{REVISION}",
  "start_key": "{START_KEY}",
  "status": "success",
  "timestamp": "{TIMESTAMP}",
  "tokens": {
    "consumed": 0,
    "remaining": 0
  },
  "version": "{VSN}"
}
```

## Create a new match list

> PUT /v2/accounts/{ACCOUNT_ID}/match_lists

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists \
    -d '{"data":{"name":"My Match List","rules":[]}}'
```

```json
{
  "data": {
    "id": "{MATCH_LIST_ID}",
    "name": "My Match List",
    "rules": []
  }
}
```

## Fetch the details of a match list

> GET /v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}
```

## Update a match list

> POST /v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}
```

## Patch a match list

> PATCH /v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}
```

## Remove a match list

> DELETE /v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/match_lists/{MATCH_LIST_ID}
```

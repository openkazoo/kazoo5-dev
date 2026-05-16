# Scope Restrictions

## About Scope Restrictions

Scope Restrictions provide a mechanism to create an alias for a scope of scopes and define a set of crossbar token restrictions.

A scope restriction is assigned by setting it in the `scope_restrictions` array on the user object.

The id chosen for scope restriction will be used as the scope of scopes. So choose one careful and make it standardized so each account will use the same id. For this example we are choosing `api:read_only` as the scope, this will be scope which enforces read allow access to api, linked document for the scope below.

The user documents also need to be patched with `"scope_restrictions":["api:read_only"]` This will add the scope to user and make each login to be restricted to scope

```bash
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"data":{"scope_restrictions":["api:read_only"]}}' \
    http://{URL}/v2/accounts/{ACCOUNT_ID}
```

This will also add `"scope":"api:read_only"` to jwt claims for the user so it may be read by other applications which use scope.

If we have another scope named `api:support` where support has more permissions then we will need to create a scope named `api:support` and patch the user doc with two scopes `"scope_restrictions":["api:read_only", "api:support"]` and the claims will be `"scope":"api:read_only api:support"`

##### Example Scope Restriction Document
This 
```json
{
  "id": "api:read_only",
  "scopes": [
    "crossbar:read_only"
  ],
  "token_restrictions": {
    "_": [
      {
        "allowed_accounts": [
          "_"
        ],
        "rules": {
          "#": [
            "GET"
          ]
        }
      }
    ]
  }
}
```

#### Schema

Crossbar Scope Restrictions  Definition



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | Scope Restriction unique identifier | `string()` |   | `false` |  
`scopes.[]` |   | `string()` |   | `false` |  
`scopes` | List of enforced scopes | `array(string())` | `[]` | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/scope_restrictions

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/scope_restrictions
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/scope_restrictions

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/scope_restrictions
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}
```


# Scopes

## About Scopes

### Crossbar Binding
You can define a callback to enforce custom scopes in a crossbar module with the `allowed_scopes` binding.


```erlang
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_scopes.accounts">>, 'allowed_scopes'}
               , .... Other Bindings
               ],
    cb_modules_util:bind(?MODULE, Bindings).
```

#### Custom List
```erlang
%%------------------------------------------------------------------------------
%% @doc 
%% @end
%%------------------------------------------------------------------------------
-spec allowed_scopes() -> kz_term:ne_binaries().
allowed_scopes() ->   
  ?CB_DEFAULT_SCOPES.

-spec allowed_scopes(kz_term:ne_binary()) -> kz_term:ne_binaries().
allowed_scopes(AuthModule) ->
  lager:debug("fetching allowed scopes for ~p", [AuthModule]),
  kz_auth_scope:to_list(<<"crossbar:read_only">>).
```

#### Auth Module Config
```erlang
%%------------------------------------------------------------------------------
%% @doc 
%% @end
%%------------------------------------------------------------------------------
-spec allowed_scopes() -> kz_term:ne_binaries().
allowed_scopes() ->   
  ?CB_DEFAULT_SCOPES.

-spec allowed_scopes(kz_term:ne_binary()) -> kz_term:ne_binaries().
allowed_scopes(AuthModule) ->
  lager:debug("fetching allowed scopes for ~p", [AuthModule]),  
  crossbar_auth:available_scopes(AuthModule).
```

#### Schema

Kazoo Auth Scope Definition



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | Scope unique identifier | `string()` |   | `false` |  
`scopes.[]` |   | `string()` |   | `false` |  
`scopes` | List of available subscopes | `array(string())` | `[]` | `false` |  



## Fetch

> GET /v2/scopes

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/scopes
```

## Create

> PUT /v2/scopes

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/scopes
```

## Fetch

> GET /v2/scopes/{SCOPE}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/scopes/{SCOPE}
```

## Change

> POST /v2/scopes/{SCOPE}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/scopes/{SCOPE}
```

## Remove

> DELETE /v2/scopes/{SCOPE}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/scopes/{SCOPE}
```


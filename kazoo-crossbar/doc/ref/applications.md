# Applications

## About Applications

#### Schema

UI application metadata schema



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`api_url` | Optional API URL that application can use. default to Kazoo Crossbar API | `string(7..)` |   | `false` |  
`author` | Name of app publisher | `string(2..64)` |   | `true` |  
`i18n` | Application translation | `object()` |   | `false` |  
`icon` | Name of application icon | `string()` |   | `false` |  
`license` | Application license | `string()` |   | `true` |  
`masqueradable` | Whether an application is masqueradable or not | `boolean()` | `true` | `false` |  
`name` | Application name | `string(3..64)` |   | `true` |  
`phase` | Application test phase | `string('alpha' \| 'beta' \| 'gold')` |   | `false` |  
`price` | Application price | `number()` |   | `false` |  
`published` | Indicated if the app is published | `boolean()` | `true` | `false` |  
`screenshots.[]` |   | `string()` |   | `false` |  
`screenshots` |   | `array(string())` |   | `false` |  
`source_url` | an URL which indicates where the UI must load the application source files | `string()` |   | `false` |  
`tags.[]` |   | `string()` |   | `false` |  
`tags` |   | `array(string())` |   | `false` |  
`type` | Type of application that can be used, for example commland_ui, monster_ui | `string(2..64)` |   | `true` |  
`urls` |   | `object()` |   | `false` |  
`version` | Application version | `string()` |   | `true` |  

### app_i18n

Application translation


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`[a-z]{2}\-[A-Z]{2}.description` | Application Summary | `string(3..)` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.extended_description` | Application extended description | `string()` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.features.[]` |   | `string()` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.features` | Application features list | `array(string())` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.icon` | Application icon name | `string()` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.label` | Application label | `string(3..64)` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.screenshots.[]` |   | `string()` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.screenshots` | Application screenshot names | `array(string())` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}.urls` | Application urls | `object()` |   | `false` |  
`[a-z]{2}\-[A-Z]{2}` |   | `object()` |   | `false` |  



## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/entitlements

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/entitlements
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/blocklists

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/blocklists
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}
```

## Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/icon

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/icon
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/entitlement
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block
```

## Create

> PUT /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/block
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon
```

## Change

> POST /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/icon
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/screenshots/{SCREENSHOT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/{APP_TYPE}/{APP_ID}/screenshots/{SCREENSHOT_ID}
```

## Fetch

> GET /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots/{SCREENSHOT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots/{SCREENSHOT_ID}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots/{SCREENSHOT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/applications/application/{APP_ID}/screenshots/{SCREENSHOT_ID}
```


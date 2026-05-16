# Apps Store

Apps Store API lists UI applications allowed by your service plan.

## Apps Structure

Application document are added by system admin in and are not modifiable. They can only be accessed through API.

### Schema

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`allowed_users` | User type allowed to access the app | `string('specific' | 'all' | 'admins')` |   | `false` |
`api_url` | Application api url | `string()` |   | `true` |
`author` | Application author | `string(2..64)` |   | `true` |
`i18n` | Application translation | [#/definitions/app_i18n](#app_i18n) |   | `true` |
`icon` | Application icon | `string()` |   | `true` |
`license` | Application license | `string()` |   | `true` |
`masqueradable` | Whether an application is masqueradable or not | `boolean()` | `true` | `false` |
`name` | Application name | `string(3..64)` |   | `true` |
`phase` | Application test phase | `string('alpha' | 'beta' | 'gold')` |   | `false` |
`price` | Application price | `number()` |   | `true` |
`published` | is the app published | `boolean()` |   | `false` |
`screenshots.[]` |   | `string()` |   | `false` |
`screenshots` |   | `array(string())` |   | `false` |
`source_url` | Application source url | `string()` |   | `false` |
`tags.[]` |   | `string()` |   | `false` |
`tags` |   | `array(string())` |   | `false` |
`urls` |   | `object()` |   | `false` |
`users.[]` |   | `string()` |   | `false` |
`users` | User IDs authorized to use the app (when allowed_users = 'specific') | `array(string())` |   | `false` |
`version` | Application version | `string()` |   | `true` |

### app_i18n schema

Application translation


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`[a-z]{2}\-[A-Z]{2}.description` |   | `string(3..)` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.extended_description` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.features.[]` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.features` |   | `array(string())` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.icon` | I18N application icon attachment name | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.label` |   | `string(3..64)` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.screenshots.[]` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.screenshots` |   | `array(string())` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.urls` |   | `object()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}` |   | `object()` |   | `false` |



### App Internationalization (i18n)

App documents may have internationalization of their metadata like description or name/label or screenshots. The language code are standard language-country format like `en-US`.

!!! note
    `icon` and `screenshot` in `i18n.en-US` section of app document has priority over their counterparts on the root of the document. For example if screenshots defined in both places ONLY values from `i18n.en-US.screenshots` will honored!

### Branding (White labeling) UI Apps

Re-seller can change `i18n` section of the app documents to their needs. See below for API `override` endpoint. This whitelabel overrides will be saved in their account database. When listing or getting apps metadata these whitelabeled data will merged.

Brand UI apps will affect the reseller and all their sub-accounts. Please note that these overrides has priority over default values from master account.

### How to specify brand or language specific UI applications

To request brand or language app metadata simply include them in the URL path:

* To request language add this part to URL: `/i18n/{{LANGUAGE_CODE}}`
* To request brand add this part to URL: `/whitelabel/{{DOMAIN}}`

### Examples

Clients can request languages specific screenshots or icon by requesting the desired language in URL:

```
GET /v2/accounts/{{account_id}}/i18n/de-DE/apps_store/{{app_id}}/screenshot/{{screenshot_index}
```

For getting branded icon or screenshots client can include whitelabel domain in the request:

```
GET /v2/whitelabel/{{domain}}/apps_store/screenshot/{{screenshot_index}}
```

Combining these together:

```
GET /v2/whitelabel/{{domain}}/i18n/de-DE/apps_store/{{app_id}}/screenshot/{{screenshot_index}
```

### Install Master applications

This is for system administrator when they initializing the system for the first time or after update. This will install the app in the system for master account so they can used and install to other accounts using API.

Assuming you've installed your Monster applications to `/path/to/monster-ui/apps`, you can run the following SUP command on the to add them into the system. The URL at the end is address that Crossbar API URL that the apps will be accessible:

```bash
sup crossbar_maintenance init_apps '/path/to/monster-ui/apps' 'http://your.api.{{SERVER}}:8000/v2'
```

This will load the apps (and let you know which apps it couldn't automatically load) into the master account (including icons, if present). For any apps that failed to be loaded automatically, you can follow the manual instructions below.

If you want to install a single Monster application:

```bash
sup crossbar_maintenance init_app '/path/to/monster-ui/apps/{{APP}}' 'http://{{SERVER}}:8000/v2'
```

In the future after updating system (monster-ui packages) you may use this command to install/upgrade the apps metadata as they change. This also is useful if you need to change the `api_url` later on:

```bash
sup crossbar_maintenance refresh_apps '/path/to/monster-ui/apps' 'http://your.api.{{SERVER}}:8000/v2'
```

### App Permission

Blacklisting apps and user base permission is configurable using this API endpoint. The values are store in a document in the account's DB. If an app is blacklisted, it won't be accessible by any users of the account.

```json
{
    "apps": {
        "{{application_id}}": {
            "allowed_users": "specific",
            "users": []
        },
        "{{application_id}}": {
            "allowed_users": "specific",
            "users": [{
                "id": {{user_id}}
            }]
        },
        "{{application_id}}": {
            "allowed_users": "admins"
        },
        "{{application_id}}": {
            "allowed_users": "all"
        }
    },
    "blacklist": [
        "{{application_id}}"
    ]
}
```

| Allowed Users  | To | key |
| ------------- | ------------- | ------------- |
| Specific with **no user**  | No one  | specific
| Specific with **user(s)**  | Only listed users  | specific
| All  | Everyone in the account  | all
| Admins | Only Admins  | admins

## Fetch App(s):

> GET /v2/accounts/{ACCOUNT_ID}/apps_store

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}
```

```json
{
    "data": [
        {APP}
    ],
    "status": "success"
}
```

## Install App for an account:

> PUT /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}

Install app on your account.

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"allowed_users": "specific", "users": []}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}
```

```json
{
    "data": {
        "name": "{APP_ID}",
        "allowed_users": "specific",
        "users": []
    }
}
```


## Update an App permission:

> POST /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}

Update app permission on your account.

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"allowed_users": "all"}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}
```

```json
{
    "data": {
        "allowed_users": "all"
    },
    "status": "success"
}
```

## Uninstall an App from an account:

> DELETE /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}

Uninstall app on your account (remove permission for all users).

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}
```

```json
{
    "data": {},
    "status": "success"
}
```

## Fetch App icon

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/icon

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/icon
```

Streams application icon back.


## Fetch App screen shots

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/screenshot/{APP_SCREENSHOT_INDEX}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/screenshot/{APP_SCREENSHOT_INDEX}
```

Streams application screenshot number `{APP_SCREENSHOT_INDEX}` back.

## Get Blacklist

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/blacklist

Need to be reseller.

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/blacklist
```

```json
{
    "data": {
        "blacklist": [
            "{APP_1}",
            "{APP_2}"
        ]
    },
    "status": "success"
}
```

## Update Blacklist

> POST /v2/accounts/{ACCOUNT_ID}/apps_store/blacklist

Need to be reseller.

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"blacklist": [{APP_3}]}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/blacklist
```

```json
{
    "data": {
        "blacklist": [
            "{APP_1}",
            "{APP_2}",
            "{APP_3}"
        ]
    },
    "status": "success"
}
```

## Brand/Whitelabel UI applications override

The reseller account can override some part of UI application meta data like icon, screen shots and i18n settings.

Reseller should create the overrides, then sub-account can get branded data when they include the reseller's whilteabel domain in URL:

```
GET /v2/whitelabel/{{domain}}/apps_store
```



### Schema

Application Whitelabel



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`i18n` | Application translation | [#/definitions/app_i18n](#app_i18n) |   | `false` |
`icon` | Application icon | `string()` |   | `false` |
`screenshots.[]` |   | `string()` |   | `false` |
`screenshots` |   | `array(string())` |   | `false` |

### app_i18n

Application translation


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`[a-z]{2}\-[A-Z]{2}.description` |   | `string(3..)` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.extended_description` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.features.[]` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.features` |   | `array(string())` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.icon` | I18N application icon attachment name | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.label` |   | `string(3..64)` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.screenshots.[]` |   | `string()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.screenshots` |   | `array(string())` |   | `false` |
`[a-z]{2}\-[A-Z]{2}.urls` |   | `object()` |   | `false` |
`[a-z]{2}\-[A-Z]{2}` |   | `object()` |   | `false` |



### Fetch app whitelabel overrides

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override
```
```json

```

!!! note: this will 404 if you haven't created the override via PUT yet

### Create app whitelabel overrides

> PUT /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override \
    -d {"data":{"screenshots":[], "icon":"", "i18n":{}}}
```

### Change app whitelabel overrides

> POST /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override
```

### Remove app whitelabel overrides

> DELETE /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override
```

### Fetch branded icon

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "Accept: image/png" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon
```

The response body will be the PNG file (not base64 encoded).

### Change branded icon

> POST /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon

See [Multipart](./multipart.md) on different ways to upload files.

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -H "content-type: multipart/form-data; boundary={BOUNDARY}" \
    -H "accept: application/json" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon
```

```json
{
  "data":{
    "i18n":{
      "en-US":{
        "icon":"icon-en-US-image-icon.png"
      }
    },
    "id":"app_whitelabel-{ID}"
  },
  "status":"success"
}
```

### Remove branded icon

> DELETE /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/icon
```

### Fetch branded screenshot at an index

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot/{APP_SCREENSHOT_INDEX}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot/{APP_SCREENSHOT_INDEX}
```

### Change branded screenshot

You must supply the same filename in the request to replace the old image. Otherwise this will be added as a new screenshot.

See [Multipart](./multipart.md) on different ways to upload files.

> POST /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot
```

### Remove branded screenshot at an index

> DELETE /v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot/{APP_SCREENSHOT_INDEX}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/{APP_ID}/override/screenshot/{APP_SCREENSHOT_INDEX}
```

## 2600Hz Marketplace Connector

This is an API endpoint to interact with 2600Hz Marketplace Connector and its
configurations. Sysadmins (super duper admins) are expected to use this API to setup their
Kazoo Cluster to be able to use Kazoo Applications from 2600Hz Marketplace.

Sysadmins can browse and purchase applications from 2600Hz Marketplace. To use those
apps, Kazoo needs to be configured and linked to Marketplace Server to be able to request
access to Apps.

After cluster is linked to Marketplace Server, and all things are configured, sysadmins can
purchase apps from Marketplace, then try to load and start the apps in their cluster.

Please consult each application documentation or Marketplace to see how to initially
config the app and then how to start them.

When starting applications purchase through Marketplace, Kazoo will see the app is
available locally and tries to ask Marketplace Server to check if the sysadmin has access
to the app, and will fetch, load and start the app on demand.

Please consult 2600Hz [Marketplace Doc](https://marketplace.2600hz.com/docs) for more
information.

!!! note
    Only Super Duper admin as the owner of the cluster can be able to access the Marketplace Connector API.

### Get Marketplace Connector Configurations

> GET /v2/accounts/{ACCOUNT_ID}/apps_store/marketplace

Super duper admin can use this API to get the Marketplace Connector settings and its link
state. This is useful to get info to show in Marketplace Connector page in UI.

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/apps_store/marketplace
```

#### Sample successful response

This is a sample response, in this case cluster is already linked and properly configured
and is ready to access the purchased apps.

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "cluster_id": "d9b4a2bb568f7a2cd2f25e6f733209a3",
        "enabled": true,
        "app_exchange_url": "https://localhost:8080",
        "api_url": "http://localhost:8000/v2/",
        "marketplace_url": "https://marketplace.2600hz.com",
        "is_linked": true,
        "is_aio_cluster": true,
        "name": "cluster001",
        "kazoo_version": "5.3.11"
    },
    "request_id": "{REQUEST_ID}",
    "status": "success"
}
```


### Enable Marketplace Connector


> PATCH /v2/apps_store/marketplace
>
> ```shell
> curl -v -X PATCH \
>     -H "X-Auth-Token: {AUTH_TOKEN}" \
>     http://{SERVER}:8000/v2/apps_store/marketplace \
>     -d '{"data":{"action":"enable"}}'
> ```

To enable starting apps off the marketplace, super duper admin can use this API to enable it.

Please note this won't start the apps from marketplace and sysadmin still need to perform
starting the apps manually using `sup` commands!

This app won't have any effect on stopping the marketplace apps.


### Disable Marketplace Connector

> PATCH /v2/apps_store/marketplace
>
> ```shell
> curl -v -X PATCH \
>     -H "X-Auth-Token: {AUTH_TOKEN}" \
>     http://{SERVER}:8000/v2/apps_store/marketplace \
>     -d '{"data":{"action":"disable"}}'
> ```

In case the sysadmin decided to disable starting apps off the marketplace, super duper
admin can use this API to disable it.

Please note this won't stop the currently running apps that have been fetched from the marketplace!
To stop those apps, sysadmin needs to stop each app manually using `sup` commands.


### Link Cluster to Marketplace

> PATCH /v2/apps_store/marketplace
>
> ```shell
> curl -v -X PATCH \
>     -H "X-Auth-Token: {AUTH_TOKEN}" \
>     http://{SERVER}:8000/v2/apps_store/marketplace \
>     -d '{"data":{"action":"link","access_code":"test","settings":{"name":"My Cool Cluster","is_aio_cluster":true}}}'
> ```

This will link the cluster to 2600Hz Marketplace server. Sysadmin first needs to get an
Access Code from Marketplace Portal, in [Manage
Cluster] (https://marketplace.2600hz.com/settings/account/manage-cluster) section.

The only required payload is `access_code` that you got from Marketplace Portal, the
settings is optional. It suggested at least set a friendly name for your cluster so you
can recognize it in Marketplace Portal.


#### Request Schema

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`access_code` | Access Code from Marketplace Portal during cluster link request | `string()` |   | `true`  | `true` |
`settings.api_url` | Crossbar API URL to be used to serve UI applications | `string()` |   | `false` |
`settings.is_aio_cluster` | Indicates all Kazoo VM nodes are running same list of Kazoo Apps | `boolean()` |   | `false` |
`settings.name` | A friendly name for cluster | `string()` |   | `false` |
`settings` |   | `object()` |   | `false` |


### Unlink Cluster from Marketplace

> PATCH /v2/apps_store/marketplace
>
> ```shell
> curl -v -X PATCH \
>     -H "X-Auth-Token: {AUTH_TOKEN}" \
>     http://{SERVER}:8000/v2/apps_store/marketplace \
>     -d '{"data":{"action":"unlink"}}'
> ```

If the sysadmin decided to unlink their cluster from Marketplace, they can use this API to
do so.

Please note this won't stop the currently running apps that are fetched off marketplace.
Also, your purchases in your Marketplace Account won't be affected and you are going to
billed for them.


### Updating Marketplace Connector Configurations

> PATCH /v2/apps_store/marketplace
>
> ```shell
> curl -v -X PATCH \
>     -H "X-Auth-Token: {AUTH_TOKEN}" \
>     http://{SERVER}:8000/v2/apps_store/marketplace \
>     -d '{"data":{"action":"update","settings":{"api_url":"http://localhost:8000/v2","name":"Super cool name","is_aio_cluster":true}}}'
> ```

Super duper admin can use this to update and control the settings of Marketplace
Connector.

#### Request Payload schema

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`settings.api_url` | Crossbar API URL to be used to serve UI applications | `string()` |   | `false` |
`settings.is_aio_cluster` | Indicates all Kazoo VM nodes are running same list of Kazoo Apps | `boolean()` |   | `false` |
`settings.name` | A friendly name for cluster | `string()` |   | `false` |
`settings` |   | `object()` |   | `false` |

- `api_url`: this is the Crossbar API URL, and is being used to serve the UI applications
  assets. If you don't set this setting, the UI applications from Marketplace won't be
able to start or work.
- `is_aio_cluster`: This indicates that All of Kazoo VM node servers in your cluster are
running the same list of Kazoo apps across your whole cluster. This is the intended way of
using Marketplace apps. If you don't set this to `true`, you're in expert mode. This means you as sysadmin is
knowing how to setup and start marketplace apps on your own, you


#### Sample successful response

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "cluster_id": "d9b4a2bb568f7a2cd2f25e6f733209a3",
        "enabled": true,
        "app_exchange_url": "https://localhost:8080",
        "api_url": "http://192.168.1.150:8000/v2/",
        "marketplace_url": "https://marketplace.2600hz.com",
        "is_linked": true,
        "is_aio_cluster": true,
        "name": "cluster001",
        "kazoo_version": "5.3.11"
    },
    "request_id": "{REQUEST_ID}",
    "status": "success"
}
```

### Screenpops

#### About Screenpops

This API is intended to serve as an information source for screenpops:

* Store data sent by users from screenpops-admin.
* Show the data in the preview of how the screenpop should look like.
* Serve the screenpop data when receiving a call.

Permissions object used to set/identify which users are allowed and not allowed for an screenpop. This has 3 keys, all_users, allow and deny. For a screenpop for a specific userid if (all_users=true or userid in allow list) and (userid not in deny list) the screenpop will be allowed for that specific userid.

#### Schema



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`custom_parameters.[].custom_url` | Stores the dynamic link URL | `string()` |   | `false` |  
`custom_parameters.[].link_text` | Stores the value of the custom text for the custom_url | `string()` |   | `false` |  
`custom_parameters.[].name` | Contains the name that can be used to identify the caller | `string()` |   | `false` |  
`custom_parameters.[].render_name_as_label` | Stores whether the name will be shown in the screenpop | `boolean()` |   | `false` |  
`custom_parameters.[].request_method` | Stores the HTTP method of the external source parameters | `string()` |   | `false` |  
`custom_parameters.[].token` | Represents a dynamic value that can will be replaced by either a system data or a custom source | `string()` |   | `false` |  
`custom_parameters.[].type_custom_parameter` | Contains the type of information the screenpop will load (no additional data, System Data, Dynamic Link, External Data) | `string()` |   | `false` |  
`custom_parameters.[].url` | Stores the URL to fetch the external source parameters | `string()` |   | `false` |  
`custom_parameters.[].url_parameters.[].name` | Contains the name for the url_parameters | `string()` |   | `false` |  
`custom_parameters.[].url_parameters.[].value` | Contains the value for the url_parameters | `string()` |   | `false` |  
`custom_parameters.[].url_parameters` | Contains all the url custom params defined to concat to the custom url | `array(object())` |   | `false` |  
`custom_parameters` |   | `array(object())` |   | `false` |  
`permissions.all_users` | Whether the screenpop allowed for all users in the account | `boolean()` | `true` | `false` |  
`permissions.allow.[]` |   | `string()` |   | `false` |  
`permissions.allow` | Specific list of users who are allowed the screenpop | `array(string())` | `[]` | `false` |  
`permissions.deny.[]` |   | `string()` |   | `false` |  
`permissions.deny` | Specific list of users who are not allowed the screenpop | `array(string())` | `[]` | `false` |  
`permissions` | Used when screenpops are allowed for userwise, this object contains which users are allowed and not allowed for a screenpop | `object()` | `{}` | `false` |  
`post_call_extension_time` | Contains the time the screenpop will remain active when the temporal type is selected. | `number()` |   | `false` |  
`show_location_call_time` | Flag field for location and local time of customer call | `boolean()` | `false` | `false` |  
`type_screenpops` | Type of screenpops | `string()` | `notification` | `false` |  



#### Fetch all screenpops for an Account

> GET /v2/accounts/{ACCOUNT_ID}/screenpops

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": [
        {
            "id": "3e665f11ca893955d7dd770b7241b6b6",
            "flags": [],
            "features": [],
            "custom_parameters": [
                {
                    "type_custom_parameter": "external_data",
                    "name": "CRM Lookup",
                    "render_name_as_label": false,
                    "url": "example.com/crm_lookup"
                }
            ],
            "post_call_extension_time": 35,
            "type_screenpops": "persistent",
            "show_location_call_time": false,
            "permissions": {
                "allow": [
                    "56dfa34418a30b7f14b7a71d29774071"
                ],
                "deny": [],
                "all_users": false
            }
        },
        {
            "id": "03568e5dd9a35aa0afed4eec58e6d9ab",
            "flags": [],
            "features": [],
            "custom_parameters": [
                {
                    "type_custom_parameter": "system_data",
                    "name": "Caller Number",
                    "render_name_as_label": false,
                    "token": "<<caller_id_number>>"
                }
            ],
            "post_call_extension_time": 15,
            "type_screenpops": "notification",
            "show_location_call_time": false,
            "permissions": {
                "allow": [],
                "deny": [],
                "all_users": true
            }
        }
    ],
  "revision": "{REVISION}",
  "metadata": {},
  "status": "success"

}
```

#### Fetch screenpops allowed for an user

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/screenpops

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/screenpops
```

```json
{ "auth_token": "{AUTH_TOKEN}",
  "data": [
        {
            "type_screenpops": "notification",
            "post_call_extension_time": 15,
            "custom_parameters": [
                {
                    "type_custom_parameter": "system_data",
                    "name": "Caller Number",
                    "render_name_as_label": false,
                    "token": "<<caller_id_number>>"
                }
            ],
            "permissions": {
                "allow": [],
                "deny": [],
                "all_users": true
            },
            "show_location_call_time": false,
            "flags": [],
            "features": [],
            "id": "03568e5dd9a35aa0afed4eec58e6d9ab"
        },
        {
            "type_screenpops": "persistent",
            "post_call_extension_time": 35,
            "custom_parameters": [
                {
                    "type_custom_parameter": "external_data",
                    "name": "CRM Lookup",
                    "render_name_as_label": false,
                    "url": "example.com/crm_lookup"
                }
            ],
            "permissions": {
                "allow": [
                    "56dfa34418a30b7f14b7a71d29774071"
                ],
                "deny": [],
                "all_users": false
            },
            "show_location_call_time": false,
            "flags": [],
            "features": [],
            "id": "3e665f11ca893955d7dd770b7241b6b6"
        }
    ],
    "revision": "3d1c7f179a36c496c708032b8417ff8a",
    "metadata": {},
    "status": "success"
}
```

#### Fetch a screenpop by id

> GET /v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
      "type_screenpops": "persistent",
      "post_call_extension_time": 35,
      "custom_parameters": [
          {
              "type_custom_parameter": "external_data",
              "name": "CRM Lookup",
              "render_name_as_label": false,
              "url": "example.com/crm_lookup"
          }
      ],
      "permissions": {
          "allow": [
              "56dfa34418a30b7f14b7a71d29774071"
          ],
          "deny": [],
          "all_users": false
      },
      "show_location_call_time": false,
      "id": "{SCREENPOPS_ID}"
  },
  "metadata": {
    "modified": 63796787745,
    "id": "{SCREENPOP_ID}",
    "created": 63796787745
  },
  "revision": "{REVISION}",
  "status": "success"
}
```

#### Create a new screenpop

> PUT /v2/accounts/{ACCOUNT_ID}/screenpops

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d "{"data":{"type_screenpops": "notification","post_call_extension_time": 15,"custom_parameters": [{"type_custom_parameter": "system_data","name": "Caller Number","render_name_as_label": false,"token": "Token"}],"permissions": {"allow": [],"deny": [],"all_users": true}}}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
      "type_screenpops": "notification",
      "post_call_extension_time": 15,
      "custom_parameters": [
          {
              "type_custom_parameter": "system_data",
              "name": "Caller Number",
              "render_name_as_label": false,
              "token": "Token"
          }
      ],
      "permissions": {
          "allow": [],
          "deny": [],
          "all_users": true
      },
      "show_location_call_time": false,
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab"
  },
  "revision": "1-b171790b8c3687ca2026395a7f086603",
  "metadata": {
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab",
      "created": 63839872247,
      "modified": 63839872247
  },
  "status": "success"
}
```

#### Patch

> PATCH /v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d "{"data":{"permissions": {"allow": ["56dfa34418a30b7f14b7a71d29774071"],"deny": [],"all_users": false}}}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
      "type_screenpops": "notification",
      "show_location_call_time": false,
      "post_call_extension_time": 15,
      "permissions": {
          "deny": [],
          "allow": [
              "56dfa34418a30b7f14b7a71d29774071"
          ],
          "all_users": false
      },
      "custom_parameters": [
          {
              "type_custom_parameter": "system_data",
              "name": "Caller Number",
              "render_name_as_label": false,
              "token": "<<caller_id_number>>"
          }
      ],
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab"
  },
  "metadata": {
    "modified": 63796962651,
    "id": "{SCREENPOP_ID}",
    "created": 63796961940
  },
  "revision": "{REVISION}",
  "status": "success"
}
```

#### Post

> POST /v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d "{"data": {"type_screenpops": "notification","show_location_call_time": false,"post_call_extension_time": 15,"permissions": {"deny": [],"allow": ["56dfa34418a30b7f14b7a71d29774071"],"all_users": false},"custom_parameters": [{"type_custom_parameter": "system_data","name": "Caller Number","render_name_as_label": false,"token": "Token2"}]}}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOPS_ID}
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
      "type_screenpops": "notification",
      "show_location_call_time": false,
      "post_call_extension_time": 15,
      "permissions": {
          "deny": [],
          "allow": [
              "56dfa34418a30b7f14b7a71d29774071"
          ],
          "all_users": false
      },
      "custom_parameters": [
          {
              "type_custom_parameter": "system_data",
              "name": "Caller Number",
              "render_name_as_label": false,
              "token": "Token2"
          }
      ],
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab"
  },
  "metadata": {
    "modified": 63796963125,
    "id": "{SCREENPOP_ID}",
    "created": 63796961974
  },
  "revision": "{REVISION}",
  "status": "success"
}
```

## Remove

> DELETE /v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOP_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/screenpops/{SCREENPOP_ID}
```

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": {
      "type_screenpops": "notification",
      "show_location_call_time": false,
      "post_call_extension_time": 15,
      "permissions": {
          "deny": [],
          "allow": [
              "56dfa34418a30b7f14b7a71d29774071"
          ],
          "all_users": false
      },
      "custom_parameters": [
          {
              "type_custom_parameter": "system_data",
              "name": "Caller Number",
              "render_name_as_label": false,
              "token": "Token2"
          }
      ],
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab"
  },
  "revision": "4-d438fec8866aaf89186307232f3a42ae",
  "metadata": {
      "id": "03568e5dd9a35aa0afed4eec58e6d9ab",
      "created": 63839872247,
      "modified": 63839874971,
      "deleted": true
  },
  "status": "success"
}
```
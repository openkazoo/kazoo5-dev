# Lists

Lists API offers a new way to save contacts.

Through the entries associated with a list, you can generate the behavior of a series of contacts which can be accessed by users who have different permissions or ownership over the list.

As an example, in the callflows when looking up a contact to set the caller id, if a contact matches then the caller id returned is of `type: voice and primary: true` unless there are no primary voice entries in which case its just the first voice entry.

### Examples

Sample contact list document

```json
{
    "data": {
        "first_name": "User",
        "contacts": [
            {
                "type": "voice",
                "contact": "4156546297",
                "primary": false,
                "device_type": "mobile"
            },
            {
                "type": "voice",
                "contact": "4158867903",
                "primary": true,
                "device_type": "work"
            },
            {
                "type": "email",
                "contact": "bitbashing@gmail.com",
                "primary": false,
                "email_type": "home"
            },
            {
                "type": "email",
                "contact": "user@2600hz.com",
                "primary": false,
                "email_type": "work"
            },
            {
                "type": "email",
                "contact": "user@ooma.com",
                "primary": true,
                "email_type": "work"
            }
        ]
    }
}
```

Sample Response for the given document

```json
{
    "data": [
        {
            "id": "ffd5db89a6d91d95c482d9f2408c3727",
            "first_name": "User",
            "contacts": [
                {
                    "voice": "4158867903"
                },
                {
                    "email": "user@ooma.com"
                }
            ],
            "favorite": false
        }
    ]
}
```

#### Schema

Schema for a match list



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`description` | A friendly list description | `string(1..128)` |   | `false` |  
`name` | A friendly match list name | `string(1..128)` |   | `true` |  
`org` | Full legal name of the organization | `string()` |   | `false` |  



### Schema for a list of contacts

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`capture_group.key` | The number which is used to select this contact, length should be same as `capture_group_length` | `string()` |  | `false` |  
`capture_group.length` | Length of the numbers in the contacts for which it used to select desire Caller ID | `integer()` |  | `false` |  
`capture_group` | The capture group information | `object()` | `{}` | `false` |  
`contacts` | A list of contact information | `array([#/definitions/contacts](#contacts))` |  | `true` | 
`favorite` | Whether the contact is a favorite | `boolean()` | `false` | `false` |  
`first_name` | The first name of the contact | `string()` |  | `true` |  
`history` | The history of contact usage | `array([#/definitions/history](#history))` | `[]` | `false` |  
`last_name` | The last name of the contact | `string()` |  | `false` |  
`organization.name` | The name of the organization | `string()` |  | `false` |  
`organization` | The organization this entity belongs to | `object()` | `{}` | `false` |  
`pattern` | Match pattern | `string()` |  | `false` |  
`tags.[]` |   | `string()` |   | `false` |  
`tags` | Tags that contact belong to | `array(string())` |   | `false` | 

### contacts

Schema for a contact.

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`contact` | The phone number or email associated with the contact (Ex: +14158867903, user@2600hz.com) | `string()` |  | `true` | 
`device_type` | The type of the device | `string('work', 'home', 'mobile', 'personal', 'fax')` |  | `false` |  
`email_type` | The type of the email | `string('work', 'home')` |  | `false` |  
`ext` | The extension of the user (Ex: 356, 622) | `string()` |  | `false` |  
`primary` | If this is the primary contact for this contact type. | `boolean()` |  | `true` |  
`type` | The type of this contact | `string('voice', 'email', 'sms')` |  | `true` |  

There is only one `primary` contact (`primary`: `true`) for a given contact `type`. Otherwise, it will result `400 Validation Error` HTTP response status with response payload like this:

```json
{
    "data": {
        "contacts": {
            "primary": {
                "message": "more than one primary contact for a contact type"
            }
        }
    },
    "error": "400",
    "message": "validation error",
    "status": "error"
}
```

### history

Schema for a history.

Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`contact` | The contact that was used | [#/definitions/contacts](#contacts) |  | `true` | 
`notes` | Notes from the communication | `string()` |  | `false` |  
`timestamp` | The gregorian timestamp | `integer()` |  | `false` |  

### Company Contact (No associated Owner ID)

Company contact does not contain an `owner_id` and these endpoints do not associate with `users/user_id`.

If auth token does not belong to an admin, only `GET` requests are continued.
If you perform a request other than `GET` and the auth token does not belong to an admin, the request is stopped. It will result in `403 Forbidden` HTTP response status with response payload like this:

```json
{
    "data": {
        "message": "only admins have permissions for this operation"
    },
    "error": "403",
    "message": "forbidden",
    "status": "error"
}
```

#### Fetch

Lists all contacts in the account that have no/empty owner_id

> GET /v2/accounts/{ACCOUNT_ID}/lists

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CONTACT_ID}",
            "name": "User",
            "contacts": [
                {
                    "voice": "1234567890"
                },
                {
                    "email": "user@2600hz.com"
                },
                {
                    "sms": "1234567891"
                }
            ],
            "favorite": false
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Fetch contact lists by Tag

Lists all contacts in the account that have no/empty owner_id and the document has a tag that matches the tag in the URL (without the prefix “tag-“)

> GET /v2/accounts/{ACCOUNT_ID}/lists/tag-{tag}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/tag-{TAG1}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CONTACT_ID}",
            "name": "User",
            "contacts": [
                {
                    "voice": "1234567890"
                },
                {
                    "email": "user@2600hz.com"
                },
                {
                    "sms": "1234567891"
                }
            ],
            "favorite": false,
            "tags": [
                "{TAG1}",
                "{TAG2}"
            ]
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Fetch a contact list

Fetches the contact of given contact_id, if it has no/empty owner_id

> GET /v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "favorite": false,
        "history": [],
        "organization": {},
        "first_name": "User",
        "contacts": [
            {
                "type": "voice",
                "contact": "1234567890",
                "primary": true
            },
            {
                "type": "email",
                "contact": "user@2600hz.com",
                "primary": true
            },
            {
                "type": "sms",
                "contact": "1234567891",
                "primary": true
            }
        ],
        "id": "{CONTACT_ID}"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```


#### Create a new contact list

Creates a new company contact only if the auth token belongs to an admin

> PUT /v2/accounts/{ACCOUNT_ID}/lists

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{
            "data": {
                "first_name": "User",
                "contacts": [
                    {
                        "type": "voice",
                        "contact": "1234567890",
                        "primary": true
                    },
                    {
                        "type": "email",
                        "contact": "user@2600hz.com",
                        "primary": true
                    },
                    {
                        "type": "sms",
                        "contact": "1234567891",
                        "primary": true
                    }
                ]
            }
        }' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists
```

Response is the full contact list doc, same as fetching a contact list by contact ID.

#### Replace contact list

Replaces an existing company contact, only if the auth token belongs to an admin

> POST /v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{
            "data": {
                "first_name": "User",
                "contacts": [
                    {
                        "type": "voice",
                        "contact": "1234567890",
                        "primary": true
                    },
                    {
                        "type": "email",
                        "contact": "user@2600hz.com",
                        "primary": false
                    },
                    {
                        "type": "sms",
                        "contact": "1234567891",
                        "primary": false
                    }
                ]
            }
        }' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}
```

Request and response are same as create API.

#### Delete contact list

Deletes an existing company contact only if auth token belongs to an admin

> DELETE /v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}
```

#### Update contact list

Patches an existing company contact only if the auth token belongs to an admin

> PATCH /v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"favorite": true}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/lists/{CONTACT_ID}
```

Response is the full contact list doc, same as fetching a contact list by contact ID.


### Personal Contact (With Owner ID)

Personal contact contains an `owner_id` and these endpoints associate with `users/user_id`.

- If the `auth token` belongs to an admin, allows the request to continue.
- If the `auth token` does not belong to an admin,
    - The `owner_id` of the `auth token` must match the `user_id` in the URL.
    - Otherwise, the request is stopped and it will result in `403 Forbidden` HTTP response status with response payload like this:

        ```json
        {
            "data": {
                "message": "auth token user and requested user doesn't match"
            },
            "error": "403",
            "message": "forbidden",
            "status": "error"
        }
        ```

**If the `auth token` does not belong to an admin, auth token `owner_id` must match the `user_id` in the URL**


- For entity URLS which contains {CONTACT_ID} like `GET`, `POST`, `PATCH`, `DELETE`
    - The `owner_id` of the given contact must match the `user_id` in the URL.
    - Otherwise, the request is stopped and it will result in `400 Validation Error` HTTP response status with response payload like this:

        ```json
        {
            "data": {
                "owner_id": {
                    "missmatch": {
                        "message": "request userid token and contact owner_id doesn't match"
                    }
                }
            },
            "error": "400",
            "message": "validation error",
            "status": "error"
        }
        ```

**For entity URLs, contact `owner_id` must match the `user_id` in the URL**



#### Fetch contact lists by User Id

Lists all contacts in the account where the `owner_id` is empty or matches the `user_id` in the URL.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CONTACT_ID}",
            "name": "User",
            "contacts": [
                {
                    "voice": "1234567890"
                },
                {
                    "email": "user@2600hz.com"
                },
                {
                    "sms": "1234567891"
                }
            ],
            "favorite": false
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Fetch contact lists by Tag and User Id

Lists all contacts in the account that match the tag (whithout the prefix “tag-“) and the `owner_id` is empty or matches the `user_id` in the URL.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/tag-{tag}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/tag-{TAG1}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": [
        {
            "id": "{CONTACT_ID}",
            "name": "User",
            "contacts": [
                {
                    "voice": "1234567890"
                },
                {
                    "email": "user@2600hz.com"
                },
                {
                    "sms": "1234567891"
                }
            ],
            "favorite": false,
            "tags": [
                "{TAG1}",
                "{TAG2}"
            ]
        }
    ],
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```

#### Fetch a contact list by User Id

Fetches the contact of given contact_id, if the `user_id` in the URL matches `owner_id` of the contact.

> GET /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}
```

```json
{
    "auth_token": "{AUTH_TOKEN}",
    "data": {
        "favorite": false,
        "history": [],
        "organization": {},
        "first_name": "User",
        "contacts": [
            {
                "type": "voice",
                "contact": "1234567890",
                "primary": true
            },
            {
                "type": "email",
                "contact": "user@2600hz.com",
                "primary": true
            },
            {
                "type": "sms",
                "contact": "1234567891",
                "primary": true
            }
        ],
        "id": "{CONTACT_ID}"
    },
    "request_id": "{REQUEST_ID}",
    "revision": "{REVISION}",
    "status": "success"
}
```


#### Create a new contact list with User Id

Creates a new contact with `user_id` in the URL as the `owner_id` of the contact.

> PUT /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{
            "data": {
                "first_name": "User",
                "contacts": [
                    {
                        "type": "voice",
                        "contact": "1234567890",
                        "primary": true
                    },
                    {
                        "type": "email",
                        "contact": "user@2600hz.com",
                        "primary": true
                    },
                    {
                        "type": "sms",
                        "contact": "1234567891",
                        "primary": true
                    }
                ]
            }
        }' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists
```

Response is the full contact list doc, same as fetching a contact list by contact ID.

#### Replace contact list with User Id

Replaces an existing contact, only if the `user_id` in the URL matches `owner_id` of the contact.

> POST /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{
            "data": {
                "first_name": "User",
                "contacts": [
                    {
                        "type": "voice",
                        "contact": "1234567890",
                        "primary": true
                    },
                    {
                        "type": "email",
                        "contact": "user@2600hz.com",
                        "primary": false
                    },
                    {
                        "type": "sms",
                        "contact": "1234567891",
                        "primary": false
                    }
                ]
            }
        }' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}
```

Request and response are same as create API.

#### Delete contact list with User Id

Deletes an existing contact, only if the `user_id` in the URL matches `owner_id` of the contact.

> DELETE /v2/accounts/{ACCOUNT_ID}/lists/users/{USER_ID}/{CONTACT_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}
```

#### Update contact list with User Id

Patches an existing contact, only if the `user_id` in the URL matches `owner_id` of the contact.

> PATCH /v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    -d '{"data": {"favorite": true}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/lists/{CONTACT_ID}
```

Response is the full contact list doc, same as fetching a contact list by contact ID.

**If you want to access a contact and the contact list has an owner id, the user must be an admin or owner of that list**

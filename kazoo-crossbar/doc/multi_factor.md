# Multi Factor Authentication Configuration

## About Multi Factor

API endpoint to configure Crossbar Multi Factor Authentication (MFA) providers.

See [Kazoo Auth multi factor documentation](../../../core/kazoo_auth/doc/multi_factor.md) to learn more about available providers and their required settings.

## Enable MFA for a Crossbar auth module

If you want to use multi factor authentication for a module, set the `multi_factor.enabled` to `true` for that authentication module. You can control if the multi factor settings can be applied to the account's children by `multi_factor.include_subaccounts`. See [Crossbar Security API documentation](./security.md).

!!! note
    You can specify the `id` of multi factor provider settings. If you miss this value, system's default MFA provider will be used!

## Multi Factor Authentication (MFA) flow summary

The MFA process in Kazoo is straight forward. Configure the KAZOO integrated MFA service provider and enable the multi-factor setting for an authentication endpoint. A user (for example) will authenticate as usual by their KAZOO credentials. If the first factor authentication passed, second-factor provider information (usually a signed token) would be returned to client with HTTP `401 Unauthorized` status.

User's client performs the second-factor authentication with the provider and sends provider response to Kazoo in the `multi_factor_response` key. If the provider validates true, the user will be authenticated successfully and a KAZOO token will be generated as usual; otherwise, if the second-factor provider response is not validated, an HTTP `401 Unauthorized` will be returned.

### OTP (one-time password) MFA flow

KAZOO comes with a built-in OTP MFA provider that can work with users' authenticator apps (like [Google Authenticator](https://googleauthenticator.net/)). Once configured, the user will include the TOTP code as part of the payload for authentication.

#### Setup OTP provider

!!! warning
    All API commands here require you to use an auth token generated for a super-duper admin.

First, you can see the available providers on the cluster:

> GET http://{SERVER}:8000/v2/multi_factor

```json
{
  "auth_token": "{AUTH_TOKEN}",
  "data": [
    {
      "enabled": false,
      "id": "duo",
      "name": "System Default Provider",
      "provider_name": "duo",
      "provider_type": "multi_factor"
    }
  ],
  "request_id": "{REQUEST_ID}",
  "revision": "{REV}",
  "status": "success"
}

```

Here you can see that the [DUO integration](https://duo.com/product/multi-factor-authentication-mfa) is available already.

Let's create the KAZOO OTP provider:

> PUT  http://{SERVER}:8000/v2/multi_factor -d '{"data":{"enabled":true,"name":"KAZOO","provider_name":"otp","settings": {}}}'

The important bit is `provider_name = otp`.

```json
{
  "data": {
    "enabled": true,
    "id": "{PROVIDER_ID}",
    "name": "KAZOO",
    "provider_name": "otp",
    "settings": {
    }
  },
  "metadata": {
    "created": 63814257545,
    "id": "{PROVIDER_ID}",
    "modified": 63814257545
  },
  "revision": "{REV}",
  "status": "success"
}
```

Now we need to create the security policy for the account we're enabling MFA for. First, check available security options:

> GET http://{SERVER}:8000/v2/security

```json
{
  "data": {
    "available_auth_methods": [
      "cb_api_auth",
      "cb_auth",
      "cb_ip_auth",
      "cb_user_auth"
    ]
  },
  "status": "success"
}
```

We can also look at the existing security policy for the account:

> GET http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/security
```json
{
  "data": {
    "account": {
    },
    "inherited_config": {
      "auth_modules": {
        "cb_api_auth": {
          "enabled": true,
          "log_failed_attempts": true,
          "log_successful_attempts": false,
          "scopes": [
            "crossbar"
          ],
          "token_auth_expiry_s": 3600
        },
        "cb_auth": {
          "enabled": true,
          "log_failed_attempts": true,
          "log_successful_attempts": false,
          "scopes": [
            "crossbar"
          ],
          "token_auth_expiry_s": 3600
        },
        "cb_conference_auth": {
          "enabled": true,
          "log_failed_attempts": true,
          "log_successful_attempts": false,
          "scopes": [
            "crossbar"
          ],
          "token_auth_expiry_s": "infinity"
        },
        "cb_ip_auth": {
          "enabled": true,
          "log_failed_attempts": true,
          "log_successful_attempts": false,
          "scopes": [
            "crossbar"
          ],
          "token_auth_expiry_s": 3600
        },
        "cb_user_auth": {
          "enabled": true,
          "log_failed_attempts": true,
          "log_successful_attempts": true,
          "scopes": [
            "crossbar"
          ],
          "token_auth_expiry_s": 3600
        }
      }
    }
  },
  "status": "success"
}
```

We specifically want users to be required to use MFA, so let's PATCH the `cb_user_auth` portion:

> PATCH http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/security -d '{"data":{"auth_modules":{"cb_user_auth":{"multi_factor":{"configuration_id":"{PROVIDER_ID}","account_id":"{ACCOUNT_ID}","enabled":true}}}}}'

Here we use the `{PROVIDER_ID}` of the KAZOO OTP provider creation earlier.

```json
{
  "data": {
    "auth_modules": {
      "cb_user_auth": {
        "multi_factor": {
          "account_id": "{ACCOUNT_ID}",
          "configuration_id": "{PROVIDER_ID}",
          "enabled": true
        },
        "scopes": []
      }
    },
    "id": "configs_crossbar.auth"
  },
  "status": "success"
}

```

#### User MFA Authentication

Now that the OTP provider is enabled and the account's security settings are ready for multi-factor authentication, let's look at a user's authentication flow.

First, the user needs to generate their QR code to scan into their authenticator application:

> GET http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/users/{USER_ID}/qrcode

The result of the API request will be a PNG QR code. The user should then open their authenticator application to scan the QR code.

Now, when the user tries to authenticate, the 401 response should include the `multi_factor_request` to indicate the need to include the current TOTP.

> PUT http://{SERVER}:8000/v2/user_auth -d '{"data":{"credentials":"{HASH}", "account_name":"{NAME}"}}'

```json
{
  "data": {
    "message": "client needs to preform second-factor authentication",
    "multi_factor_request": {
      "key_type": "totp",
      "provider_name": "otp"
    }
  },
  "error": "401",
  "message": "invalid_credentials",
  "status": "error"
}
```

At this point, the user should check the TOTP code on their authenticator application and include it on the subsequent request in the `multi_factor_response` key:

> PUT http://{SERVER}:8000/v2/user_auth -d '{"data":{"credentials":"{HASH}", "account_name":"{NAME}", "multi_factor_response":"{TOTP_CODE}"}}'

Here, `{TOTP_CODE}` is the 6-digit code.

Assuming the TOTP is correct (and KAZOO will check one time period before, the current time period, and the next time period to account for delays), the API request should respond with the generated auth token and expected user_auth response.

## Provider Configuration Schema

#### Schema

multi factor provider configuration



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`enabled` | whether or not this configuration is enabled or not | `boolean()` |   | `true` |
`name` | A friendly name for the configuration | `string()` |   | `true` |
`provider_name` | multi factor provider name | `string()` |   | `true` |
`settings` | provider configuration | `object()` |   | `false` |



## List Account Configuration and Available System Providers

List configured multi factor providers and available system multi factor provider.

> GET /v2/accounts/{ACCOUNT_ID}/multi_factor

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor
```

**Responses**

```json
{
  "data": {
    "configured": [
      {
        "id": "c757665dca55edba2395df3ca6423f4f",
        "enabled": true,
        "name": "a nice day",
        "provider_name": "duo",
        "provider_type": "multi_factor"
      }
    ],
    "multi_factor_providers": [
      {
        "id": "duo",
        "enabled": false,
        "name": "System Default Provider",
        "provider_name": "duo",
        "provider_type": "multi_factor"
      }
    ]
  },
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Create a Provider Configuration for an Account

Create configuration for a MFA provider. Provider config should be in `"settings"`. See [Kazoo Auth Multi-Factor](../../../core/kazoo_auth/doc/multi_factor.md) to find out required configuration for each provider.

> PUT /v2/accounts/{ACCOUNT_ID}/multi_factor

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"name": "another nice day", "enabled": true, "provider_name": "duo", "settings": {"integration_key": "{DUO_IKEY}", "secret_key": "{DUO_SKEY}", "application_secret_key": "{DUO_AKEY}", "api_hostname": "{DUO_HOST_NAME}", "duo_expire": 300,"app_expire": 3600}}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "another nice day",
    "enabled": true,
    "id": "c757665dca55edba2395df3ca6423f4f"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Fetch an Account's Provider Configuration

Get account's configuration of a provider.

> GET /v2/accounts/{ACCOUNT_ID}/multi_factor/{CONFIG_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/c757665dca55edba2395df3ca6423f4f
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "another nice day",
    "enabled": true,
    "id": "c757665dca55edba2395df3ca6423f4f"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Change an Account's Provider Configuration

> POST /v2/accounts/{ACCOUNT_ID}/multi_factor/{CONFIG_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"name": "another nice day with a change", "enabled": true, "provider_name": "duo", "settings": {"integration_key": "{DUO_IKEY}", "secret_key": "{DUO_SKEY}", "application_secret_key": "{DUO_AKEY}", "api_hostname": "{DUO_HOST_NAME}", "duo_expire": 300,"app_expire": 3600}}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/c757665dca55edba2395df3ca6423f4f
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "another nice day with a change",
    "enabled": true,
    "id": "c757665dca55edba2395df3ca6423f4f"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Patch Fields in an Account's Provider Configuration

> PATCH /v2/accounts/{ACCOUNT_ID}/multi_factor/{CONFIG_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"enabled": false}}' \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/c757665dca55edba2395df3ca6423f4f
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "another nice day with a change",
    "enabled": false,
    "id": "c757665dca55edba2395df3ca6423f4f"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Remove an Account's Provider Configuration

> DELETE /v2/accounts/{ACCOUNT_ID}/multi_factor/{CONFIG_ID}

```shell
curl -v -X DELETE \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/c757665dca55edba2395df3ca6423f4f
```

## Get a Summary of Multi Factor Login Attempts

> GET /v2/accounts/{ACCOUNT_ID}/multi_factor/attempts

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/attempts
```

**Responses**

```json
{
  "data": [
    {
      "id": "201702-09a979346eff06746e445a8cc1e574c4",
      "auth_type": "multi_factor",
      "auth_module": "cb_user_auth",
      "status": "failed",
      "message": "no multi factor authentication provider is configured",
      "timestamp": 63655033238,
      "client_ip": "10.1.0.2:8000",
    }
  ],
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Fetch Details of a Multi Factor Login Attempts

> GET /v2/accounts/{ACCOUNT_ID}/multi_factor/attempts/{ATTEMPT_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/multi_factor/attempts/201702-09a979346eff06746e445a8cc1e574c4
```

**Responses**

```json
{
  "data": {
    "auth_type": "multi_factor",
    "status": "failed",
    "auth_module": "cb_user_auth",
    "message": "no multi factor authentication provider is configured",
    "client_headers": {
      "host": "10.1.0.2:8000",
      "connection": "keep-alive",
      "content-length": "83",
      "accept": "application/json, text/javascript, */*; q=0.01",
      "x-auth-token": "undefined",
      "user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.39 Safari/537.36",
      "origin": "http://127.0.0.1:3000",
      "content-type": "application/json",
      "dnt": "1",
      "referer": "http://127.0.0.1:3000/",
      "accept-encoding": "gzip, deflate",
      "accept-language": "en-US,en;q=0.8"
    },
    "client_ip": "10.1.0.2:8000",
    "crossbar_request_id": "5dd9a7b69f74b3c09ca065316096b83e",
    "timestamp": 63655033238,
    "metadata": {
        "owner_id": "b6205d9a4a62d8e971c2d8f177676130",
        "account_id": "a391d64a083b99232f6d2633c47432e3"
    },
    "id": "201702-09a979346eff06746e445a8cc1e574c4"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## List System Multi Factor Providers

List system multi factor providers

> GET /v2/multi_factor

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/multi_factor
```

**Responses**

```json
{
  "page_size": 1,
  "start_key": [
    "multi_factor"
  ],
  "data": [
    {
      "id": "duo",
      "enabled": false,
      "name": "System Default Provider",
      "provider_name": "duo",
      "provider_type": "multi_factor"
    }
  ],
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Create a System Provider Configuration

Provider config should be in `"settings"`. See [Kazoo Auth Multi-Factor](../../../core/kazoo_auth/doc/multi_factor.md) to find out required configuration for each provider.

!!! note
    Only super duper admin can create system providers configuration!

> PUT /v2/multi_factor

```shell
curl -v -X PUT \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"name": "have a nice day", "enabled": true, "provider_name": "duo", "settings": {"integration_key": "{DUO_IKEY}", "secret_key": "{DUO_SKEY}", "application_secret_key": "{DUO_AKEY}", "api_hostname": "{DUO_HOST_NAME}", "duo_expire": 300,"app_expire": 3600}}}' \
    http://{SERVER}:8000/v2/multi_factor
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "have a nice day",
    "enabled": true,
    "id": "5c61dd2098466017f716417792f769cc"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Fetch a System Provider Configuration

!!! note
    Only super duper admin can get system providers configuration!

> GET /v2/multi_factor/{CONFIG_ID}

```shell
curl -v -X GET \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    http://{SERVER}:8000/v2/multi_factor/c757665dca55edba2395df3ca6423f4f
```

**Responses**

```json
{
  "data": {
    "settings": {},
    "provider_name": "duo",
    "name": "System Default Provider",
    "enabled": false,
    "id": "duo"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Change a System Provider Configuration

!!! note
    Only super duper admin can change system providers configuration!

> POST /v2/multi_factor/{CONFIG_ID}

```shell
curl -v -X POST \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"name": "System Default Provider", "enabled": true, "provider_name": "duo", "settings": {"integration_key": "{DUO_IKEY}", "secret_key": "{DUO_SKEY}", "application_secret_key": "{DUO_AKEY}", "api_hostname": "{DUO_HOST_NAME}", "duo_expire": 300,"app_expire": 3600}}}' \
    http://{SERVER}:8000/v2/multi_factor/duo
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "System Default Provider",
    "enabled": true,
    "id": "duo"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Patch fields in a System provider configuration

!!! note
    Only super duper admin can change system providers configuration!

> PATCH /v2/multi_factor/{CONFIG_ID}

```shell
curl -v -X PATCH \
    -H "X-Auth-Token: {AUTH_TOKEN}" \
    --data '{"data": {"enabled": false}}' \
    http://{SERVER}:8000/v2/multi_factor/duo
```

**Responses**

```json
{
  "data": {
    "settings": {
      "secret_key": "{DUO_SKEY}",
      "integration_key": "{DUO_IKEY}",
      "duo_expire": 300,
      "application_secret_key": "{DUO_AKEY}",
      "app_expire": 3600,
      "api_hostname": "{DUO_HOST_NAME}"
    },
    "provider_name": "duo",
    "name": "System Default Provider",
    "enabled": false,
    "id": "duo"
  },
  "revision": "{REVERSION}",
  "timestamp": "{TIMESTAMP}",
  "version": "{VERSION}",
  "node": "{NODE_HASH}",
  "request_id": "{REQUEST_ID}",
  "status": "success",
  "auth_token": "{AUTH_TOKEN}"
}
```

## Generate MFA QR Code

Generates a Multi-Factor Authentication (MFA) QR code based on the provided credentials and account name.
The response format depends on the Accept header:

Accept: application/json → Returns QR code URL
Accept: image/png → Returns QR code image

> PUT /v2/multi_factor/qrcode

```shell
curl -v -X PUT \
  -H "Accept: image/png" \
  -H "Content-Type: application/json" \
    --data '{"data": {"credentials": "{HASH}", "account_name": "{Account_Name}"}}' \
    http://{SERVER}:8000/v2/multi_factor/qrcode
```

**Responses**
!!!Note
  If the request headers include the Accept: application/json header, the response body will contain the QR code in JSON format. Otherwise, the response will be in image/png format. For a successful response, the status code will be 201 Created; if the request fails, the status code will be 401 along with the reason.
```json
{
    "qr_url": "otpauth://totp/KAZOO:admin?secret=X2TH5HHZRY754FG7FKSOQRQMUNWGIFXR&issuer=KAZOO&period=30"
}
```

## MFA Verification

Validate MFA using credentials and multi_factor_response

> PUT /v2/multi_factor/qrcode

```shell
curl -v -X PUT \
  -H "Content-Type: application/json" \
    --data '{"data": {"credentials": "{HASH}", "account_name": "{Account_Name}", "multi_factor_response": "{Totp_Code}"}}' \
    http://{SERVER}:8000/v2/multi_factor/qrcode
```

**Responses**
!!!Note
  If successful, return the response code 201 Created; otherwise, return the response code 401 with the reason

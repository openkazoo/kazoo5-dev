# Multi Factor Authentication Configuration for Duo Universal

Duo provides a "Universal" experience

Once the user has been prompted for their 2FA the UI will receive a `code` back. This code should be included in the authentication request to `/v2/user_auth`.

## System configuration

In your Duo admin panel, locate the Client ID, Client Secret, and API Hostname.

Configure your KAZOO cluster:

```bash
sup kapps_config set_default duo.universal client_id {DUO_CLIENT_ID}

sup kapps_config set_default duo.universal client_secret {DUO_CLIENT_SECRET}

sup kapps_config set_default duo.universal api_hostname {DUO_API_HOSTNAME}
```

Note: `{DUO_API_HOSTNAME}` will look something like `api-{8-char}.duosecurity.com`

### Test settings

Once your Duo settings are configured, test them by issuing a request to the [Health Check](https://duo.com/docs/oauthapi#health-check) API:

```bash
sup kz_mfa_duo_universal duo_health_check
health check resp: {"stat": "OK", "response": {"timestamp": {UNIX_TIMESTAMP}}}
```

## Configure KAZOO to use Duo as an MFA provider

As superduper admin, let's create the Duo OTP provider:

> PUT http://{SERVER}:8000/v2/multi_factor -d '{"data":{"enabled":true,"name":"Duo Universal","provider_name":"duo_universal","settings": {}}}'

The important bit is `provider_name = duo_universal`.

Note the response's ID, as this is the `{DUO_PROVIDER_ID}` used in later steps.

### Configure DUO settings for different accounts

Since different accounts (typically resellers) will have their own DUO accounts, the cluster operator can create multiple "providers" where the `settings` key contains the DUO configs to use:

> PUT http://{SERVER}:8000/v2/multi_factor -d '{"data":{"enabled":true,"name":"Duo Universal for Account {ACCOUNT_ID}","provider_name":"duo_universal","settings": {"client_id":"{DUO_CLIENT_ID}"}, "client_secret":"{CLIENT_SECRET}", "api_hostname":"https://{api_hostname}", "redirect_uri":"https://back.to.UI"}}}'

`provider_name` still must be `duo_universal` but `name` and `settings` should be per-account.

## Update an account's security policy

Look at the existing security policy for the account:

> GET http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/security

```json
{ ...
  "metadata": {},
  "data": {
    "account": {},
    "inherited_config": {}
  }
}
```

We specifically want users to be required to use MFA, so let's PATCH the `cb_user_auth` portion:

> PATCH http://{SERVER}:8000/v2/accounts/{ACCOUNT_ID}/security -d '{"data":{"auth_modules":{"cb_user_auth":{"multi_factor":{"configuration_id":"{DUO_PROVIDER_ID}","account_id":"{ACCOUNT_ID}","enabled":true}}}}}'

```json
{
  "data": {
    "auth_modules": {
      "cb_user_auth": {
        "multi_factor": {
          "account_id": "{ACCOUNT_ID}",
          "configuration_id": "{DUO_PROVIDER_ID}",
          "enabled": true
        },
        "scopes": []
      }
    },
    "id": "configs_crossbar.auth"
  }
}
```

Here we use the `{DUO_PROVIDER_ID}` of the Duo Universal provider creation earlier. Make sure you assign the correct provider ID if you're setting up per-account Duo Universal providers!

## User MFA Authentication

Now that the Duo provider is enabled and the account's security settings are ready for multi-factor authentication, let's look at a user's authentication flow.

> PUT http://{SERVER}:8000/v2/user_auth -d '{"data":{"credentials":"{HASH}", "account_name":"{NAME}"}}'

```json
{
  "data": {
    "message": "client needs to perform second-factor authentication",
    "multi_factor_request": {
      "provider_name": "duo_universal",
      "duo_redirect": "https://{api_hostname}/frame/frameless/v4/auth/...",
      "duo_state": "{STATE}"
    },
    "user_id":"{USER_ID}"
  },
  "error": "401",
  "message": "invalid_credentials",
  "status": "error"
}
```

At this point, the client should redirect to the Duo Authorization Request Endpoint, provide the 2FA to Duo which, if successful, will redirect back to the provided `redirect_uri` in the redirect to Duo. Included in the redirect back from Duo will be a `code` and `state` variables (`state` should match the value for `duo_state` returned in the 401 payload above).

Armed with this `code` and the `redirect_uri` used, the client should issue the user_auth request again:

> PUT http://{SERVER}:8000/v2/user_auth -d '{"data":{"credentials":"{HASH}", "account_name":"{NAME}", "multi_factor_response":{"code":"{CODE}", "redirect_uri":"https://{REDIRECT_URI}"}}}'

### Successful MFA check

Will match a typical user_auth response payload.

### Failing MFA check

```json
{
  "data": {
    "message": "client needs to perform second-factor authentication",
    "multi_factor_request": {
      "error": "invalid_grant",
      "error_description": "The provided authorization grant (e.g., authorization code) or refresh token is invalid, expired, revoked, does not match the redirection URI used in the authorization request, or was issued to another client."
    },
    "user_id": "{USER_ID}"
  },
  "error": "401",
  "message": "invalid_credentials"
}
```

KAZOO will use the code and redirect_uri to reach out to Duo's [access_token](https://duo.com/docs/oauthapi#access-token) API to verify the code against the user and confirm it matches the user attempting to authenticate.

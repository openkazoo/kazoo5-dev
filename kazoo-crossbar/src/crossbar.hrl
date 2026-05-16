-ifndef(CROSSBAR_HRL).

-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").
-include_lib("kazoo_documents/include/kazoo_documents.hrl").

-include("crossbar_types.hrl").

-define(APP, 'crossbar').
-define(APP_NAME, <<"crossbar">>).
-define(CROSSBAR_AUTH_BUCKET, <<"crossbar_auth_bucket">>).
-define(APP_VERSION, <<"4.0.0">>).
-define(CONFIG_CAT, ?APP_NAME).
-define(AUTH_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".auth">>).

-define(CACHE_NAME, 'crossbar_cache').

-define(INBOUND_HOOK, <<"hooks">>).

-define(CROSSBAR_DEFAULT_CONTENT_TYPE, {<<"application">>, <<"json">>, '*'}).

-define(CB_ACCOUNT_TOKEN_RESTRICTIONS, <<"token_restrictions">>).

-define(CONTENT_PROVIDED, [{'to_json', ?JSON_CONTENT_TYPES}
                          ,{'to_csv', ?CSV_CONTENT_TYPES}
                          ]).
-define(CONTENT_ACCEPTED, [{'from_json', ?JSON_CONTENT_TYPES}
                          ,{'from_form', ?MULTIPART_CONTENT_TYPES}
                          ,{'from_binary', ?CSV_CONTENT_TYPES}
                          ]).
-define(ALLOWED_METHODS, [?HTTP_GET
                         ,?HTTP_POST
                         ,?HTTP_PUT
                         ,?HTTP_DELETE
                         ,?HTTP_HEAD
                         ,?HTTP_PATCH
                         ,?HTTP_OPTIONS
                         ]).

-define(DEVICES_QCALL_NOUNS(DeviceId, Number)
       ,[{<<"quickcall">>, [Number]}
        ,{<<"devices">>, [DeviceId]}
        ,{?KZ_ACCOUNTS_DB, [_AccountId]}
        ]).
-define(USERS_QCALL_NOUNS(UserId, Number)
       ,[{<<"quickcall">>, [Number]}
        ,{<<"users">>, [UserId]}
        ,{?KZ_ACCOUNTS_DB, [_AccountId]}
        ]).

-define(DEFAULT_MODULES, ['cb_about'
                         ,'cb_accounts'
                         ,'cb_alerts'
                         ,'cb_api_auth'
                         ,'cb_apps_store'
                         ,'cb_auth'
                         ,'cb_basic_auth'
                         ,'cb_blacklists'
                         ,'cb_callflows'
                         ,'cb_cdrs'
                         ,'cb_channels'
                         ,'cb_clicktocall'
                         ,'cb_comments'
                         ,'cb_conference_auth'
                         ,'cb_conferences'
                         ,'cb_configs'
                         ,'cb_connectivity'
                         ,'cb_contact_list'
                         ,'cb_devices'
                         ,'cb_directories'
                         ,'cb_faxboxes'
                         ,'cb_faxes'
                         ,'cb_groups'
                         ,'cb_hotdesks'
                         ,'cb_ips'
                         ,'cb_ledgers'
                         ,'cb_limits'
                         ,'cb_media'
                         ,'cb_menus'
                         ,'cb_metaflows'
                         ,'cb_inbound_messaging'
                         ,'cb_multi_factor'
                         ,'cb_notifications'
                         ,'cb_parked_calls'
                         ,'cb_phone_numbers'
                         ,'cb_pivot'
                         ,'cb_port_requests'
                         ,'cb_presence'
                         ,'cb_quickcall'
                         ,'cb_rates'
                         ,'cb_registrations'
                         ,'cb_resource_templates'
                         ,'cb_resources'
                         ,'cb_schemas'
                         ,'cb_scopes'
                         ,'cb_scope_retrictions'
                         ,'cb_screenpops'
                         ,'cb_search'
                         ,'cb_security'
                         ,'cb_services'
                         ,'cb_simple_authz'
                         ,'cb_sms'
                         ,'cb_system_configs'
                         ,'cb_tasks'
                         ,'cb_temporal_rules'
                         ,'cb_temporal_rules_sets'
                         ,'cb_token_auth'
                         ,'cb_token_restrictions'
                         ,'cb_transactions'
                         ,'cb_user_auth'
                         ,'cb_users'
                         ,'cb_vmboxes'
                         ,'cb_webhooks'
                         ,'cb_websites'
                         ,'cb_websockets'
                         ,'cb_whitelabel'
                         ]).

-define(DEFAULT_RESP_ERROR_CODE, 500).

-define(MAX_RANGE, kapps_config:get_pos_integer(?CONFIG_CAT
                                               ,<<"maximum_range">>
                                               ,(?SECONDS_IN_DAY * 31 + ?SECONDS_IN_HOUR)
                                               )
       ).

-define(NUMBERS_COLLECTION, <<"collection">>).

-define(OPTION_EXPECTED_TYPE, 'expected_type').
-define(TYPE_CHECK_OPTION(ExpectedType), [{?OPTION_EXPECTED_TYPE, ExpectedType}]).
-define(TYPE_CHECK_OPTION_ANY, ?TYPE_CHECK_OPTION(<<"any">>)).

-define(CROSSBAR_HRL, 'true').

-define(DEFAULT_CONFIG_ID, <<"default">>).
-endif.

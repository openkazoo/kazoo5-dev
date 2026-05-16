%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(local_accounts).

-export([local/0
        ,local_cp_47/0
        ,local_kzoo_270/0
        ,cleanup/0, cleanup/1
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).
-define(CP_47_DESCENDENTS, 5).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_cp_47/0
                  ,fun local_kzoo_270/0
                  ]
                 ).

-spec local_cp_47() -> 'ok'.
local_cp_47() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account ~s", [AccountResp]),

    <<ParentAccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    AccountIds = seq_accounts:create_account_tree(API#{account_id => ParentAccountId}, ?CP_47_DESCENDENTS),
    lager:info("created parent ~s sub accounts: ~p", [ParentAccountId, AccountIds]),

    verify_enabled_status(API, [ParentAccountId | AccountIds], 'true'),
    crossbar_maintenance:cascade_disable_accounts(ParentAccountId),
    verify_enabled_status(API, [ParentAccountId | AccountIds], 'false'),
    cleanup(API).

%% Test migrating legacy call forward settings from account/user/device
-spec local_kzoo_270() -> 'ok'.
local_kzoo_270() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts', 'cb_users', 'cb_devices']),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account ~s", [AccountResp]),

    <<AccountId/binary>> = kz_json:get_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    AccountDoc = update_account_cfwd(AccountId),
    UserDoc = create_user_cfwd(AccountId),
    DeviceDoc = create_device_cfwd(AccountId),

    crossbar_maintenance:migrate([AccountId]),

    verify_cfwd(AccountId, [AccountDoc, UserDoc, DeviceDoc]),

    cleanup(API).

update_account_cfwd(AccountId) ->
    {'ok', AccountDoc} = kzd_accounts:fetch(AccountId),
    Updated = kz_json:set_value(<<"call_forward">>, legacy_cfwd(), AccountDoc),
    {'ok', Saved} = kzd_accounts:save(Updated),
    Saved.

create_user_cfwd(AccountId) ->
    BaseUser = kz_doc:update_pvt_parameters(seq_users:new_user()
                                           ,AccountId
                                           ,[{'type', kzd_users:type()}]
                                           ),
    User = kz_json:set_value(<<"call_forward">>, legacy_cfwd(), BaseUser),
    {'ok', Saved} = kz_datamgr:save_doc(AccountId, User),
    Saved.

create_device_cfwd(AccountId) ->
    BaseUser = kz_doc:update_pvt_parameters(seq_devices:new_device()
                                           ,AccountId
                                           ,[{'type', kzd_devices:type()}]
                                           ),
    User = kz_json:set_value(<<"call_forward">>, legacy_cfwd(), BaseUser),
    {'ok', Saved} = kz_datamgr:save_doc(AccountId, User),
    Saved.

verify_cfwd(_AccountId, []) -> 'ok';
verify_cfwd(AccountId, [Doc | Docs]) ->
    verify_migrated_doc(AccountId, Doc),
    verify_cfwd(AccountId, Docs).

verify_migrated_doc(AccountId, Doc) ->
    {'ok', Updated} = kz_datamgr:open_doc(AccountId, kz_doc:id(Doc)),

    LegacyCfwd = kz_json:get_json_value(<<"call_forward">>, Doc),
    NewCfwd = kzd_devices:call_forward(Updated),

    case verify_migrated_cfwd(LegacyCfwd, NewCfwd) of
        'true' -> 'ok';
        'false' ->
            lager:info("failed to match cfwd from legacy ~p to new ~p", [LegacyCfwd, NewCfwd]),
            lager:info("~p/~p", [kz_doc:id(Doc), AccountId])
    end.

verify_migrated_cfwd(LegacyCfwd, NewCfwd) ->
    kz_json:get_boolean_value(<<"enabled">>, LegacyCfwd)
        =:= kz_json:get_boolean_value([<<"unconditional">>, <<"enabled">>], NewCfwd).

legacy_cfwd() ->
    kz_json:from_list([{<<"enabled">>, true_or_false()}
                      ,{<<"number">>, kz_binary:rand_hex(5)}
                      ]).

true_or_false() ->
    rand:uniform() < 0.5.

verify_enabled_status(_API, [], _IsEnabled) -> 'ok';
verify_enabled_status(API, [<<AccountId/binary>> | AccountIds], IsEnabled) ->
    verify_account_enabled(API, AccountId, IsEnabled),
    verify_enabled_status(API, AccountIds, IsEnabled);
verify_enabled_status(API, [{_Prefix, AccountId} | AccountIds], IsEnabled) ->
    verify_account_enabled(API, AccountId, IsEnabled),
    verify_enabled_status(API, AccountIds, IsEnabled).

verify_account_enabled(API, AccountId, IsEnabled) ->
    AccountResp = pqc_cb_accounts:fetch(API, AccountId),
    lager:info("is account ~s enabled set to ~s: ~s", [AccountId, IsEnabled, AccountResp]),
    IsEnabled = kz_json:is_true([<<"metadata">>, <<"enabled">>], kz_json:decode(AccountResp)).

-spec cleanup() -> 'ok'.
cleanup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),
    cleanup(API).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    AllAccounts = seq_accounts:sub_account_names(?CP_47_DESCENDENTS),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES ++ AllAccounts),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

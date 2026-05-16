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
-module(seq_forum_11759).

-export([seq/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ALLOW_ID, <<"allow_onboarding_setting_id">>).

-properly({'standalone', [seq/0]}).

%% @doc if enabled, allow PUT (create) requests to set doc's "id"
-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar']
                             ,['cb_system_configs']
                             ),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    PatchConfig = pqc_cb_system_configs:patch_default_config(API
                                                            ,<<"crossbar">>
                                                            ,kz_json:from_list([{<<"default">>, kz_json:from_list([{?ALLOW_ID, 'true'}])}])
                                                            ),
    lager:info("patched system config: ~s", [PatchConfig]),
    'true' = kz_json:is_true([<<"data">>, <<"default">>, ?ALLOW_ID], kz_json:decode(PatchConfig)),

    Resources = [{fun pqc_cb_devices:create/3, fun pqc_cb_devices:fetch/3, fun seq_devices:new_device/0}
                ,{fun pqc_cb_users:create/3, fun pqc_cb_users:fetch/3, fun seq_users:new_user/0}
                ,{fun pqc_cb_resources:create/3, fun pqc_cb_resources:fetch/3, fun seq_resources:new_resource/0}
                ,{fun pqc_cb_callflows:create/3, fun pqc_cb_callflows:fetch/3, fun seq_callflows:new_callflow/0}
                ],

    lists:foreach(fun(Resource) -> test_setting_id(API, AccountId, Resource) end
                 ,Resources
                 ),

    UnPatchConfig = pqc_cb_system_configs:patch_default_config(API
                                                              ,<<"crossbar">>
                                                              ,kz_json:from_list([{<<"default">>, kz_json:from_list([{?ALLOW_ID, 'false'}])}])
                                                              ),
    lager:info("patched system config: ~s", [UnPatchConfig]),
    'false' = kz_json:is_true([<<"data">>, <<"default">>, ?ALLOW_ID], kz_json:decode(UnPatchConfig)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED FORUM 11759").

test_setting_id(API, AccountId, {CreateFun, FetchFun, NewEntityFun}) ->
    Id = kz_datamgr:get_uuid(),
    NewEntity = kz_json:set_value(<<"id">>, Id, NewEntityFun()),
    lager:info("trying to create new entity with id ~s", [Id]),
    CreateResp = CreateFun(API, AccountId, NewEntity),
    lager:info("created: ~s", [CreateResp]),

    Id = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(CreateResp)),

    FetchResp = FetchFun(API, AccountId, Id),
    lager:info("fetched by Request's id: ~s", [FetchResp]).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = properly_maintenance:cleanup_module_accounts(?MODULE),
    cleanup_system().

cleanup(API, AccountIds) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, AccountIds),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_account(API, AccountName) ->
    AccountResp = properly_accountant:create_account(API, AccountName),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)).

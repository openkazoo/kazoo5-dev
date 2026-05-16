%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author Manushi Perera
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_presence).

-export([seq/0
        ,cleanup/0
        ,seq_user_presence/0
        ,seq_device_presence/0
        ,seq_presence/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-define(SET_ACTION, <<"set">>).
-define(RESET_ACTION, <<"reset">>).
-define(CONFIRMED, <<"confirmed">>).
-define(EARLY, <<"early">>).
-define(TERMINATED, <<"terminated">>).
-define(PRESENCE_STATES, [?CONFIRMED, ?EARLY, ?TERMINATED]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_presence/0
                  ,fun seq_user_presence/0
                  ,fun seq_device_presence/0
                  ]
                 ).

-spec seq_presence() -> 'ok'.
seq_presence() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_presence']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_presence:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    'true' = kz_term:is_empty(kz_json:get_json_value([<<"data">>, <<"Subscriptions">>]
                                                    ,kz_json:decode(EmptySummaryResp)
                                                    )
                             )
        orelse (0 =:= kz_nodes:node_role_count(<<"Presence">>, 'true')),

    Extension = kz_binary:rand_hex(4),

    EmptyFetchResp = pqc_cb_presence:fetch(API, AccountId, Extension),
    lager:info("empty fetch resp: ~s", [EmptyFetchResp]),

    'true' = kz_term:is_empty(kz_json:get_json_value(<<"data">>
                                                    ,kz_json:decode(EmptyFetchResp)
                                                    )
                             )
        orelse (0 =:= kz_nodes:node_role_count(<<"Presence">>, 'true')),

    PresenceJObj = new_presence(),
    CreateResp = pqc_cb_presence:update(API, AccountId, Extension, PresenceJObj),
    lager:info("created presence ~s", [CreateResp]),
    CreatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(CreateResp)),
    <<"command sent">> = CreatedPresence,

    PresenceId = Extension,

    UpdateEarlyJObj = new_presence(PresenceJObj, ?EARLY),
    UpdateEarlyResp = pqc_cb_presence:update(API, AccountId, PresenceId, UpdateEarlyJObj),
    lager:info("updated presence with state early ~s", [UpdateEarlyResp]),
    UpdatedEarlyPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateEarlyResp)),
    <<"command sent">> = UpdatedEarlyPresence,

    UpdateResetJObj = new_presence(PresenceJObj, ?RESET_ACTION),
    UpdateResetResp = pqc_cb_presence:update(API, AccountId, PresenceId, UpdateResetJObj),
    lager:info("updated presence with reset ~s", [UpdateResetResp]),
    UpdatedResetPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateResetResp)),
    <<"command sent">> = UpdatedResetPresence,

    UpdateTerminatedJObj = new_presence(PresenceJObj, ?TERMINATED),
    UpdateTerminatedResp = pqc_cb_presence:update(API, AccountId, PresenceId, UpdateTerminatedJObj),
    lager:info("updated presence with state terminated ~s", [UpdateTerminatedResp]),
    UpdatedTerminatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateTerminatedResp)),
    <<"command sent">> = UpdatedTerminatedPresence,

    cleanup(API, [AccountId]),
    lager:info("FINISHED PRESENCE SEQ").

-spec seq_user_presence() -> 'ok'.
seq_user_presence() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_presence']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    UserId = create_user(API, AccountId),
    _DeviceId = create_device(API, AccountId, UserId),

    PresenceJObj = new_presence(),
    CreateResp = pqc_cb_presence:update_user_presence(API, AccountId, PresenceJObj, UserId),
    lager:info("created presence for user ~s", [CreateResp]),
    CreatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(CreateResp)),
    <<"command sent">> = CreatedPresence,

    _DeviceId2 = create_device(API, AccountId, UserId),

    UpdateEarlyJObj = new_presence(PresenceJObj, ?EARLY),
    UpdateEarlyResp = pqc_cb_presence:update_user_presence(API, AccountId, UpdateEarlyJObj, UserId),
    lager:info("updated presence with state early for user ~s", [UpdateEarlyResp]),
    UpdatedEarlyPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateEarlyResp)),
    <<"command sent">> = UpdatedEarlyPresence,

    UpdateResetJObj = new_presence(PresenceJObj, ?RESET_ACTION),
    UpdateResetResp = pqc_cb_presence:update_user_presence(API, AccountId, UpdateResetJObj, UserId),
    lager:info("updated presence with reset for user ~s", [UpdateResetResp]),
    UpdatedResetPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateResetResp)),
    <<"command sent">> = UpdatedResetPresence,

    UpdateTerminatedJObj = new_presence(PresenceJObj, ?TERMINATED),
    UpdateTerminatedResp = pqc_cb_presence:update_user_presence(API, AccountId, UpdateTerminatedJObj, UserId),
    lager:info("updated presence with state terminated for user ~s", [UpdateTerminatedResp]),
    UpdatedTerminatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateTerminatedResp)),
    <<"command sent">> = UpdatedTerminatedPresence,

    cleanup(API, [AccountId]),
    lager:info("FINISHED PRESENCE SEQ FOR USER").

-spec seq_device_presence() -> 'ok'.
seq_device_presence() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_presence']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    UserId = create_user(API, AccountId),
    DeviceId = create_device(API, AccountId, UserId),

    PresenceJObj = new_presence(),
    CreateResp = pqc_cb_presence:update_device_presence(API, AccountId, PresenceJObj, DeviceId),
    lager:info("created presence for device ~s", [CreateResp]),
    CreatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(CreateResp)),
    <<"command sent">> = CreatedPresence,

    UpdateEarlyJObj = new_presence(PresenceJObj, ?EARLY),
    UpdateEarlyResp = pqc_cb_presence:update_device_presence(API, AccountId, UpdateEarlyJObj, DeviceId),
    lager:info("updated presence with state early for device ~s", [UpdateEarlyResp]),
    UpdatedEarlyPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateEarlyResp)),
    <<"command sent">> = UpdatedEarlyPresence,

    UpdateResetJObj = new_presence(PresenceJObj, ?RESET_ACTION),
    UpdateResetResp = pqc_cb_presence:update_device_presence(API, AccountId, UpdateResetJObj, DeviceId),
    lager:info("updated presence with reset for device ~s", [UpdateResetResp]),
    UpdatedResetPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateResetResp)),
    <<"command sent">> = UpdatedResetPresence,

    UpdateTerminatedJObj = new_presence(PresenceJObj, ?TERMINATED),
    UpdateTerminatedResp = pqc_cb_presence:update_device_presence(API, AccountId, UpdateTerminatedJObj, DeviceId),
    lager:info("updated presence with state terminated for device ~s", [UpdateTerminatedResp]),
    UpdatedTerminatedPresence = kz_json:get_binary_value(<<"data">>, kz_json:decode(UpdateTerminatedResp)),
    <<"command sent">> = UpdatedTerminatedPresence,

    cleanup(API, [AccountId]),
    lager:info("FINISHED PRESENCE SEQ FOR DEVICE").


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

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_presence() -> kzd_presence:doc().
new_presence() ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_presence:set_action/2, ?SET_ACTION}
                         ,{fun kzd_presence:set_state/2, ?CONFIRMED}
                         ]
                        ,kzd_presence:new()
                        )
     ).

-spec new_presence(kzd_presence:doc(), kz_term:ne_binary()) -> kzd_presence:doc().
new_presence(PresenceJObj, ?RESET_ACTION) ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_presence:set_action/2, ?RESET_ACTION}
                         ]
                        ,kz_json:merge(PresenceJObj, kzd_presence:new())
                        )
     );

new_presence(PresenceJObj, Action) ->
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_presence:set_action/2, ?SET_ACTION}
                         ,{fun kzd_presence:set_state/2, Action}
                         ]
                        ,kz_json:merge(PresenceJObj, kzd_presence:new())
                        )
     ).

-spec create_user(pqc_cb_api:state(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_user(API, AccountId) ->
    UserDoc = seq_users:new_user(),
    CreateUserResp = pqc_cb_users:create(API, AccountId, UserDoc),
    lager:info("created user ~p", [CreateUserResp]),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(CreateUserResp)).

-spec create_device(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
create_device(API, AccountId, OwnerId) ->
    DeviceDoc = kz_doc:setters(kzd_devices:new()
                              ,[{fun kzd_devices:set_name/2, kz_binary:rand_hex(5)}
                               ,{fun kzd_devices:set_owner_id/2, OwnerId}
                               ,{fun kzd_devices:set_presence_id/2, kz_binary:rand_hex(4)}
                               ]
                              ),
    CreateDeviceResp = pqc_cb_devices:create(API, AccountId, DeviceDoc),
    lager:info("created device ~p", [CreateDeviceResp]),
    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(CreateDeviceResp)).

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
-module(local_conferences).

-export([local/0
        ,local_kcro_144/0
        ,cleanup/0, cleanup/1
        ]).

%% -include("properly.hrl").
-include_lib("ecallmgr/src/ecallmgr.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec local() -> 'ok'.
local() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun local_kcro_144/0]
                 ).

-spec local_kcro_144() -> 'ok'.
local_kcro_144() ->
    API = pqc_cb_api:init_api(['crossbar', 'ecallmgr'], ['cb_accounts', 'cb_conferences']),

    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account ~s", [AccountResp]),
    AccountId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)),

    %% create new conference
    ConfResp = pqc_cb_conferences:create(API, AccountId, kz_json:from_list([{<<"name">>, <<?MODULE_STRING>>}])),
    lager:info("conference resp: ~s", [ConfResp]),
    ConferenceId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(ConfResp)),

    %% Start a conference
    [FSNode|_] = ecallmgr_fs_nodes:connected(),

    JObj = kz_json:from_list([{<<"Account-ID">>, AccountId}
                             ,{<<"Call-Interaction">>, kz_json:from_list([{<<"Id">>, kz_binary:rand_hex(6)}])}
                             ,{<<"Conference-ID">>, ConferenceId}
                             ,{<<"Conference-Node">>, kz_term:to_binary(FSNode)}
                             ,{<<"Event">>, <<"conference-create">>}
                             ,{<<"Instance-ID">>, kz_binary:rand_hex(16)}
                             ,{<<"Profile">>, <<"default">>}
                             ,{<<"Switch-Hostname">>, kz_term:to_binary(FSNode)}
                             ,{<<"Switch-URL">>, <<"sip:", (kz_term:to_binary(FSNode))/binary>>}
                             ]),
    ecallmgr_fs_conference_stream:handle_event(#{node => FSNode, payload => JObj}),
    timer:sleep(60),

    %% send API to update conf vars
    Key = kz_binary:rand_hex(5),
    Value = kz_binary:rand_hex(5),

    FirstSetResp = pqc_cb_conferences:action(API, AccountId, ConferenceId
                                            ,<<"vars">>
                                            ,kz_json:from_list([{<<"custom_conference_vars">>
                                                                ,kz_json:from_list([{Key, Value}])
                                                                }
                                                               ]
                                                              )
                                            ),
    lager:info("first set resp: ~s", [FirstSetResp]),
    timer:sleep(60),

    {'ok', #conference{custom_conference_vars=CCVs}} = ecallmgr_fs_conferences:conference(ConferenceId),
    lager:info("conf ccvs: ~p", [CCVs]),
    Value = kz_json:get_ne_binary_value(Key, CCVs),

    Key1 = kz_binary:rand_hex(5),
    Value1 = kz_binary:rand_hex(5),

    SecondSetResp = pqc_cb_conferences:action(API, AccountId, ConferenceId
                                             ,<<"vars">>
                                             ,kz_json:from_list([{<<"custom_conference_vars">>
                                                                 ,kz_json:from_list([{Key1, Value1}])
                                                                 }
                                                                ]
                                                               )
                                             ),
    lager:info("second set resp: ~s", [SecondSetResp]),
    timer:sleep(60),

    {'ok', #conference{custom_conference_vars=CCVs1}} = ecallmgr_fs_conferences:conference(ConferenceId),
    lager:info("conf ccvs: ~p", [CCVs1]),
    Value = kz_json:get_ne_binary_value(Key, CCVs1),
    Value1 = kz_json:get_ne_binary_value(Key1, CCVs1),

    ConfDetailsResp = pqc_cb_conferences:fetch(API, AccountId, ConferenceId),
    lager:info("conf details resp: ~s", [ConfDetailsResp]),
    ConfDetailsEnv = kz_json:decode(ConfDetailsResp),
    ConfDetails = kz_json:get_json_value(<<"data">>, ConfDetailsEnv),
    ConfMeta = kz_json:get_json_value(<<"metadata">>, ConfDetailsEnv),

    <<?MODULE_STRING>> = kz_json:get_ne_binary_value(<<"name">>, ConfDetails),
    ConferenceId = kz_json:get_ne_binary_value(<<"id">>, ConfDetails),

    ConferenceId = kz_json:get_ne_binary_value(<<"conference_id">>, ConfMeta),
    ConferenceId = kz_json:get_ne_binary_value(<<"id">>, ConfMeta),

    ConfVars = kz_json:get_json_value(<<"custom_conference_vars">>, ConfMeta),
    Value = kz_json:get_ne_binary_value(Key, ConfVars),
    Value1 = kz_json:get_ne_binary_value(Key1, ConfVars),

    cleanup(API).

-spec cleanup() -> 'ok'.
cleanup() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_accounts']),
    cleanup(API).

-spec cleanup(pqc_cb_api:state()) -> 'ok'.
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    'ok'.

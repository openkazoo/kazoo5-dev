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
-module(seq_resources).

-export([seq/0
        ,seq_crud/0
        ,seq_cp33/0
        ,seq_kzoo_503/0
        ,cleanup/0
        ,new_resource/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_crud/0
                  ,fun seq_cp33/0
                  ,fun seq_kzoo_503/0
                  ]
                 ).

%% @doc Tests basic CRUD of resources API
-spec seq_crud() -> 'ok'.
seq_crud() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_resources']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_resources:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ResourceJObj = new_resource(),
    CreateResp = pqc_cb_resources:create(API, AccountId, ResourceJObj),
    lager:info("created resource ~s", [CreateResp]),
    CreatedResource = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    ResourceId = kz_doc:id(CreatedResource),

    PatchKit = [{[<<"classifiers">>, <<"unknown">>, <<"enabled">>], 'false'}
               ,{[<<"classifiers">>, <<"unknown">>, <<"emergency">>], 'false'}
               ,{[<<"classifiers">>, <<"unknown">>, <<"weight_cost">>], 50}
               ],
    Patch = kz_json:set_values(PatchKit, kz_json:new()),
    PatchResp = pqc_cb_resources:patch(API, AccountId, ResourceId, Patch),
    lager:info("patched to ~s", [PatchResp]),
    PatchedResource = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp)),
    'true' = kz_json:are_equal(PatchedResource
                              ,kz_json:set_values(PatchKit, CreatedResource)
                              ),

    SummaryResp = pqc_cb_resources:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryResource] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    ResourceId = kz_doc:id(SummaryResource),

    DeleteResp = pqc_cb_resources:delete(API, AccountId, ResourceId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_resources:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED RESOURCE SEQ").

%% @doc Test for spaces in IP addresses in carrier fields
-spec seq_cp33() -> 'ok'.
seq_cp33() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_resources']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_resources:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ResourceJObj = add_bad_gateway(new_resource()),
    {'error', CreateResp} = pqc_cb_resources:create(API, AccountId, ResourceJObj),
    lager:info("expected error creating resource ~s", [CreateResp]),

    ErrorJObj = kz_json:decode(CreateResp),


    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, ErrorJObj),
    400 = kz_json:get_integer_value(<<"error">>, ErrorJObj),

    Data = kz_json:get_json_value(<<"data">>, ErrorJObj),
    %% realm is localhost, server has space preceding
    'true' = kz_json:is_defined([<<"gateways.0.realm">>, <<"wrong_format">>, <<"message">>], Data),
    'true' = kz_json:is_defined([<<"gateways.0.server">>, <<"wrong_format">>, <<"message">>], Data),

    %% server is localhost, realm has space preceding
    'true' = kz_json:is_defined([<<"gateways.1.realm">>, <<"wrong_format">>, <<"message">>], Data),
    'true' = kz_json:is_defined([<<"gateways.1.server">>, <<"wrong_format">>, <<"message">>], Data),

    cleanup(API, [AccountId]),
    lager:info("FINISHED CP33").

%% test hostname resolution in realm/server fields
%% should check:
%%   1. SRV -> A
-spec seq_kzoo_503() -> 'ok'.
seq_kzoo_503() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_resources']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    HzJObj = add_gateway(new_resource(), <<"sip.2600hz.com">>),
    CreateHz = pqc_cb_resources:create(API, AccountId, HzJObj),
    lager:info("created Hz resource: ~s", [CreateHz]),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, kz_json:decode(CreateHz)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED KZOO-503").

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

-spec new_resource() -> kzd_resources:doc().
new_resource() ->
    EmergencyClassifier = kz_json:from_list([{<<"enabled">>, 'true'}]),
    Classifiers = kz_json:from_list([{<<"emergency">>, EmergencyClassifier}]),
    kz_doc:public_fields(
      kz_json:exec_first([{fun kzd_resources:set_name/2, kz_binary:rand_hex(4)}
                         ,{fun kzd_resources:set_gateways/2, []}
                         ,{fun kzd_resources:set_classifiers/2, Classifiers}
                         ]
                        ,kzd_resources:new()
                        )
     ).

-spec add_bad_gateway(kzd_resources:doc()) -> kzd_resources:doc().
add_bad_gateway(ResourceDoc) ->
    Gateway0 = kz_json:from_list([{<<"server">>, <<" 1.2.3.4">>} % leading whitespace error
                                 ,{<<"realm">>, <<"127.0.0.1">>} % forbidden value
                                 ]),

    Gateway1 = kz_json:from_list([{<<"realm">>, <<" 1.2.3.4">>} % leading whitespace error
                                 ,{<<"server">>, <<"127.0.0.1">>} % forbidden value
                                 ]),

    kzd_resources:set_gateways(ResourceDoc, [Gateway0, Gateway1]).

-spec add_gateway(kzd_resources:doc(), kz_term:ne_binary()) -> kzd_resources:doc().
add_gateway(ResourceDoc, Server) ->
    Gateway = kz_json:from_list([{<<"server">>, Server}]),
    kzd_resources:set_gateways(ResourceDoc, [Gateway]).

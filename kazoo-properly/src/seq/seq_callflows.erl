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
-module(seq_callflows).

-export([seq/0, seq_url/0, seq_merged_errors/0
        ,cleanup/0
        ,new_callflow/0
        ]).

-include("properly.hrl").


-define(ACCOUNT_NAME, list_to_binary([?MODULE_STRING "_", kz_term:to_binary(?FUNCTION_NAME)])).
-define(ACCOUNT_NAMES, [?ACCOUNT_NAME]).

-spec seq() -> 'ok'.
seq() ->
    lists:foreach(fun(F) -> F() end
                 ,[fun seq_crud/0
                  ,fun seq_url/0
                  ,fun seq_merged_errors/0
                  ]).

seq_crud() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_callflows']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    EmptySummaryResp = pqc_cb_callflows:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    CallflowJObj = new_callflow(),
    CreateResp = pqc_cb_callflows:create(API, AccountId, CallflowJObj),
    lager:info("created callflow ~s", [CreateResp]),
    CreatedCallflow = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    CallflowId = kz_doc:id(CreatedCallflow),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_callflows:patch(API, AccountId, CallflowId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_callflows:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryCallflow] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    CallflowId = kz_doc:id(SummaryCallflow),

    DeleteResp = pqc_cb_callflows:delete(API, AccountId, CallflowId),
    lager:info("delete resp: ~s", [DeleteResp]),
    Deleted = kz_json:decode(DeleteResp),

    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, Deleted),
    CallflowId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], Deleted),
    'true' = kz_json:is_true([<<"metadata">>, <<"deleted">>], Deleted),

    EmptyAgain = pqc_cb_callflows:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API, [AccountId]),
    lager:info("FINISHED CALLFLOW SEQ").

-spec seq_url() -> any().
seq_url() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_callflows']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    {'error', ErrorResp} = pqc_cb_callflows:create(API, AccountId, pivot_url_callflow()),
    lager:info("create resp failed with internal url: ~s", [ErrorResp]),

    lager:info("FINISHED SEQ_URL!"),
    _ = cleanup(API, [AccountId]).

%% @doc when request has multiple validation errors for the same key,
%% only one error would be returned. Instead, merge the results so all
%% errors related to the key are returned.
%% See kazoo-crossbar/pull/140
-spec seq_merged_errors() -> 'ok'.
seq_merged_errors() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_callflows']),
    AccountId = create_account(API, ?ACCOUNT_NAME),

    Callflow = kz_json:from_list([{<<"numbers">>, <<"12345">>}
                                 ,{<<"name">>, kz_binary:rand_hex(5)}
                                 ]),
    {'error', ErrorResp} = pqc_cb_callflows:create(API, AccountId, Callflow),
    lager:info("error resp: ~s", [ErrorResp]),

    RespJObj = kz_json:decode(ErrorResp),

    400 = kz_json:get_integer_value(<<"error">>, RespJObj),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, RespJObj),

    ValidationErrors = kz_json:get_json_value(<<"data">>, RespJObj),

    'true' = kz_json:is_defined([<<"numbers">>, <<"type">>, <<"value">>], ValidationErrors),
    'true' = kz_json:is_defined([<<"numbers">>, <<"required">>, <<"message">>], ValidationErrors),

    cleanup(API, [AccountId]),
    lager:info("FINISHED MERGED_ERRORS").

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

-spec new_callflow() -> kzd_callflows:doc().
new_callflow() ->
    Flow = kz_json:from_list([{<<"module">>, <<"hangup">>}]),
    kz_doc:public_fields(
      kz_doc:setters(kzd_callflows:new()
                    ,[{fun kzd_callflows:set_numbers/2, [<<"2600">>]}
                     ,{fun kzd_callflows:set_flow/2, Flow}
                     ]
                    )).

pivot_url_callflow() ->
    PivotData = kz_json:from_list([{<<"voice_url">>, <<"http://localhost/123">>}]),
    Flow = kz_json:from_list([{<<"module">>, <<"pivot">>}
                             ,{<<"data">>, PivotData}
                             ]),
    kz_doc:setters(kzd_callflows:new()
                  ,[{fun kzd_callflows:set_numbers/2, [<<"345">>]}
                   ,{fun kzd_callflows:set_flow/2, Flow}
                   ]).

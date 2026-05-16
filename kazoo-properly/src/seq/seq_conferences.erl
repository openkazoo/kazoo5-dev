%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_conferences).

-export([seq/0
        ,cleanup/0
        ,new_conference/0, new_callflow/1
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_conferences']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_conferences:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    ConferenceJObj = new_conference(),
    CreateResp = pqc_cb_conferences:create(API, AccountId, ConferenceJObj),
    lager:info("created conference ~s", [CreateResp]),
    CreatedConference = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),

    'true' = kzd_conferences:video(CreatedConference),

    ConferenceId = kz_doc:id(CreatedConference),

    ConfName = kzd_conferences:name(ConferenceJObj),

    {'error', ErrorResp} = pqc_cb_conferences:create(API, AccountId, ConferenceJObj),
    lager:info("creating a conference with already in used name is disallowed ~s", [ErrorResp]),
    ConfName = kz_json:get_value([<<"data">>, <<"name">>, <<"unique">>, <<"cause">>], kz_json:decode(ErrorResp)),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_conferences:patch(API, AccountId, ConferenceId, Patch),
    lager:info("patched to ~s", [PatchResp]),
    PatchedConference = kz_json:get_json_value(<<"data">>, kz_json:decode(PatchResp)),

    'true' = kzd_conferences:video(PatchedConference),
    <<"value">> = kz_json:get_ne_binary_value(<<"custom">>, PatchedConference),

    SummaryResp = pqc_cb_conferences:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryConference] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    ConferenceId = kz_doc:id(SummaryConference),
    'true' = kzd_conferences:video(SummaryConference),

    _ = pqc_cb_system_configs:patch_default_config(API
                                                  ,<<"crossbar">>
                                                  ,kz_json:from_list([{<<"default">>
                                                                      ,kz_json:from_list([{<<"allow_fetch_full_docs">>, 'true'}])
                                                                      }])
                                                  ),

    FullDocsResp = pqc_cb_conferences:summary(API, AccountId, [{<<"full_docs">>, 'true'}]),
    lager:info("full docs resp: ~s", [SummaryResp]),
    [FullDoc] = kz_json:get_list_value(<<"data">>, kz_json:decode(FullDocsResp)),
    ConferenceId = kz_doc:id(FullDoc),

    'true' = kz_term:is_boolean(kzd_conferences:play_name(FullDoc, 'undefined')),
    'true' = kz_term:is_empty(kz_doc:private_fields(kz_json:delete_key(<<"_read_only">>, FullDoc))),
    'true' = kzd_conferences:video(FullDoc),
    <<"value">> = kz_json:get_ne_binary_value(<<"custom">>, FullDoc),

    Fields = kz_json:encode([<<"conference_numbers">>, <<"name">>]),
    FieldsResp = pqc_cb_conferences:summary(API, AccountId, [{<<"fields">>, Fields}]),
    lager:info("fields resp: ~s", [FieldsResp]),
    [FieldsDoc] = kz_json:get_list_value(<<"data">>, kz_json:decode(FieldsResp)),
    ConferenceId = kz_doc:id(FieldsDoc),
    [] = kzd_conferences:conference_numbers(FieldsDoc),
    ConfName = kzd_conferences:name(FieldsDoc),
    'true' = kz_term:is_empty(kz_json:delete_keys([<<"id">>, <<"conference_numbers">>, <<"name">>], FieldsDoc)),

    {'error', BadActionResp} = pqc_cb_conferences:action(API, AccountId, ConferenceId, <<"jackson">>, kz_json:new()),
    lager:info("expected error for bad action: ~s", [BadActionResp]),
    BadAction = kz_json:decode(BadActionResp),

    <<"jackson">> = kz_json:get_ne_binary_value([<<"data">>, <<"action">>, <<"enum">>, <<"value">>], BadAction),
    400 = kz_json:get_integer_value(<<"error">>, BadAction),
    <<"validation error">> = kz_json:get_ne_binary_value(<<"message">>, BadAction),
    <<"error">> = kz_json:get_ne_binary_value(<<"status">>, BadAction),

    DeleteResp = pqc_cb_conferences:delete(API, AccountId, ConferenceId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_conferences:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED CONFERENCE SEQ").

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = seq_accounts:cleanup_accounts(?ACCOUNT_NAMES),
    cleanup_system().

cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = pqc_cb_api:cleanup(API),
    cleanup_system().

cleanup_system() -> 'ok'.

-spec create_account(pqc_cb_api:state()) -> kz_term:ne_binary().
create_account(API) ->
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_conference() -> kzd_conferences:doc().
new_conference() ->
    kz_doc:setters(kz_doc:public_fields(kzd_conferences:new())
                  ,[{fun kzd_conferences:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_conferences:set_video/2, 'true'}
                   ]
                  ).

-spec new_callflow(kz_term:ne_binary()) -> kzd_callflows:doc().
new_callflow(ConferenceId) ->
    Flow = kz_json:from_list([{<<"module">>, <<"conference">>}
                             ,{<<"data">>, kz_json:from_list([{<<"id">>, ConferenceId}])}
                             ]
                            ),
    Number = kz_term:to_binary(rand:uniform(50) + 1000),
    kz_doc:setters(kz_doc:public_fields(kzd_callflows:new())
                  ,[{fun kzd_callflows:set_name/2, kz_binary:rand_hex(5)}
                   ,{fun kzd_callflows:set_flow/2, Flow}
                   ,{fun kzd_callflows:set_numbers/2, [Number]}
                   ]
                  ).

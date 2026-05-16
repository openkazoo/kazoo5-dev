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
-module(seq_faxboxes).

-export([seq/0, kcro_95_seq/0
        ,cleanup/0
        ,new_faxbox/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    faxboxes_seq(),
    kcro_95_seq().

-spec faxboxes_seq() -> 'ok'.
faxboxes_seq() ->
    lager:info("STARTED FAXBOXES SEQ"),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_faxboxes']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_faxboxes:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptySummaryResp)),

    FaxboxJObj = new_faxbox(),
    CreateResp = pqc_cb_faxboxes:create(API, AccountId, FaxboxJObj),
    lager:info("created faxbox ~s", [CreateResp]),
    CreatedFaxbox = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),
    FaxboxId = kz_doc:id(CreatedFaxbox),

    Patch = kz_json:from_list([{<<"custom">>, <<"value">>}]),
    PatchResp = pqc_cb_faxboxes:patch(API, AccountId, FaxboxId, Patch),
    lager:info("patched to ~s", [PatchResp]),

    SummaryResp = pqc_cb_faxboxes:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [SummaryFaxbox] = kz_json:get_list_value(<<"data">>, kz_json:decode(SummaryResp)),
    FaxboxId = kz_doc:id(SummaryFaxbox),

    DeleteResp = pqc_cb_faxboxes:delete(API, AccountId, FaxboxId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptyAgain = pqc_cb_faxboxes:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptyAgain]),
    [] = kz_json:get_list_value(<<"data">>, kz_json:decode(EmptyAgain)),

    cleanup(API),
    lager:info("FINISHED FAXBOXES SEQ").

-spec kcro_95_seq() -> 'ok'.
kcro_95_seq() ->
    lager:info("STARTED KCRO-95 SEQ"),
    API = pqc_cb_api:init_api(['crossbar'], ['cb_faxboxes']),
    AccountId = create_account(API),

    FaxBox = kz_json:set_value(<<"pvt_key">>, <<"pvt_value">>, new_faxbox()),
    CreateResp = pqc_cb_faxboxes:create(API, AccountId, FaxBox),
    lager:info("created faxbox ~s", [CreateResp]),
    CreateRespJObj = kz_json:decode(CreateResp),
    CreatedBox = kz_json:get_json_value(<<"data">>, CreateRespJObj),
    FaxBoxId = kz_doc:id(CreatedBox),

    <<Hostname/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"custom_smtp_address">>]
                                                     ,CreateRespJObj
                                                     ),

    'undefined' = kz_json:get_ne_binary_value(<<"pvt_key">>, CreatedBox),

    FetchResp = pqc_cb_faxboxes:fetch(API, AccountId, FaxBoxId),
    lager:info("fetched ~s: ~s", [FaxBoxId, FetchResp]),
    FetchRespJObj = kz_json:decode(FetchResp),
    FetchedBox = kz_json:get_json_value(<<"data">>, FetchRespJObj),

    <<Hostname/binary>> = kz_json:get_ne_binary_value([<<"metadata">>, <<"custom_smtp_address">>]
                                                     ,FetchRespJObj
                                                     ),
    'true' = kz_json:are_equal(CreatedBox, FetchedBox),

    cleanup(API),
    lager:info("FINISHED KCRO-95 SEQ").

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

    kz_json:get_ne_binary_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)).

-spec new_faxbox() -> kzd_faxbox:doc().
new_faxbox() ->
    kz_doc:public_fields(
      kzd_faxbox:set_name(kzd_faxbox:new()
                         ,kz_binary:rand_hex(4)
                         )
     ).

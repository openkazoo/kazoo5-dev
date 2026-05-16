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
-module(seq_kz_formatters).

-export([seq/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    seq_help_18404().

%% @doc verify that formatters affect caller ID as expected when
%% dialing NZ-formatted numbers mapped to a device
seq_help_18404() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_devices']),
    AccountId = create_account(API),

    Formatter = kz_json:from_list([{<<"regex">>, <<"\\+?64(\\d{8,})", $$>>}
                                  ,{<<"prefix">>, <<"0">>}
                                  ]),
    Formatters = kz_json:from_list([{<<"from">>, [Formatter]}
                                   ,{<<"caller_id_number">>, [Formatter]}
                                   ,{<<"outbound_caller_id_number">>, [Formatter]}
                                   ]),
    NewDevice = kzd_devices:set_formatters(seq_devices:new_device()
                                          ,Formatters
                                          ),
    CreateResp = pqc_cb_devices:create(API, AccountId, NewDevice),
    lager:info("create: ~s", [CreateResp]),
    RespDevice = kz_json:get_json_value(<<"data">>, kz_json:decode(CreateResp)),

    DeviceId = kz_doc:id(RespDevice),
    {'ok', Endpoint} = kz_endpoint:get(DeviceId, AccountId),

    CallFs = [{fun kapps_call:set_resource_type/2, <<"audio">>}
             ,{fun kapps_call:set_account_id/2, AccountId}
             ,{fun kapps_call:set_caller_id_number/2, <<"6491234567">>}
             ,{fun kapps_call:set_from/2, <<"6491234567@some.realm">>}
             ],
    Call = kapps_call:exec(CallFs, kapps_call:new()),
    {'ok', [SIPEndpoint]} = kz_endpoint:build(Endpoint, kz_json:new(), Call),

    <<"091234567">> = kz_json:get_value(<<"Outbound-Caller-ID-Number">>, SIPEndpoint),

    cleanup(API),
    lager:info("FINISHED FORMATTERS").

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

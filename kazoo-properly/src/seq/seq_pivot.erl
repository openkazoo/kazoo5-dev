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
-module(seq_pivot).

-export([seq/0
        ,cleanup/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

init_system() ->
    API = pqc_cb_api:init_api(['crossbar', 'pivot'], ['cb_callflows']),
    {'ok', HTTPD} = pqc_httpd:start_link(kz_log:get_callid(), #{'store_headers' => 'true'}),
    API#{httpd => HTTPD}.

-spec seq() -> 'ok'.
seq() ->
    API = init_system(),
    AccountId = create_account(API),

    %% 1. create callflow with pivot action to our server, with custom header
    {HeaderName, HeaderValue} = CustomHeader = {<<"x-pivot-header">>, kz_binary:rand_hex(5)},
    PivotData = create_pivot_callflow(API, AccountId, CustomHeader),

    %% 2. publish the pivot_req
    %%   0. set a callflow response
    pqc_httpd:add_response(API, [<<?MODULE_STRING>>], kz_json:new(), <<"{\"module\":\"hangup\",\"data\":{}}">>),
    %%   1. publish the AMQP req to pivot
    _Pid = kz_process:spawn(fun publish_pivot_req/1, [PivotData]),

    %% 3. recv HTTP req, verify the header is present and value matches
    {Headers, PivotHTTP} = pqc_httpd:wait_for_req(API, [<<?MODULE_STRING>>], 2 * ?MILLISECONDS_IN_SECOND),
    lager:info("pivot HTTP req: ~p ~p", [Headers, PivotHTTP]),
    HeaderValue = kz_json:get_value(HeaderName, Headers),

    cleanup(API, [AccountId]),
    lager:info("FINISHED PIVOT SEQ").

create_pivot_callflow(API, AccountId, CustomHeader) ->
    URL = <<(pqc_httpd:base_url(API))/binary, ?MODULE_STRING>>,
    PivotData = kz_json:from_list([{<<"voice_url">>, URL}
                                  ,{<<"method">>, <<"post">>}
                                  ,{<<"custom_request_headers">>
                                   ,kz_json:from_list([CustomHeader])
                                   }
                                  ]
                                 ),
    Flow = kz_json:from_list([{<<"module">>, <<"pivot">>}
                             ,{<<"data">>, PivotData}
                             ]),
    Callflow = kz_doc:setters(kzd_callflows:new()
                             ,[{fun kzd_callflows:set_numbers/2, [<<"345">>]}
                              ,{fun kzd_callflows:set_flow/2, Flow}
                              ,{fun kzd_callflows:set_name/2, <<?MODULE_STRING>>}
                              ]),
    CallflowResp = pqc_cb_callflows:create(API, AccountId, Callflow),
    lager:info("created callflow: ~s", [CallflowResp]),
    PivotData.

publish_pivot_req(Data) ->
    {'ok', Worker} = kz_amqp_worker:checkout_worker(),
    WorkerQueue = gen_listener:queue_name(Worker),

    Routines = [{fun kapps_call:set_to/2, <<"to@nodomain">>}
               ,{fun kapps_call:set_from/2, <<"from@nodomain">>}
               ,{fun kapps_call:set_call_id/2, kz_binary:rand_hex(12)}
               ,{fun kapps_call:set_caller_id_number/2, <<"123456">>}
               ,{fun kapps_call:set_caller_id_name/2, <<"from">>}
               ,{fun kapps_call:set_controller_queue/2, WorkerQueue}
               ],
    Call = kapps_call:exec(Routines, kapps_call:new()),

    Prop = props:filter_empty(
             [{<<"Call">>, kapps_call:to_json(Call)}
             ,{<<"HTTP-Method">>, kzt_util:http_method(kz_json:get_value(<<"method">>, Data, 'get'))}
             ,{<<"Custom-Request-Headers">>, kz_json:get_json_value(<<"custom_request_headers">>, Data)}
             ,{<<"Voice-URI">>, kz_json:get_ne_binary_value(<<"voice_url">>, Data)}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
             ]),
    Resp = kz_amqp_worker:call(Prop, fun kapi_pivot:publish_req/1),
    lager:info("published pivot request: ~p", [Resp]).

-spec cleanup() -> 'ok'.
cleanup() ->
    _ = seq_accounts:cleanup_accounts(?ACCOUNT_NAMES).

cleanup(API, Accounts) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    _ = seq_accounts:cleanup_accounts(API, Accounts),
    cleanup_system(API).

cleanup_system(API) ->
    pqc_httpd:stop(API).

-spec create_account(pqc_cb_api:state()) -> kz_term:ne_binary().
create_account(API) ->
    AccountResp = properly_accountant:create_account(API, hd(?ACCOUNT_NAMES)),
    lager:info("created account: ~s", [AccountResp]),

    kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>], kz_json:decode(AccountResp)).

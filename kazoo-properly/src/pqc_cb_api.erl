%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_api).

-export([authenticate/0, authenticate/3, authenticate_by_id/3
        ,api_authenticate/1
        ,v2_base_url/0, v2_base_url/1
        ,auth_account_id/1

        ,request_headers/1, request_headers/2
        ,default_request_headers/0, default_request_headers/1
        ,create_envelope/1, create_envelope/2
        ,make_request/4, make_request/5

        ,cleanup/1

        ,set_log_level/1
        ,get_current_token_costs/1
        ,patch_token_costs/2

        ,init_api/2
        ,init_system/2
        ]).

-include("properly.hrl").

-define(TRACE_FORMAT
       ,[{'elapsed', <<"-0">>}, "|"
        ,'request_id', "|"
        ,'module', ":", 'line', " (", 'pid', ")|"
        ,'message', "\n"
        ]
       ).

-type response() :: binary() |
                    kz_http:ret() |
                    {'error', binary()}.

-type fun_2() :: fun((string(), kz_term:proplist()) -> kz_http:ret()).
-type fun_3() :: fun((string(), kz_term:proplist(), iodata()) -> kz_http:ret()).

-type state() :: #{'account_id' => kz_term:api_ne_binary()
                  ,'auth_account_id' => kz_term:api_ne_binary()
                  ,'base_url' => kz_term:text()
                  ,'auth_token' => kz_term:api_ne_binary()
                  ,'basic_auth' => kz_term:ne_binary() % base64-encoded
                  ,'request_id' => kz_term:ne_binary()
                  ,'start' => kz_time:start_time()
                  ,'trace_file' => kz_data_tracing:trace_ref()
                  ,'httpd' => pid()
                  }.

-export_type([state/0
             ,response/0
             ]).

-spec cleanup(state()) -> any().
cleanup(#{'trace_file' := Trace
         ,'start' := Start
         }=API) ->
    lager:info("cleanup after ~p ms", [kz_time:elapsed_ms(Start)]),
    _ = kz_data_tracing:stop_trace(Trace),
    cleanup_httpd(API).

cleanup_httpd(#{httpd := Pid}) ->
    case erlang:is_process_alive(Pid) of
        'true' -> pqc_httpd:stop(Pid);
        'false' -> 'ok'
    end;
cleanup_httpd(_) -> 'ok'.

-spec base_url() -> iolist().
base_url() ->
    Host = kz_network_utils:get_hostname(),
    {'ok', IPTuple} = inet:getaddr(Host, 'inet'),
    Address = kz_network_utils:iptuple_to_binary(IPTuple),

    {Scheme, Port} = case kapps_config:get_integer(<<"crossbar">>, <<"port">>) of
                         'undefined' -> maybe_ssl_url();
                         P -> {"http://", P}
                     end,
    [Scheme, Address, $:, integer_to_list(Port), "/v2"].

maybe_ssl_url() ->
    maybe_ssl_url(kapps_config:get_integer(<<"crossbar">>, <<"ssl_port">>)).

maybe_ssl_url('undefined') ->
    {"http://", 8000};
maybe_ssl_url(P) ->
    {"https://", P}.

%% can we build API URL based on kz_nodes:status() and where crossbar is running?
%% if in same zone, point to running node instead of local

-spec authenticate() -> state().
authenticate() ->
    {'ok', _} = kapps_controller:start_app('crossbar'),
    URL =  string:join([base_url(), "api_auth"], "/"),
    Data = kz_json:from_list([{<<"api_key">>, api_key()}]),
    Envelope = create_envelope(Data),

    {'ok', Trace} = start_trace(),

    Resp = make_request([pqc_cb_expect:code(201)]
                       ,fun kz_http:put/3
                       ,URL
                       ,default_request_headers(kz_log:get_callid())
                       ,kz_json:encode(Envelope)
                       ),
    create_api_state(base_url(), Resp, Trace).

%% {auth key, auth value}
%%   auth key could be "account_id", "account_name", "phone_number"
-type account_identifier() :: {kz_term:ne_binary(), kz_term:ne_binary()} |
                              kz_term:ne_binary().

-spec authenticate(account_identifier(), kz_term:ne_binary(), kz_term:ne_binary()) -> state().
authenticate(AccountName, Username, Password) ->
    {'ok', _} = kapps_controller:start_app('crossbar'),

    {'ok', Trace} = start_trace(),
    APIBase = base_url(),
    Resp = pqc_cb_user_auth:by_account_name(APIBase, AccountName, Username, Password),
    create_api_state(APIBase, Resp, Trace).

-spec authenticate_by_id(account_identifier(), kz_term:ne_binary(), kz_term:ne_binary()) -> state().
authenticate_by_id(AccountId, Username, Password) ->
    {'ok', _} = kapps_controller:start_app('crossbar'),

    {'ok', Trace} = start_trace(),
    APIBase = base_url(),
    Resp = pqc_cb_user_auth:by_account_id(APIBase, AccountId, Username, Password),
    create_api_state(APIBase, Resp, Trace).

-spec api_authenticate(kz_term:ne_binary()) -> state().
api_authenticate(<<AccountId/binary>>) ->
    URL = base_url() ++ "/api_auth",
    Data = kz_json:from_list([{<<"api_key">>, api_key(AccountId)}]),
    Envelope = create_envelope(Data),

    make_api_request(URL, Envelope).

-spec make_api_request(kz_term:text(), kz_json:object()) -> state().
make_api_request(URL, Envelope) ->
    make_api_request(URL, Envelope, base_url()).

-spec make_api_request(kz_term:text(), kz_json:object(), kz_term:text()) -> state().
make_api_request(URL, Envelope, APIBase) ->
    {'ok', Trace} = start_trace(),

    Resp = make_request([pqc_cb_expect:code(201)]
                       ,fun kz_http:put/3
                       ,URL
                       ,default_request_headers(kz_log:get_callid())
                       ,kz_json:encode(Envelope)
                       ),
    create_api_state(APIBase, Resp, Trace).

-spec api_key() -> kz_term:ne_binary().
api_key() ->
    case kapps_util:get_master_account_id() of
        {'ok', MasterAccountId} ->
            api_key(MasterAccountId);
        {'error', _} ->
            lager:warning("failed to find master account, please create an account first"),
            throw('no_master_account')
    end.

-spec api_key(kz_term:ne_binary()) -> kz_term:ne_binary().
api_key(MasterAccountId) ->
    case kzd_accounts:fetch(MasterAccountId) of
        {'ok', MasterAccount} ->
            case kzd_accounts:api_key(MasterAccount) of
                <<APIKey/binary>> -> APIKey;
                _Key ->
                    lager:warning("failed to fetch api key for ~s: ~p", [MasterAccountId, _Key]),
                    throw('missing_api_key')
            end;
        {'error', _E} ->
            lager:warning("failed to fetch master account ~s: ~p", [MasterAccountId, _E]),
            throw('missing_master_account')
    end.

-spec create_api_state(kz_term:text(), response(), kz_data_tracing:trace_ref()) -> state().
create_api_state(_APIBase, {'error', {'failed_connect', 'econnrefused'}}, _Trace) ->
    lager:warning("failed to connect to Crossbar; is it running?"),
    throw({'error', 'econnrefused'});
create_api_state(APIBase, <<RespJSON/binary>>, Trace) ->
    lager:info("creating API state from ~s", [RespJSON]),
    RespEnvelope = kz_json:decode(RespJSON),
    create_api_state(APIBase
                    ,Trace
                    ,kz_json:get_ne_binary_value(<<"auth_token">>, RespEnvelope)
                    ,kz_json:get_ne_binary_value([<<"data">>, <<"account_id">>], RespEnvelope)
                    ).

create_api_state(APIBase, Trace, <<AuthToken/binary>>, <<AccountId/binary>>) ->
    RequestId = kz_log:get_callid(),

    API = #{'auth_token' => AuthToken
           ,'account_id' => AccountId
           ,'request_id' => RequestId
           ,'trace_file' => Trace
           ,'start' => get('start_time')
           ,'base_url' => APIBase
           },

    %% patch_token_costs(API, 0),

    API.

-spec v2_base_url() -> string().
v2_base_url() -> base_url().

-spec v2_base_url(state()) -> string().
v2_base_url(#{base_url:=APIBase}) -> APIBase.

-spec auth_account_id(state()) -> kz_term:ne_binary().
auth_account_id(#{'account_id' := AccountId}) -> AccountId.

-spec request_headers(state()) -> kz_http:headers().
request_headers(API) ->
    request_headers(API, []).

-spec request_headers(state(), request_headers()) -> kz_http:headers().
request_headers(#{'request_id' := RequestId}=API, RequestHeaders) ->
    lager:md([{'request_id', RequestId}]),
    Defaults = auth_header(API) ++ default_request_headers(RequestId),
    props:unique([{kz_term:to_binary(K), V} || {K, V} <- RequestHeaders ++ Defaults]);
request_headers(_, RequestHeaders) -> RequestHeaders.

auth_header(#{'basic_auth' := 'undefined'}) ->
    [];
auth_header(#{'basic_auth' := BasicAuth}) ->
    [{<<"Authorization">>, <<"Basic ", BasicAuth/binary>>}];
auth_header(#{'auth_token' := 'undefined'}) ->
    [];
auth_header(#{'auth_token' := AuthToken}) ->
    [{<<"x-auth-token">>, kz_term:to_list(AuthToken)}].

%% Need binary keys to avoid props assuming "foo" is [102, 111, 111] as a nested key
-spec default_request_headers() -> request_headers().
default_request_headers() ->
    [{<<"content-type">>, "application/json"}
    ,{<<"accept">>, "application/json"}
    ].

-spec default_request_headers(kz_term:ne_binary()) -> request_headers().
default_request_headers(RequestId) ->
    NowMS = kz_time:now_ms(),
    APIRequestID = kz_term:to_list(RequestId) ++ "-" ++ integer_to_list(NowMS),
    [{<<"x-request-id">>, APIRequestID}
    | default_request_headers()
    ].

-spec make_request(pqc_cb_expect:expectation() | pqc_cb_expect:expectations(), fun_2(), kz_term:text(), request_headers()) ->
          response().
make_request(Expectations, HTTP, URL, RequestHeaders) when is_list(Expectations) ->
    lager:info("~p(~s, ~p)", [HTTP, URL, RequestHeaders]),
    handle_response(Expectations, HTTP(URL, RequestHeaders));
make_request(Expectation, HTTP, URL, RequestHeaders) ->
    make_request([Expectation], HTTP, URL, RequestHeaders).

-spec make_request(pqc_cb_expect:expectation() | pqc_cb_expect:expectations(), fun_3(), kz_term:text(), request_headers(), kz_json:object() | iodata()) ->
          response().
make_request([_|_]=Expectations, HTTP, URL, RequestHeaders, RequestBody)
  when is_binary(RequestBody); is_list(RequestBody) ->
    lager:info("~p: ~s", [HTTP, URL]),
    lager:debug("headers: ~p", [RequestHeaders]),
    lager:debug("body: ~s", [RequestBody]),
    handle_response(Expectations, HTTP(URL, RequestHeaders, iolist_to_binary(RequestBody)));
make_request([_|_]=Expectations, HTTP, URL, RequestHeaders, RequestJObj) ->
    make_request(Expectations, HTTP, URL, RequestHeaders, kz_json:encode(RequestJObj));
make_request(Expectation, HTTP, URL, RequestHeaders, RequestBody) ->
    make_request([Expectation], HTTP, URL, RequestHeaders, RequestBody).

-spec create_envelope(kz_json:json_term()) -> kz_json:object().
create_envelope(Data) ->
    create_envelope(Data, kz_json:new()).

-spec create_envelope(kz_json:json_term(), kz_json:object()) ->
          kz_json:object().
create_envelope(Data, Envelope) ->
    kz_json:set_value(<<"data">>, Data, Envelope).

-spec handle_response(pqc_cb_expect:expectations(), kz_http:ret()) -> response().
handle_response(Expectations, {'ok', ActualCode, RespHeaders, RespBody} = Response) ->
    lager:info("checking expectations against ~p: ~p", [ActualCode, RespHeaders]),
    case pqc_cb_expect:run(Expectations, Response) of
        'true' -> RespBody;
        'false' ->
            lager:warning("expectations not met: ~w", [Expectations]),
            lager:info("~p: ~p", [ActualCode, RespHeaders]),
            lager:info("~s", [RespBody]),
            {'error', RespBody}
    end;
handle_response(_Expectations, {'error','socket_closed_remotely'}=E) ->
    lager:warning("we broke crossbar!"),
    throw(E);
handle_response(_Expectations, {'error',{'could_not_parse_as_http', Bin}}=E) ->
    lager:warning("crossbar speaking in tongues, don't use http pipeline with 204 No Content: ~s", [Bin]),
    throw(E);
handle_response(_ExpectedCode, {'error', _}=E) ->
    lager:warning("broken req: ~p", [E]),
    E.

-spec start_trace() -> {'ok', kz_data_tracing:trace_ref()}.
start_trace() ->
    RequestId = case kz_log:get_callid() of
                    'undefined' ->
                        RID = kz_binary:rand_hex(5),
                        kz_log:put_callid(RID),
                        RID;
                    RID -> RID
                end,
    lager:md([{'request_id', RequestId}]),
    put('start_time', kz_time:start_time()),

    TracePath = trace_path(),

    TraceFile = filename:join(TracePath, kz_term:to_list(RequestId) ++ ".log"),
    lager:info("tracing at ~s", [TraceFile]),

    {'ok', _}=OK = kz_data_tracing:trace_file([glc_ops:eq('request_id', RequestId)]
                                             ,TraceFile
                                             ,?TRACE_FORMAT
                                             ,get_log_level()
                                             ),

    lager:info("authenticating...~s", [RequestId]),
    OK.

-spec trace_path() -> file:filename_all().
trace_path() ->
    case application:get_env('properly', 'trace_path') of
        'undefined' -> "/tmp";
        {'ok', Path} -> Path
    end.

-spec set_log_level(atom()) -> atom().
set_log_level(LogLevel) ->
    put('log_level', LogLevel).

-spec get_log_level() -> atom().
get_log_level() ->
    case get('log_level') of
        'undefined' -> 'debug';
        LogLevel -> LogLevel
    end.

-spec init_api([atom()], [module()]) -> state().
init_api(AppsToStart, ModulesToStart) when is_list(AppsToStart)
                                           andalso is_list(ModulesToStart) ->
    Model = initial_state(AppsToStart, ModulesToStart),
    pqc_kazoo_model:api(Model).

-spec initial_state([atom()], [module()]) -> pqc_kazoo_model:model().
initial_state(AppsToStart, ModulesToStart) ->
    _ = init_system(AppsToStart, ModulesToStart),
    API = authenticate(),
    pqc_kazoo_model:new(API).

-spec init_system([atom()], [module()]) -> 'ok'.
init_system(AppsToStart, ModulesToStart) ->
    TestId = kz_binary:rand_hex(5),
    kz_log:put_callid(TestId),

    _ = kz_data_tracing:clear_all_traces(),
    _AppStarts = [{App, kapps_controller:start_app(App)}
                  || App <- AppsToStart
                 ],
    lager:info("started apps: ~p", [_AppStarts]),

    %% using `crossbar_init:start_mod/1' because it doesn't add
    %% the module to autostart, and also it doesn't print `module x started'
    _ = [crossbar_init:start_mod(Mod) || Mod <- ModulesToStart],

    'true' = ensure_started(AppsToStart, kapps_controller:running_apps()),

    lager:info("INIT FINISHED").

ensure_started(AppsToStart, RunningApps) ->
    'true' = lists:all(fun(ToStart) -> lists:member(ToStart, RunningApps) end
                      ,AppsToStart
                      ).

-spec patch_token_costs(state(), non_neg_integer()) -> 'ok'.
patch_token_costs(API, Cost) ->
    CBConfig = pqc_cb_system_configs:patch_default_config(API
                                                         ,<<"crossbar">>
                                                         ,kz_json:from_list([{<<"default">>, kz_json:from_list([{<<"token_costs">>, Cost}])}])
                                                         ),
    handle_patched_cost(API, Cost, CBConfig).

handle_patched_cost(_API, Cost, <<CBConfig/binary>>) ->
    lager:info("patched token costs to ~p: ~s", [Cost, CBConfig]);
handle_patched_cost(API, Cost, {'error', ErrorResp}) ->
    case kz_json:get_integer_value(<<"error">>, kz_json:decode(ErrorResp)) of
        409 ->
            lager:info("conflict saving our update, trying again"),
            patch_token_costs(API, Cost);
        _E ->
            lager:info("error patching token costs to ~p: ~s", [Cost, ErrorResp])
    end.

-spec get_current_token_costs(state()) -> integer().
get_current_token_costs(API) ->
    CBConfig = pqc_cb_system_configs:get_default_config(API, <<"crossbar">>),
    TokenCost = kz_json:get_integer_value([<<"data">>, <<"default">>, <<"token_costs">>], kz_json:decode(CBConfig), 1),
    'true' = is_integer(TokenCost),
    TokenCost.

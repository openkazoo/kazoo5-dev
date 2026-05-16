%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Handler for route requests, responds if Callflows match.
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_route_req).

-export([handle_req/2
        ,allow_no_match/1
        ]).

-include("callflow.hrl").

-define(DEFAULT_ROUTE_WIN_TIMEOUT_MS, 3 * ?MILLISECONDS_IN_SECOND).
-define(ROUTE_WIN_TIMEOUT_KEY, <<"route_win_timeout">>).
-define(ROUTE_WIN_TIMEOUT, kapps_config:get_integer(?CF_CONFIG_CAT, ?ROUTE_WIN_TIMEOUT_KEY, ?DEFAULT_ROUTE_WIN_TIMEOUT_MS)).

-spec handle_req(kapi_route:req(), kz_term:proplist()) -> 'ok'.
handle_req(RouteReq, Props) ->
    CallId = kapi_route:call_id(RouteReq),
    kz_log:put_callid(CallId),
    lager:debug("handle route request with fetch-id ~s", [kapi_route:fetch_id(RouteReq)]),
    'true' = kapi_route:req_v(RouteReq),
    ControllerQ = kapi:encode_pid(props:get_value('queue', Props)),
    Routines = [fun maybe_restricted_endpoint/1
               ,{fun kapps_call:set_controller_queue/2, ControllerQ}
               ],
    Call = kapps_call:exec(Routines, kapps_call:from_route_req(RouteReq)),
    case is_binary(kapps_call:account_id(Call))
        andalso callflow_should_respond(Call)
    of
        'true' -> handle_route_req(RouteReq, Call);
        'false' ->
            lager:debug("callflow not handling fetch-id ~s", [kapi_route:fetch_id(RouteReq)])
    end.

handle_route_req(RouteReq, Call) ->
    lager:info("received request ~s asking if callflows can route the call to ~s"
              ,[kapi_route:fetch_id(RouteReq), kapps_call:request_user(Call)]
              ),
    AllowNoMatch = allow_no_match(Call),
    case cf_flow:lookup(Call) of
        {'ok', Flow, 'false'} ->
            maybe_reply_to_req(RouteReq, Call, Flow, 'false');
        %% if callflow is the no_match, and we are able allowed to use it for this
        %% call, proceed
        {'ok', Flow, 'true'} when AllowNoMatch ->
            maybe_reply_to_req(RouteReq, Call, Flow, 'true');
        {'ok', _Flow, 'true'} ->
            lager:info("only available callflow is a nomatch for a unauthorized call", []);
        {'error', R} ->
            lager:info("unable to find callflow ~p", [R])
    end.

-spec skip_prepend(kapps_call:call()) -> boolean().
skip_prepend(Call) ->
    kapps_call:is_transfer(Call)
        orelse kapps_call:is_call_forward(Call)
        orelse kz_term:is_true(kapps_call:custom_sip_header(<<"X-Preferred-Media">>, Call)).

-spec maybe_prepend_preflow(kapps_call:call(), kzd_callflows:doc()) -> kzd_callflows:doc().
maybe_prepend_preflow(Call, Callflow) ->
    maybe_prepend_preflow(Call, Callflow, skip_prepend(Call)).

-spec maybe_prepend_preflow(kapps_call:call(), kzd_callflows:doc(), boolean()) -> kzd_callflows:doc().
maybe_prepend_preflow(_Call, Callflow, 'true') ->
    lager:info("request is the result of a transfer or forward, skipping preflow"),
    Callflow;
maybe_prepend_preflow(Call, Callflow, 'false') ->
    AccountId = kapps_call:account_id(Call),
    case kzd_accounts:fetch(AccountId) of
        {'error', _E} ->
            lager:warning("could not open account doc ~s : ~p", [AccountId, _E]),
            Callflow;
        {'ok', AccountDoc} ->
            maybe_prepend_account_preflow(Callflow, AccountDoc)
    end.

maybe_prepend_account_preflow(Callflow, AccountDoc) ->
    case kzd_accounts:preflow_id(AccountDoc) of
        'undefined' ->
            lager:debug("ignore preflow, not set"),
            Callflow;
        PreflowId ->
            lager:info("prepending callflow ~s", [PreflowId]),
            kzd_callflows:prepend_preflow(Callflow, PreflowId)
    end.

-spec maybe_reply_to_req(kapi_route:req(), kapps_call:call(), kzd_callflows:doc(), boolean()) -> 'ok'.
maybe_reply_to_req(RouteReq, Call, Flow, NoMatch) ->
    lager:info("callflow ~s in ~s satisfies request for ~s"
              ,[kz_doc:id(Flow)
               ,kapps_call:account_id(Call)
               ,kapps_call:request_user(Call)
               ]),
    case cf_util:token_check(Call, Flow) of
        'false' -> lager:debug("token bucket prevented callflow reply");
        'true' -> send_route_response(RouteReq, Call, Flow, NoMatch)
    end.

%%------------------------------------------------------------------------------
%% @doc Should this call be able to use outbound resources, the exact opposite
%% exists in the handoff module.  When updating this one make sure to sync
%% the change with that module.
%% @end
%%------------------------------------------------------------------------------
-spec allow_no_match(kapps_call:call()) -> boolean().
allow_no_match(Call) ->
    is_restricted_endpoint_set(Call)
        orelse allow_no_match_type(Call)
        orelse is_authz_context(Call).

-spec is_authz_context(kapps_call:call()) -> boolean().
is_authz_context(Call) ->
    is_authz_context(Call, kapps_config:is_true(?APP_NAME, <<"allow_authz_context_overrides">>, 'false')).

-spec is_authz_context(kapps_call:call(), boolean()) -> boolean().
is_authz_context(_Call, 'false') ->
    lager:debug("authz context overrides disabled"),
    'false';
is_authz_context(Call, 'true') ->
    AuthzContexts = kapps_config:get_ne_binaries(?APP_NAME, <<"authz_contexts">>, []),
    CallContext = kapps_call:context(Call),
    lager:debug("checking authz contexts: ~p against call's ~p", [AuthzContexts, CallContext]),
    is_binary(CallContext)
        andalso lists:member(CallContext, AuthzContexts).

-spec allow_no_match_type(kapps_call:call()) -> boolean().
allow_no_match_type(Call) ->
    DeniedTypes = ['undefined', kzd_resources:type(), kzd_connectivity:type()],

    case lists:member(kapps_call:authorizing_type(Call), DeniedTypes) of
        'true' -> 'false';
        'false' ->
            lager:debug("allowing no-match for authz type ~s", [kapps_call:authorizing_type(Call)]),
            'true'
    end.

%%------------------------------------------------------------------------------
%% @doc Determine if Callflows should respond to a route request.
%% @end
%%------------------------------------------------------------------------------
-spec callflow_should_respond(kapps_call:call()) -> boolean().
callflow_should_respond(Call) ->
    case kapps_call:authorizing_type(Call) of
        <<"account">> -> 'true';
        <<"user">> -> 'true';
        <<"device">> -> 'true';
        <<"mobile">> -> 'true';
        <<"callforward">> -> 'true';
        <<"clicktocall">> -> 'true';
        <<"click2call">> -> 'true';
        <<"conference">> -> 'true';
        <<"resource">> -> 'true';
        <<"sys_info">> ->
            timer:sleep(500),
            Number = kapps_call:request_user(Call),
            (not knm_converters:is_reconcilable(Number));
        'undefined' -> 'true';
        _Else ->
            lager:debug("not responding to calls from auth-type ~s", [_Else]),
            'false'
    end.

-spec ccvs(kzd_callflows:doc()) -> kz_term:api_object().
ccvs(Flow) ->
    kz_json:from_list([{<<"CallFlow-ID">>, kz_doc:id(Flow)}]).

%%------------------------------------------------------------------------------
%% @doc Send a route response for a route request that can be fulfilled by this
%% process.
%% @end
%%------------------------------------------------------------------------------
-spec send_route_response(kapi_route:req(), kapps_call:call(), kzd_callflows:doc(), boolean()) -> 'ok'.
send_route_response(RouteReq, Call, Flow, NoMatch) ->
    lager:info("callflows knows how to route the call! sending park response"),
    AccountId = kapps_call:account_id(Call),
    CallId = kapps_call:call_id(Call),
    ControllerQ = kapps_call:controller_queue(Call),
    FetchId =  kz_api:msg_id(RouteReq),

    Resp = props:filter_undefined(
             [{?KEY_MSG_ID, FetchId}
             ,{?KEY_API_ACCOUNT_ID, AccountId}
             ,{?KEY_API_CALL_ID, CallId}
             ,{<<"Routes">>, []}
             ,{<<"Method">>, <<"park">>}
             ,{<<"Transfer-Media">>, get_transfer_media(Flow, RouteReq)}
             ,{<<"Ringback-Media">>, get_ringback_media(Flow, RouteReq)}
             ,{<<"Pre-Park">>, pre_park_action(Call)}
             ,{<<"From-Realm">>, kzd_accounts:fetch_realm(AccountId)}
             ,{<<"Custom-Channel-Vars">>, ccvs(Flow)}
             ,{<<"Context">>, kapps_call:context(Call)}
             | kz_api:default_headers(ControllerQ, ?APP_NAME, ?APP_VERSION)
             ]),
    ServerId = kz_api:server_id(RouteReq),
    kapi_route:publish_resp(ServerId, Resp),
    wait_for_route_win(Call, FetchId, Flow, NoMatch).

wait_for_route_win(Call, FetchId, Flow, NoMatch) ->
    receive
        {'kapi', {_, {'call_event', 'CHANNEL_DESTROY'}, JObj}} ->
            case kz_call_event:fetch_id(JObj) of
                FetchId -> lager:info("received channel destroy while waiting for route_win, exiting");
                _Other -> wait_for_route_win(Call, FetchId, Flow, NoMatch)
            end;
        {'kapi', {_, {'dialplan', 'route_win'}, RouteWin}} ->
            lager:info("callflow has received a route win, taking control of the call"),
            execute_callflow(kapps_call:from_route_win(RouteWin, Call), Flow, NoMatch)
    after ?ROUTE_WIN_TIMEOUT ->
            lager:warning("callflow didn't received a route win, exiting")
    end.

execute_callflow(Call, Flow, NoMatch) ->
    cf_route_win:execute_callflow(update_call(Flow, NoMatch, Call)).

-spec get_transfer_media(kzd_callflows:doc(), kapi_route:req()) -> kz_term:api_ne_binary().
get_transfer_media(Flow, RouteReq) ->
    case kzd_callflows:ringback_transfer(Flow) of
        'undefined' ->
            kz_json:get_ne_binary_value(<<"Transfer-Media">>, RouteReq);
        MediaId -> MediaId
    end.

-spec get_ringback_media(kzd_callflows:doc(), kapi_route:req()) -> kz_term:api_ne_binary().
get_ringback_media(Flow, RouteReq) ->
    case kzd_callflows:ringback_early(Flow) of
        'undefined' ->
            kz_json:get_ne_binary_value(<<"Ringback-Media">>, RouteReq);
        MediaId -> MediaId
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec pre_park_action(kapps_call:call()) -> kz_term:ne_binary().
pre_park_action(Call) ->
    case kapps_config:get_is_true(?CF_CONFIG_CAT, <<"ring_ready_offnet">>, 'true')
        andalso kapps_call:inception(Call) =/= 'undefined'
    of
        'false' -> <<"none">>;
        'true' -> <<"ring_ready">>
    end.

%%------------------------------------------------------------------------------
%% @doc process
%% @end
%%------------------------------------------------------------------------------
-spec update_call(kzd_callflows:doc(), boolean(), kapps_call:call()) -> kapps_call:call().
update_call(Flow, NoMatch, Call) ->
    Callflow = maybe_prepend_preflow(Call, Flow),
    Props = [{'cf_flow_id', kz_doc:id(Flow)}
            ,{'cf_flow_name', kzd_callflows:name(Flow, kapps_call:request_user(Call))}
            ,{'cf_flow', kzd_callflows:flow(Callflow)}
            ,{'cf_capture_group', kzd_callflows:capture_group(Flow)}
            ,{'cf_capture_groups', kzd_callflows:capture_groups(Flow, kz_json:new())}
            ,{'cf_no_match', NoMatch}
            ],

    Updaters = [{fun kapps_call:kvs_store_proplist/2, Props}
               ,{fun kapps_call:set_application_name/2, ?APP_NAME}
               ,{fun kapps_call:set_application_version/2, ?APP_VERSION}
               ,{fun kapps_call:insert_custom_channel_var/3, <<"CallFlow-ID">>, kz_doc:id(Flow)}
               ],
    kapps_call:exec(Updaters, Call).

%%------------------------------------------------------------------------------
%% @doc process
%% @end
%%------------------------------------------------------------------------------
-spec maybe_restricted_endpoint(kapps_call:call()) -> kapps_call:call().
maybe_restricted_endpoint(Call) ->
    case kapps_call:restricted_endpoint_id(Call) of
        'undefined' -> Call;
        EndpointId -> kapps_call:kvs_store(?RESTRICTED_ENDPOINT_KEY, EndpointId, Call)
    end.

-spec is_restricted_endpoint_set(kapps_call:call()) -> boolean().
is_restricted_endpoint_set(Call) ->
    kapps_call:kvs_fetch(?RESTRICTED_ENDPOINT_KEY, Call) =/= 'undefined'.

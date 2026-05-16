%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_user).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

-type endpoint_get_error() :: kz_endpoint:build_errors() |
                              'endpoint_not_configured' |
                              'no_endpoints'.

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    UserId = kz_json:get_ne_binary_value(<<"id">>, Data),
    case kz_endpoint:get(UserId, Call) of
        {'ok', Endpoint} ->
            handle(Data, Call, Endpoint);
        {'error', Error} ->
            handle_error(Call, UserId, Error, should_block_self(Call))
    end.

handle(Data, Call, Endpoint) ->
    case kz_endpoint_cfwd:selective(Endpoint, Call) of
        'undefined' -> build_endpoints(Data, Call);
        Selective ->
            lager:info("bridging to selective cfwd settings"),
            Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
            bridge(Data, Call, [kz_endpoint:create_call_fwd_endpoint(Endpoint, Params, Call, Selective)])
    end.

build_endpoints(Data, Call) ->
    UserId = kz_json:get_ne_binary_value(<<"id">>, Data),
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
    case kz_endpoint:build(UserId, Params, Call) of
        {'ok', Endpoints} -> bridge(Data, Call, Endpoints);
        {'error', Error} -> handle_error(Call, UserId, Error, should_block_self(Call))
    end.

-spec handle_error(kapps_call:call(), kz_term:api_ne_binary(), endpoint_get_error(), boolean()) -> 'ok'.
handle_error(Call, UserId, 'endpoint_called_self', 'true') ->
    lager:warning("endpoint ~s called self with transfer/cfwd", [UserId]),
    cf_exe:stop(Call, <<"DESTINATION_OUT_OF_ORDER">>);
handle_error(Call, UserId, 'owner_called_self', 'true') ->
    lager:warning("owner ~s called self with transfer/cfwd", [UserId]),
    cf_exe:stop(Call, <<"DESTINATION_OUT_OF_ORDER">>);
handle_error(Call, UserId, Error, _ShouldBlockSelf) ->
    lager:info("error getting user ~s endpoints: ~s", [UserId, Error]),
    cf_exe:continue(kz_term:to_upper_binary(Error), Call).

-spec should_block_self(kapps_call:call()) -> boolean().
should_block_self(Call) ->
    kapps_call:is_call_forward(Call)
        orelse kapps_call:is_transfer(Call).

get_timeout(Data) ->
    kz_json:get_integer_value(<<"timeout">>, Data, ?DEFAULT_TIMEOUT_S).

get_strategy(Data) ->
    kz_json:get_ne_binary_value(<<"strategy">>, Data, <<"simultaneous">>).

should_ignore_early_media(<<"simultaneous">>, _Endpoints) -> 'true';
should_ignore_early_media(_Strategy, Endpoints) ->
    kz_endpoints:ignore_early_media(Endpoints).

fail_on_single_reject(Data) ->
    kz_json:get_value_type(<<"fail_on_single_reject">>, fun kz_api_term:is_boolean_or_ne_binaries/1, Data).

-spec bridge(kz_json:object(), kapps_call:call(), [kzd_endpoint:endpoint()]) -> 'ok'.
bridge(Data, Call0, Endpoints) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),


    FailOnSingleReject = fail_on_single_reject(Data),
    Strategy = get_strategy(Data),

    IgnoreEarlyMedia = should_ignore_early_media(Strategy, Endpoints),
    CustomSIPHeaders = kz_json:get_ne_json_value(<<"custom_sip_headers">>, Data),

    lager:info("dialing user ~s ~p endpoints with strategy ~s"
              ,[kz_doc:id(Data), length(Endpoints), Strategy]
              ),

    case kapps_call_command:b_bridge(Endpoints
                                    ,get_timeout(Data)  % how long to ring endpoints
                                    ,Strategy           % in what order to ring endpoints
                                    ,IgnoreEarlyMedia   % whether to ignore early media from endpoints
                                    ,'undefined'        % Ringback
                                    ,CustomSIPHeaders
                                    ,<<"false">>        % IgnoreForward
                                    ,FailOnSingleReject % whether to fail on first endpoint to reject call
                                    ,set_context_flags(Data, Call)
                                    )
    of
        {'ok', JObj} ->
            lager:info("completed successful bridge to user"),
            stop(Call, kz_call_event:channel_answer_state(JObj));
        {'fail', JObj}=Reason ->
            lager:info("bridge to user failed : ~s / ~s / ~s"
                      ,[kz_call_event:application_response(JObj)
                       ,kz_call_event:hangup_cause(JObj)
                       ,kz_call_event:hangup_code(JObj)
                       ]
                      ),
            maybe_handle_bridge_failure(Data
                                       ,Call
                                       ,kz_call_event:channel_answer_state(JObj)
                                       ,Reason
                                       );
        {'error', _R} ->
            lager:info("error bridging to user: ~p", [_R]),
            cf_exe:continue(Call)
    end.

-spec stop(kapps_call:call(), kz_term:api_ne_binary()) -> 'ok'.
stop(Call, <<"hangup">>) -> cf_exe:hard_stop(Call);
stop(Call, _) -> cf_exe:stop(Call).

-type bridge_failure_cause() :: {'fail', kz_json:object()}.

-spec maybe_handle_bridge_failure(kz_json:object(), kapps_call:call(), kz_term:api_ne_binary(), bridge_failure_cause()) -> 'ok'.
maybe_handle_bridge_failure(_Data, Call, <<"hangup">>, _Reason) ->
    cf_exe:hard_stop(Call);
maybe_handle_bridge_failure(Data, Call, AppState, Reason) ->
    EndpointId = kz_doc:id(Data),
    maybe_handle_bridge_failure(Data, Call, AppState, Reason, kz_endpoint:get(EndpointId, Call)).

maybe_handle_bridge_failure(_Data, Call, _AppState, Reason, {'error', _E}) ->
    lager:info("failed to get endpoint for failure cfwd: ~p", [_E]),
    handle_bridge_failure(Reason, Call);
maybe_handle_bridge_failure(Data, Call, _AppState, Reason, {'ok', Endpoint}) ->
    case cf_util:should_call_forward_after_failure(Reason, Endpoint) of
        {'true', CallForward} ->
            call_forward_endpoint(Data, Call, Endpoint, CallForward);
        'false' ->
            handle_bridge_failure(Reason, Call)
    end.

call_forward_endpoint(Data, Call, Endpoint, CallForward) ->
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
    CfwdEndpoint = kz_endpoint:create_call_fwd_endpoint(Endpoint
                                                       ,Params
                                                       ,Call
                                                       ,CallForward
                                                       ),
    Timeout = kz_json:get_integer_value(<<"Timeout">>, CfwdEndpoint, get_timeout(Data)),

    Bridge = [{<<"Application-Name">>, <<"bridge">>}
             ,{<<"Endpoints">>, [CfwdEndpoint]}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
             ],
    kapps_call_command:send_command(Bridge, Call),
    lager:info("sent bridge to call-forward, waiting ~ps", [Timeout]),
    case kapps_call_command:b_bridge_wait(Timeout, Call) of
        {'ok', JObj} ->
            lager:info("completed successful bridge to call forward"),
            stop(Call, kz_call_event:channel_answer_state(JObj));
        {'fail', JObj} ->
            lager:info("bridge to user failed : ~s / ~s / ~s"
                      ,[kz_call_event:application_response(JObj)
                       ,kz_call_event:hangup_cause(JObj)
                       ,kz_call_event:hangup_code(JObj)
                       ]
                      ),
            cf_exe:continue(Call);
        {'error', _R} ->
            lager:info("error bridging to user: ~p", [_R]),
            cf_exe:continue(Call)
    end.

handle_bridge_failure(Reason, Call) ->
    case cf_util:handle_bridge_failure(Reason, Call) of
        'not_found' -> cf_exe:continue(Call);
        'ok' -> lager:info("handled bridge failure, done here")
    end.

set_context_flags(Data, Call) ->
    Flags = lists:filtermap(fun is_context_flag/1, kz_json:to_proplist(Data)),
    kapps_call:kvs_store('context-flags', Flags, Call).

is_context_flag({K, V}) ->
    case kz_term:is_true(V) of
        'true' -> {'true', K};
        'false' -> 'false'
    end.

%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc handler for route requests, responds if reorder match
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(reorder_route_req).

-include("reorder.hrl").

-export([handle_req/2]).

-spec handle_req(kapi_route:req(), kz_term:proplist()) -> 'ok'.
handle_req(RouteReq, Props) ->
    Call = kapps_call:from_route_req(RouteReq),
    IsCallForward = kapps_call:is_call_forward(Call),
    case is_inbound(RouteReq)
        orelse IsCallForward
    of
        'true' when IsCallForward ->
            handle_call_forward(RouteReq, Props, Call);
        'true' ->
            handle_inbound(RouteReq, Props, Call);
        'false' -> 'ok'
    end.

-spec is_inbound(kapi_route:req()) -> boolean().
is_inbound(RouteReq) ->
    case kapi_route:inception(RouteReq) of
        'undefined' -> 'false';
        _Other -> 'true'
    end.

-spec should_defer_response(kz_term:ne_binary(), kapi_route:req()) -> boolean().
should_defer_response(Number, RouteReq) ->
    not knm_converters:is_reconcilable(Number)
        orelse is_transfer(RouteReq).

-spec is_transfer(kapi_route:req()) -> boolean().
is_transfer(RouteReq) ->
    kz_json:is_true(<<"Is-Transfer">>, RouteReq).

-spec handle_call_forward(kapi_route:req(), kz_term:proplist(), kapps_call:call()) -> 'ok'.
handle_call_forward(RouteReq, Props, Call) ->
    lager:debug("received cfw route request"),
    ControllerQ = props:get_value('queue', Props),
    Number = get_dest_number(Call),
    lager:debug("adding a refer respond for forwarded call to ~s", [Number]),
    send_error_response(RouteReq, ControllerQ, 'true', <<"forwarded_call">>).

-spec handle_inbound(kapi_route:req(), kz_term:proplist(), kapps_call:call()) -> 'ok'.
handle_inbound(RouteReq, Props, Call) ->
    lager:debug("received route request"),
    ControllerQ = props:get_value('queue', Props),
    Number = get_dest_number(Call),
    case knm_numbers:lookup_account(Number) of
        {'ok', _, _} ->
            choose_response(RouteReq, ControllerQ, 'true', <<"known_number">>);
        {'error', _R} ->
            lager:debug("~s is not associated with any account, ~p", [Number, _R]),
            ShouldDefer = should_defer_response(Number, RouteReq),
            choose_response(RouteReq, ControllerQ, ShouldDefer, <<"unknown_number">>)
    end.

-spec choose_response(kapi_route:req(), kz_term:ne_binary(), boolean(), kz_term:ne_binary()) -> 'ok'.
choose_response(RouteReq, ControllerQ, ShouldDefer, Type) ->
    case kapps_config:get_ne_binary(?CONFIG_CAT, [Type, <<"action">>], <<"respond">>) of
        <<"respond">> -> send_error_response(RouteReq, ControllerQ, ShouldDefer, Type);
        <<"transfer">> -> maybe_send_transfer(RouteReq, ControllerQ, ShouldDefer, Type);
        <<"bridge">> -> maybe_send_bridge(RouteReq, ControllerQ, ShouldDefer, Type)
    end.

-spec send_error_response(kz_json:object(), kz_term:ne_binary(), boolean(), kz_term:ne_binary()) -> 'ok'.
send_error_response(RouteReq, ControllerQ, ShouldDefer, Type) ->
    Response = [{<<"Msg-ID">>, kz_api:msg_id(RouteReq)}
               ,{<<"Method">>, <<"error">>}
               ,{<<"Defer-Response">>, ShouldDefer}
               ,{<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Reorder-Reason">>, Type}])}
               | kz_api:default_headers(ControllerQ, ?APP_NAME, ?APP_VERSION)
               ],
    Updates = error_response_by_type(Type),
    send_response(RouteReq, props:set_values(Updates, Response)).

-spec error_response_by_type(kz_term:ne_binary()) -> kz_term:proplist().
error_response_by_type(<<"unknown_number">> = Type) ->
    [{<<"Route-Error-Code">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_code">>], <<"604">>)
     }
    ,{<<"Route-Error-Message">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_message">>], <<"Nope Nope Nope">>)
     }
    ];
error_response_by_type(<<"known_number">> = Type) ->
    [{<<"Route-Error-Code">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_code">>], <<"686">>)
     }
    ,{<<"Route-Error-Message">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_message">>], <<"PICNIC">>)
     }
    ];
error_response_by_type(<<"forwarded_call">> = Type) ->
    [{<<"Route-Error-Code">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_code">>], <<"404">>)
     }
    ,{<<"Route-Error-Message">>
     ,kapps_config:get_binary(?APP_NAME, [Type, <<"response_message">>], <<"NO_ROUTE_DESTINATION">>)
     }
    ].

-spec send_response(kz_json:object(), kz_json:object()) -> 'ok'.
send_response(RouteReq, Response) ->
    Code = kz_json:get_ne_value(<<"Route-Error-Code">>, Response),
    Message = kz_json:get_ne_value(<<"Route-Error-Message">>, Response),
    Type = kz_json:get_ne_value([<<"Custom-Channel-Vars">>, <<"Reorder-Reason">>], Response),
    kapi_route:publish_resp(kz_api:server_id(RouteReq), Response),
    lager:debug("sent error response for ~s as: ~s ~s", [Type, Code, Message]).

-spec maybe_send_transfer(kz_json:object(), kz_term:ne_binary(), boolean(), kz_term:ne_binary()) -> 'ok'.
maybe_send_transfer(RouteReq, ControllerQ, ShouldDefer, Type) ->
    case kapps_config:get_ne_binary(?CONFIG_CAT, [Type, <<"transfer_target">>]) of
        'undefined' -> send_error_response(RouteReq, ControllerQ, ShouldDefer, Type);
        Number -> send_transfer(RouteReq, ControllerQ, ShouldDefer, Type, Number)
    end.

-spec send_transfer(kapi_route:req(), kz_term:ne_binary(), boolean(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
send_transfer(RouteReq, ControllerQ, ShouldDefer, _Type, Number) ->
    lager:debug("sending transfer to ~s for error type ~s", [Number, _Type]),
    Route = kz_json:from_list([{<<"Invite-Format">>, <<"loopback">>}
                              ,{<<"Route">>, Number}
                              ,{<<"To-DID">>, Number}
                              ]),
    Resp = [{<<"Msg-ID">>, kz_api:msg_id(RouteReq)}
           ,{<<"Method">>, <<"bridge">>}
           ,{<<"Routes">>, [Route]}
           ,{<<"Defer-Response">>, ShouldDefer}
           | kz_api:default_headers(ControllerQ, ?APP_NAME, ?APP_VERSION)
           ],
    kapi_route:publish_resp(kz_api:server_id(RouteReq), Resp).

-spec maybe_send_bridge(kapi_route:req(), kz_term:ne_binary(), boolean(), kz_term:ne_binary()) -> 'ok'.
maybe_send_bridge(RouteReq, ControllerQ, ShouldDefer, Type) ->
    AccountId = kapps_config:get_ne_binary(?CONFIG_CAT, [Type, <<"bridge_account_id">>]),
    EndpointId = kapps_config:get_ne_binary(?CONFIG_CAT, [Type, <<"bridge_endpoint_id">>]),
    case kz_term:is_empty(AccountId)
        orelse kz_term:is_empty(EndpointId)
    of
        'true' -> send_error_response(RouteReq, ControllerQ, ShouldDefer, Type);
        'false' ->
            Routines = [{fun kapps_call:set_account_id/2, AccountId}],
            Call = kapps_call:exec(Routines, kapps_call:from_route_req(RouteReq)),
            Endpoint = kz_endpoint:build(EndpointId, Call),
            send_bridge(RouteReq, ControllerQ, ShouldDefer, Type, Endpoint)
    end.

-spec send_bridge(kapi_route:req(), kz_term:ne_binary(), boolean(), kz_term:ne_binary(), kz_term:jobjs_return()) -> 'ok'.
send_bridge(RouteReq, ControllerQ, ShouldDefer, _Type, {'ok', Routes}) ->
    lager:debug("sending bridge to endpoint for error type ~s", [_Type]),
    Resp = [{<<"Msg-ID">>, kz_api:msg_id(RouteReq)}
           ,{<<"Method">>, <<"bridge">>}
           ,{<<"Routes">>, Routes}
           ,{<<"Defer-Response">>, ShouldDefer}
           | kz_api:default_headers(ControllerQ, ?APP_NAME, ?APP_VERSION)
           ],
    kapi_route:publish_resp(kz_api:server_id(RouteReq), Resp);
send_bridge(RouteReq, ControllerQ, ShouldDefer, Type, _) ->
    send_error_response(RouteReq, ControllerQ, ShouldDefer, Type).

-spec get_dest_number(kapps_call:call()) -> kz_term:ne_binary().
get_dest_number(Call) ->
    get_dest_number(Call, kapps_config:get(?APP_NAME, <<"inbound_user_field">>, <<"Request">>)).

-spec get_dest_number(kapps_call:call(), kz_term:api_ne_binary()) -> kz_term:ne_binary().
get_dest_number(Call, <<"To">>) ->
    maybe_format_dest(Call, kapps_call:to_user(Call));
get_dest_number(Call, _Type) ->
    maybe_format_dest(Call, kapps_call:request_user(Call)).

-spec maybe_format_dest(kapps_call:call(), kz_term:ne_binary()) -> kz_term:ne_binary().
maybe_format_dest(Call, User) ->
    case kapps_config:get_is_true(?CONFIG_CAT, <<"assume_inbound_e164">>, 'false') of
        'true' ->
            Number = assume_e164(User),
            lager:debug("assuming number is e164, normalizing to ~s", [Number]),
            Number;
        'false' ->
            Number = knm_converters:normalize(User, kapps_call:account_id(Call), kapps_call:endpoint_id(Call)),
            lager:debug("converted number ~s to e164: ~s", [User, Number]),
            Number
    end.

-spec assume_e164(kz_term:ne_binary()) -> kz_term:ne_binary().
assume_e164(<<$+, _/binary>> = Number) -> Number;
assume_e164(<<Number/binary>>) -> <<$+, Number/binary>>.

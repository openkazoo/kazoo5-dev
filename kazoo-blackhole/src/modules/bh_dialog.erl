%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_dialog).

-export([init/0
        ,authorize_subscription/2
        ,validate_subscription/2
        ,bindings/2
        ,authorize_push/2
        ,validate_push/2
        ,push/2
        ]).

-include("blackhole.hrl").

-define(ACCOUNT_BINDING(AccountId, DialogId, CallId)
       ,<<"dialog.event.", AccountId/binary, ".", DialogId/binary, ".", CallId/binary>>
       ).

-define(BINDING(DialogId, CallId)
       ,<<"dialog.event.", DialogId/binary, ".", CallId/binary>>
       ).

-define(EVENT_BINDINGS(DialogId, CallId)
       ,[?BINDING(DialogId, CallId)]
       ).

-define(PUSH_REQ_VALUES, [{<<"Event-Category">>, <<"dialog">>}
                         ,{<<"Event-Name">>, <<"push">>}
                         ]).
-define(EXCHANGE_DLG, <<"dialog">>).

-spec init() -> any().
init() ->
    init_bindings(),
    _ = blackhole_bindings:bind(<<"blackhole.events.authorize.dialog">>, ?MODULE, 'authorize_subscription'),
    _ = blackhole_bindings:bind(<<"blackhole.events.validate.dialog">>, ?MODULE, 'validate_subscription'),
    _ = blackhole_bindings:bind(<<"blackhole.events.bindings.dialog">>, ?MODULE, 'bindings'),
    _ = blackhole_bindings:bind(<<"blackhole.authorize.dialog.push">>, ?MODULE, 'authorize_push'),
    _ = blackhole_bindings:bind(<<"blackhole.validate.dialog.push">>, ?MODULE, 'validate_push'),
    _ = blackhole_bindings:bind(<<"blackhole.command.dialog.push">>, ?MODULE, 'push').


init_bindings() ->
    Bindings = ?EVENT_BINDINGS(<<"{DIALOG_ID}">>, <<"{CALL_ID}">>),
    case kapps_config:set_default(?CONFIG_CAT, [<<"bindings">>, <<"dialog">>], Bindings) of
        {'ok', _} -> lager:debug("initialized dialog bindings");
        {'error', _E} -> lager:info("failed to initialize dialog bindings: ~p", [_E])
    end.

-spec authorize_subscription(bh_context:context(), map()) -> bh_context:context().
authorize_subscription(Context, #{}) -> Context.

-spec validate_subscription(bh_context:context(), map()) -> bh_context:context().
validate_subscription(Context, #{keys := [_, _]}) -> Context;
validate_subscription(Context, #{keys := Keys}) ->
    bh_context:add_error(Context, <<"invalid format for dialog subscription : ", (kz_binary:join(Keys))/binary>>).

-spec bindings(bh_context:context(), map()) -> map().
bindings(_Context, #{account_id := AccountId
                    ,keys := [DialogId, InstanceId]
                    }=Map) ->
    Requested = ?BINDING(DialogId, InstanceId),
    Subscribed = [?ACCOUNT_BINDING(AccountId, DialogId, InstanceId)],
    Listeners = [{'amqp', 'bind', event_binding_options(AccountId, DialogId, InstanceId)}],
    Map#{requested => Requested
        ,subscribed => Subscribed
        ,listeners => Listeners
        }.

-spec authorize_push(bh_context:context(), kz_json:object()) -> bh_context:context().
authorize_push(Context, _Payload) -> Context.

-spec validate_push(bh_context:context(), kz_json:object()) -> bh_context:context().
validate_push(Context, Payload) ->
    case push_data_payload(Payload) of
        'undefined' -> bh_context:add_error(Context, <<"missing required data object">>);
        _Data -> Context
    end.

-spec push(bh_context:context(), kz_json:object()) -> bh_context:context().
push(Context, Payload) ->
    JObj = kz_json:set_values(kz_api:default_headers(?APP_NAME, ?APP_VERSION), push_data_payload(Payload)),
    case publish_push(JObj) of
        'ok' -> bh_context:set_resp_status(Context, <<"success">>);
        {'error', Error} -> bh_context:add_error(Context, Error)
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec event_binding_options(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:proplist().
event_binding_options(AccountId, DialogId, InstanceId) ->
    [{'exchange', [{'name', ?EXCHANGE_DLG}, {'type', <<"topic">>}]}
    ,{'routing', kz_binary:join([<<"dialog">>, <<"event">>, AccountId, DialogId, InstanceId], <<".">>)}
    ,'federate'
    ].

push_data_payload(JObj) ->
    kz_json:get_json_value(<<"data">>, JObj).

-spec publish_push(kz_json:object()) -> 'ok' | {'error', any()}.
publish_push(API) ->
    publish_push(kz_api:server_id(API), API).

-spec publish_push(kz_term:api_ne_binary(), kz_json:object()) -> 'ok' | {'error', any()}.
publish_push('undefined', _API) ->
    {'error', <<"no server_id to publish dialog">>};
publish_push(ServerId, API) ->
    {'ok', Payload} = kz_api:prepare_api_payload(kz_json:set_values(?PUSH_REQ_VALUES, API), [], fun build/1),
    kz_amqp_util:targeted_publish(ServerId, Payload).

-spec build(kz_term:proplist()) -> kz_api:api_formatter_return().
build(Props) ->
    kz_api:build_message(Props, props:get_keys(Props), []).

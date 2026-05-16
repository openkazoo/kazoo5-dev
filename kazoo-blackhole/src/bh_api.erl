%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_api).

-export([init/0
        ,authorize/2
        ,validate/2
        ,api/2
        ]).

-include("blackhole.hrl").

-spec init() -> 'ok'.
init() ->
    _ = blackhole_bindings:bind(<<"blackhole.authorize.api">>, ?MODULE, 'authorize'),
    _ = blackhole_bindings:bind(<<"blackhole.validate.api">>, ?MODULE, 'validate'),
    _ = blackhole_bindings:bind(<<"blackhole.command.api">>, ?MODULE, 'api'),
    'ok'.

-spec authorize(bh_context:context(), kz_json:object()) -> bh_context:context().
authorize(Context, _Payload) -> Context.

-spec validate(bh_context:context(), kz_json:object()) -> bh_context:context().
validate(Context, Payload) ->
    case api_data_payload(Payload) of
        'undefined' -> bh_context:add_error(Context, <<"missing required data object">>);
        _Data -> validate_api(Context, Payload)
    end.

-spec validate_api(bh_context:context(), kz_json:object()) -> bh_context:context().
validate_api(Context, Payload) ->
    case api_endpoint(Payload) of
        'undefined' -> bh_context:add_error(Context, <<"missing endpoint">>);
        _Data -> Context
    end.

-spec api(bh_context:context(), kz_json:object()) -> bh_context:context().
api(Context, Payload) ->
    kz_process:spawn(fun api_call/2, [Context, Payload]),
    bh_context:set_async_reply(Context, 'true').

api_uri() ->
    Default = <<"http://localhost:8000">>,
    Key = <<"bh_api_url">>,
    uri_string:parse(kz_app_config:get_ne_binary(?APP, Key, Default)).

api_call(Context, Payload) ->
    RequestId = bh_context:req_id(Context),
    SessionPid = bh_context:websocket_pid(Context),
    Headers = api_headers(Context),
    Method = api_verb(Payload),
    Endpoint = uri_string:parse(maybe_fix_endpoint(Payload)),
    Url = uri_string:recompose(maps:merge(api_uri(), Endpoint)),
    Body = api_body(Payload),
    Reply = kz_http:req(Method, Url, Headers, Body),
    ReplyData = handle_api_reply(Reply),
    blackhole_data_emitter:reply(SessionPid, RequestId, <<"success">>, ReplyData).

api_headers(Context) ->
    Auth = bh_context:auth_token(Context),
    RequestId = bh_context:req_id(Context),
    [{<<"X-Auth-Token">>, Auth}
    ,{<<"x-request-id">>, RequestId}
    ].

handle_api_reply({'ok', _Code, _Headers, Body}) ->
    kz_json:decode(Body).

api_data_payload(JObj) ->
    kz_json:get_json_value(<<"data">>, JObj).

api_endpoint(JObj) ->
    kz_json:get_ne_binary_value(<<"endpoint">>, data_payload(JObj)).

data_payload(JObj) ->
    kz_json:get_json_value(<<"data">>, JObj, kz_json:new()).

api_verb(JObj) ->
    kz_json:get_atom_value(<<"verb">>, data_payload(JObj), 'get').

maybe_fix_endpoint(JObj) ->
    case kz_json:get_ne_binary_value(<<"endpoint">>, data_payload(JObj)) of
        'undefined' -> 'undefined';
        <<"/", _/binary>> = EP -> EP;
        EP -> <<"/", EP/binary>>
    end.

api_body(JObj) ->
    kz_json:get_binary_value(<<"body">>, data_payload(JObj), <<>>).

%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_httpd_handler).
-behaviour(cowboy_handler).

%% Cowboy callbacks
-export([init/2
        ,handle/2
        ,terminate/3
        ]).

-export([start_plaintext/1
        ,stop_listener/1
        ,port/1
        ]).

-include("properly.hrl").

-define(LISTENER, 'properly_httpd').

-spec port(kz_term:ne_binary()) -> inet:port_number().
port(LogId) ->
    ranch:get_port(kz_term:to_atom(LogId, 'true')).

-spec routes(kz_term:ne_binary()) -> cowboy_router:routes().
routes(LogId) -> [host(LogId)].

host(LogId) ->
    {'_' % HostMatch
    ,paths_list(LogId) % PathsList
    }.

paths_list(LogId) ->
    [default_path(LogId)].

default_path(LogId) ->
    {'_'     % path match
    ,?MODULE % handler module
     %% initial state sent to init/2
    ,[{'log_id', LogId}
     ,{'server', self()}
     ]
    }.

-spec start_plaintext(kz_term:ne_binary()) -> {'ok', pid()}.
start_plaintext(LogId) ->
    Routes = routes(LogId),
    Dispatch = cowboy_router:compile(Routes),
    lager:info("starting ~s: ~p", [LogId, Routes]),
    cowboy:start_clear(kz_term:to_atom(LogId, 'true')
                      ,#{'num_acceptors' => 5}
                      ,#{'env' => #{'dispatch' => Dispatch}}
                      ).

-spec init(cowboy_req:req(), HandlerOpts) ->
          {'ok', cowboy_req:req(), HandlerOpts}
              when HandlerOpts :: kz_term:proplist().
init(Req, HandlerOpts) ->
    lager:info("handler opts: ~p", [HandlerOpts]),
    log_meta(props:get_value('log_id', HandlerOpts)),
    handle(Req, HandlerOpts).

-spec handle(cowboy_req:req(), HandlerOpts) -> {'ok', cowboy_req:req(), HandlerOpts}.
handle(Req, HandlerOpts) ->
    put('start_time', kz_time:start_time()),
    handle(Req, HandlerOpts, cowboy_req:method(Req)).

handle(Req, HandlerOpts, <<"GET">>) ->
    get_from_state(Req, HandlerOpts);
handle(Req, HandlerOpts, CreateMethod) ->
    add_req_to_state(Req, HandlerOpts, CreateMethod).

get_from_state(Req, HandlerOpts) ->
    Path = cowboy_req:path(Req), % <<"/foo/bar/baz">>
    PathParts = tl(binary:split(Path, <<"/">>, ['global', 'trim'])),

    lager:info("processing GET ~s", [Path]),

    {Req1, ReqBody} = maybe_handle_multipart(Req),

    ReqHeaders = kz_json:from_map(cowboy_req:headers(Req)),

    {RespCode, RespHeaders, RespBody} =
        case pqc_httpd:get_req(props:get_value('server', HandlerOpts), PathParts) of
            'undefined' -> {404, #{}, <<>>};
            {#{<<"response-code">> := Code}=Headers, Body} -> {Code, maps:remove(<<"response-code">>, Headers), Body};
            {Headers, Body} -> {200, Headers, Body}
        end,

    lager:info("GET req ~s: resp ~p", [Path, RespCode]),

    QueryString = cowboy_req:parse_qs(Req1),

    pqc_httpd:add_request(props:get_value('server', HandlerOpts), PathParts, iolist_to_binary(ReqBody), ReqHeaders, QueryString),

    lager:info("resp headers: ~p", [RespHeaders]),
    Req2 = cowboy_req:reply(RespCode, kz_json:to_map(RespHeaders), RespBody, Req1),
    lager:info("cw req2: ~p", [Req2]),
    {'ok', Req2, HandlerOpts}.

add_req_to_state(Req, HandlerOpts, CreateMethod) ->
    Path = cowboy_req:path(Req), % <<"/foo/bar/baz">>
    PathParts = tl(binary:split(Path, <<"/">>, ['global', 'trim'])),

    lager:info("processing ~s ~s", [CreateMethod, Path]),

    {Req1, ReqBody} = maybe_handle_multipart(Req),
    ReqHeaders = kz_json:from_map(cowboy_req:headers(Req)),

    RespCode = case {pqc_httpd:get_req(props:get_value('server', HandlerOpts), PathParts), CreateMethod} of
                   {'undefined', <<"PUT">>} -> 201;
                   {_Value, _} -> 200
               end,

    QueryString = cowboy_req:parse_qs(Req),

    lager:info("~s req ~s: ~p: ~s", [CreateMethod, Path, RespCode, ReqBody]),
    pqc_httpd:add_request(props:get_value('server', HandlerOpts), PathParts, iolist_to_binary(ReqBody), ReqHeaders, QueryString),

    DefaultHeaders = kz_json:from_list([{<<"content-type">>, <<"application/json">>}]),
    {RespHeaders, RespBody} =
        try pqc_httpd:get_req(props:get_value('server', HandlerOpts), PathParts) of
            'undefined' -> {DefaultHeaders, <<"{}">>};
            {Hdrs, Body} -> {kz_json:merge(Hdrs, DefaultHeaders), Body}
        catch
            _E:_R:_ST ->
                lager:info("crashed getting req data for ~p: ~p ~p", [Path, _E, _R]),
                lager:info("st: ~p", [_ST]),
                {DefaultHeaders, <<"{}">>}
        end,

    lager:info("replying with '~s'", [RespBody]),
    Req2 = cowboy_req:reply(RespCode, kz_json:to_map(RespHeaders), RespBody, Req1),
    {'ok', Req2, HandlerOpts}.

-spec read_body({'ok', binary(), cowboy_req:req()} |
                {'more', binary(), cowboy_req:req()}
               ) -> {cowboy_req:req(), iodata()}.
read_body({'ok', BodyPart, Req}) ->
    {Req, BodyPart};
read_body({'more', BodyPart, Req}) ->
    {Req1, Rest} = read_body(cowboy_req:read_body(Req)),
    {Req1, [BodyPart, Rest]}.

-spec maybe_handle_multipart(cowboy_req:req()) -> {cowboy_req:req(), iodata()}.
maybe_handle_multipart(Req) ->
    maybe_handle_multipart(Req, cowboy_req:parse_header(<<"content-type">>, Req)).

maybe_handle_multipart(Req, {<<"multipart">>, <<"form-data">>, _Boundary}) ->
    lager:info("handle multipart body with boundary: ~p", [_Boundary]),
    handle_multipart(Req);
maybe_handle_multipart(Req, _CT) ->
    lager:info("req has content-type: ~p", [_CT]),
    read_body(cowboy_req:read_body(Req)).

handle_multipart(Req0) ->
    case cowboy_req:read_part(Req0) of
        {'ok', Headers, Req1} ->
            lager:info("recv part headers: ~p", [Headers]),
            handle_part_headers(Req1, Headers);
        {'done', Req1} ->
            lager:info("finished reading parts, no body"),
            {Req1, <<>>}
    end.

handle_part_headers(Req, #{<<"content-type">> := <<"application/json">>}) ->
    lager:info("skipping JSON metadata"),
    handle_multipart(Req);
handle_part_headers(Req, Headers) ->
    case cow_multipart:form_data(Headers) of
        {'data', Field} ->
            lager:info("field: ~p", [Field]),
            {'ok', Body, Req1} = cowboy_req:read_part_body(Req),
            lager:info("body: ~p", [Body]),
            {Req1, Body};
        {'file', _FieldName, _Filename, _CType} ->
            lager:info("file ~p: ~p: ~p", [_FieldName, _Filename, _CType]),
            {'ok', Body, Req1} = cowboy_req:read_part_body(Req),
            lager:info("body: ~p", [Body]),
            {Req1, Body}
    end.

-spec terminate(any(), cowboy_req:req(), any()) -> 'ok'.
terminate(_Reason, _Req, _State) ->
    lager:info("finished req in ~pms: ~p", [kz_time:elapsed_ms(get('start_time')), _Reason]).

-spec stop_listener(kz_term:ne_binary()) -> 'ok'.
stop_listener(LogId) ->
    cowboy:stop_listener(kz_term:to_atom(LogId, 'true')).

log_meta(LogId) ->
    kz_log:put_callid(LogId),
    lager:md([{'request_id', LogId}]),
    put('start_time', kz_time:start_time()),
    lager:info("starting HTTP request").

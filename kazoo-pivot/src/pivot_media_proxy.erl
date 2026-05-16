%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pivot_media_proxy).
-behaviour(cowboy_handler).

-export([init/2
        ,terminate/3
        ]).

-export([media_path/3]).

%%------------------------------------------------------------------------------
%% @doc Inits the request in all its glory!
%% @end
%%------------------------------------------------------------------------------
-spec init(cowboy_req:req(), cowboy_websocket:opts()) ->
          {'ok' , cowboy_req:req(), kz_term:proplist()}.
init(Req, HandlerOpts) ->
    MediaId = cowboy_req:binding('media_id', Req),
    FilePath = media_path(MediaId),
    case filelib:is_regular(FilePath) of
        'true' ->
            ContentType = kz_mime:from_extension(filename:extension(FilePath)),
            lager:debug("sending ~s file ~s", [ContentType, FilePath]),
            Headers = #{<<"content-type">> => ContentType},
            Len = filelib:file_size(FilePath),
            {'ok', cowboy_req:reply(200, Headers, {'sendfile', 0, Len, FilePath}, Req), HandlerOpts};
        'false' ->
            lager:info("media file ~s not found", [FilePath]),
            {'ok', cowboy_req:reply(404, Req), HandlerOpts}
    end.

-spec terminate(any(), cowboy_req:req(), any()) -> 'ok'.
terminate(_Reason, _Req, _State) ->
    lager:debug("terminating media file proxy req: ~p", [_Reason]).

-spec media_path(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
media_path(CallId, StreamId, ContentType) ->
    Ext = kz_mime:to_extension(ContentType),
    Id = kz_binary:join([<<"stream_buffer">>, CallId, StreamId, kz_binary:rand_hex(4)], <<"_">>),
    FileName = <<Id/binary, ".", Ext/binary>>,
    filename:join([<<"/tmp">>, FileName]).

-spec media_path(kz_term:ne_binary()) -> kz_term:ne_binary().
media_path(MediaId) ->
    filename:join([<<"/tmp">>, MediaId]).

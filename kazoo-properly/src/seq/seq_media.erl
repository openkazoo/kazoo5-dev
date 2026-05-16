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
-module(seq_media).

-export([seq/0
        ,cleanup/0
        ,new_media_doc/0
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).

-spec seq() -> 'ok'.
seq() ->
    Fs = [fun seq_media_file/0],
    run_funs(Fs).

run_funs([]) -> 'ok';
run_funs([F|Fs]) ->
    _ = F(),
    cleanup(),
    run_funs(Fs).

seq_media_file() ->
    API = pqc_cb_api:init_api(['crossbar', 'media_mgr'], ['cb_media']),
    AccountId = create_account(API),

    EmptySummaryResp = pqc_cb_media:summary(API, AccountId),
    lager:info("empty summary resp: ~s", [EmptySummaryResp]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryResp)),

    CreateMetaResp = pqc_cb_media:create(API, AccountId, new_media_doc()),
    lager:info("created media meta: ~s", [CreateMetaResp]),
    CreatedMeta = kz_json:get_json_value([<<"data">>], kz_json:decode(CreateMetaResp)),
    MediaId = kz_doc:id(CreatedMeta),

    SummaryResp = pqc_cb_media:summary(API, AccountId),
    lager:info("summary resp: ~s", [SummaryResp]),
    [MediaSummary] = kz_json:get_list_value([<<"data">>], kz_json:decode(SummaryResp)),
    'true' = kz_doc:id(CreatedMeta) =:= kz_doc:id(MediaSummary),

    {'ok', MP3} = file:read_file(filename:join([code:priv_dir('properly'), "mp3.mp3"])),

    UploadResp = pqc_cb_media:update_binary(API, AccountId, MediaId, MP3),
    lager:info("upload resp: ~s", [UploadResp]),
    UploadedMediaMeta = kz_json:get_json_value([<<"data">>], kz_json:decode(UploadResp)),
    MediaId = kz_doc:id(UploadedMediaMeta),

    UpdateResp = pqc_cb_media:update(API, AccountId, MediaId, MP3),
    lager:info("update resp: ~s", [UploadResp]),
    UpdatedMediaMeta = kz_json:get_json_value([<<"data">>], kz_json:decode(UpdateResp)),
    MediaId = kz_doc:id(UpdatedMediaMeta),

    FetchedMedia = pqc_cb_media:fetch_binary(API, AccountId, MediaId),
    lager:info("fetched binary: ~p", [FetchedMedia]),
    MP3 = FetchedMedia,

    FetchedMediaAgain = pqc_cb_media:fetch(API, AccountId, MediaId, <<"audio/mp3">>),
    lager:info("fetched binary again: ~p", [FetchedMediaAgain]),
    MP3 = FetchedMediaAgain,

    MediaName = kz_media_util:media_path(<<"/", AccountId/binary, "/", MediaId/binary>>, kz_binary:rand_hex(16)),

    lager:info("fetching URL for ~s", [MediaName]),
    {'ok', [AMQPResp|_]} = pqc_media_mgr:request_media_url(MediaName, <<"new">>),
    lager:info("fetched URL for ~s: ~p", [MediaName, AMQPResp]),
    StreamURL = kz_json:get_ne_binary_value(<<"Stream-URL">>, AMQPResp),
    lager:info("streaming from ~s", [StreamURL]),
    {'ok', 200, _, FetchedMP3} = kz_http:get(kz_term:to_list(StreamURL)),
    lager:info("streamed: ~p", [FetchedMP3]),
    MP3 = FetchedMP3,

    DeleteResp = pqc_cb_media:delete(API, AccountId, MediaId),
    lager:info("delete resp: ~s", [DeleteResp]),

    EmptySummaryAgain = pqc_cb_media:summary(API, AccountId),
    lager:info("empty summary again: ~s", [EmptySummaryAgain]),
    [] = kz_json:get_list_value([<<"data">>], kz_json:decode(EmptySummaryAgain)),

    cleanup(API),
    lager:info("FINISHED MEDIA SEQ").

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

-spec new_media_doc() -> kzd_media:doc().
new_media_doc() ->
    Set = [{fun kzd_media:set_name/2, kz_binary:rand_hex(6)}],
    kz_doc:public_fields(kz_json:exec_first(Set, kzd_media:new())).

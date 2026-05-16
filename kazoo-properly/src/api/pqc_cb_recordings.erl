%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_recordings).

-export([summary/2
        ,create/2
        ,fetch/3
        ,fetch_binary/3, fetch_tunneled/3
        ,delete/3
        ]).

-include("properly.hrl").

-define(ACCOUNT_NAMES, [<<"account_for_recordings">>]).

-spec summary(pqc_cb_api:state(), seq_accounts:account_id()) ->
          {'error', 'not_found'} |
          {'ok', kz_json:objects()}.
summary(API, AccountId) ->
    case pqc_cb_crud:summary(API, recordings_url(API, AccountId)) of
        {'error', _E} ->
            ?DEBUG("listing recordings errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            ?DEBUG("listing recordings: ~s", [Response]),
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch(pqc_cb_api:state(), seq_accounts:account_id(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
fetch(API, AccountId, RecordingId) ->
    case pqc_cb_crud:fetch(API, recordings_url(API, AccountId, RecordingId)) of
        {'error', _E} ->
            ?DEBUG("fetching recording errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            ?DEBUG("fetching recording: ~s", [Response]),
            {'ok', kz_json:get_json_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch_binary(pqc_cb_api:state(), seq_accounts:account_id(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binary()} |
          {'error', 'not_found'}.
fetch_binary(API, AccountId, RecordingId) ->
    ExpectedHeaders = [{"content-type", "audio/mpeg"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    case pqc_cb_crud:fetch(API
                          ,recordings_url(API, AccountId, RecordingId)
                          ,Expectations
                          ,pqc_cb_api:request_headers(API, [{<<"accept">>, "audio/mpeg"}])
                          )
    of
        {'error', _E} ->
            ?DEBUG("fetching binary errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', Response}
    end.

-spec fetch_tunneled(pqc_cb_api:state(), seq_accounts:account_id(), kz_term:ne_binary()) ->
          {'ok', kz_term:ne_binary()} |
          {'error', 'not_found'}.
fetch_tunneled(API, AccountId, RecordingId) ->
    ExpectedHeaders = [{"content-type", "audio/mpeg"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    case pqc_cb_crud:fetch(API
                          ,recordings_url(API, AccountId, RecordingId) ++ "?accept=audio/mpeg"
                          ,Expectations
                          )
    of
        {'error', _E} ->
            ?DEBUG("fetching binary/tunneled errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', Response}
    end.

-spec create(pqc_cb_api:state(), seq_accounts:account_id()) ->
          {'ok', kzd_call_recordings:doc()}.
create(_API, AccountId) ->
    MODB = kzs_util:format_account_mod_id(AccountId),

    BaseMediaDoc = create_doc(),
    MediaDoc = kz_doc:update_pvt_parameters(BaseMediaDoc, MODB, [{'type', kzd_call_recordings:type()}]),
    ?INFO("saving to ~s: ~p", [MODB, MediaDoc]),
    {'ok', Doc} = kazoo_modb:save_doc(MODB, MediaDoc, [{'ensure_saved', 'true'}]),
    {'ok', _} = create_attachment(MODB, kz_doc:id(Doc)),
    kz_datamgr:open_cache_doc(MODB, kz_doc:id(Doc)).

-define(RECORDING_ID, <<"bf8a6522730f93248d41f2521cfe2b95">>).
create_doc() ->
    lists:foldl(fun({F, V}, Doc) -> F(Doc, V) end
               ,kzd_call_recordings:new()
               ,[{fun kzd_call_recordings:set_id/2, ?RECORDING_ID}
                ,{fun kzd_call_recordings:set_description/2, <<"pqc_cb_recordings test">>}
                ,{fun kzd_call_recordings:set_source_type/2, kz_term:to_binary(?MODULE)}
                ]
               ).

-define(MP3_FILE, filename:join([code:priv_dir('properly'), <<"mp3.mp3">>])).
create_attachment(MODB, DocId) ->
    File = ?MP3_FILE,
    AName = filename:basename(File, <<".mp3">>),
    {'ok', Contents} = file:read_file(File),
    ?INFO("adding attachment to ~s/~s: ~s", [MODB, DocId, AName]),
    kz_datamgr:put_attachment(MODB, DocId, AName, Contents, [{'content_type', kz_mime:from_filename(File)}]).

-spec delete(pqc_cb_api:state(), seq_accounts:account_id(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
delete(API, AccountId, RecordingId) ->
    Expectations = [pqc_cb_expect:codes([200,404])],
    case pqc_cb_crud:delete(API, recordings_url(API, AccountId, RecordingId), Expectations) of
        {'error', _E} ->
            ?DEBUG("delete recording errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            JObj = kz_json:decode(Response),
            case kz_json:get_integer_value(<<"error">>, JObj) of
                404 -> {'error', 'not_found'};
                _Code -> {'ok', kz_json:get_json_value(<<"data">>, JObj)}
            end
    end.

-spec recordings_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
recordings_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"recordings">>).

-spec recordings_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
recordings_url(API, AccountId, RecordingId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"recordings">>, RecordingId).

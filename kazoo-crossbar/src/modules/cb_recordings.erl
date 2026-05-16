%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc Provides access to stored call recordings.
%%%
%%% @author OnNet (Kirill Sysoev [github.com/onnet])
%%% @author Dinkor (Andrew Korniliv [github.com/dinkor])
%%% @author Lazedo (Luis Azedo [github.com/2600hz])
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_recordings).

-export([init/0
        ,allowed_methods/0, allowed_methods/1
        ,resource_exists/0, resource_exists/1
        ,content_types_provided/2
        ,validate/1, validate/2
        ,patch/2
        ,delete/2
        ]).

-include("crossbar.hrl").

-define(CB_LIST, <<"recordings/crossbar_listing">>).
-define(CB_LIST_BY_OWNERID, <<"recordings/listing_by_user">>).

-define(MEDIA_MIME_TYPES, [{<<"audio">>, <<"mpeg">>}
                          ,{<<"audio">>, <<"mp3">>}
                          ]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    Bindings = [{<<"*.allowed_methods.recordings">>, 'allowed_methods'}
               ,{<<"*.resource_exists.recordings">>, 'resource_exists'}
               ,{<<"*.content_types_provided.recordings">>, 'content_types_provided'}
               ,{<<"*.validate.recordings">>, 'validate'}
               ,{<<"*.execute.patch.recordings">>, 'patch'}
               ,{<<"*.execute.delete.recordings">>, 'delete'}
               ],
    cb_modules_util:bind(?MODULE, Bindings).

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_GET].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(_RecordingId) -> [?HTTP_GET, ?HTTP_PATCH, ?HTTP_DELETE].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_RecordingId) -> 'true'.

%%------------------------------------------------------------------------------
%% @doc What content-types will the module be using to respond (matched against
%% client's Accept header).
%% Of the form `{atom(), [{Type, SubType}]} :: {to_json, [{<<"application">>, <<"json">>}]}'
%% @end
%%------------------------------------------------------------------------------
-spec content_types_provided(cb_context:context(), path_token()) -> cb_context:context().
content_types_provided(Context, _RecordingId) ->
    content_types_provided_for_download(Context, cb_context:req_verb(Context)).

-spec content_types_provided_for_download(cb_context:context(), http_method()) -> cb_context:context().
content_types_provided_for_download(Context, ?HTTP_GET) ->
    CTP = [{'to_json', ?JSON_CONTENT_TYPES}
          ,{'to_binary', ?MEDIA_MIME_TYPES}
          ],
    cb_context:set_content_types_provided(Context, CTP);
content_types_provided_for_download(Context, _Verb) ->
    Context.

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    recording_summary(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?MATCH_MODB_PREFIX(Year, Month, _)=RecordingId) ->
    Context1 = cb_context:set_db_name(Context
                                     ,kzs_util:format_account_id(
                                        cb_context:account_id(Context)
                                       ,kz_term:to_integer(Year)
                                       ,kz_term:to_integer(Month)
                                       )
                                     ),
    validate_recording(Context1, RecordingId, cb_context:req_verb(Context1));
validate(Context, RecordingId) ->
    crossbar_util:response_bad_identifier(RecordingId, Context).

validate_recording(Context, RecordingId, ?HTTP_GET) ->
    case action_lookup(Context) of
        'read' ->
            load_recording_doc(Context, RecordingId);
        'download' ->
            load_recording_binary(Context, RecordingId)
    end;
validate_recording(Context, RecordingId, ?HTTP_PATCH) ->
    Context1 = validate_only_writable_props_included(
                 cb_context:set_resp_status(Context, 'success')
                ),

    case cb_context:has_errors(Context1) of
        'true' -> Context1;
        'false' ->
            crossbar_doc:patch_and_validate(
              RecordingId
             ,Context1
             ,fun validate_patch/2
             ,?TYPE_CHECK_OPTION(kzd_call_recordings:type())
             )
    end;
validate_recording(Context, RecordingId, ?HTTP_DELETE) ->
    load_recording_doc(Context, RecordingId).

%%------------------------------------------------------------------------------
%% @doc Validate the request body of a `PATCH' request.
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(path_token(), cb_context:context()) -> cb_context:context().
validate_patch(_, Context) ->
    cb_context:validate_request_data(<<"call_recordings">>
                                    ,strip_id_from_req_data(Context)
                                    ).

%%------------------------------------------------------------------------------
%% @doc Save changes to the writable properties of a recording. If there have
%% been no changes, this is a no-op.
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, RecordingId) ->
    Doc = cb_context:doc(Context),
    ReqData = cb_context:fetch(Context, 'patch'),

    case kz_json:is_json_object(kzd_call_recordings:user_metadata(ReqData)) of
        'false' -> crossbar_doc:handle_json_success(Doc, Context);
        'true' -> save_user_metadata(Context, RecordingId, Doc)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _RecordingId) ->
    crossbar_doc:delete(Context).

-spec recording_summary(cb_context:context()) -> cb_context:context().
recording_summary(Context) ->
    UserId = cb_context:user_id(Context),
    ViewName = get_view_name(UserId),
    Options = summary_options(UserId),
    crossbar_view:load_modb(Context, ViewName, Options).

summary_options(UserId) ->
    [{'mapper', fun summary_doc_fun/2}
    ,{'range_start_keymap', [UserId]}
    ,{'range_end_keymap', fun(Ts) -> build_end_key(Ts, UserId) end}
    ,{'field_key', 'filtermap'}
    ,'include_docs'
    ].

-spec summary_doc_fun(kz_json:object(), kz_json:objects()) -> kz_json:objects().
summary_doc_fun(View, Acc) ->
    Recording = kz_json:get_json_value(<<"doc">>, View),
    Attachments = kz_doc:attachments(Recording, kz_json:new()),
    ContentTypes = kz_json:foldl(fun attachment_content_type/3, [], Attachments),

    [kz_json:set_value([<<"_read_only">>, <<"content_types">>]
                      ,lists:usort(ContentTypes)
                      ,Recording
                      )
    | Acc
    ].

-spec attachment_content_type(kz_json:key(), kz_json:object(), kz_term:ne_binaries()) ->
          kz_term:ne_binaries().
attachment_content_type(_Name, Meta, CTs) ->
    [kz_json:get_ne_binary_value(<<"content_type">>, Meta) | CTs].

-spec build_end_key(kz_time:gregorian_seconds(), kz_term:api_ne_binary()) -> kazoo_data:key_range().
build_end_key(Timestamp, 'undefined') -> [Timestamp, kz_json:new()];
build_end_key(Timestamp, UserId) -> [UserId, Timestamp, kz_json:new()].

-spec get_view_name(kz_term:api_ne_binary()) -> kz_term:ne_binary().
get_view_name('undefined') -> ?CB_LIST;
get_view_name(_) -> ?CB_LIST_BY_OWNERID.

-spec load_recording_doc(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_recording_doc(Context, RecordingId) ->
    crossbar_doc:load({kzd_call_recordings:type(), RecordingId}
                     ,Context
                     ,?TYPE_CHECK_OPTION(kzd_call_recordings:type())
                     ).

-spec load_recording_binary(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_recording_binary(Context, DocId) ->
    Context1 = load_recording_doc(Context, DocId),
    case cb_context:resp_status(Context1) of
        'success' ->
            do_load_recording_binary_attachment(Context1, DocId);
        _Status -> Context1
    end.

-spec do_load_recording_binary_attachment(cb_context:context(), kz_term:ne_binary()) ->
          cb_context:context().
do_load_recording_binary_attachment(Context, DocId) ->
    case kz_doc:attachment_names(cb_context:doc(Context)) of
        [] ->
            cb_context:add_system_error('bad_identifier'
                                       ,kz_json:from_list([{<<"details">>, DocId}])
                                       ,Context
                                       );
        [AName | _] ->
            LoadedContext = crossbar_doc:load_attachment({kzd_call_recordings:type(), DocId}
                                                        ,AName
                                                        ,?TYPE_CHECK_OPTION(kzd_call_recordings:type())
                                                        ,Context
                                                        ),

            set_resp_headers(LoadedContext
                            ,AName
                            ,kz_doc:attachment(cb_context:doc(Context), AName)
                            )
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec set_resp_headers(cb_context:context(), kz_term:ne_binary(), kz_json:object()) ->
          cb_context:context().
set_resp_headers(Context, AName, Attachment) ->
    Headers = #{<<"content-disposition">> => get_disposition(AName, Context)
               ,<<"content-type">> => kz_json:get_ne_binary_value(<<"content_type">>, Attachment)
               },
    cb_context:add_resp_headers(Context, Headers).

-spec get_disposition(kz_term:ne_binary(), cb_context:context()) -> kz_term:ne_binary().
get_disposition(MediaName, Context) ->
    case kz_json:is_true(<<"inline">>, cb_context:query_string(Context), 'false') of
        'false' -> <<"attachment; filename=", MediaName/binary>>;
        'true' -> <<"inline; filename=", MediaName/binary>>
    end.

-spec action_lookup(cb_context:context()) -> atom().
action_lookup(Context) ->
    Acceptable = acceptable_content_types(Context),
    action_lookup(Acceptable, accept_values(Context)).

-spec action_lookup(kz_term:proplist(), media_values()) -> atom().
action_lookup(_, [?MEDIA_VALUE(<<"application">>, <<"json">>, _, _, _)|_]) ->
    'read';
action_lookup(_, [?MEDIA_VALUE(<<"application">>, <<"x-json">>, _, _, _)|_]) ->
    'read';
action_lookup(_, [?MEDIA_VALUE(<<"*">>, <<"*">>, _, _, _)|_]) ->
    lager:debug("catch-all accept header, using json"),
    'read';
action_lookup(Acceptable, [{{Type, SubType, _}=ContentType, _, _}|Accepts]) ->
    case is_acceptable_accept(ContentType, Acceptable) of
        'false' ->
            lager:debug("unknown accept header: ~s/~s", [Type, SubType]),
            action_lookup(Acceptable, Accepts);
        'true' ->
            lager:debug("accept header: ~s/~s", [Type, SubType]),
            'download'
    end;
action_lookup(_, []) ->
    lager:debug("no accept headers, using json"),
    'read'.

-spec accept_values(cb_context:context()) -> media_values().
accept_values(Context) ->
    AcceptValue = cb_context:req_header(Context, <<"accept">>),
    Tunneled = cb_context:req_value(Context, <<"accept">>),
    media_values(AcceptValue, Tunneled).

-spec media_values(kz_term:api_binary(), kz_term:api_binary()) -> media_values().
media_values('undefined', 'undefined') ->
    lager:debug("no accept headers, assuming JSON"),
    [?MEDIA_VALUE(<<"application">>, <<"json">>)];
media_values(AcceptValue, 'undefined') ->
    case cb_modules_util:parse_media_type(AcceptValue) of
        {'error', 'badarg'} -> media_values('undefined', 'undefined');
        AcceptValues -> lists:reverse(lists:keysort(2, AcceptValues))
    end;
media_values(AcceptValue, Tunneled) ->
    case cb_modules_util:parse_media_type(Tunneled) of
        {'error', 'badarg'} -> media_values(AcceptValue, 'undefined');
        TunneledValues ->
            lager:debug("using tunneled accept value ~s", [Tunneled]),
            lists:reverse(lists:keysort(2, TunneledValues))
    end.

-spec acceptable_content_types(cb_context:context()) -> kz_term:proplist().
acceptable_content_types(Context) ->
    props:get_value('to_binary', cb_context:content_types_provided(Context), []).

-spec is_acceptable_accept(cowboy_content_type(), [cowboy_content_type()]) -> boolean().
is_acceptable_accept(ContentType, Acceptable) ->
    api_util:content_type_matches(ContentType, Acceptable).

%%------------------------------------------------------------------------------
%% @doc Strip the `"id"' property from the context's request data.
%% @end
%%------------------------------------------------------------------------------
-spec strip_id_from_req_data(cb_context:context()) -> cb_context:context().
strip_id_from_req_data(Context) ->
    ReqData = cb_context:req_data(Context),
    cb_context:set_req_data(Context, kz_doc:delete_id(ReqData)).

%%------------------------------------------------------------------------------
%% @doc Validate that only writable properties of the recording have been
%% included in the request. Errors are added if read-only properties have been
%% included.
%% @end
%%------------------------------------------------------------------------------
-spec validate_only_writable_props_included(cb_context:context()) -> cb_context:context().
validate_only_writable_props_included(Context) ->
    ReqData = cb_context:req_data(Context),
    Context1 = cb_context:store(Context, 'patch', ReqData),
    ReadOnlyData = kz_json:filter(fun is_read_only_prop/1, ReqData),
    kz_json:foldl(fun add_read_only_error/3, Context1, ReadOnlyData).

%%------------------------------------------------------------------------------
%% @doc Return `true' if the property is read-only.
%% @end
%%------------------------------------------------------------------------------
-spec is_read_only_prop({kz_json:key(), kz_json:json_term()}) -> boolean().
is_read_only_prop({K, _}) ->
    WritablePaths = [kzd_call_recordings:path_user_metadata()],
    not lists:member([K], WritablePaths).

%%------------------------------------------------------------------------------
%% @doc Add a read-only validation error for a property.
%% @end
%%------------------------------------------------------------------------------
-spec add_read_only_error(kz_json:key(), kz_json:json_term(), cb_context:context()) ->
          cb_context:context().
add_read_only_error(K, _, Context) ->
    Message = <<"Read-only property">>,
    cb_context:add_validation_error([K], <<"forbidden">>, Message, Context).

%%------------------------------------------------------------------------------
%% @doc Attempt to save user metadata. If there is an attachment handler
%% configured for call recordings in the account, the handler tries to update
%% metadata on the external service first. If this fails, the recording metadata
%% will not be saved.
%% @end
%%------------------------------------------------------------------------------
-spec save_user_metadata(cb_context:context(), kz_term:ne_binary(), kz_doc:doc()) ->
          cb_context:context().
save_user_metadata(Context, RecordingId, Doc) ->
    DbName = cb_context:db_name(Context),
    [AttachmentName] = kz_doc:attachment_names(Doc),

    case kz_datamgr:update_attachment_metadata(DbName, RecordingId, AttachmentName, Doc) of
        'ok' -> crossbar_doc:save(Context);
        {'error', E, _} -> cb_context:add_system_error(E, Context)
    end.

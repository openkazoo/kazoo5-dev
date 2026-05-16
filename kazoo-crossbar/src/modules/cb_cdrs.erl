%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc CDR
%%% Read only access to CDR docs
%%%
%%%
%%% @author Edouard Swiac
%%% @author James Aimonetti
%%% @author Karl Anderson
%%% @author Ben Wann
%%% @author Sponsored by GTNetwork LLC, Implemented by SIPLABS LLC
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_cdrs).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,content_types_provided/1, content_types_provided/2, content_types_provided/3
        ,validate/1, validate/2, validate/3
        ]).

-ifdef(TEST).
-export([handle_utc_time_offset/2]).
-endif.

-export([fix_qs_filter_keys/1
        ,normalize_cdr/3
        ]).

-include("crossbar.hrl").

-define(MOD_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".cdrs">>).
-define(MOD_MAX_RANGE, kapps_config:get_pos_integer(?MOD_CONFIG_CAT, <<"maximum_range">>, ?MAX_RANGE)).
-define(MAX_BULK, kapps_config:get_pos_integer(?MOD_CONFIG_CAT, <<"maximum_bulk">>, 50)).
-define(STALE_CDR, kapps_config:get_is_true(?MOD_CONFIG_CAT, <<"cdr_stale_view">>, 'false')).

-define(CB_LIST, <<"cdrs/crossbar_listing">>).
-define(CB_LIST_BY_USER, <<"cdrs/listing_by_owner">>).
-define(CB_INTERACTION_LIST, <<"interactions/interaction_listing">>).
-define(CB_INTERACTION_LIST_BY_USER, <<"interactions/interaction_listing_by_owner">>).
-define(CB_INTERACTION_LIST_BY_ID, <<"interactions/interaction_listing_by_id">>).
-define(CB_SUMMARY_VIEW, <<"cdrs/summarize_cdrs">>).
-define(CB_SUMMARY_LIST, <<"format_summary">>).

-define(PATH_INTERACTION, <<"interaction">>).
-define(PATH_LEGS, <<"legs">>).
-define(PATH_SUMMARY, <<"summary">>).

-define(KEY_UTC_OFFSET, <<"utc_offset">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.cdrs">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.cdrs">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.content_types_provided.cdrs">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.validate.cdrs">>, ?MODULE, 'validate'),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc This function determines the verbs that are appropriate for the
%% given Nouns.  IE: '/cdr/' can only accept GET
%%
%% Failure here returns `405 Method Not Allowed'.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?PATH_INTERACTION) ->
    [?HTTP_GET];
allowed_methods(?PATH_SUMMARY) ->
    [?HTTP_GET];
allowed_methods(_CDRId) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(?PATH_LEGS, _InteractionId) ->
    [?HTTP_GET].

%%------------------------------------------------------------------------------
%% @doc This function determines if the provided list of Nouns are valid.
%% Failure here returns `404 Not Found'.
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> boolean().
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> boolean().
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> boolean().
resource_exists(?PATH_LEGS, _) -> 'true';
resource_exists(_, _) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc Add content types accepted and provided by this module
%% @end
%%------------------------------------------------------------------------------
-spec content_types_provided(cb_context:context()) -> cb_context:context().
content_types_provided(Context) ->
    provided_types(Context).

-spec content_types_provided(cb_context:context(), path_token()) -> cb_context:context().
content_types_provided(Context, _) ->
    provided_types(Context).

-spec content_types_provided(cb_context:context(), path_token(), path_token()) -> cb_context:context().
content_types_provided(Context, _, _) ->
    provided_types(Context).

-spec provided_types(cb_context:context()) -> cb_context:context().
provided_types(Context) ->
    cb_context:add_content_types_provided(Context
                                         ,[{'to_json', ?JSON_CONTENT_TYPES}
                                          ,{'to_csv', ?CSV_CONTENT_TYPES}
                                          ]).

%%------------------------------------------------------------------------------
%% @doc This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400.
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_utc_offset(Context).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?PATH_INTERACTION) ->
    validate_chunk_view(Context);
validate(Context, ?PATH_SUMMARY) ->
    load_cdr_summary(Context);
validate(Context, CDRId) ->
    load_cdr(CDRId, Context).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?PATH_LEGS, InteractionId) ->
    load_legs(InteractionId, Context);
validate(Context, _, _) ->
    lager:debug("invalid URL chain for cdr request"),
    cb_context:add_system_error('faulty_request', Context).

-spec validate_utc_offset(cb_context:context()) -> cb_context:context().
validate_utc_offset(Context) ->
    UTCSecondsOffset = cb_context:req_value(Context, ?KEY_UTC_OFFSET),
    validate_utc_offset(Context, UTCSecondsOffset).

-spec validate_utc_offset(cb_context:context(), kz_time:gregorian_seconds()) -> cb_context:context().
validate_utc_offset(Context, 'undefined') ->
    validate_chunk_view(Context);
validate_utc_offset(Context, 'true') ->
    crossbar_util:response('error', <<"utc_offset must be a number">>, 404, Context);
validate_utc_offset(Context, UTCSecondsOffset) ->
    try kz_term:to_number(UTCSecondsOffset) of
        _ ->
            lager:debug("adjusting CDR datetime field with UTC Time Offset: ~p", [UTCSecondsOffset]),
            validate_chunk_view(Context)
    catch
        'error':'badarg' ->
            crossbar_util:response('error', <<"utc_offset must be a number">>, 404, Context)
    end.

-spec validate_chunk_view(cb_context:context()) -> cb_context:context().
validate_chunk_view(Context) ->
    case get_view_options(cb_context:req_nouns(Context)) of
        {'undefined', []} ->
            lager:debug("invalid URL chain for cdrs request"),
            cb_context:add_system_error('faulty_request', Context);
        {ViewName, Options} ->
            load_chunk_view(Context, ViewName, Options)
    end.

-spec load_chunk_view(cb_context:context(), kz_term:ne_binary(), kz_term:proplist()) -> cb_context:context().
load_chunk_view(Context, ViewName, Options0) ->
    AuthAccountId = cb_context:auth_account_id(Context),

    Setters = [{fun cb_context:store/3, 'is_reseller', kz_services_reseller:is_reseller(AuthAccountId)}
              ,{fun cb_context:store/3, 'accept_type', accept_type(Context)}
              ],
    Options = [{'is_chunked', 'true'}
              ,{'batch_size', ?MAX_BULK}
              ,{'max_range', ?MOD_MAX_RANGE}
              | Options0
              ],
    maybe_add_fields_fun(
      crossbar_view:load_modb(cb_context:setters(fix_qs_filter_keys(Context), Setters), ViewName, Options)
     ).

maybe_add_fields_fun(Context) ->
    case cb_context:fetch(Context, 'fields', []) of
        [] ->
            Context;
        Fields ->
            FieldsFun = kz_view:build_fields_fun(Fields, 'undefined'),
            cb_context:store(Context, 'fields_fun', FieldsFun)
    end.

-spec fix_qs_filter_keys(cb_context:context()) -> cb_context:context().
fix_qs_filter_keys(Context) ->
    NewQs = kz_json:map(fun(K, V) -> fix_filter_key(kz_binary:reverse(K), V) end
                       ,cb_context:query_string(Context)
                       ),
    cb_context:set_query_string(Context, NewQs).

-spec fix_filter_key(kz_term:ne_binary(), any()) -> {kz_term:ne_binary(), any()}.
fix_filter_key(<<"di_llac", _/binary>> = Key, Val) ->
    {kz_binary:reverse(Key), fix_filter_call_id(Val)};
fix_filter_key(Key, Val) ->
    {kz_binary:reverse(Key), Val}.

fix_filter_call_id(?MATCH_MODB_PREFIX(_Year, _Month, CallId)) ->
    CallId;
fix_filter_call_id(CallId) ->
    CallId.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Attempt to CDRs summary.
%% @end
%%------------------------------------------------------------------------------
-spec load_cdr_summary(cb_context:context()) -> cb_context:context().
load_cdr_summary(Context) ->
    lager:debug("loading cdr summary for account ~s", [cb_context:account_id(Context)]),
    Options = [{'mapper', fun normalize_summary_results/2}
              ,{'range_start_keymap', []}
              ,{'range_end_keymap', crossbar_view:suffix_key_fun([kz_json:new()])}
              ,{'list', ?CB_SUMMARY_LIST}
              ,{'max_range', ?MOD_MAX_RANGE}
              ,{'no_fields', 'true'}
              ],
    C1 = crossbar_view:load_modb(Context, ?CB_SUMMARY_VIEW, Options),
    case cb_context:resp_status(C1) of
        'success' ->
            JObjs = cb_context:resp_data(C1),
            cb_context:set_resp_data(C1, merge_cdr_summaries(JObjs));
        _ -> C1
    end.

merge_cdr_summaries(JObjs) ->
    lists:foldl(fun merge_cdr_summary/2, kz_json:new(), JObjs).

-spec merge_cdr_summary(kz_json:object(), kz_json:objects()) -> kz_json:object().
merge_cdr_summary(JObj1, JObj2) ->
    kz_json:foldl(fun(Key1, Value1, JObj) ->
                          case kz_json:get_value(Key1, JObj1) of
                              'undefined' -> kz_json:set_value(Key1, Value1, JObj);
                              Value1 when is_integer(Value1) ->
                                  kz_json:set_value(Key1, Value1 + Value1, JObj);
                              Value1 ->
                                  NewValue = merge_cdr_summary(Value1, Value1),
                                  kz_json:set_value(Key1, NewValue, JObj)
                          end
                  end
                 ,JObj2
                 ,JObj1
                 ).

-spec normalize_summary_results(kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_summary_results(JObj, Acc) -> [JObj|Acc].

%%------------------------------------------------------------------------------
%% @doc Generate specific view options for the path.
%% @end
%%------------------------------------------------------------------------------
-spec get_view_options(req_nouns()) -> {kz_term:api_ne_binary(), crossbar_view:options()}.
get_view_options([{<<"cdrs">>, []}, {?KZ_ACCOUNTS_DB, _}|_]) ->
    {?CB_LIST
    ,[{'mapper', fun cdrs_listing_mapper/3}
     ,{'range_start_keymap', []}
     ,{'range_end_keymap', crossbar_view:suffix_key_fun([kz_json:new()])}
     ,'include_docs'
     ]
    };
get_view_options([{<<"cdrs">>, []}, {<<"users">>, [OwnerId]}|_]) ->
    {?CB_LIST_BY_USER
    ,[{'range_start_keymap', [OwnerId]}
     ,{'range_end_keymap', fun(Ts) -> [OwnerId, Ts, kz_json:new()] end}
     ,{'mapper', fun cdrs_listing_mapper/3}
     ,'include_docs'
     ]
    };
get_view_options([{<<"cdrs">>, [?PATH_INTERACTION]}, {?KZ_ACCOUNTS_DB, _}|_]) ->
    {?CB_INTERACTION_LIST
    ,props:filter_undefined(
       [{'range_start_keymap', []}
       ,{'range_end_keymap', crossbar_view:suffix_key_fun([kz_json:new()])}
       ,{'key_min_length', 3}
       ,{'group', 'true'}
       ,{'group_level', 2}
       ,{'reduce', 'true'}
       ,{'no_filter', 'true'}
       ,{'no_fields', 'true'}
       ,{'mapper', {'context', fun load_chunked_cdrs/2}}
       | maybe_add_stale_to_options(?STALE_CDR)
       ])
    };
get_view_options([{<<"cdrs">>, [?PATH_INTERACTION]}, {<<"users">>, [OwnerId]}|_]) ->
    {?CB_INTERACTION_LIST_BY_USER
    ,props:filter_undefined(
       [{'range_start_keymap', [OwnerId]}
       ,{'range_end_keymap', [OwnerId]}
       ,{'key_min_length', 4}
       ,{'group', 'true'}
       ,{'group_level', 3}
       ,{'reduce', 'true'}
       ,{'no_filter', 'true'}
       ,{'no_fields', 'true'}
       ,{'mapper', {'context', fun load_chunked_cdrs/2}}
       | maybe_add_stale_to_options(?STALE_CDR)
       ])
    };
get_view_options(_) ->
    {'undefined', []}.

-spec maybe_add_stale_to_options(boolean()) -> [{'stale', 'ok'}] | [].
maybe_add_stale_to_options('true') -> [{'stale', 'ok'}];
maybe_add_stale_to_options('false') ->[].

-spec cdrs_listing_mapper(cb_context:context(), kz_json:object(), kz_json:objects()) -> kz_json:objects().
cdrs_listing_mapper(Context, JObj, Acc) ->
    [normalize_cdr(Context, <<"json">>, JObj) | Acc].

%%------------------------------------------------------------------------------
%% @doc Loads CDR docs from database and normalized the them.
%% @end
%%------------------------------------------------------------------------------
-spec load_chunked_cdrs(cb_context:context(), kz_json:objects()) ->
          kz_json:objects() |
          {'error', cb_context:context()}.
load_chunked_cdrs(Context0, JObjs) ->
    RespType = cb_context:fetch(Context0, 'accept_type'),
    QS = cb_context:query_string(Context0),
    %% range keys are using interaction_time, crossbar_filter for create_* is using pvt_created
    %% and interaction_time could be before pvt_created
    Context = cb_context:set_query_string(Context0, kz_json:delete_keys([<<"created_from">>, <<"created_to">>], QS)),

    SplitIds = split_to_modbs(cb_context:account_id(Context), JObjs, #{}),

    ContextSetter = [{fun cb_context:set_resp_data/2, []}
                    ,{fun cb_context:set_resp_status/2, 'success'}
                    ],
    C1 = cb_context:setters(Context, ContextSetter),
    try load_chunked_cdr_ids(C1, RespType, SplitIds) of
        FetchedContext ->
            case cb_context:resp_status(FetchedContext) of
                'success' ->
                    cb_context:resp_data(FetchedContext);
                _ ->
                    {'error', FetchedContext}
            end
    catch
        _T:_E:ST ->
            lager:debug("exception when loading cdr chunks. {~p, ~p}", [_T, _E]),
            kz_log:log_stacktrace(ST, "exception when loading cdr chunks. {~p, ~p}", [_T, _E]),
            {'error', cb_context:add_system_error('datastore_fault', Context)}
    end.

load_chunked_cdr_ids(Context, RespType, SplitIds) ->
    lists:foldl(fun({Db, Ids}, Ctx) -> load_chunked_cdr_ids(Ctx, RespType, Db, Ids) end
               ,Context
               ,SplitIds
               ).

-spec split_to_modbs(kz_term:ne_binary(), kz_json:objects(), map()) -> kz_term:proplist().
split_to_modbs(_, [], Map) ->
    %% resp_data is already sorted so Ids are already sorted,
    %% but since items sort in map can be unspecefied we're doing
    %% a sort here to sort first level of proplist which is dbs
    lists:reverse(lists:sort(maps:to_list(Map)));
split_to_modbs(AccountId, [JObj|JObjs], Map) ->
    ?MATCH_MODB_PREFIX(Year, Month, _) = Id = kz_doc:id(JObj),
    Db = kazoo_modb:get_modb(AccountId, Year, Month),
    split_to_modbs(AccountId
                  ,JObjs
                  ,maps:update_with(Db, fun(List) -> List ++ [Id] end, [Id], Map)
                  ).

-spec load_chunked_cdr_ids(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binaries()) -> cb_context:context().
load_chunked_cdr_ids(Context, RespType, Db, Ids) ->
    load_chunked_cdr_ids(Context, RespType, Db, Ids, cb_context:resp_status(Context)).

load_chunked_cdr_ids(Context, RespType, Db, Ids, 'success') ->
    case kz_datamgr:open_docs(Db, Ids, [{'doc_type', kzd_cdrs:type()}]) of
        {'ok', Results} ->
            Resp0 = [normalize_cdr(Context, RespType, Result)
                     || Result <- Results,
                        %% Filter those docs which have accidentally put into this db.
                        %% See {@link cdr_channel_destroy} comment for function `prepare_and_save/3`
                        %% when it uses interaction_timestamp to generates modb_id like ID.
                        kz_json:get_value(<<"error">>, Result) =:= 'undefined',

                        %% if there are no filters, include doc
                        %% otherwise run filters against doc for inclusion
                        crossbar_filter:by_doc(kz_json:get_json_value(<<"doc">>, Result), Context)
                    ],
            cb_context:set_resp_data(Context, cb_context:resp_data(Context) ++ Resp0);
        {'error', Reason} ->
            lager:debug("failed to load cdrs doc from ~s: ~p", [Db, Reason]),
            crossbar_doc:handle_datamgr_errors(Reason, <<"load_cdrs">>, Context)
    end;
load_chunked_cdr_ids(Context, _RespType, _Db, _Ids, _Status) ->
    Context.

-spec normalize_cdr(cb_context:context(), kz_term:ne_binary(), kz_json:object()) -> kz_json:object() | kz_term:ne_binary().
normalize_cdr(Context, ContentType, Result) ->
    JObj = kz_json:get_json_value(<<"doc">>, Result),
    MappedRows = map_rows(Context, ContentType, JObj),
    case cb_context:fetch(Context, 'fields_fun') of
        'undefined' ->
            case kz_term:is_true(cb_context:fetch(Context, 'has_full_docs')) of
                'true' when ContentType =:= <<"json">> ->
                    kz_doc:public_fields(JObj);
                _ ->
                    do_normalize_cdr(ContentType, kz_json:from_list(MappedRows))
            end;
        FieldsFun ->
            NewDoc = kz_doc:public_fields(FieldsFun(kz_json:set_values(MappedRows, JObj))),
            do_normalize_cdr(ContentType, NewDoc)
    end.

-spec do_normalize_cdr(kz_term:ne_binary(), kz_json:object()) -> kz_json:object() | kz_term:ne_binary().
do_normalize_cdr(<<"json">>, JObj) ->
    JObj;
do_normalize_cdr(<<"csv">>, JObj) ->
    Result = [kz_term:safe_cast(V, <<>>, fun kz_term:to_binary/1)
              || {_, V} <- kz_json:to_proplist(kz_json:flatten(JObj))
             ],
    <<(kz_binary:join(Result, <<",">>))/binary, "\r\n">>.

-spec map_rows(cb_context:context(), kz_term:ne_binary(), kz_json:object()) -> kz_json:json_proplist().
map_rows(Context, ContentType, JObj) ->
    Timestamp = kzd_cdrs:created_timestamp(JObj),

    MappedRows = [{K, apply_row_mapper(K, F, JObj, Timestamp, Context)} || {K, F} <- csv_rows(Context)],
    case ContentType of
        <<"json">> ->
            ShouldFilterEmpty = kapps_config:is_true(?MOD_CONFIG_CAT, <<"should_filter_empty_strings">>, 'false'),
            maybe_filter_empties(MappedRows, ShouldFilterEmpty);
        _ ->
            MappedRows
    end.

-spec apply_row_mapper(kz_term:ne_binary(), fun(), kz_json:object(), kz_time:gregorian_seconds(), cb_context:context()) -> binary().
apply_row_mapper(<<"datetime">>, _F, _JObj, Timestamp, Context) ->
    tz_pretty_print(Timestamp, Context);
apply_row_mapper(_, F, JObj, Timestamp, _Context) ->
    F(JObj, Timestamp, 'undefined').

-spec tz_pretty_print(kz_time:gregorian_seconds(), cb_context:context()) -> kz_term:ne_binary().
tz_pretty_print(Timestamp, Context) ->
    UTCSecondsOffset = cb_context:req_value(Context, ?KEY_UTC_OFFSET),
    %% maintain compatibility with old format.
    %% NOTE: kzd_cdrs:col_pretty_print/3 is using the new format kz_time:pretty_print_datetime/2 with underscore
    %% as a separator and timezone at the end.
    kz_time:pretty_print_datetime_legacy(handle_utc_time_offset(Timestamp, UTCSecondsOffset)).

-spec maybe_filter_empties(kz_json:json_proplist(), boolean()) -> kz_json:json_proplist().
maybe_filter_empties(Rows, 'true') ->
    props:filter_empty_strings(Rows);
maybe_filter_empties(Rows, 'false') ->
    Rows.

csv_rows(Context) ->
    kzd_cdrs:csv_headers(cb_context:fetch(Context, 'is_reseller', 'false')).

-spec handle_utc_time_offset(kz_time:gregorian_seconds(), kz_term:api_integer()) -> kz_time:gregorian_seconds().
handle_utc_time_offset(Timestamp, 'undefined') -> Timestamp;
handle_utc_time_offset(Timestamp, UTCSecondsOffset) ->
    Timestamp + kz_term:to_number(UTCSecondsOffset).

%%------------------------------------------------------------------------------
%% @doc Load a CDR document from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_cdr(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_cdr(?MATCH_MODB_PREFIX(Year, Month, _Day) = CDRId, Context) ->
    AccountId = cb_context:account_id(Context),
    AccountDb = kazoo_modb:get_modb(AccountId, kz_term:to_integer(Year), kz_term:to_integer(Month)),
    Context1 = cb_context:set_db_name(Context, AccountDb),
    Context2 = crossbar_doc:load({kzd_cdrs:type(), CDRId}, Context1, ?TYPE_CHECK_OPTION(kzd_cdrs:type())),
    filter_pvt_fields(Context2);
load_cdr(CDRId, Context) ->
    lager:debug("error loading cdr by id ~p", [CDRId]),
    crossbar_util:response('error', <<"could not find cdr with supplied id">>, 404, Context).

%%------------------------------------------------------------------------------
%% @doc Load Legs for a cdr interaction from the database
%% @end
%%------------------------------------------------------------------------------
-spec load_legs(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_legs(<<Year:4/binary, Month:2/binary, "-", _/binary>> = DocId, Context) ->
    AccountId = cb_context:account_id(Context),
    MODB = kazoo_modb:get_modb(AccountId, kz_term:to_integer(Year), kz_term:to_integer(Month)),
    case kz_datamgr:open_cache_doc(MODB, {kzd_cdrs:type(), DocId}) of
        {'ok', JObj} ->
            lager:debug("finding interaction id in ~s / ~s", [MODB, DocId]),
            load_legs(kzd_cdrs:interaction_id(JObj), Context);
        {'error', _} ->
            lager:debug("error loading legs for cdr id ~p", [DocId]),
            crossbar_util:response('error', <<"could not find legs for supplied id">>, 404, Context)
    end;
load_legs(<<BinTimestamp:11/binary, "-", _Key/binary>>=InteractionId, Context) ->
    MODB = kazoo_modb:get_modb(cb_context:account_id(Context), kz_term:to_integer(BinTimestamp)),

    lager:debug("finding legs for ~s / ~s", [MODB, InteractionId]),

    Options = [{'mapper', fun normalize_leg_view_results/2}
              ,{'range_start_keymap',  fun(_) -> [InteractionId] end}
              ,{'range_end_keymap', fun(_) -> [InteractionId, kz_json:new()] end}
              ,{'databases', [MODB]}
              ,{'max_range', ?MOD_MAX_RANGE}
              ,'include_docs'
              ],
    crossbar_view:load_modb(Context, ?CB_INTERACTION_LIST_BY_ID, Options);
load_legs(Id, Context) ->
    crossbar_util:response_bad_identifier(Id, Context).

-spec normalize_leg_view_results(kz_json:object(), kz_json:objects()) ->
          kz_json:objects().
normalize_leg_view_results(JObj, Acc) ->
    Acc ++ [remove_pvt_ccvs(kz_json:get_json_value(<<"doc">>, JObj))].

-spec accept_type(cb_context:context()) -> kz_term:api_ne_binary().
accept_type(Context) ->
    accept_type(cb_context:req_header(Context, <<"accept">>)
               ,cb_context:req_value(Context, <<"accept">>)
               ).

-spec accept_type(kz_term:api_ne_binary(), kz_term:api_ne_binary()) -> kz_term:ne_binary().
accept_type('undefined', 'undefined') -> <<"json">>;
accept_type(Header, 'undefined') -> normalize_accept_type(cb_modules_util:parse_media_type(Header));
accept_type(_Header, <<"csv">>) -> <<"text/csv">>;
accept_type(_Header, Tunneled) -> normalize_accept_type(cb_modules_util:parse_media_type(Tunneled)).

-spec normalize_accept_type({'error', 'badarg'} | media_values()) ->
          kz_term:ne_binary().
normalize_accept_type({'error', 'badarg'}) ->
    lager:info("failed to parse the accept header, assuming json"),
    <<"json">>;
normalize_accept_type([?MEDIA_VALUE(<<"application">>, <<"json">>, _, _, _)|_]) ->
    <<"json">>;
normalize_accept_type([?MEDIA_VALUE(<<"application">>, <<"x-json">>, _, _, _)|_]) ->
    <<"json">>;
normalize_accept_type([?MEDIA_VALUE(<<"*">>, <<"*">>, _, _, _)|_]) ->
    <<"json">>;
normalize_accept_type([?MEDIA_VALUE(<<"text">>, <<"csv">>, _, _, _)|_]) ->
    <<"csv">>;
normalize_accept_type([?MEDIA_VALUE(<<"text">>, <<"comma-separated-values">>, _, _, _)|_]) ->
    <<"csv">>;
normalize_accept_type([?MEDIA_VALUE(<<"application">>, <<"octet-stream">>, _, _, _)|_]) ->
    <<"csv">>;
normalize_accept_type([_Accept|Accepts]) ->
    lager:debug("failed to handle accept value ~p, assuming json", [_Accept]),
    normalize_accept_type(Accepts);
normalize_accept_type([]) ->
    lager:info("failed to find valid accept value, assuming json"),
    <<"json">>.

-spec filter_pvt_fields(cb_context:context()) -> cb_context:context().
filter_pvt_fields(Context) ->
    case cb_context:resp_status(Context) of
        'success' ->
            JObj = cb_context:resp_data(Context),
            cb_context:set_resp_data(Context, remove_pvt_ccvs(JObj));
        _ -> Context
    end.

-spec remove_pvt_ccvs(kz_json:object()) -> kz_json:object().
remove_pvt_ccvs(JObj) ->
    CCVs = kz_json:get_json_value(<<"custom_channel_vars">>, JObj, kz_json:new()),
    kz_json:set_value(<<"custom_channel_vars">>, kz_doc:public_fields(CCVs), JObj).

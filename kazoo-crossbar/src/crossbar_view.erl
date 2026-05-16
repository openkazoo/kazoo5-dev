%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author Roman Galeev
%%% @author Hesaam Farhang
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_view).

-export([load/2, load/3
        ,load_time_range/2, load_time_range/3
        ,load_modb/2, load_modb/3
        ,load_yodb/2, load_yodb/3

        ,prepare_docs/1, prepare_docs/2

        ,direction/1, direction/2

        ,get_page_size/2

        ,suffix_key_fun/1

        ,get_doc_fun/0
        ,get_value_fun/0
        ,get_key_fun/0
        ,get_id_fun/0
        ]).

-export([next_batch/2]).

-export([find/4]).

-ifdef(TEST).
-export([has_valid_dbs/1
        ]).
-endif.

-include("crossbar.hrl").

%% too many types {{{
-define(USER_PARAMS_ONLY,
        ['ascending', 'databases', 'no_filter', 'no_fields', 'run_mapper'

         %% non-range query
        ,'end_keymap', 'keymap', 'start_keymap'

         %% chunked query
        ,'chunk_size', 'is_chunked', 'unchunkable'

         %% ranged query
        ,'created_to', 'created_from', 'max_range'
        ,'range_end_keymap', 'time_filter_key', 'range_keymap', 'range_start_keymap'
        ,'should_paginate', 'is_time_query'

         %% start/end key length fixer
        ,'key_min_length'
        ]).
-define(CB_SPECIFIC_VIEW_OPTIONS,
        ['mapper'
        | ?USER_PARAMS_ONLY
        ]).

-type time_range() :: {kz_time:gregorian_seconds(), kz_time:gregorian_seconds()}.
%% `{StartTimestamp, EndTimestamp}'.
-type api_range_key() :: 'undefined' | ['undefined'] | kazoo_data:key_range().
-type range_keys() :: {api_range_key(), api_range_key()}.
%% `{Startkey, EndKey}'.
-type keymap_fun() :: fun((cb_context:context()) -> api_range_key()) |
                      fun((cb_context:context(), kazoo_data:view_options()) -> api_range_key()).
%% Function of arity 1 or 2 to create customize start/end key.
-type keymap() :: api_range_key() | keymap_fun().
%% A literal CouchDB `startkey' or `endkey', or a {@link keymap_fun()} for non-range requests.
%% See also {@link build_start_end/3}.

-type range_keymap_fun() :: fun((kz_time:gregorian_seconds()) -> api_range_key()).
%% A function of arity 1. The timestamp from `created_from' or `created_to' will pass to this function
%% to construct the start or end key.
-type range_keymap() :: 'nil' | api_range_key() | range_keymap_fun().
%% Creates a start/end key for ranged queries. A binary or integer or a list of binary or integer
%% to create start/end key. The timestamp will added to end of it.
%% If `undefined' only the timestamp will be used as the key. If timestamp in the view key is at start of the key,
%% use {@link suffix_key_fun}. If the view doesn't need any start/end key you can set this `nil' to bypass setting
%% timestamp as key.

-type mapper_error() :: cb_context:context().
-type user_mapper_fun() :: 'undefined' |
                           fun((kz_json:objects()) -> kz_json:objects() | {'error', mapper_error()}) |
                           fun((kz_json:object(), kz_json:objects()) -> kz_json:objects() | {'error', mapper_error()}) |
                           fun((cb_context:context(), kz_json:object(), kz_json:objects()) -> kz_json:objects() | {'error', mapper_error()}) |
                           {'context', fun(({cb_context:context(), kz_json:objects()}) -> kz_json:objects() | {'error', mapper_error()})}.
%% A function to filter/map view result. For use in Crossbar modules to call {@link crossbar_view} functions.
-type mapper_fun() :: 'undefined' |
                      fun((kz_json:objects()) -> kz_json:objects() | {'error', mapper_error()}) |
                      fun((kz_json:object(), kz_json:objects()) -> kz_json:objects() | {'error', mapper_error()}).
%% A function to filter/map view result. Internal to {@link crossbar_view}.

-type options() :: kz_view:options() |
                   [{'mapper', user_mapper_fun()} |
                    {'max_range', pos_integer()} |
                    {'no_filter', boolean()} |
                    {'no_fields', boolean()} |
                    {'unchunkable', boolean()} |
                    {'run_mapper', boolean()} |

                    %% for non-ranged query
                    {'end_keymap', keymap()} |
                    {'keymap', keymap()} |
                    {'start_keymap', keymap()} |

                    %% for chunked query
                    {'chunk_size', pos_integer()} |
                    {'is_chunked', boolean()} |

                    %% for ranged/modb query
                    {'created_from', pos_integer()} |
                    {'created_to', pos_integer()} |
                    {'range_end_keymap', range_keymap()} |
                    {'range_keymap', range_keymap()} |
                    {'time_filter_key', kz_term:ne_binary()} |
                    {'range_start_keymap', range_keymap()} |
                    {'should_paginate', boolean()} |
                    {'is_time_query', boolean()} |

                    %% start/end key length fixer
                    {'key_min_length', pos_integer()}
                   ].


-type context_options() :: {cb_context:context(), kz_view:options()}.
-type maybe_load_params() :: kz_either:either(cb_context:context(), context_options()).

-export_type([range_keys/0, time_range/0
             ,options/0
             ,mapper_fun/0 ,user_mapper_fun/0
             ,keymap/0, keymap_fun/0
             ,range_keymap/0, range_keymap_fun/0
             ]
            ).
%% }}}

%% @equiv load(Context, View, [])
-spec load(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load(Context, View) ->
    load(Context, View, []).

%%------------------------------------------------------------------------------
%% @doc This function attempts to load the context with the results of a view
%% run against the database.
%% @end
%%------------------------------------------------------------------------------
-spec load(cb_context:context(), kz_term:ne_binary(), options()) -> cb_context:context().
load(Context, View, Options) ->
    Build = build_cursor_options(Context, Options, 'true', 'false'),
    load_view(View, [], build_range_keys(Build)).

%% @equiv load_time_range(Context, View, [])
-spec load_time_range(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_time_range(Context, View) ->
    load_time_range(Context, View, []).

%%------------------------------------------------------------------------------
%% @doc This function attempts to load the context with the timestampe
%% results of a view run against the database.
%% @end
%%------------------------------------------------------------------------------
-spec load_time_range(cb_context:context(), kz_term:ne_binary(), options()) -> cb_context:context().
load_time_range(Context, View, Options) ->
    Build = build_cursor_options(Context, Options, 'true', 'true'),
    load_view(View, [], build_time_range_keys(Build)).


%% @equiv load_modb(Context, View, [])
-spec load_modb(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_modb(Context, View) ->
    load_modb(Context, View, []).

%%------------------------------------------------------------------------------
%% @doc This function attempts to load the context with the results of a view
%% run against the account's MODBs.
%% @end
%%------------------------------------------------------------------------------

-spec load_modb(cb_context:context(), kz_term:ne_binary(), options()) -> cb_context:context().
load_modb(Context, View, Options) ->
    Build = build_cursor_options(Context, Options, 'true', 'true'),
    load_view(View, [], build_modb_options(Build)).


%% @equiv load_yodb(Context, View, [])
-spec load_yodb(cb_context:context(), kz_term:ne_binary()) -> cb_context:context().
load_yodb(Context, View) ->
    load_yodb(Context, View, []).

%%------------------------------------------------------------------------------
%% @doc This function attempts to load the context with the results of a view
%% run against the account's YODBs.
%% @end
%%------------------------------------------------------------------------------
-spec load_yodb(cb_context:context(), kz_term:ne_binary(), options()) -> cb_context:context().
load_yodb(Context, View, Options) ->
    Build = build_cursor_options(Context, Options, 'true', 'true'),
    load_view(View, [], build_yodb_options(Build)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find(cb_context:context(), kz_term:ne_binary(), kz_view:selector(), options()) -> cb_context:context().
find(Context, View, Selector, Options) ->
    Build = build_cursor_options(Context, Options, 'false', 'false'),
    load_view(View, Selector, build_range_keys(Build)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec prepare_docs(cb_context:context()) -> cb_context:context().
prepare_docs(Context) ->
    prepare_docs(Context, []).

-spec prepare_docs(cb_context:context(), options()) -> cb_context:context().
prepare_docs(Context, Options) ->
    %% TODO: how to honoring page size? start/end/bookmark keys? chunking?
    try
        {'ok', {NewContext, CursorOptions}} = build_prepare_docs_options(Context, Options),
        do_prepare_docs(NewContext, CursorOptions, cb_context:doc(Context))
    catch
        'throw':{'error', ErrorMsg} ->
            cb_context:add_system_error(404, 'faulty_request', ErrorMsg, Context);
        _E:_T:ST ->
            kz_log:log_stacktrace(ST, "crashed when running prepare_docs: ~p:~p", [_E, _T]),
            cb_context:add_system_error('unspecified_fault', Context)
    end.

do_prepare_docs(Context, CursorOptions, JObjs) ->
    ShouldFields = props:is_true(['user_params', 'should_fields'], CursorOptions, 'false'),
    FilterMap = props:get_value('filtermap', CursorOptions, fun kz_term:identity/1),
    case kz_view:apply_filtermap(FilterMap, JObjs) of
        {'error', Error} ->
            case cb_context:is_context(Error) of
                'true' -> Error;
                'false' ->
                    crossbar_doc:handle_datamgr_errors(Error, 'undefined', Context)
            end;
        FilteredJObjs ->
            maybe_apply_fields(Context, CursorOptions, FilteredJObjs, ShouldFields)
    end.

maybe_apply_fields(Context, CursorOptions, JObjs, 'true') ->
    Fields = props:get_value('fields', CursorOptions),
    FieldKey = props:get_value('field_key', CursorOptions),

    case kz_view:build_fields_fun(Fields, FieldKey) of
        'undefined' ->
            crossbar_doc:handle_datamgr_success(JObjs, Context);
        FieldsFun ->
            FieldsJObjs = kz_view:apply_fields_fun(FieldsFun, JObjs),
            crossbar_doc:handle_datamgr_success(FieldsJObjs, Context)
    end;
maybe_apply_fields(Context, _, JObjs, 'false') ->
    crossbar_doc:handle_datamgr_success(JObjs, Context).


%% build options funs {{{
%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec build_range_keys(maybe_load_params()) -> maybe_load_params().
build_range_keys({'ok', {Context, CursorOptions}}) ->
    Bookmark = props:get_value('bookmark', CursorOptions, []),
    case props:is_true('no_design_module', CursorOptions, 'true') of
        'false' ->
            {'ok', {Context, CursorOptions}};
        'true' ->
            {StartKey, EndKey} = build_start_end_keys(Context, CursorOptions, props:get_value('direction', CursorOptions)),
            Prop = props:filter_undefined(
                     [{'startkey', StartKey}
                     ,{'endkey', EndKey}
                     ,{'startkey_docid', props:get_value('next_startkey_docid', Bookmark)}
                     ]),
            {'ok', {Context, props:set_values(Prop, props:delete('bookmark', CursorOptions))}}
    end;
build_range_keys({'error', _}=Error) ->
    Error.

-spec build_time_range_keys(maybe_load_params()) -> maybe_load_params().
build_time_range_keys({'ok', {Context, CursorOptions}}) ->
    Bookmark = props:get_value('bookmark', CursorOptions, []),
    case props:is_true('no_design_module', CursorOptions, 'true') of
        'false' ->
            {'ok', {Context, CursorOptions}};
        'true' ->
            {StartKey, EndKey} = build_time_start_end_keys(CursorOptions),
            Prop = props:filter_undefined(
                     [{'startkey', StartKey}
                     ,{'endkey', EndKey}
                     ,{'startkey_docid', props:get_value('next_startkey_docid', Bookmark)}
                     ]),
            {'ok', {Context, props:set_values(Prop, props:delete('bookmark', CursorOptions))}}
    end;
build_time_range_keys({'error', _}=Error) ->
    Error.

-spec build_modb_options(maybe_load_params()) -> maybe_load_params().
build_modb_options(Thing) ->
    case build_time_range_keys(Thing) of
        {'ok', {Context, CursorOptions}} ->
            check_range_ne_db(Context, CursorOptions, 'modb', get_range_modbs(Context, CursorOptions));
        {'error', _}=Error -> Error
    end.

-spec build_yodb_options(maybe_load_params()) -> maybe_load_params().
build_yodb_options(Thing) ->
    case build_time_range_keys(Thing) of
        {'ok', {Context, CursorOptions}} ->
            check_range_ne_db(Context, CursorOptions, 'yodb', get_range_yodbs(Context, CursorOptions));
        {'error', _}=Error -> Error
    end.

-spec check_range_ne_db(cb_context:context(), kz_view:options(), 'modb' | 'yodb', kz_term:ne_binaries()) ->
          maybe_load_params().
check_range_ne_db(Context, CursorOptions, _DbType, []) ->
    lager:debug("no ~s database found for the requested range, falling back to databases from options if any", [_DbType]),
    {'ok', {cb_context:store(Context, 'no_db_in_range', 'true'), CursorOptions}};
check_range_ne_db(Context, CursorOptions, _, DbNames) ->
    {'ok', {Context, props:set_value('databases', DbNames, CursorOptions)}}.
%% }}}

%% get_*_funs {{{
%%------------------------------------------------------------------------------
%% @doc Returns a function to get `doc' object from each view result.
%% @end
%%------------------------------------------------------------------------------
-spec get_doc_fun() -> mapper_fun().
get_doc_fun() -> fun(JObj, Acc) -> [kz_json:get_json_value(<<"doc">>, JObj)|Acc] end.

%%------------------------------------------------------------------------------
%% @doc Returns a function to get `value' object from each view result.
%% @end
%%------------------------------------------------------------------------------
-spec get_value_fun() -> mapper_fun().
get_value_fun() -> fun(JObj, Acc) -> [kz_json:get_value(<<"value">>, JObj)|Acc] end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec get_key_fun() -> mapper_fun().
get_key_fun() -> fun(JObj, Acc) -> [kz_json:get_value(<<"key">>, JObj)|Acc] end.

%%------------------------------------------------------------------------------
%% @doc Returns a function to get `value' object from each view result.
%% @end
%%------------------------------------------------------------------------------
-spec get_id_fun() -> mapper_fun().
get_id_fun() -> fun(JObj, Acc) -> [kz_doc:id(JObj)|Acc] end.
%% }}}

%% build kz_view:options {{{
%%%=============================================================================
%%% Build load view parameters internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec build_cursor_options(cb_context:context(), options(), boolean(), boolean()) -> maybe_load_params().
build_cursor_options(Context, Options, NoDesignModule, IsTimeQuery) ->
    NewOptions = props:set_value('is_time_query', IsTimeQuery, Options),
    try
        Bookmark = cb_context:req_value(Context, <<"bookmark">>, 'undefined'),
        CursorOptions = props:filter_undefined(
                          [{'batch_size', get_batch_size(Context, Options)}
                          ,{'bookmark', Bookmark}
                           %% Please don't change the next line again next time.
                           %% we can't use default empty list for databases here, we need it to be undefined
                           %% so modb and yodb functions will build db ranges.
                          ,{'databases', props:get_value('databases', Options)}
                          ,{'direction', direction(Context, Options)}
                          ,{'key_min_length', props:get_value('key_min_length', Options)}
                          ,{'lager_prefix', "(crossbar)"}
                          ,{'memory_limit', kapps_config:get_integer(?CONFIG_CAT, <<"request_memory_limit">>)}
                          ,{'no_batch', kz_term:is_true(props:get_first_defined(['no_batch', 'unchunkable'], Options, 'false'))}
                          ,{'no_design_module', props:is_true('no_design_module', Options, NoDesignModule)}
                          ,{'page_size', get_page_size(Context, Options)}
                          ,{'verbose_log', 'true'}
                          ]),
        add_user_params(Context, CursorOptions, NewOptions)
    catch
        'throw':{'error', ErrorMsg} ->
            {'error', cb_context:add_system_error(404, 'faulty_request', ErrorMsg, Context)};
        _E:_T:ST ->
            kz_log:log_stacktrace(ST, "crashed when building crusor options: ~p:~p", [_E, _T]),
            {'error', cb_context:add_system_error('unspecified_fault', Context)}
    end.


-spec add_user_params(cb_context:context(), kz_view:options(), options()) -> maybe_load_params().
add_user_params(Context, CursorOptions0, Options) ->
    {'ok', {NewContext, CursorOptions1}} = build_prepare_docs_options(Context, Options),

    UserParams = [{'is_chunked', is_chunked(Context, Options)}
                 ,{'should_paginate', cb_context:should_paginate(Context)}
                 | [{K, V}
                    || {K, V} <- Options,
                       lists:member(K, ?USER_PARAMS_ONLY)
                   ] ++ props:get_value('user_params', CursorOptions1, [])
                 ],
    CursorProp =
        props:set_values([{'user_params',  UserParams}
                         ]
                        ,CursorOptions1
                        ),
    merge_options(NewContext, props:set_values(CursorProp, CursorOptions0), Options).

-spec build_prepare_docs_options(cb_context:context(), options()) -> maybe_load_params().
build_prepare_docs_options(Context, Options) ->
    IsTimeQuery = props:is_true('is_time_query', Options, 'false'),
    HasQSFilter = has_qs_filter(Context, Options),
    TimeFilterKey = props:get_ne_binary_value('time_filter_key', Options, <<"created">>),
    ShouldFilter = (HasQSFilter
                    andalso not props:is_true('no_filter', Options, 'false')
                   )
        orelse props:is_true('run_mapper', Options, 'false'),

    Fields = get_fields(Context),
    FieldKey = props:get_value('field_key', Options, <<"doc">>),
    HasFields = kz_term:is_not_empty(Fields),
    ShouldFields = HasFields
        andalso not props:is_true('no_fields', Options, 'false'),

    HasFullDocs = has_full_docs(Context),
    ShouldFullDocs = not HasFields
        andalso HasFullDocs
        andalso not kz_term:is_true(props:get_first_defined(['no_fields', 'no_filter'], Options, 'false')),

    Setters = [{fun cb_context:store/3, 'fields', Fields}
              ,{fun cb_context:store/3, 'has_fields', HasFields}
              ,{fun cb_context:store/3, 'has_qs_filter', HasQSFilter}
              ,{fun cb_context:store/3, 'has_full_docs', HasFullDocs}
              ],
    %% in case usermap is a fun/3, store some variables
    NewContext = cb_context:setters(Context, Setters),

    UserParams = [{'has_fields', HasFields}
                 ,{'has_full_docs', HasFullDocs}
                 ,{'has_qs_filter', HasQSFilter}
                 ,{'is_time_query', IsTimeQuery}
                 ,{'should_filter', ShouldFilter}
                 ,{'should_fields', ShouldFields}
                 ,{'should_full_docs', ShouldFullDocs}
                 ,{'time_filter_key', TimeFilterKey}
                 ],
    CursorOptions = [{'field_key', FieldKey}
                    ,{'user_params',  UserParams}
                    ],
    add_filtermap_fields_options({NewContext, CursorOptions}, Options).


-spec merge_options(cb_context:context(), kz_view:options(), options()) -> maybe_load_params().
merge_options(Context, CursorOptions, Options) ->
    kz_either:state({'ok', {Context, CursorOptions}}
                   ,Options
                   ,[fun cleanse_options/2
                    ,fun add_time_range/2
                    ,fun maybe_set_log_prefix/2
                    ,fun maybe_set_include_docs/2
                    ,fun set_context_vars/2
                    ]).

-spec add_time_range(context_options(), options()) -> maybe_load_params().
add_time_range({Context, CursorOptions}, Options) ->
    TimeFilterKey = props:get_ne_binary_value('time_filter_key', Options, <<"created">>),
    case time_range(Context, Options, TimeFilterKey) of
        {StartTime, EndTime} ->
            Prop = [{['user_params', 'start_time'], StartTime}
                   ,{['user_params', 'end_time'], EndTime}
                   ],
            {'ok', {Context, props:set_values(Prop, CursorOptions)}};
        Ctx -> {'error', Ctx}
    end.

-spec add_filtermap_fields_options(context_options(), options()) -> {'ok', context_options()}.
add_filtermap_fields_options({Context, CursorOptions}, Options) ->
    case props:is_true(['user_params', 'should_fields'], CursorOptions) of
        'true' ->
            {'ok', add_fields_options(Context, CursorOptions, Options)};
        'false' ->
            ShouldFullDocs = props:is_true(['user_params', 'should_full_docs'], CursorOptions),
            {'ok', maybe_add_full_docs_options(Context, CursorOptions, Options, ShouldFullDocs)}
    end.

-spec add_fields_options(cb_context:context(), kz_view:options(), options()) ->  context_options().
add_fields_options(Context, CursorOptions0, CbViewOptions) ->
    Fields = cb_context:fetch(Context, 'fields'),
    UserMapper = props:get_value('mapper', CbViewOptions),
    CursorOptions = [{'fields', Fields}
                    | CursorOptions0
                    ],

    %% this only builds filtermap fun with crossbar qs filter
    %% if has_qs_filter and filter_key is filtermap
    case build_filtermap(Context, CursorOptions, UserMapper) of
        'undefined' ->
            {Context, CursorOptions};
        FilterMap ->
            {Context, props:set_value('filtermap', FilterMap, CursorOptions)}
    end.

-spec maybe_add_full_docs_options(cb_context:context(), kz_view:options(), options(), boolean()) -> context_options().
maybe_add_full_docs_options(Context, CursorOptions, CbViewOptions, 'true') ->
    UserMapper = props:get_value('mapper', CbViewOptions),
    FilterMap = build_filtermap(Context, CursorOptions, UserMapper, get_doc_fun()),
    {Context, props:set_value('filtermap', FilterMap, CursorOptions)};
maybe_add_full_docs_options(Context, CursorOptions, CbViewOptions, 'false') ->
    UserMapper = props:get_value('mapper', CbViewOptions),
    ShouldFilter = props:is_true(['user_params', 'should_filter'], CursorOptions, 'false'),
    FilterMap = crossbar_filter:build_with_mapper(Context, UserMapper, ShouldFilter),
    {Context, props:set_value('filtermap', FilterMap, CursorOptions)}.

build_filtermap(Context, Options, UserMapper) ->
    build_filtermap(Context, Options, UserMapper, 'undefined').

build_filtermap(Context, Options, UserMapper, Default) ->
    case {props:get_value('field_key', Options)
         ,props:is_true(['user_params', 'should_filter'], Options)
         }
    of
        {'filtermap', ShouldFilter} ->
            crossbar_filter:build_with_mapper(Context, UserMapper, ShouldFilter);
        {_, 'true'} ->
            crossbar_filter:build_with_mapper(Context, Default, 'true');
        {_, 'false'} ->
            Default
    end.

-spec maybe_set_include_docs(context_options(), options()) -> {'ok', context_options()}.
maybe_set_include_docs({Context, CursorOptions}, _Options) ->
    case props:is_true(['user_params', 'should_filter'], CursorOptions)
        orelse (props:is_true(['user_params', 'should_fields'], CursorOptions)
                andalso props:get_value('field_key', CursorOptions) =:= <<"doc">>
               )
        orelse props:is_true(['user_params', 'should_full_docs'], CursorOptions)
    of
        'true' -> {'ok', {Context, ['include_docs' | props:delete('include_docs', CursorOptions)]}};
        'false' -> {'ok', {Context, CursorOptions}}
    end.

-spec maybe_set_log_prefix(context_options(), options()) -> {'ok', context_options()}.
maybe_set_log_prefix({Context, Options}, _CbViewOptions) ->
    case props:is_true(['user_params', 'is_chunked'], Options) of
        'true' -> {'ok', {Context, props:set_value('lager_prefix', "(chunked)", Options)}};
        'false' -> {'ok', {Context, Options}}
    end.

-spec set_context_vars(context_options(), options()) -> {'ok', context_options()}.
set_context_vars({Context, Options}, _CbViewOptions) ->
    Setters = [{fun cb_context:set_doc/2, []}
              ,{fun cb_context:set_resp_data/2, []}
              ,{fun cb_context:set_resp_status/2, 'success'}
              ],
    {'ok', {cb_context:setters(Context, Setters), Options}}.

-spec cleanse_options(context_options(), options()) -> {'ok', context_options()}.
cleanse_options({Context, CursorOptions}, Options) ->
    DeleteKeys = ['descending', 'limit', 'result_key'
                 | ?CB_SPECIFIC_VIEW_OPTIONS
                 ],
    {'ok', {Context, props:set_values(CursorOptions, props:delete_keys(DeleteKeys, Options))}}.


%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec has_qs_filter(cb_context:context(), options()) -> boolean().
has_qs_filter(Context, Options) ->
    case cb_context:fetch(Context, 'has_qs_filter') of
        'undefined' ->
            IsTimeQuery = props:is_true('is_time_query', Options, 'false'),
            TimeFilterKey = props:get_ne_binary_value('time_filter_key', Options, <<"created">>),
            has_qs_filter(Context, TimeFilterKey, IsTimeQuery);
        HasQSFilter ->
            HasQSFilter
    end.
-spec has_qs_filter(cb_context:context(), kz_term:ne_binary(), boolean()) -> boolean().
has_qs_filter(Context, TimeFilterKey, 'true') ->
    crossbar_filter:is_defined(Context)
        andalso not crossbar_filter:is_only_time_filter(Context, TimeFilterKey);
has_qs_filter(Context, _, 'false') ->
    crossbar_filter:is_defined(Context).

-spec has_full_docs(cb_context:context()) -> boolean().
has_full_docs(Context) ->
    case cb_context:fetch(Context, 'has_full_docs') of
        'undefined' ->
            kz_term:is_true(cb_context:req_param(Context, <<"full_docs">>, 'false'))
                andalso (kapps_config:is_true(?CONFIG_CAT, <<"allow_fetch_full_docs">>, 'false')
                         orelse module_allows_include_docs(cb_context:req_nouns(Context))
                        );
        HasFullDocs ->
            HasFullDocs
    end.

-spec module_allows_include_docs(req_nouns()) -> boolean().
module_allows_include_docs([]) ->
    'false';
module_allows_include_docs([{Endpoint, _} | _]) ->
    Module = <<"cb_", Endpoint/binary>>,
    kz_term:is_true(kapps_config:is_true(?CONFIG_CAT, [<<"allowed_modules_fetch_full_docs">>, Module])).

-spec get_fields(cb_context:context()) -> kz_view:fields().
get_fields(Context) ->
    QSFields = kz_json:get_value(<<"fields">>, cb_context:query_string(Context)),
    Fields = cb_context:fetch(Context, 'fields'),
    get_fields(Fields, QSFields).

-spec get_fields(kz_view:fields(), kz_term:api_ne_binary()) -> kz_view:fields().
get_fields('undefined', 'undefined') ->
    [];
get_fields(Fields, 'undefined') ->
    Fields;
get_fields(_, <<Fields/binary>>) ->
    lager:debug("normalizing found fields in query string: ~p", [Fields]),
    try normalize_fields(decode_fields(Fields))
    catch
        _E:_T:ST ->
            kz_log:log_stacktrace(ST, "normalizing fields crashed with ~p:~p", [_E, _T]),
            throw({'error', <<"invalid fields query string">>})
    end;
get_fields(_, _Other) ->
    lager:debug("fields qs is not valid json term: ~p", [_Other]),
    throw({'error', <<"invalid fields query string">>}).

-spec decode_fields(binary()) -> kz_view:fields().
decode_fields(Fields) ->
    case kz_json:unsafe_decode(Fields) of
        [] ->
            [];
        [Thing|_] = List ->
            case kz_json:is_json_object(Thing) of
                'true' -> kz_json:flatten_deep(List);
                'false' -> List
            end;
        <<Binary/binary>> ->
            binary:split(Binary, <<",">>, ['global']);
        JObj ->
            'true' = kz_json:is_json_object(JObj),
            kz_json:flatten_deep(JObj)
    end.

-spec normalize_fields(kz_view:fields()) -> kz_view:fields().
normalize_fields(List) ->
    %% technically we don't need to add _id here, kz_view will add it for us,
    %% but we are doing this because we store fields in context and to let modules like
    %% cb_cdrs use normalized fields from context when  need it.
    case lists:foldl(fun normalize_fields/2, [], List) of
        [] -> [];
        Fields ->
            case props:get_value(<<"_id">>, Fields) of
                'undefined' ->
                    lists:usort([<<"_id">> | Fields]);
                _ ->
                    lists:usort(Fields)
            end
    end.

-spec normalize_fields(kz_view:fields(), kz_view:fields()) -> kz_view:fields().
normalize_fields([], Acc) ->
    Acc;
%% handling _id and _read_only
normalize_fields(Field = <<"_id">>, Acc) ->
    [Field | Acc];
normalize_fields(<<"id">>, Acc) ->
    [<<"_id">> | Acc];
normalize_fields(Field = <<"_read_only">>, Acc) ->
    [Field | Acc];
normalize_fields([<<"_read_only">>|_] = Field, Acc) ->
    [Field | Acc];
%% handling `{_id, boolean()}' and `{_read_only, boolean()}'
normalize_fields({<<"_id">> = Field, Bool}, Acc) ->
    'true' = kz_term:is_boolean(Bool),
    [{Field, kz_term:is_true(Bool)}|Acc];
normalize_fields({<<"id">>, Bool}, Acc) ->
    'true' = kz_term:is_boolean(Bool),
    [{<<"_id">>, kz_term:is_true(Bool)} | Acc];
normalize_fields({<<"_read_only">> = Field, Bool}, Acc) ->
    'true' = kz_term:is_boolean(Bool),
    [{Field, kz_term:is_true(Bool)}|Acc];

normalize_fields(<<Field/binary>>, Acc) ->
    Path = binary:split(Field, <<".">>, ['global']),
    case is_valid_field(Path) of
        'true' ->
            [Path | Acc];
        'false' ->
            Acc
    end;
normalize_fields({<<Field/binary>>, Bool}, Acc) ->
    'true' = kz_term:is_boolean(Bool),
    Path = binary:split(Field, <<".">>, ['global']),
    case is_valid_field(Path) of
        'true' ->
            [{Path, kz_term:is_true(Bool)}  | Acc];
        'false' ->
            Acc
    end.

-spec is_valid_field(kz_json:path()) -> boolean().
is_valid_field([]) ->
    'false';
is_valid_field([<<"_read_only">>|Path]) ->
    kz_term:is_ne_binaries(Path);
is_valid_field([Key|Path]) ->
    kz_term:is_ne_binary(Key)
        andalso not kz_doc:is_private_key(Key)
        andalso kz_term:is_ne_binaries(Path).

%%------------------------------------------------------------------------------
%% @doc
%% @equiv direction(Context, [])
%% @end
%%------------------------------------------------------------------------------
-spec direction(cb_context:context()) -> kz_view:direction().
direction(Context) ->
    direction(Context, []).

%%------------------------------------------------------------------------------
%% @doc Find view sort direction from `Options' or request
%% query string. Default to `descending'.
%% @end
%%------------------------------------------------------------------------------
-spec direction(cb_context:context(), kz_view:options() | options()) -> kz_view:direction().
direction(Context, Options) ->
    %% In Crossbar default direction is: `descending'. Either cb modules can set it or the
    %% user can request it using query string. Options set by cb modules ALWAYS have priority over QS.
    %%
    %% `direction' is the new preferred option, check it first:
    case props:get_value('direction', Options) of
        'descending' -> 'descending';
        'ascending' -> 'ascending';
        _ -> check_des_asc_options(Context, Options)
    end.

-spec check_des_asc_options(cb_context:context(), kz_view:options() | options()) -> kz_view:direction().
check_des_asc_options(Context, Options) ->
    %% `descending' and `ascending' are old options. Both keys still have priority
    %% over query string options.
    %%
    %% descending has priority over ascending, check it first:
    case props:is_true('descending', Options, 'undefined') of
        'true' -> 'descending';
        'false' -> 'ascending';
        'undefined' ->
            case props:is_true('ascending', Options, 'undefined') of
                'true' -> 'ascending';
                'false' -> 'descending';
                'undefined' -> check_des_asc_qs(Context)
            end
    end.

-spec check_des_asc_qs(cb_context:context()) -> kz_view:direction().
check_des_asc_qs(Context) ->
    %% descending has priority over ascending, check it first.
    QS = cb_context:query_string(Context),
    case kz_json:is_true(<<"descending">>, QS, 'undefined') of
        'true' -> 'descending';
        'false' -> 'ascending';
        'undefined' ->
            case kz_json:is_true(<<"ascending">>, QS, 'undefined') of
                'true' -> 'ascending';
                'false' -> 'descending';
                'undefined' ->
                    %% neither cb module or qs has direction, using default value:
                    'descending'
            end
    end.

-spec get_batch_size(cb_context:context(), options()) -> kz_term:api_pos_integer().
get_batch_size(Context, Options) ->
    SystemSize = kapps_config:get_pos_integer(?CONFIG_CAT, <<"load_view_chunk_size">>, 50),
    OptionsSize = props:get_integer_value('batch_size', Options, SystemSize),

    case kz_json:get_first_defined([<<"batch_size">>, <<"chunk_size">>], cb_context:query_string(Context)) of
        'undefined' -> OptionsSize;
        Size ->
            try kz_term:to_integer(Size) of
                ChunkSize when ChunkSize > 0,
                               ChunkSize =< SystemSize ->
                    ChunkSize;
                ChunkSize when ChunkSize < 0 ->
                    throw({'error', <<"chunk size must be at least 1">>});
                ChunkSize when ChunkSize > SystemSize ->
                    throw({'error', <<"chunk size must be lower than ", (integer_to_binary(SystemSize))/binary>>})
            catch
                _:_ ->
                    throw({'error', <<"invalid chunk size">>})
            end
    end.

-spec is_chunked(cb_context:context(), options()) -> boolean().
is_chunked(Context, Options) ->
    kz_json:is_true(<<"is_chunked">>
                   ,cb_context:query_string(Context)
                   ,props:get_is_true('is_chunked', Options, 'false')
                   )
        andalso not kz_term:is_true(props:get_first_defined(['no_batch', 'unchunkable'], Options, 'false')).

%%------------------------------------------------------------------------------
%% @doc If pagination available, returns page size.
%%
%% <div class="notice">DO NOT ADD ONE (1) TO PAGE_SIZE OR LIMIT YOURSELF!
%% It will be added by this module during querying.</div>
%% If `paginate=false` is explicitly set, still load results in pages but check
%% process' memory usage on each page, terminating if memory exceeds a threshold
%% @end
%%------------------------------------------------------------------------------
-spec get_page_size(cb_context:context(), options()) -> kz_view:limit().
get_page_size(Context, Options) ->
    case props:is_true('should_paginate', Options, 'true')
        andalso cb_context:should_paginate(Context)
    of
        'true' ->
            case props:get_value('limit', Options) of
                'undefined' ->
                    get_page_size_from_request(Context);
                Limit ->
                    lager:debug("got limit from options: ~b", [Limit]),
                    Limit
            end;
        'false' ->
            lager:debug("pagination disabled in context or option"),
            'infinity'
    end.

-spec get_page_size_from_request(cb_context:context()) -> pos_integer().
get_page_size_from_request(Context) ->
    case cb_context:req_value(Context, <<"page_size">>) of
        'undefined' -> cb_context:pagination_page_size();
        Size ->
            try kz_term:to_integer(Size) of
                PageSize when PageSize > 0 -> PageSize;
                _ ->
                    throw({'error', <<"page size must be at least 1">>})
            catch
                _:_ ->
                    throw({'error', <<"invalid page size">>})
            end
    end.

%%------------------------------------------------------------------------------
%% @doc Create ranged view lookup database list using start/end time and
%% direction.
%% @end
%%------------------------------------------------------------------------------
-spec get_range_modbs(cb_context:context(), kz_view:options()) -> kz_term:ne_binaries().
get_range_modbs(Context, Options) ->
    Direction = props:get_value('direction', Options),
    StartTime = props:get_value(['user_params', 'start_time'], Options),
    EndTime = props:get_value(['user_params', 'end_time'], Options),
    case props:get_value('databases', Options) of
        'undefined' when Direction =:= 'ascending' ->
            kazoo_modb:get_range(cb_context:account_id(Context), StartTime, EndTime);
        'undefined' when Direction =:= 'descending' ->
            lists:reverse(kazoo_modb:get_range(cb_context:account_id(Context), StartTime, EndTime));
        Dbs when Direction =:= 'ascending' ->
            lists:usort(Dbs);
        Dbs when Direction =:= 'descending' ->
            lists:reverse(lists:usort(Dbs))
    end.

%%------------------------------------------------------------------------------
%% @doc Create ranged view lookup database list using start/end time and
%% direction.
%% @end
%%------------------------------------------------------------------------------
-spec get_range_yodbs(cb_context:context(), kz_view:options()) -> kz_term:ne_binaries().
get_range_yodbs(Context, Options) ->
    Direction = props:get_value('direction', Options),
    StartTime = props:get_value(['user_params', 'start_time'], Options),
    EndTime = props:get_value(['user_params', 'end_time'], Options),
    case props:get_value('databases', Options) of
        'undefined' when Direction =:= 'ascending' ->
            kazoo_yodb:get_range(cb_context:account_id(Context), StartTime, EndTime);
        'undefined' when Direction =:= 'descending' ->
            lists:reverse(kazoo_yodb:get_range(cb_context:account_id(Context), StartTime, EndTime));
        Dbs when Direction =:= 'ascending' ->
            lists:usort(Dbs);
        Dbs when Direction =:= 'descending' ->
            lists:reverse(lists:usort(Dbs))
    end.
%% }}}

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec load_view(kz_term:ne_binary(), kz_view:selector(), maybe_load_params()) ->
          cb_context:context().
load_view(_, _, {'error', Context}) ->
    Context;
load_view(View, Selector, {'ok', ContextOptions}) ->
    case has_valid_dbs(ContextOptions) of
        {'ok', {Context, Options}} ->
            Extra = cb_context:fetch(Context, 'crossbar_view_extra'),
            maybe_apply_extra(Context, View, Selector, Options, Extra);
        {'no_db', Context} ->
            Context;
        {'error', ErrorContext} ->
            ErrorContext
    end.

maybe_apply_extra(Context, View, Selector, Options, 'undefined') ->
    load_view({'ok', {Context, View, Selector, Options}});
maybe_apply_extra(Context, View, Selector, Options, Fun) ->
    load_view(Fun(Context, View, Selector, Options)).

-spec has_valid_dbs(context_options()) -> maybe_load_params() | {'no_db', cb_context:context()}.
has_valid_dbs({Context, Options}) ->
    DbName = cb_context:db_name(Context),
    case {get_databases(Options)
         ,kz_term:is_ne_binary(DbName)
         ,cb_context:fetch(Context, 'no_db_in_range', 'false')
         }
    of
        {[], 'false', 'true'} ->
            %% If there is no db in options or context, then there is no need to alarm the client.
            %% In other hand we lose visibilty to underlying issue why the database list was empty?
            %% Was it because the cb module developers forgot to set one or because modb/yodb
            %% was missing?
            lager:debug("no databases in options or context, returning empty result set"),
            {'no_db', crossbar_doc:handle_datamgr_success([], Context)};
        {[], 'false', 'false'} ->
            lager:debug("can not find any databases in options or context"),
            {'error', cb_context:add_system_error('invalid_db_name', Context)};
        {[], 'true', _} ->
            lager:debug("using database from context"),
            {'ok', {Context, props:set_value('databases', [cb_context:db_name(Context)], Options)}};
        {Dbs, _, _} when is_list(Dbs) ->
            lager:debug("using databases from option"),
            {'ok', {Context, props:set_value('databases', Dbs, Options)}};
        {Invalid, _, _} ->
            lager:debug("invalid databases set in options: ~p", [Invalid]),
            {'error', cb_context:add_system_error('internal_error', Context)}
    end.

get_databases(Options) ->
    case props:get_value('databases', Options, []) of
        <<>> -> [];
        <<Db/binary>> -> [Db];
        Dbs when is_list(Dbs) ->
            [Db || Db <- Dbs, kz_term:is_ne_binary(Db)];
        Invalid ->
            Invalid
    end.

load_view({'ok', {Context, View, Selector, Options}}) ->
    [Database|_] = props:get_value('databases', Options, [cb_context:db_name(Context)]),
    IsChunked = props:is_true(['user_params', 'is_chunked'], Options),
    case kz_view:find_batch(Database, View, Selector, Options) of
        {'ok', Cursor} ->
            handle_load_view(Context, View, Cursor, IsChunked);
        {'error', Reason} ->
            crossbar_doc:handle_datamgr_errors(Reason, View, Context)
    end;
load_view({'error', Context}) ->
    Context.

handle_load_view(Context, _, Cursor, 'true') ->
    Setters = [{fun cb_context:store/3, 'is_chunked', 'true'}
              ,{fun cb_context:store/3, 'chunking_started', 'false'}
              ,{fun cb_context:store/3, 'view_cursor', Cursor}
              ],
    cb_context:setters(Context, Setters);
handle_load_view(Context, View, Cursor, 'false') ->
    case kz_view_cursor:next(Cursor) of
        {'ok', 'cursor_exhausted'} ->
            crossbar_doc:handle_datamgr_success([], Context);
        {'ok', {NewCursor, JObjs}} ->
            Envelope = kz_json:set_values(kz_view_cursor:bookmark_compat(NewCursor), cb_context:resp_envelope(Context)),
            crossbar_doc:handle_datamgr_success(JObjs, cb_context:set_resp_envelope(Context, Envelope));
        {'error', Reason} ->
            handle_datamgr_errors(Reason, View, Context)
    end.

-spec next_batch(cb_context:context(), kz_view_cursor:cursor()) ->
          kz_either:either(cb_context:context(), {kz_view_cursor:cursor(), kz_view:result_value()} | 'cursor_exhausted').
next_batch(Context, Cursor) ->
    #{design_view := View} = kz_view_cursor:get_driver_params(Cursor),
    case kz_view_cursor:next_batch(Cursor) of
        {'ok', _}=OK -> OK;
        {'error', Reason} ->
            {'error', handle_datamgr_errors(Reason, View, Context)}
    end.

-spec handle_datamgr_errors(kazoo_data:data_errors() | cb_context:context(), kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
handle_datamgr_errors(Reason, View, Context) ->
    case cb_context:is_context(Reason) of
        'true' ->
            Reason;
        'false' ->
            lager:debug("cursor failed: ~p", [Reason]),
            crossbar_doc:handle_datamgr_errors(Reason, View, Context)
    end.

%% start/end, range keys {{{
%%------------------------------------------------------------------------------
%% @doc Suffix the Timestamp to the provided key map option. Useful to use
%% generate the keys like `[Timestamp, InteractionId]' for the end key in
%% {@link cb_cdrs} for example.
%% @end
%%------------------------------------------------------------------------------
-spec suffix_key_fun(range_keymap()) -> range_keymap_fun().
suffix_key_fun('nil') -> fun(_) -> 'undefined' end;
suffix_key_fun('undefined') -> fun kz_term:identity/1;
suffix_key_fun(['undefined']) -> fun kz_term:identity/1;
suffix_key_fun(K) when is_binary(K) -> fun(Ts) -> [Ts, K] end;
suffix_key_fun(K) when is_integer(K) -> fun(Ts) -> [Ts, K] end;
suffix_key_fun(K) when is_list(K) -> fun(Ts) -> [Ts | K] end;
suffix_key_fun(K) when is_function(K, 1) -> K.

%%------------------------------------------------------------------------------
%% @doc Returns a time range for range query based or payload on request or `Options'
%% and default range based on system configuration (maximum range).
%%
%% The start time, `created_from' (default), should always be prior to end time
%% `created_to'.
%%
%% <strong>Options:</strong>
%% <dl>
%%   <dt>`max_range'</dt><dd>Maximum range allowed. Default is the value of
%%   `crossbar.maximum_range', 31 days.</dd>
%%
%%   <dt>`range_key'</dt><dd>The key name in query string to get values
%%   from (created, modified or ...). Default is `created'.</dd>
%%
%%   <dt>`{RANGE_KEY}_from'</dt><dd>Start time.</dd>
%%
%%   <dt>`{RANGE_KEY}_to'</dt><dd>End time.</dd>
%% </dl>
%% @private
%% @end
%%------------------------------------------------------------------------------
-spec time_range(cb_context:context(), options(), kz_term:ne_binary()) -> time_range() | cb_context:context().
time_range(Context, Options, Key) ->
    MaxRange = get_max_range(Options),
    TSTime = kz_time:now_s(),
    RangeTo = get_time_key(Context, <<Key/binary, "_to">>, Options, TSTime),
    RangeFrom = get_time_key(Context, <<Key/binary, "_from">>, Options, RangeTo - MaxRange),
    time_range(Context, MaxRange, Key, RangeFrom, RangeTo).

%%------------------------------------------------------------------------------
%% @doc Get time key value from options or request.
%% @end
%%------------------------------------------------------------------------------
-spec get_time_key(cb_context:context(), kz_term:ne_binary(), options(), pos_integer()) -> pos_integer().
get_time_key(Context, Key, Options, Default) ->
    case props:get_integer_value(Key, Options) of
        'undefined' ->
            case kz_term:safe_cast(cb_context:req_value(Context, Key), Default, fun kz_term:to_integer/1) of
                T when T > 0 -> T;
                _ -> Default
            end;
        Value -> Value
    end.

%%------------------------------------------------------------------------------
%% @doc Get `max_range' from option or system config.
%% @end
%%------------------------------------------------------------------------------
-spec get_max_range(options()) -> pos_integer().
get_max_range(Options) ->
    case props:get_integer_value('max_range', Options) of
        'undefined' -> ?MAX_RANGE;
        MaxRange -> MaxRange
    end.

%%------------------------------------------------------------------------------
%% @doc Checks whether or not end time is prior to start time. Returns a ranged
%% tuple `{start_time, end_time}' or `context' with validation error.
%% @end
%%------------------------------------------------------------------------------
-spec time_range(cb_context:context(), pos_integer(), kz_term:ne_binary(), pos_integer(), pos_integer()) ->
          time_range() | cb_context:context().
time_range(Context, MaxRange, Key, RangeFrom, RangeTo) ->
    Path = <<Key/binary, "_from">>,
    case RangeTo - RangeFrom of
        N when N < 0 ->
            Msg = kz_term:to_binary(io_lib:format("~s_to ~b is prior to ~s ~b", [Key, RangeTo, Path, RangeFrom])),
            JObj = kz_json:from_list([{<<"message">>, Msg}, {<<"cause">>, RangeFrom}]),
            lager:debug("range error: ~s", [Msg]),
            cb_context:add_validation_error(Path, <<"date_range">>, JObj, Context);
        N when N > MaxRange ->
            Msg = kz_term:to_binary(io_lib:format("~s_to ~b is more than ~b seconds from ~s ~b", [Key, RangeTo, MaxRange, Path, RangeFrom])),
            JObj = kz_json:from_list([{<<"message">>, Msg}, {<<"cause">>, RangeTo}]),
            lager:debug("range_error: ~s", [Msg]),
            cb_context:add_validation_error(Path, <<"date_range">>, JObj, Context);
        _ ->
            {RangeFrom, RangeTo}
    end.

%%------------------------------------------------------------------------------
%% @doc Returns start/end keys based on direction.
%% Returned tuple is `{start_key, end_key}'.
%%
%% If `start_key' is present in the request (query string or payload)
%% they will be returned instead. Otherwise the keys will built by key map options.
%%
%% <strong>Options description:</strong>
%% <dl>
%%   <dt>`keymap'</dt><dd>Use this to map both start/end keys.</dd>
%%   <dt>`start_keymap'</dt><dd>Maps start key only.</dd>
%%   <dt>`end_keymap'</dt><dd>Maps end key only.</dd>
%% </dl>
%%
%% See also {@link direction/2} for `direction' option explanation.
%%
%% <strong>Keymap description:</strong>
%% <dl>
%%   <dt>{@type kazoo_data:key_range()}</dt><dd>A regular CouchDB key to construct
%%    keys like `[<<"en">>, <<"us">>]'.</dd>
%%   <dt>{@type keymap_fun()}</dt><dd>To customize your own key using a function.</dd>
%% </dl>
%%
%% The keys will be swapped if direction is descending.
%% @see direction/2
%% @private
%% @end
%%------------------------------------------------------------------------------
-spec build_start_end_keys(cb_context:context(), kz_view:options(), kz_view:direction()) -> range_keys().
build_start_end_keys(Context, Options, Direction) ->
    {StartKey, EndKey} = build_start_end_keys(Context, Options),
    case props:get_value(['bookmark', 'next_startkey'], Options) of
        'undefined' when Direction =:= 'ascending' ->
            {StartKey, EndKey};
        'undefined' when Direction =:= 'descending' ->
            {EndKey, StartKey};
        NextStartKey when Direction =:= 'ascending' ->
            {NextStartKey, EndKey};
        NextStartKey when Direction =:= 'descending' ->
            {NextStartKey, StartKey}
    end.

%%------------------------------------------------------------------------------
%% @doc Build customized start/end key mapper.
%% @end
%%------------------------------------------------------------------------------
-spec build_start_end_keys(cb_context:context(), kz_view:options()) -> {api_range_key(), api_range_key()}.
build_start_end_keys(Context, Options) ->
    UserParams = props:get_value('user_params', Options),
    KeyMap = props:get_value('keymap', UserParams),
    {maybe_keymap(Context, Options, KeyMap, 'startkey', 'start_keymap')
    ,maybe_keymap(Context, Options, KeyMap, 'endkey', 'end_keymap')
    }.

maybe_keymap(Context, Options, 'undefined', Key, KeyKeymap) ->
    UserParams = props:get_value('user_params', Options),
    ValueKeymap = props:get_value(KeyKeymap, UserParams),
    Value = props:get_value(Key, Options, ValueKeymap),
    map_keymap(Context, Options, Value);
maybe_keymap(Context, Options, KeyMap, _, _) ->
    map_keymap(Context, Options, KeyMap).

-spec map_keymap(cb_context:context(), options(), keymap()) -> api_range_key().
map_keymap(Context, _, Fun) when is_function(Fun, 1) -> Fun(Context) ;
map_keymap(Context, Options, Fun) when is_function(Fun, 2) -> Fun(Options, Context);
map_keymap(_, _, ApiRangeKey) -> ApiRangeKey.

%%------------------------------------------------------------------------------
%% @doc Returns start/end keys based on direction. Start/end timestamp will be
%% added to keys based on requested time range.
%% Returned tuple is `{start_key, end_key}'.
%%
%% If `start_key' is present in the request (query string or payload)
%% they will be returned instead. Otherwise the keys will built by key map options.
%%
%% <strong>Options description:</strong>
%% <dl>
%%   <dt>`range_keymap'</dt><dd>Use this to map both start/end keys.</dd>
%%   <dt>`range_start_keymap'</dt><dd>maps start key only.</dd>
%%   <dt>`range_end_keymap'</dt><dd>maps end key only.</dd>
%% </dl>
%%
%% See also {@link direction/2} and {@link time_range/2} for explanation of
%% other options.
%%
%% <strong>Keymap description:</strong>
%% <dl>
%%   <dt>{@type kz_term:ne_binary()}</dt><dd>Constructs keys like `[<<"account">>, Timestamp]'.</dd>
%%   <dt>{@type integer()}</dt><dd>Constructs keys like `[1234, Timestamp]'.</dd>
%%   <dt>{@type list()}</dt><dd>Constructs keys like `[<<"en">>, <<"us">>, Timestamp]'.</dd>
%%   <dt>{@type range_keymap_fun()}</dt><dd>Customize your own key using a function.</dd>
%% </dl>
%%
%% The keys will be swapped if direction is descending.
%% @private
%% @end
%%------------------------------------------------------------------------------
-spec build_time_start_end_keys(kz_view:options()) -> range_keys().
build_time_start_end_keys(CursorOptions) ->
    Direction = props:get_value('direction', CursorOptions),

    UserParams = props:get_value('user_params', CursorOptions, CursorOptions),
    StartTime = props:get_value('start_time', UserParams),
    EndTime = props:get_value('end_time', UserParams),

    {StartKeyMap, EndKeyMap} = build_time_range_keymaps_fun(CursorOptions),
    case props:get_value(['bookmark', 'next_startkey'], CursorOptions) of
        'undefined' when Direction =:= 'ascending' ->
            {StartKeyMap(StartTime), EndKeyMap(EndTime)};
        'undefined' when Direction =:= 'descending' ->
            {EndKeyMap(EndTime), StartKeyMap(StartTime)};
        NextStartKey when Direction =:= 'ascending' ->
            {NextStartKey, EndKeyMap(EndTime)};
        NextStartKey when Direction =:= 'descending' ->
            {NextStartKey, StartKeyMap(StartTime)}
    end.

%%------------------------------------------------------------------------------
%% @doc See {@link build_time_start_end_keys/2} for explaining of options and range_keymap.
%% @end
%%------------------------------------------------------------------------------
-spec build_time_range_keymaps_fun(kz_view:options()) -> {range_keymap_fun(), range_keymap_fun()}.
build_time_range_keymaps_fun(Options) ->
    UserParams = props:get_value('user_params', Options),
    case props:get_value('range_keymap', UserParams) of
        'undefined' ->
            {map_range_keymap(props:get_value('startkey', Options, props:get_value('range_start_keymap', UserParams)))
            ,map_range_keymap(props:get_value('endkey', Options, props:get_value('range_end_keymap', UserParams)))
            };
        KeyMap -> {map_range_keymap(KeyMap), map_range_keymap(KeyMap)}
    end.

-spec map_range_keymap(range_keymap()) -> range_keymap_fun().
map_range_keymap('nil') -> fun(_) -> 'undefined' end;
map_range_keymap('undefined') -> fun kz_term:identity/1;
map_range_keymap(['undefined']) -> fun(Ts) -> [Ts] end;
map_range_keymap(K) when is_binary(K) -> fun(Ts) -> [K, Ts] end;
map_range_keymap(K) when is_integer(K) -> fun(Ts) -> [K, Ts] end;
map_range_keymap(K) when is_list(K) -> fun(Ts) -> K ++ [Ts] end;
map_range_keymap(K) when is_function(K, 1) -> K.
%% }}}

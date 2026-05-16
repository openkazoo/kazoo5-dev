%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2023, 2600Hz
%%% @doc
%%% @author Pierre Fenoll
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(kt_cleanup).

%% behaviour: tasks_provider
-export([init/0]).

%% Triggerables
-export([cleanup_soft_deletes/1]).

-include("tasks.hrl").

-define(CLEANUP_CAT, <<(?CONFIG_CAT)/binary, ".cleanup">>).

%% How long to pause before attempting to delete the next chunk of soft-deleted docs
-define(SOFT_DELETE_PAUSE
       ,kapps_config:get_integer(?CONFIG_CAT, <<"soft_delete_pause_ms">>, 10 * ?MILLISECONDS_IN_SECOND)
       ).


-define(DEFAULT_CLEANUP
       ,kz_json:from_list(
          [{<<"classifications">>, [<<"account">>
                                   ,<<"modb">>
                                   ,<<"yodb">>
                                   ,<<"ratedeck">>
                                   ,<<"resource_selectors">>
                                   ]
           }
          ,{<<"databases">>, [?KZ_ALERTS_DB
                             ,?KZ_ACCOUNTS_DB
                             ,?KZ_CONFIG_DB
                             ,?KZ_DATA_DB
                             ,?KZ_FUNCTIONS_DB
                             ,?KZ_MEDIA_DB
                             ,?KZ_OFFNET_DB
                             ,?KZ_PORT_REQUESTS_DB
                             ,?KZ_SIP_DB
                             ,?KZ_WEBHOOKS_DB
                             ]
           }
          ]
         )
       ).
-define(CLEANUP_DBS
       ,kapps_config:get_json(?CLEANUP_CAT, <<"cleanup_dbs">>, ?DEFAULT_CLEANUP)
       ).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = tasks_bindings:bind(?TRIGGER_ALL_DBS, ?MODULE, 'cleanup_soft_deletes').

%%% Triggerables

-spec cleanup_soft_deletes(kz_term:ne_binary()) -> 'ok'.
cleanup_soft_deletes(Db) ->
    CleanupDbs = ?CLEANUP_DBS,
    Classification = kzs_util:db_classification(Db),
    case lists:member(Db, kz_json:get_list_value(<<"databases">>, CleanupDbs, []))
        orelse lists:member(kz_term:to_binary(Classification)
                           ,kz_json:get_list_value(<<"classifications">>, CleanupDbs, [])
                           )
    of
        'true' ->
            lager:debug("cleaning up database ~s(~s)", [Db, Classification]),
            kz_datamgr:suppress_change_notice(),
            cleanup_db(Db, Classification),
            kz_datamgr:enable_change_notice();
        'false' ->
            'ok'
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec cleanup_db(kz_term:ne_binary(), kazoo_data:db_classification()) -> 'ok'.
cleanup_db(Db, _Classfication) ->
    do_cleanup_soft_deleted(Db).

-spec do_cleanup_soft_deleted(kz_term:ne_binary()) -> 'ok'.
do_cleanup_soft_deleted(Db) ->
    do_cleanup(Db, <<"maintenance/soft_deletes">>).

-spec do_cleanup(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
do_cleanup(Db, View) ->
    ViewOptions = [{'batch_size', kz_datamgr:max_bulk_insert()}
                  ,{'no_design_module', 'true'}
                  ,{'filtermap', fun build_id_rev/2}
                  ,{'reductions_max', 10}
                  ,{'memory_limit', 'true'}
                  ],
    case kz_view:find_batch(Db, View, [], ViewOptions) of
        {'ok', Cursor} ->
            kz_view_cursor:foreach(fun(JObjs) -> cleanup_fold(Db, JObjs) end, Cursor);
        {'error', _E} ->
            lager:debug("failed to lookup soft-deleted tokens: ~p", [_E])
    end.

-spec cleanup_fold(kz_term:ne_binary(), kz_json:objects()) -> 'ok'.
cleanup_fold(Db, JObjs) ->
    lager:debug("removing ~b soft-deleted docs from ~s", [length(JObjs), Db]),
    _ = kz_datamgr:del_docs(Db, JObjs),
    timer:sleep(?SOFT_DELETE_PAUSE).

-spec build_id_rev(kz_json:object(), kz_json:objects()) -> kz_json:objects().
build_id_rev(JObj0, Acc) ->
    JObj =
        kz_json:get_ne_json_value(<<"value">>, JObj0
                                 ,kz_json:get_ne_json_value(<<"doc">>, JObj0, JObj0)
                                 ),
    [kz_json:from_list(
       [{<<"_id">>, kz_doc:id(JObj)}
       ,{<<"_rev">>, kz_doc:revision(JObj)}
       ])
    | Acc
    ].

%%% End of Module.

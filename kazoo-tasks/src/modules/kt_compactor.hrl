-ifndef(KT_COMPACTOR_HRL).

-include_lib("couchbeam/include/couchbeam.hrl").

-define(HEUR_NONE, 'none').
-define(HEUR_RATIO, 'ratio').
%% Maximum number of tries to check if shard or design document is being compacted before giving up on it.
-define(IS_BEING_COMPACTED_MAX_RETRIES, 3).
%% Maximum number of tries to check if a shard or design document are still being compacted before moving to the next one.
-define(WAIT_FOR_COMPACTION_MAX_RETRIES, 500). %% ~25 minutes if using default SLEEP_BETWEEN_POLL value. 500 * 3s = 1500s.

-type heuristic() :: ?HEUR_NONE | ?HEUR_RATIO.

%% Ratio of legacy data, including metadata, to current data in the database file size.
%% The percentage is expressed as an integer percentage. Taken from
%% https://docs.couchdb.org/en/2.3.1/config/compaction.html `db_fragmentation' section.
-define(MIN_RATIO
       ,kapps_config:get_float(<<"kazoo_couch">>, <<"min_ratio">>, 25)
       ).
-define(MIN_DATA
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"min_data_size">>, 131072)  %% 128Kb
       ).
-define(MAX_WAIT_FOR_COMPACTION_PIDS
       ,case kapps_config:get(<<"kazoo_couch">>, <<"max_wait_for_compaction_pids">>, 360 * ?MILLISECONDS_IN_SECOND) of
            <<"infinity">> -> 'infinity';
            N -> kz_term:to_integer(N)
        end
       ).
-define(MAX_COMPACTING_SHARDS
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"max_compacting_shards">>, 2)
       ).
-define(MAX_COMPACTING_VIEWS
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"max_compacting_views">>, 2)
       ).
-define(SLEEP_BETWEEN_POLL
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"sleep_between_poll">>, 3 * ?MILLISECONDS_IN_SECOND)
       ).

-define(COMPACT_AUTOMATICALLY
       ,kapps_config:get_is_true(<<"kazoo_couch">>, <<"compact_automatically">>, 'false')
       ).
%% How many dbs to read between pauses.
-define(COMPACTION_LIST_DBS_CHUNK_SIZE
       ,kapps_config:get_integer(?CONFIG_CAT, <<"compaction_list_dbs_chunk_size">>, 20)
       ).
%% How long to pause before attempting to get the next chunk of dbs.
-define(COMPACTION_LIST_DBS_PAUSE
       ,kapps_config:get_integer(?CONFIG_CAT, <<"compaction_list_dbs_pause_ms">>, 200)
       ).

-define(ADMIN_PORT
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"admin_port">>, 5986)
       ).
-define(NODE_ADMIN_PORT(Node)
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"admin_port">>, 5986, Node)
       ).

-define(API_PORT
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"api_port">>, 5984)
       ).
-define(NODE_API_PORT(Node)
       ,kapps_config:get_integer(<<"kazoo_couch">>, <<"api_port">>, 5984, Node)
       ).

-define(KT_COMPACTOR_HRL, 'true').

-endif.

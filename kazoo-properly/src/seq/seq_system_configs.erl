%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_system_configs).

-export([seq/0
        ,cleanup/0, cleanup/1
        ,default/0, init_db/0, cleanup_db/0
        ]
       ).

-properly({standalone, [seq/0]}).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(CATEGORY_ID, <<"properly">>).
-define(SCHEMA_ID, <<"system_config.properly">>).
-define(NODE_ID, <<"foo@bar.com">>).

-define(KEY_SCHEMA, kz_json:from_list([{<<"type">>, <<"string">>}
                                      ,{<<"default">>, <<"default_key">>}
                                      ])
       ).
-define(KNEE_SCHEMA, kz_json:from_list([{<<"type">>, <<"string">>}
                                       ,{<<"default">>, <<"default_knee">>}
                                       ])
       ).

-define(NESTED_SCHEMA, kz_json:from_list([{<<"type">>, <<"object">>}
                                         ,{<<"properties">>, kz_json:from_list([{<<"knee">>, ?KNEE_SCHEMA}])}
                                         ,{<<"default">>, kz_json:from_list([{<<"knee">>, <<"default_knee">>}])}
                                         ])
       ).

-define(CONFIG_SCHEMA
       ,kz_json:from_list([{<<"_id">>, ?SCHEMA_ID}
                          ,{<<"$schema">>, <<"http://json-schema.org/draft-04/schema#">>}
                          ,{<<"properties">>, kz_json:from_list([{<<"key">>, ?KEY_SCHEMA}
                                                                ,{<<"nested">>, ?NESTED_SCHEMA}
                                                                ])}
                          ,{<<"type">>, <<"object">>}
                          ])
       ).

init() ->
    _ = kz_data_tracing:clear_all_traces(),
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar', 'conference']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_system_configs']
        ],
    _ = init_db(),
    ?INFO("INIT FINISHED").

-spec init_db() -> {'ok', kz_json:object()}.
init_db() ->
    {'ok', _} = kz_datamgr:save_doc(?KZ_SCHEMA_DB, ?CONFIG_SCHEMA).

-spec cleanup_db() -> 'ok'.
cleanup_db() ->
    _ = kz_datamgr:del_doc(?KZ_CONFIG_DB, ?CATEGORY_ID),
    _ = kz_datamgr:del_doc(?KZ_SCHEMA_DB, ?SCHEMA_ID),
    'ok'.

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    _ = init(),
    API = pqc_cb_api:authenticate(),
    ?INFO("state initialized to ~p", [API]),
    pqc_kazoo_model:new(API).

-spec default() -> 'ok'.
default() ->
    _ = init_db(),
    cleanup_db().

-spec seq() -> any().
seq() ->
    Model = initial_state(),
    API = pqc_kazoo_model:api(Model),

    ListingResp = pqc_cb_system_configs:list_configs(API),
    Listing = pqc_cb_response:data(ListingResp),
    'false' = lists:member(?CATEGORY_ID, Listing),

    GetSchemaDefaultsResp = pqc_cb_system_configs:get_default_config(API, ?CATEGORY_ID),
    lager:info("get schema defaults: ~s", [GetSchemaDefaultsResp]),
    GetSchemaDefaults = pqc_cb_response:data(GetSchemaDefaultsResp),

    ?CATEGORY_ID = kz_json:get_value(<<"id">>, GetSchemaDefaults),
    <<"default_key">> = kz_json:get_value([<<"default">>, <<"key">>], GetSchemaDefaults),
    <<"default_knee">> = kz_json:get_value([<<"default">>, <<"nested">>, <<"knee">>], GetSchemaDefaults),

    Section = kz_json:from_list([{<<"key">>, <<"value">>}
                                ,{<<"nested">>, kz_json:from_list([{<<"knee">>, <<"nalue">>}])}
                                ]),
    Defaults = kz_json:from_list([{<<"default">>, Section}
                                 ,{<<"id">>, ?CATEGORY_ID}
                                 ]),

    SetResp = pqc_cb_system_configs:set_default_config(API, Defaults),
    lager:info("set resp: ~s~n", [SetResp]),
    Set = pqc_cb_response:data(SetResp),
    'true' = kz_json:are_equal(kz_doc:public_fields(Set), Defaults),

    GetResp = pqc_cb_system_configs:get_node_config(API, ?CATEGORY_ID, <<"default">>),
    lager:info("get resp: ~s", [GetResp]),
    Get = pqc_cb_response:data(GetResp),
    <<"nalue">> = kz_json:get_value([<<"nested">>, <<"knee">>], Get),
    [?CATEGORY_ID, <<"default">>] = binary:split(kz_doc:id(Get), <<"/">>),
    <<"value">> = kz_json:get_value(<<"key">>, Get),

    NodeSection = kz_json:from_list([{<<"key">>, <<"node">>}
                                    ,{<<"nested">>, kz_json:from_list([{<<"ankle">>, <<"alue">>}])}
                                    ]),
    NodeSettings = kz_json:from_list([{?NODE_ID, NodeSection}]),

    PatchResp = pqc_cb_system_configs:patch_default_config(API, ?CATEGORY_ID, NodeSettings),
    lager:info("patch resp: ~s", [PatchResp]),
    Patch = pqc_cb_response:data(PatchResp),

    <<"node">> = kz_json:get_value([?NODE_ID, <<"key">>], Patch),
    <<"alue">> = kz_json:get_value([?NODE_ID, <<"nested">>, <<"ankle">>], Patch),

    GetAllResp = pqc_cb_system_configs:get_default_config(API, ?CATEGORY_ID),
    lager:info("get all resp: ~s", [GetAllResp]),
    GetAll = pqc_cb_response:data(GetAllResp),

    <<"node">> = kz_json:get_value([?NODE_ID, <<"key">>], GetAll),
    <<"alue">> = kz_json:get_value([?NODE_ID, <<"nested">>, <<"ankle">>], GetAll),
    <<"nalue">> = kz_json:get_value([<<"default">>, <<"nested">>, <<"knee">>], GetAll),

    GetNodeResp = pqc_cb_system_configs:get_node_config(API, ?CATEGORY_ID, ?NODE_ID),
    lager:info("get node resp: ~s", [GetNodeResp]),
    GetNode = pqc_cb_response:data(GetNodeResp),

    [?CATEGORY_ID, ?NODE_ID] = binary:split(kz_doc:id(GetNode), <<"/">>),
    <<"node">> = kz_json:get_value([<<"key">>], GetNode),
    <<"alue">> = kz_json:get_value([<<"nested">>, <<"ankle">>], GetNode),
    <<"nalue">> = kz_json:get_value([<<"nested">>, <<"knee">>], GetNode),

    InListingResp = pqc_cb_system_configs:list_configs(API),
    InListing = pqc_cb_response:data(InListingResp),
    'true' = lists:member(?CATEGORY_ID, InListing),

    DeleteResp = pqc_cb_system_configs:delete_config(API, ?CATEGORY_ID),
    lager:info("delete resp: ~s", [DeleteResp]),

    Delete = pqc_cb_response:metadata(DeleteResp),

    'true' = kz_json:is_true([<<"deleted">>], Delete),

    OutListingResp = pqc_cb_system_configs:list_configs(API),
    OutListing = pqc_cb_response:data(OutListingResp),
    'false' = lists:member(?CATEGORY_ID, OutListing),

    _ = cleanup(API),
    lager:info("COMPLETED SUCCESSFULLY!").

-spec cleanup() -> any().
cleanup() ->
    ?INFO("CLEANUP ALL THE THINGS"),
    kz_data_tracing:clear_all_traces(),
    cleanup(pqc_cb_api:authenticate()).

-spec cleanup(pqc_cb_api:state()) -> any().
cleanup(API) ->
    ?INFO("CLEANUP TIME, EVERYBODY HELPS"),
    cleanup_db(),
    pqc_cb_api:cleanup(API).

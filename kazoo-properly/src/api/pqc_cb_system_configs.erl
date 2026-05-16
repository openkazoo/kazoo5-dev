%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_system_configs).

%% API
-export([list_configs/1
        ,set_default_config/2
        ,patch_default_config/3
        ,get_config/2
        ,get_default_config/2
        ,get_node_config/3
        ,delete_config/2
        ]).

-include("properly.hrl").

-spec list_configs(pqc_cb_api:state()) ->
          pqc_cb_api:response().
list_configs(API) ->
    URL = configs_url(API),
    pqc_cb_crud:summary(API, URL).

-spec get_config(pqc_cb_api:state(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
get_config(API, Id) ->
    URL = config_url(API, Id),
    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:fetch(API, URL, Expectations).

-spec get_default_config(pqc_cb_api:state(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
get_default_config(API, Id) ->
    URL = config_url(API, Id) ++ "?with_defaults=true",
    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:fetch(API, URL, Expectations).

-spec get_node_config(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
get_node_config(API, Id, NodeId) ->
    URL = config_url(API, Id, NodeId) ++ "?with_defaults=true",
    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:fetch(API, URL, Expectations).

-spec set_default_config(pqc_cb_api:state(), kz_json:object()) ->
          pqc_cb_api:response().
set_default_config(API, Config) ->
    ?INFO("setting default config for ~p", [Config]),
    URL = config_url(API, kz_doc:id(Config)),
    Data = pqc_cb_api:create_envelope(Config),

    pqc_cb_crud:update(API, URL, Data).

-spec patch_default_config(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
patch_default_config(API, Id, Config) ->
    ?INFO("patching default config for ~p", [Config]),
    URL = config_url(API, Id),
    Data = pqc_cb_api:create_envelope(Config),

    pqc_cb_crud:patch(API, URL, Data).

-spec delete_config(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_config(API, Id) ->
    URL = config_url(API, Id),
    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:delete(API, URL, Expectations).

-spec configs_url(pqc_cb_api:state()) -> string().
configs_url(API) ->
    pqc_cb_crud:collection_url(API, <<"system_configs">>).

-spec config_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
config_url(API, Id) ->
    pqc_cb_crud:entity_url(API, <<"system_configs">>, Id).

-spec config_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
config_url(API, Id, NodeId) ->
    string:join([config_url(API, Id)
                ,kz_term:to_list(NodeId)
                ]
               ,"/"
               ).

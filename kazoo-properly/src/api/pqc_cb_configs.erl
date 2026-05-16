%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_configs).
%% API
-export([fetch/1
        ]).

-spec fetch(pqc_cb_api:state()) ->
          pqc_cb_api:response().
fetch(API) ->
    pqc_cb_crud:fetch(API, configs_url(API)).

-spec configs_url(pqc_cb_api:state()) -> string().
configs_url(#{base_url:=BaseURL}) ->
    string:join([kz_term:to_list(BaseURL), "configs"], "/").

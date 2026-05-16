%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_configs).

-export([seq/0
        ,cleanup/0, cleanup/1
        ]).

-spec seq() -> 'ok'.
seq() ->
    API = initial_state(),

    GetResp = pqc_cb_configs:fetch(API),
    lager:info("fetched config: ~s", [GetResp]),

    Data = pqc_cb_response:data(GetResp),
    <<"configs_default">> = kz_json:get_binary_value(<<"id">>, Data),
    20 = kz_json:get_integer_value(<<"smtp_max_msg_size">>, Data),
    20 = kz_json:get_integer_value(<<"max_upload_size">>, Data),

    _ = cleanup(API),
    lager:info("COMPLETED SUCCESSFULLY!").

-spec initial_state() -> pqc_cb_api:state().
initial_state() ->
    pqc_cb_api:init_api(['crossbar'], ['cb_configs']).

-spec cleanup() -> any().
cleanup() ->
    lager:info("CLEANUP ALL THE THINGS"),
    kz_data_tracing:clear_all_traces(),
    cleanup(pqc_cb_api:authenticate()).

-spec cleanup(pqc_cb_api:state()) -> any().
cleanup(API) ->
    lager:info("CLEANUP TIME, EVERYBODY HELPS"),
    pqc_cb_api:cleanup(API).

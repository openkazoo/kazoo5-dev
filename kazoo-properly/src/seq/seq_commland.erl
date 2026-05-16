%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(seq_commland).

-export([seq/0]).

-include("properly.hrl").

-spec seq() -> 'ok'.
seq() ->
    API = pqc_cb_api:init_api(['crossbar'], ['cb_commland']),
    CompatResp = pqc_cb_commland:compatibility(API),
    lager:info("compat resp: ~s", [CompatResp]),

    Resp = kz_json:decode(CompatResp),
    <<_RedirectURL/binary>> = kz_json:get_ne_binary_value([<<"data">>, <<"auto_updater_url">>], Resp),
    <<"success">> = kz_json:get_ne_binary_value(<<"status">>, Resp),
    lager:info("FINISHED COMMLAND SEQ").

%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_auth).

-export([tokeninfo/1]).

-spec tokeninfo(pqc_cb_api:state()) -> pqc_cb_api:response().
tokeninfo(#{auth_token := JWT}=API) ->
    URL = pqc_cb_crud:entity_url(API, <<"auth">>, <<"tokeninfo">>),
    Data = kz_json:from_list([{<<"token">>, JWT}]),
    Envelope = pqc_cb_api:create_envelope(Data),

    pqc_cb_crud:update(API, URL, Envelope).

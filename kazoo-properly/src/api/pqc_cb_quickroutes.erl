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
-module(pqc_cb_quickroutes).

-export([summary/2]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API, quickroutes_url(API, AccountId)).

-spec quickroutes_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
quickroutes_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"quickroutes">>).

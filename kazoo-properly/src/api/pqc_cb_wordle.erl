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
-module(pqc_cb_wordle).

-export([fetch/1, fetch/2
        ,status/2
        ,guess/3
        ]).

-include("properly.hrl").

-spec fetch(pqc_cb_api:state()) -> pqc_cb_api:response().
fetch(API) ->
    fetch(API, 5).

-spec fetch(pqc_cb_api:state(), pos_integer()) -> pqc_cb_api:response().
fetch(API, WordSize) ->
    pqc_cb_crud:summary(API, wordle_url(API, WordSize)).

-spec status(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
status(API, WordId) ->
    pqc_cb_crud:fetch(API, guess_url(API, WordId)).

-spec guess(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
guess(API, WordId, Guess) ->
    Data = kz_json:from_list([{<<"guess">>, Guess}]),
    pqc_cb_crud:update(API
                      ,guess_url(API, WordId)
                      ,pqc_cb_api:create_envelope(Data)
                      ).

wordle_url(API, WordSize) ->
    pqc_cb_crud:collection_url(API, <<"wordle">>) ++ "?word_size=" ++ kz_term:to_list(WordSize).

guess_url(API, WordId) ->
    pqc_cb_crud:entity_url(API, <<"wordle">>, WordId).

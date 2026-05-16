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
-module(pqc_cb_api_auth).

-export([authenticate/2]).

-include("properly.hrl").

-spec authenticate(pqc_cb_api:state() | kz_term:text(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
authenticate(#{base_url := APIBase}, APIKey) ->
    authenticate(APIBase, APIKey);
authenticate(<<APIBase/binary>>, APIKey) ->
    authenticate(kz_term:to_list(APIBase), APIKey);
authenticate(APIBase, APIKey) ->
    Expectations = [pqc_cb_expect:code(201)],
    Data = kz_json:from_list([{<<"api_key">>, APIKey}]),
    URL = string:join([APIBase, "api_auth"], "/"),

    pqc_cb_crud:create(APIBase
                      ,URL
                      ,pqc_cb_api:create_envelope(Data)
                      ,Expectations
                      ,pqc_cb_api:default_request_headers()
                      ).

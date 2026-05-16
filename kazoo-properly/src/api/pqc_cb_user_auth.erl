%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_user_auth).

-export([by_account_name/4
        ,by_account_realm/4
        ,by_account_id/4, by_account_id/5
        ,impersonate_user/3
        ]).

-include("properly.hrl").

-spec by_account_name(pqc_cb_api:state() | string(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
by_account_name(#{base_url := [_|_]=APIBase}=API, AccountName, Username, Password) ->
    by_account_name(APIBase, AccountName, Username, Password, pqc_cb_api:request_headers(API));
by_account_name([_|_]=APIBase, AccountName, Username, Password) ->
    Expectations = [pqc_cb_expect:code(201)],
    Data = kz_json:from_list([{<<"account_name">>, AccountName}
                             ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                             ,{<<"method">>, <<"md5">>}
                             ]),
    URL = user_auth_url(APIBase),

    pqc_cb_crud:create(APIBase
                      ,URL
                      ,pqc_cb_api:create_envelope(Data)
                      ,Expectations
                      ,pqc_cb_api:default_request_headers()
                      ).

by_account_name(APIBase, AccountName, Username, Password, RequestHeaders) ->
    Expectations = [pqc_cb_expect:code(201)],
    Data = kz_json:from_list([{<<"account_name">>, AccountName}
                             ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                             ,{<<"method">>, <<"md5">>}
                             ]),
    URL = user_auth_url(APIBase),

    pqc_cb_crud:create(APIBase
                      ,URL
                      ,pqc_cb_api:create_envelope(Data)
                      ,Expectations
                      ,RequestHeaders
                      ).

-spec by_account_realm(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
by_account_realm(#{base_url := APIBase}=API, AccountRealm, Username, Password) ->
    Data = kz_json:from_list([{<<"account_realm">>, AccountRealm}
                             ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                             ,{<<"method">>, <<"md5">>}
                             ]),
    URL = user_auth_url(APIBase),

    pqc_cb_crud:create(API, URL, pqc_cb_api:create_envelope(Data)).

-spec by_account_id(pqc_cb_api:state() | string(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
by_account_id(API, AccountId, Username, Password) ->
    by_account_id(API, AccountId, Username, Password, 'undefined').

-spec by_account_id(pqc_cb_api:state() | string(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_ne_binary()) ->
          pqc_cb_api:response().
by_account_id(#{base_url := APIBase}, AccountId, Username, Password, MFAResponse) ->
    by_account_id(APIBase, AccountId, Username, Password, MFAResponse);
by_account_id(APIBase, AccountId, Username, Password, MFAResponse) ->
    Data = kz_json:from_list([{<<"account_id">>, AccountId}
                             ,{<<"credentials">>, kz_binary:md5([Username, $:, Password])}
                             ,{<<"method">>, <<"md5">>}
                             ,{<<"multi_factor_response">>, MFAResponse}
                             ]),
    URL = user_auth_url(APIBase),

    pqc_cb_crud:create(APIBase
                      ,URL
                      ,pqc_cb_api:create_envelope(Data)
                      ,[pqc_cb_expect:code(201)]
                      ,pqc_cb_api:default_request_headers()
                      ).

-spec impersonate_user(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
impersonate_user(API, AccountId, UserId) ->
    Data = kz_json:new(),
    URL = user_auth_url(API, AccountId, UserId),

    pqc_cb_crud:create(API
                      ,URL
                      ,pqc_cb_api:create_envelope(Data, kz_json:from_list([{<<"action">>, <<"impersonate_user">>}]))
                      ).

-spec user_auth_url(string() | binary()) -> string().
user_auth_url(APIBase) ->
    string:join([kz_term:to_list(APIBase), "user_auth"], "/").

-spec user_auth_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
user_auth_url(API, AccountId, UserId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"users">>, UserId) ++ "/user_auth".

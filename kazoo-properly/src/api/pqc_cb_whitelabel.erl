%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_whitelabel).

%% Manual testing
-export([summary_whitelabel/2
        ,create_whitelabel/2
        ,create_whitelabel/3
        ,update_whitelabel/3
        ,delete_whitelabel/2
        ]).

-export([summary_email/2
        ,create_email/3
        ,update_email/4
        ,update_dkim/4
        ,fetch_email/3
        ,verify_email/4
        ,delete_email/3
        ]).

-export([fetch_verification_code/2]).

-include("properly.hrl").

-spec summary_whitelabel(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary_whitelabel(API, AccountId) ->
    pqc_cb_crud:summary(API, whitelabel_url(API, AccountId)).

-spec create_whitelabel(pqc_cb_api:state(), kz_doc:setter_funs()) -> pqc_cb_api:response().
create_whitelabel(API, Setters) ->
    Envelope = pqc_cb_api:create_envelope(kz_doc:setters(kz_json:new(), Setters)),
    pqc_cb_crud:create(API
                      ,whitelabel_url(API, pqc_cb_api:auth_account_id(API))
                      ,Envelope
                      ).

-spec create_whitelabel(pqc_cb_api:state(), kz_term:ne_binary(), kzd_whitelabel:doc()) -> pqc_cb_api:response().
create_whitelabel(API, AccountId, WhitelabelJObj) ->
    Envelope = pqc_cb_api:create_envelope(WhitelabelJObj),
    pqc_cb_crud:create(API, whitelabel_url(API, AccountId), Envelope).

-spec update_whitelabel(pqc_cb_api:state(), kz_term:ne_binary(), kzd_whitelabel:doc()) -> pqc_cb_api:response().
update_whitelabel(API, AccountId, WhitelabelJObj) ->
    Envelope = pqc_cb_api:create_envelope(WhitelabelJObj),
    pqc_cb_crud:update(API, whitelabel_url(API, AccountId), Envelope).

-spec delete_whitelabel(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_whitelabel(API, AccountId) ->
    pqc_cb_crud:delete(API, whitelabel_url(API, AccountId)).

-spec summary_email(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary_email(API, AccountId) ->
    pqc_cb_crud:summary(API, emails_url(API, AccountId)).

-spec create_email(pqc_cb_api:state(), kz_term:ne_binary(), kz_json:object()) -> pqc_cb_api:response().
create_email(API, AccountId, EmailJObj) ->
    Envelope = pqc_cb_api:create_envelope(EmailJObj),
    pqc_cb_crud:create(API, emails_url(API, AccountId), Envelope).

-spec update_email(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_object())
                  -> pqc_cb_api:response().
update_email(API, AccountId, EmailId, EmailJObj) ->
    Envelope = pqc_cb_api:create_envelope(EmailJObj),
    pqc_cb_crud:update(API, email_url(API, AccountId, EmailId), Envelope).

-spec update_dkim(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), iodata())
                 -> pqc_cb_api:response().
update_dkim(API, AccountId, EmailId, Data) ->
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([200], ExpectedHeaders)],
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "application/x-pem-file"}]),
    pqc_cb_crud:update(API
                      ,email_url(API, AccountId, EmailId)
                      ,Data
                      ,Expectations
                      ,RequestHeaders
                      ).

-spec fetch_email(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_email(API, AccountId, EmailId) ->
    pqc_cb_crud:fetch(API, email_url(API, AccountId, EmailId)).

-spec verify_email(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_object())
                  -> pqc_cb_api:response().
verify_email(API, AccountId, EmailId, JObj) ->
    Envelope = pqc_cb_api:create_envelope(JObj),
    pqc_cb_crud:update(API, email_verify_url(API, AccountId, EmailId), Envelope).

-spec delete_email(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_email(API, AccountId, EmailId) ->
    pqc_cb_crud:delete(API, email_url(API, AccountId, EmailId)).

-spec fetch_verification_code(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_ne_binary().
fetch_verification_code(AccountId, EmailId) ->
    {'ok', JObj} = kz_datamgr:open_cache_doc(kzs_util:format_account_db(AccountId), EmailId),
    kzd_emails:pvt_code(JObj).

-spec whitelabel_url(pqc_cb_api:state(), string() | kz_term:ne_binary()) -> string().
whitelabel_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"whitelabel">>).

-spec emails_url(pqc_cb_api:state(), string() | kz_term:ne_binary()) -> string().
emails_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"whitelabel">>, <<"emails">>).

-spec email_url(pqc_cb_api:state(), string() | kz_term:ne_binary(), kz_term:ne_binary()) -> string().
email_url(API, AccountId, EmailId) ->
    string:join([emails_url(API, AccountId), kz_term:to_list(EmailId)], "/").

-spec email_verify_url(pqc_cb_api:state(), string() | kz_term:ne_binary(), kz_term:ne_binary()) -> string().
email_verify_url(API, AccountId, EmailId) ->
    string:join([emails_url(API, AccountId), kz_term:to_list(EmailId), "verify"], "/").

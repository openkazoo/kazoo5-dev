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
-module(pqc_cb_lists).

-export([summary/2, summary/3]).
-export([summary_by_tag/3, summary_by_tag/4]).
-export([fetch/3, fetch/4]).
-export([create/3, create/4]).
-export([update/3, update/4]).
-export([patch/4, patch/5]).
-export([delete/3, delete/4]).

-include("properly.hrl").

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    pqc_cb_crud:summary(API
                       ,lists_url(API, AccountId)
                       ).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId, UserId) ->
    pqc_cb_crud:summary(API
                       ,lists_user_url(API, AccountId, UserId)
                       ).

-spec summary_by_tag(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary_by_tag(API, AccountId, Tag) ->
    pqc_cb_crud:summary(API
                       ,lists_tag_url(API, AccountId, Tag)
                       ).

-spec summary_by_tag(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
summary_by_tag(API, AccountId, UserId, Tag) ->
    pqc_cb_crud:summary(API
                       ,lists_tag_url(API, AccountId, UserId, Tag)
                       ).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, ContactId) ->
    pqc_cb_crud:fetch(API
                     ,lists_url(API, AccountId, ContactId)
                     ).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
fetch(API, AccountId, UserId, ContactId) ->
    pqc_cb_crud:fetch(API
                     ,lists_user_url(API, AccountId, UserId, ContactId)
                     ).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kzd_contacts:doc()) -> pqc_cb_api:response().
create(API, AccountId, ContactJObj) ->
    URL = lists_url(API, AccountId),
    create_contact(API, ContactJObj, URL).

-spec create(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kzd_contacts:doc()) ->
          pqc_cb_api:response().
create(API, AccountId, UserId, ContactJObj) ->
    URL = lists_user_url(API, AccountId, UserId),
    create_contact(API, ContactJObj, URL).

-spec create_contact(pqc_cb_api:state(), kzd_contacts:doc(), string()) ->
          pqc_cb_api:response().
create_contact(API, ContactJObj, URL) ->
    ExpectedHeaders = [{"content-type", "application/json"}],
    Expectations = [pqc_cb_expect:codes_and_headers([201], ExpectedHeaders)],
    Envelope = pqc_cb_api:create_envelope(ContactJObj),
    pqc_cb_crud:create(API, URL, Envelope, Expectations).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kzd_contacts:doc()) -> pqc_cb_api:response().
update(API, AccountId, ContactJObj) ->
    URL = lists_url(API, AccountId, kz_doc:id(ContactJObj)),
    update_contact(API, ContactJObj, URL).

-spec update(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kzd_contacts:doc()) ->
          pqc_cb_api:response().
update(API, AccountId, UserId, ContactJObj) ->
    URL = lists_user_url(API, AccountId, UserId, kz_doc:id(ContactJObj)),
    update_contact(API, ContactJObj, URL).

-spec update_contact(pqc_cb_api:state(), kzd_contacts:doc(), string()) ->
          pqc_cb_api:response().
update_contact(API, ContactJObj, URL) ->
    Envelope = pqc_cb_api:create_envelope(ContactJObj),
    pqc_cb_crud:update(API, URL, Envelope).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
patch(API, AccountId, ListId, PatchJObj) ->
    URL = lists_url(API, AccountId, ListId),
    patch_contact(API, PatchJObj, URL).

-spec patch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          pqc_cb_api:response().
patch(API, AccountId, UserId, ListId, PatchJObj) ->
    URL = lists_user_url(API, AccountId, UserId, ListId),
    patch_contact(API, PatchJObj, URL).

-spec patch_contact(pqc_cb_api:state(), kz_json:object(), string()) -> pqc_cb_api:response().
patch_contact(API, PatchJObj, URL) ->
    Envelope = pqc_cb_api:create_envelope(PatchJObj),
    pqc_cb_crud:patch(API, URL, Envelope).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, ListId) ->
    pqc_cb_crud:delete(API
                      ,lists_url(API, AccountId, ListId)
                      ).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
delete(API, AccountId, UserId, ListId) ->
    pqc_cb_crud:delete(API
                      ,lists_user_url(API, AccountId, UserId, ListId)
                      ).

-spec lists_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
lists_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"lists">>).

-spec lists_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
lists_url(API, AccountId, ListId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"lists">>, ListId).

-spec lists_tag_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
lists_tag_url(API, AccountId, Tag) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"lists">>, <<"tag-", Tag/binary>>).

lists_tag_url(API, AccountId, UserId, Tag) ->
    string:join([lists_user_url(API, AccountId, UserId), kz_term:to_list(<<"tag-", Tag/binary>>)], "/").

-spec lists_user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
lists_user_url(API, AccountId, UserId) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId), "lists"], "/").

-spec lists_user_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
lists_user_url(API, AccountId, UserId, ListId) ->
    string:join([pqc_cb_users:user_url(API, AccountId, UserId), "lists", kz_term:to_list(ListId)], "/").

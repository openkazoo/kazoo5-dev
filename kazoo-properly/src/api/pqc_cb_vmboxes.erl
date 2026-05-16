%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2018-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_cb_vmboxes).

-export([new_message/5
        ,fetch_message_metadata/4
        ,fetch_message_binary/4
        ,list_messages/3, list_messages/4
        ,create_box/3
        ,delete_box/3
        ]).

-include("properly.hrl").

-spec new_message(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object(), binary()) ->
          pqc_cb_api:response().
new_message(API, AccountId, BoxId, MessageJObj, MessageBin) ->
    MessagesURL = messages_url(API, AccountId, BoxId),

    Boundary = kz_http_util:create_boundary(),
    Body = create_body(MessageJObj, MessageBin, Boundary),

    RequestHeaders = pqc_cb_api:request_headers(API
                                               ,[{"content-type", "multipart/mixed; boundary=" ++ kz_term:to_list(Boundary)}
                                                ,{"content-length", iolist_size(Body)}
                                                ]
                                               ),

    Expectations = [pqc_cb_expect:code(201)],
    pqc_cb_crud:create(API
                      ,MessagesURL
                      ,Body
                      ,Expectations
                      ,RequestHeaders
                      ).

-spec create_body(kz_json:object(), binary(), kz_term:ne_binary()) -> binary().
create_body(MessageJObj, MessageBin, Boundary) ->
    kz_http_util:encode_multipart([{kz_json:encode(pqc_cb_api:create_envelope(MessageJObj))
                                   ,[{<<"content-type">>, <<"application/json">>}]
                                   }
                                  ,{MessageBin
                                   ,[{<<"content-type">>, <<"audio/mp3">>}]
                                   }
                                  ]
                                 ,Boundary
                                 ).

-spec fetch_message_metadata(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_message_metadata(API, AccountId, BoxId, MessageId) ->
    MessageURL = message_url(API, AccountId, BoxId, MessageId),

    pqc_cb_crud:fetch(API, MessageURL).

-spec fetch_message_binary(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_message_binary(API, AccountId, BoxId, MessageId) ->
    MessageURL = message_bin_url(API, AccountId, BoxId, MessageId),

    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"accept">>, "audio/mp3"}]),

    Expectations = [pqc_cb_expect:code(200)],
    pqc_cb_crud:fetch(API, MessageURL, Expectations, RequestHeaders).

-spec list_messages(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
list_messages(API, AccountId, BoxId) ->
    list_messages(API, AccountId, BoxId, []).

-spec list_messages(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:proplist()) -> pqc_cb_api:response().
list_messages(API, AccountId, BoxId, QuerystringParams) ->
    MessagesURL = messages_url(API, AccountId, BoxId, QuerystringParams),

    pqc_cb_crud:summary(API, MessagesURL).

-spec create_box(pqc_cb_api:state(), kz_term:ne_binary(), kzd_vmboxes:doc() | kz_term:ne_binary()) ->
          pqc_cb_api:response().
create_box(API, AccountId, <<BoxName/binary>>) ->
    create_box(API, AccountId
              ,kz_json:from_list([{<<"name">>, BoxName}
                                 ,{<<"mailbox">>, BoxName}
                                 ]));
create_box(API, AccountId, Data) ->
    BoxesURL = boxes_url(API, AccountId),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "application/json"}]),

    Req = pqc_cb_api:create_envelope(Data),
    Expectations = [pqc_cb_expect:code(201)],

    pqc_cb_crud:create(API, BoxesURL, Req, Expectations, RequestHeaders).

-spec delete_box(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete_box(API, AccountId, BoxId) ->
    BoxURL = box_url(API, AccountId, BoxId),

    pqc_cb_crud:delete(API, BoxURL).

boxes_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"vmboxes">>).

box_url(API, AccountId, BoxId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"vmboxes">>, BoxId).

messages_url(API, AccountId, BoxId) ->
    messages_url(API, AccountId, BoxId, []).

messages_url(API, AccountId, BoxId, QuerystringParams) ->
    lists:flatten([string:join([box_url(API, AccountId, BoxId), "messages"], "/")
                  ,"?", kz_http_util:props_to_querystring(QuerystringParams)
                  ]).

message_url(API, AccountId, BoxId, MessageId) ->
    string:join([box_url(API, AccountId, BoxId), "messages", kz_term:to_list(MessageId)], "/").

message_bin_url(API, AccountId, BoxId, MessageId) ->
    string:join([box_url(API, AccountId, BoxId), "messages", kz_term:to_list(MessageId), "raw"], "/").

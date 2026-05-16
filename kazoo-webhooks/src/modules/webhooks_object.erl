%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%%
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(webhooks_object).

-behaviour(gen_webhook).

-export([init/0
        ,bindings_and_responders/0
        ,account_bindings/1
        ,handle_event/2
        ,handle_account_notif/2
        ,doc_keys/1
        ]).

-include("webhooks.hrl").
-include_lib("kazoo_amqp/include/kapi_conf.hrl").
-include_lib("kazoo_documents/include/doc_types.hrl").

-define(ID, kz_term:to_binary(?MODULE)).
-define(HOOK_NAME, <<"object">>).
-define(NAME, <<"Object">>).
-define(DESC, <<"Receive notifications when objects (like JSON document objects) in Kazoo are changed">>).

-define(OBJECT_TYPES
       ,kapps_config:get(?APP_NAME, <<"object_types">>, ?DOC_TYPES)
       ).

-define(TYPE_MODIFIER
       ,kz_json:from_list(
          [{<<"type">>, <<"array">>}
          ,{<<"description">>, <<"A list of object types to handle">>}
          ,{<<"items">>, [<<"all">> | ?OBJECT_TYPES]}
          ]
         )
       ).

-define(ACTIONS_MODIFIER
       ,kz_json:from_list(
          [{<<"type">>, <<"array">>}
          ,{<<"description">>, <<"A list of object actions to handle">>}
          ,{<<"items">>, [<<"all">> | ?DOC_ACTIONS]}
          ]
         )
       ).

-define(MODIFIERS
       ,kz_json:from_list(
          [{<<"type">>, ?TYPE_MODIFIER}
          ,{<<"action">>, ?ACTIONS_MODIFIER}
          ]
         )
       ).

-define(METADATA
       ,kz_json:from_list(
          [{<<"_id">>, ?ID}
          ,{<<"name">>, ?NAME}
          ,{<<"description">>, ?DESC}
          ,{<<"modifiers">>, ?MODIFIERS}
          ]
         )
       ).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = default_keys(),
    webhooks_util:init_metadata(?ID, ?METADATA).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec bindings_and_responders() -> {gen_listener:bindings(), listener_utils:responder_start_params()}.
bindings_and_responders() ->
    {bindings(), responders()}.

-spec bindings() -> gen_listener:bindings().
bindings() ->
    [{'conf', [{'restrict_to', ['doc_updates']}]}
    ,{'notifications', [{'restrict_to', ['account_deleted']}]}
    ].

-spec responders() -> listener_utils:responder_start_params().
responders() ->
    [{{?MODULE, 'handle_event'}
     ,[{<<"configuration">>, <<"*">>}]
     }
    ,{{?MODULE, 'handle_account_notif'}
     ,[{<<"notification">>, <<"account_deleted">>}]
     }
    ].

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec account_bindings(kz_term:ne_binary()) -> gen_listener:bindings().
account_bindings(_AccountId) -> [].


-spec handle_account_notif(kapi_notifications:doc(), kz_term:proplist()) -> 'ok'.
handle_account_notif(Notification, _Props) ->
    EventName = kz_api:event_name(Notification),
    EventDefinition = kapi_notifications:api_definition(EventName),
    Validate = kapi_definition:validate_fun(EventDefinition),
    'true' = Validate(Notification),

    AccountId = kapi_notifications:account_id(Notification),
    lager:info("hijacked ~s(notification) searching for hook ~s for account ~s", [EventName, ?HOOK_NAME, AccountId]),
    case webhooks_util:find_webhooks(?HOOK_NAME, AccountId) of
        [] ->
            ParentId = kz_json:get_ne_binary_value(<<"Parent-ID">>, Notification),
            lager:info("cannot get hooks from deleted Account, searching in parent ~s", [ParentId]),
            handle_account_notif(Notification, AccountId
                                ,webhooks_util:find_webhooks(?HOOK_NAME, ParentId)
                                );
        Hooks ->
            handle_account_notif(Notification, AccountId
                                ,Hooks
                                )
    end.


-spec handle_account_notif(kapi_notifications:doc(), kz_term:ne_binary(), webhooks()) -> 'ok'.
handle_account_notif(_Notification, _AccountId, []) ->
    lager:debug("hijacked ~s no hooks to handle ~s(~s) for ~s"
               ,[kz_api:event_name(_Notification), ?HOOK_NAME, ?DOC_DELETED, _AccountId]
               );
handle_account_notif(Notification, _AccountId, Hooks) ->
    EventJobj = format_account_deleted(Notification),
    Action = <<"doc_deleted">>,
    Type = <<"account">>,
    NotifName =  kz_api:event_name(Notification),

    lager:debug("event for action ~s type ~s, hijacked from notification ~s", [Action, Type, NotifName]),
    Filtered = [Hook || Hook <- Hooks, match_action_type(Hook, Action, Type)],
    webhooks_util:fire_hooks(EventJobj, Filtered).




%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(kapi_conf:doc(), kz_term:proplist()) -> 'ok'.
handle_event(DocChange, _Props) ->
    kz_log:put_callid(DocChange),

    EventName = kz_api:event_name(DocChange),

    case kapi_definition:name(kapi_conf:api_definition(<<"doc_type_update">>)) of
        EventName ->
            'true' = kapi_conf:doc_type_update_v(DocChange);
        _ ->
            'true' = kapi_conf:doc_update_v(DocChange)
    end,

    %% Ignore account doc deleted objects, hijack notifs. see KWEB-14
    case is_account_terminus(DocChange) of
        'true' -> ok;
        _ -> handle_change(DocChange)
    end.

-spec handle_change(kapi_conf:doc()) -> 'ok'.
handle_change(DocChange) ->
    case find_account_id(DocChange) of
        'undefined' -> 'ok';
        AccountId ->
            handle_account_change(DocChange, AccountId)
    end.

-spec handle_account_change(kapi_conf:doc(), kz_term:ne_binary()) -> 'ok'.
handle_account_change(DocChange, AccountId) ->
    handle_account_change(DocChange, AccountId, webhooks_util:find_webhooks(?HOOK_NAME, AccountId)).

-spec handle_account_change(kapi_conf:doc(), kz_term:ne_binary(), webhooks()) -> 'ok'.
handle_account_change(_DocChange, _AccountId, []) ->
    lager:debug("no hooks to handle ~s(~s) for ~s"
               ,[?HOOK_NAME, kz_api:event_name(_DocChange), _AccountId]
               );
handle_account_change(DocChange, AccountId, Hooks) ->
    EventJObj = format_event(DocChange, AccountId),
    V2EventJObj = format_v2_event(DocChange),

    Action = kz_api:event_name(DocChange),
    Type = kapi_conf:get_type(DocChange),

    lager:debug("event for action ~s type ~s", [Action, Type]),

    Filtered = [Hook || Hook <- Hooks, match_action_type(Hook, Action, Type)],
    webhooks_util:fire_hooks(EventJObj, V2EventJObj, Filtered).

-spec match_action_type(webhook(), kz_term:api_binary(), kz_term:api_binary()) -> boolean().
match_action_type(#webhook{hook_event = ?HOOK_NAME
                          ,custom_data='undefined'
                          }, _Action, _Type) ->
    'true';
match_action_type(#webhook{hook_event = ?HOOK_NAME
                          ,custom_data=CustomData
                          }, Action, Type) ->
    DataAction = kz_json:get_ne_binary_value(<<"action">>, CustomData),
    DataType = kz_json:get_ne_binary_value(<<"type">>, CustomData),

    match_action_type(DataAction, Action, DataType, Type);
match_action_type(#webhook{}, _Action, _Type) ->
    'true'.

-spec match_action_type(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
match_action_type(<<"all">>, _Action, <<"all">>, _Type) ->
    lager:debug("hook matches all actions and all types"),
    'true';
match_action_type(<<"all">>, _Action, Type, Type) ->
    lager:debug("hook matches all actions and type ~s", [Type]),
    'true';
match_action_type(Action, Action, <<"all">>, _Type) ->
    lager:debug("hook matches action ~s and all types", [Action]),
    'true';
match_action_type(Action, Action, Type, Type) ->
    lager:debug("hook matches action ~s and type ~s", [Action, Type]),
    'true';
match_action_type(_DataAction, _EventAction, _DataType, _EventType) ->
    lager:debug("hook action ~s =/= ~s and type ~s =/= ~s", [_DataAction, _EventAction, _DataType, _EventType]),
    'false'.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_account_terminus(kapi_conf:doc()) -> boolean().
is_account_terminus(DocChange) ->
    case {kz_api:event_name(DocChange), kapi_conf:get_type(DocChange)} of
        {<<"doc_deleted">>, <<"account">>} -> 'true';
        {_,_} -> 'false'
    end.


-spec format_account_deleted(kapi_notification:doc()) -> kz_json:object().
format_account_deleted(Notification) ->
    Doc = account_deleted_doc(Notification),
    Data = account_deleted_event_data(Doc),
    Data1 = kz_json:set_value(<<"doc">>, kz_doc:public_fields(Doc), Data),
    Data2 = kz_json:set_value(<<"metadata">>, account_deleted_metadata(Doc), Data1),
    Msg =   [{<<"action">>, <<"event">>}
            ,{<<"name">>, ?DOC_DELETED}
            ,{<<"data">>, Data2}
            ],
    kz_json:from_list(Msg).

-spec account_deleted_doc(kapi_notifications:doc()) -> kz_doc:doc().
account_deleted_doc(Notification) ->
    EventDoc = kz_json:get_ne_json_value(<<"Doc">>, Notification),
    case kzd_accounts:fetch(kapi_notifications:account_id(Notification), 'accounts') of
        {'error', Error} ->
            lager:debug("doc from hijacked notification event failed to open with error ~p, using incomplete doc", [Error]),
            kz_doc:set_deleted(EventDoc);
        {'ok', FetchedDoc} ->
            kz_json:merge(EventDoc, FetchedDoc)
    end.

-spec account_deleted_metadata(kz_doc:doc()) -> kz_json:object().
account_deleted_metadata(Doc) ->
    Props = maybe_add_extra_metadata(Doc, ?DOC_DELETED),
    kz_json:set_values(Props, kz_doc:read_only(Doc)).

-spec account_deleted_event_data(kz_doc:doc()) -> kz_json:object().
account_deleted_event_data(Doc) ->
    ConstructedEvent = kz_json:from_list([{<<"ID">>, kz_doc:id(Doc)}
                                         ,{<<"Database">>, <<"accounts">>}
                                         ,{<<"Date-Created">>, kz_doc:created(Doc)}
                                         ,{<<"Date-Modified">>, kz_doc:modified(Doc)}
                                         ,{<<"Is-Soft-Deleted">>, kz_doc:is_deleted(Doc)}
                                         ,{<<"Rev">>, kz_doc:revision(Doc)}
                                         ,{<<"Type">>, kz_doc:type(Doc)}
                                         ,{<<"Version">>, kz_doc:vsn(Doc)}
                                         ]),
    webhooks_util:sanitize_event(ConstructedEvent).



%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec format_event(kapi_conf:doc(), kz_term:ne_binary()) -> kz_json:object().
format_event(ConfChange, AccountId) ->
    DocType = kapi_conf:get_type(ConfChange),
    DocId = kapi_conf:get_id(ConfChange),

    kz_json:from_list(
      [{<<"id">>, DocId}
      ,{<<"account_id">>, AccountId}
      ,{<<"action">>, kz_api:event_name(ConfChange)}
      ,{<<"type">>, DocType}
      | meta_event_data(kz_datamgr:open_cache_doc(AccountId, DocId), DocType)
      ]).

-spec meta_event_data({'ok', kz_doc:doc()} | kz_datamgr:data_error(), kz_term:ne_binary()) ->
          kz_json:json_proplist().
meta_event_data({'error', _E}, _DocType) -> [];
meta_event_data({'ok', Doc}, DocType) ->
    {_, Props} = lists:foldl(fun add_meta_event_datum/2
                            ,{Doc, []}
                            ,doc_keys(DocType)
                            ),
    Props.

-spec add_meta_event_datum({kz_json:get_key(), kz_json:get_key()}
                          ,{kz_doc:doc(), kz_json:json_proplist()}
                          ) ->
          {kz_doc:doc(), kz_json:json_proplist()}.
add_meta_event_datum({DocKey, HookKey}, {Doc, Props}) ->
    case kz_json:get_value(DocKey, Doc) of
        'undefined' -> {Doc, Props};
        Value -> {Doc, [{HookKey, Value} | Props]}
    end.

-spec doc_keys(kz_term:ne_binary()) -> [{kz_json:get_key(), kz_json:get_key()}].
doc_keys(DocType) ->
    ConfiguredKeys = configured_keys(DocType),
    [{DocKey, maybe_remove_pvt(DocKey)} || DocKey <- ConfiguredKeys].

configured_keys(DocType) ->
    default_keys()
        ++ kapps_config:get_ne_binaries(<<?APP_NAME/binary,".",?HOOK_NAME/binary>>
                                       ,[<<"include_fields">>, DocType]
                                       ,[]
                                       ).

-spec default_keys() -> kz_term:ne_binaries().
default_keys() ->
    kapps_config:get_ne_binaries(<<?APP_NAME/binary, ".", ?HOOK_NAME/binary>>
                                ,[<<"include_fields">>, <<"default">>]
                                ,[<<"pvt_auth_account_id">>
                                 ,<<"pvt_auth_user_id">>
                                 ]
                                ).

maybe_remove_pvt(<<"_", Key/binary>>) -> Key;
maybe_remove_pvt(<<"pvt_", Key/binary>>) -> Key;
maybe_remove_pvt(Key) -> Key.

-spec format_v2_event(kapi_conf:doc()) -> kz_json:object().
format_v2_event(Event) ->
    Type = kz_api:event_name(Event),
    Msg =   [{<<"action">>, <<"event">>}
            ,{<<"name">>, Type}
            ,{<<"data">>, maybe_include_full_doc(Event, Type)}
            ],
    kz_json:from_list(Msg).

-spec maybe_include_full_doc(kapi_conf:doc(), kz_term:api_binary()) -> kz_json:object().
maybe_include_full_doc(Event, ?DOC_DELETED) ->
    kz_json:set_value(<<"metadata">>
                     ,get_event_metadata(Event)
                     ,webhooks_util:sanitize_event(Event)
                     );
maybe_include_full_doc(Event, Type) ->
    include_full_doc(Event, Type).

- spec include_full_doc(kapi_conf:doc(), kz_term:api_binary()) -> kz_json:object().
include_full_doc(Event, Type) ->
    case kz_datamgr:open_doc(kapi_conf:get_database(Event), kapi_conf:get_id(Event)) of
        {'error', Error} ->
            lager:debug("doc from ~s event failed to open with error ~p responding without doc", [Type, Error]),
            kz_json:set_value(<<"metadata">>
                             ,get_event_metadata(Event)
                             ,webhooks_util:sanitize_event(Event)
                             );
        {'ok', Doc} ->
            Prop = [{<<"doc">>, kz_doc:public_fields(Doc)}
                   ,{<<"metadata">>, get_doc_metadata(Event, Doc)}
                   ],
            kz_json:set_values(Prop, webhooks_util:sanitize_event(Event))
    end.

-spec get_doc_metadata(kapi_conf:doc(), kz_doc:doc()) -> kz_doc:doc().
get_doc_metadata(Event, Doc) ->
    Props = maybe_add_extra_metadata(Doc, kapi_conf:get_type(Event)),
    kz_json:set_values(Props, kz_doc:read_only(Doc)).

-spec maybe_add_extra_metadata(kz_doc:doc(), kz_term:ne_binary()) -> kz_json:json_proplist().
maybe_add_extra_metadata(AccountDoc, <<"account">>) ->
    [{<<"wnm_allow_additions">>, kzd_accounts:allow_number_additions(AccountDoc)}
    ,{<<"enabled">>, kzd_accounts:is_enabled(AccountDoc)}
    ,{<<"is_reseller">>, kz_services_reseller:is_reseller(kzd_accounts:id(AccountDoc))}
    ,{<<"reseller_id">>, kz_services_reseller:get_id(kzd_accounts:id(AccountDoc))}
    ,{<<"billing_mode">>, get_billing_mode(kzd_accounts:id(AccountDoc), AccountDoc)}
    ,{<<"trial_time_left">>, kzd_accounts:trial_expiration(AccountDoc)}
    ,{<<"notification_preference">>, kzd_accounts:notification_preference(AccountDoc)}
    ];
maybe_add_extra_metadata(FaxBoxDoc, <<"faxbox">>) ->
    maybe_custom_smtp_address(FaxBoxDoc) ++ maybe_smtp_email_address(FaxBoxDoc);
maybe_add_extra_metadata(UserDoc, <<"user">>) ->
    [{<<"password_expiration_timestamp">>, kzd_users:password_expiration_timestamp(UserDoc)}
    ,{<<"is_password_expired">>, kzd_users:is_password_expired(UserDoc)}
    ];
maybe_add_extra_metadata(_Doc, _DocType) ->
    [].

-spec get_billing_mode(kz_term:api_binary(), kzd_accounts:doc()) -> kz_term:ne_binary().
get_billing_mode(EventAccountId, Doc) ->
    {'ok', MasterAccountId} = kapps_util:get_master_account_id(),
    case kz_services_reseller:get_id(kzd_accounts:id(Doc)) of
        EventAccountId  -> <<"limits_only">>;
        MasterAccountId -> <<"normal">>;
        _               -> <<"manual">>
    end.

-spec maybe_custom_smtp_address(kzd_faxbox:doc()) -> kz_json:json_proplist().
maybe_custom_smtp_address(Doc) ->
    case kz_json:get_value(<<"pvt_smtp_email_address">>, Doc) of
        'undefined' -> [];
        Value -> [{<<"smtp_email_address">>, Value}]
    end.

-spec maybe_smtp_email_address(kzd_faxbox:doc()) -> kz_json:json_proplist().
maybe_smtp_email_address(Doc) ->
    case kzd_faxbox:custom_smtp_email_address(Doc) of
        'undefined' -> [];
        Value   -> [{<<"custom_smtp_email_address">>, Value}]
    end.

-spec get_event_metadata(kapi_conf:doc()) -> kz_json:object().
get_event_metadata(Event) ->
    kz_json:from_list([{<<"id">>, kapi_conf:get_id(Event)}
                      ,{<<"created">>, kz_json:get_value(<<"Date-Created">>, Event)}
                      ,{<<"modified">>, kz_json:get_value(<<"Date-Modified">>, Event)}
                      | maybe_deleted(Event)
                      ]).

-spec maybe_deleted(kapi_conf:doc()) -> kz_json:json_proplist().
maybe_deleted(Event) ->
    case kz_api:event_name(Event) =:= ?DOC_DELETED
        orelse kapi_conf:get_is_soft_deleted(Event)
    of
        'false' -> [];
        'true' -> [{<<"deleted">>, 'true'}]
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec find_account_id(kapi_conf:doc()) -> kz_term:api_ne_binary().
find_account_id(ConfChange) ->
    DB = kapi_conf:get_database(ConfChange),
    find_account_id(kzs_util:db_classification(DB), DB, kapi_conf:get_id(ConfChange)).

-spec find_account_id(atom(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_ne_binary().
find_account_id(Classification, DB, _Id)
  when Classification =:= 'account';
       Classification =:= 'modb' ->
    kzs_util:format_account_id(DB);
find_account_id('aggregate', ?KZ_ACCOUNTS_DB, Id) -> Id;
find_account_id(_, _, _) -> 'undefined'.

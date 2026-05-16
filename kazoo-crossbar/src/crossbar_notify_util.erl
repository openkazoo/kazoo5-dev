%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2025, 2600Hz
%%% @doc Provide helper functions for firing notifications based on crossbar changes
%%% @author Mark Magnusson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_notify_util).

-include("crossbar.hrl").

-export([maybe_notify_account_change/2
        ,maybe_notify_users_features_enabled/1
        ,maybe_notify_user_features_enabled/2
        ]).

-define(TELETYPE_GENERIC_FEATURES_ENABLED, <<"generic_features_enabled">>).

-spec maybe_notify_account_change(kz_json:object(), cb_context:context()) -> 'ok'.
maybe_notify_account_change(Old, Context) ->
    New = cb_context:doc(Context),
    Filter = fun({K, V}) ->
                     case kz_json:get_value(K, New) of
                         V -> 'false';
                         _ -> 'true'
                     end
             end,

    AccountId = kz_doc:id(New),
    Changed   = kz_json:filter(Filter, Old),
    Notify    = fun({K, _}) -> notify_account_change(AccountId, {K, kz_json:get_value(K, New)}, Context) end,

    kz_json:foreach(Notify, Changed).

-spec notify_account_change(kz_term:api_binary(), {kz_term:ne_binary(), kz_json:object()}, cb_context:context()) -> 'ok'.
notify_account_change(AccountId, {<<"zones">>, Zones}, _Context) ->
    lager:info("publishing zone change notification for ~p, zones: ~p", [AccountId, Zones]),
    Props = [{<<"Account-ID">>, AccountId}
            ,{<<"Zones">>, Zones}
            | kz_api:default_headers(?APP_VERSION, ?APP_NAME)
            ],
    kapps_notify_publisher:cast(Props, fun kapi_notifications:publish_account_zone_change/1);

notify_account_change(AccountId, {<<"pvt_enabled">>, IsEnabled}, Context) ->
    lager:info("account ~s enabled has changed, sending registrations flush: pvt_enable: ~p", [AccountId, IsEnabled]),
    crossbar_util:flush_registrations(Context);

notify_account_change(_Account, {_Key, _Value}, _Context) ->
    'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% Notify users if admin enabled features/applications for them
%% from Desktop Communications Integration
%% UserId: undefined - account wide, notify all account user
%% UserId: specific - only notify this user
%% @end
%%------------------------------------------------------------------------------
-spec maybe_notify_users_features_enabled(cb_context:context()) -> 'ok'.
maybe_notify_users_features_enabled(Context) ->
    maybe_notify_user_features_enabled(Context, 'undefined').

-spec maybe_notify_user_features_enabled(cb_context:context(), kz_term:api_binary()) -> 'ok'.
maybe_notify_user_features_enabled(Context, EnabledUserId) ->
    case kz_json:get_json_value(<<"enablements">>, cb_context:req_data(Context)) of
        'undefined' -> 'ok';
        EnablementsJObj ->
            has_features_enabled_notification(Context, EnabledUserId, EnablementsJObj)
    end.

-spec has_features_enabled_notification(cb_context:context(), kz_term:api_binary(), kz_json:object()) -> 'ok'.
has_features_enabled_notification(Context, EnabledUserId, EnablementsJObj) ->
    case kapi_notifications:find_publisher(?TELETYPE_GENERIC_FEATURES_ENABLED) of
        'undefined' -> 'ok';
        PublishFun when is_function(PublishFun, 1) ->
            Features = get_enabled_features(EnablementsJObj),
            AccountId = cb_context:account_id(Context),
            AdminUserId = cb_context:auth_user_id(Context),
            publish_features_enabled_notification(PublishFun, AccountId, AdminUserId, EnabledUserId, Features)
    end.

-spec publish_features_enabled_notification(kapi_definition:publish_fun(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:api_binary(), kz_term:binaries()) -> 'ok'.
publish_features_enabled_notification(_PublishFun, _AccountId, _AdminUserId, _EnabledUserId, []) -> 'ok';
publish_features_enabled_notification(PublishFun, AccountId, AdminUserId, EnabledUserId, Features) ->
    case EnabledUserId of
        'undefined' ->
            lager:info("publishing features enablements notification from admin user ~s to all account users", [AdminUserId]);
        EnabledUserId ->
            lager:info("publishing features enablements notification from admin user ~s to user ~s", [AdminUserId, EnabledUserId])
    end,
    Props = props:filter_undefined([{<<"Account-ID">>, AccountId}
                                   ,{<<"Admin-User-ID">>, AdminUserId}
                                   ,{<<"Enabled-User-ID">>, EnabledUserId}
                                   ,{<<"Features">>, Features}
                                   | kz_api:default_headers(?APP_VERSION, ?APP_NAME)
                                   ]),
    kapps_notify_publisher:cast(Props, PublishFun).

-spec get_enabled_features(kz_json:object()) -> kz_term:binaries().
get_enabled_features(EnablementsJObj) ->
    Fun = fun(Key, Value, Acc) ->
                  case kz_json:is_true(<<"enabled">>, Value, 'false') of
                      'true' -> [Key|Acc];
                      'false' -> Acc
                  end
          end,
    kz_json:foldl(Fun, [], EnablementsJObj).

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
-module(pqc_cb_services).

-export([create_service_plan/2
        ,delete_service_plan/2
        ,assign_service_plan/3
        ,available_service_plans/2
        ,summary/2
        ,cleanup/0
        ]).

-include("properly.hrl").

-spec create_service_plan(pqc_cb_api:state(), kzd_service_plan:doc()) ->
          {'ok', kzd_service_plan:doc()}.
create_service_plan(_API, ServicePlan) ->
    %% No API to add service plans to master account
    %% Doing so manually for now
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    {'ok', OldVsn} = kz_datamgr:save_doc(MasterAccountDb, ServicePlan),
    Migrate = kazoo_services_maintenance:migrate_service_plan(MasterAccountDb, OldVsn),
    {'ok', Migrate}.

-spec delete_service_plan(pqc_cb_api:state(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
delete_service_plan(_API, ServicePlanId) ->
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    kz_datamgr:del_doc(MasterAccountDb, ServicePlanId).

-spec assign_service_plan(pqc_cb_api:state(), kz_term:ne_binary() | proper_types:type(), kz_term:ne_binary()) -> pqc_cb_api:response().
assign_service_plan(API, AccountId, ServicePlanId) ->
    URL = account_service_plan_url(API, AccountId),

    RequestData = kz_json:from_list([{<<"add">>, [ServicePlanId]}]),
    RequestEnvelope = pqc_cb_api:create_envelope(RequestData),

    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:update(API, URL, RequestEnvelope, Expectations).

-spec available_service_plans(pqc_cb_api:state(), kz_term:ne_binary() | proper_types:type()) ->
          pqc_cb_api:response().
available_service_plans(API, AccountId) ->
    URL = account_service_plan_available_url(API, AccountId),
    pqc_cb_crud:fetch(API, URL).

-spec summary(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
summary(API, AccountId) ->
    URL = pqc_cb_crud:entity_url(API, AccountId, <<"services">>, <<"summary">>),
    pqc_cb_crud:fetch(API, URL).

-spec account_service_plan_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
account_service_plan_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"services">>).

-spec account_service_plan_available_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
account_service_plan_available_url(API, AccountId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"services">>, <<"available">>).

-spec cleanup() -> 'ok'.
cleanup() ->
    kazoo_services_maintenance:remove_orphaned_services(),
    kt_cleanup:cleanup_soft_deletes(<<"services">>).

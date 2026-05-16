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
-module(pqc_cb_rates).

-export([upload_rate/2, upload_csv/2
        ,upload_rates/2

        ,delete_rates_task/2
        ,delete_csv/2

        ,rate_did/3
        ,create_rate/2, create_rate/3
        ,delete_rate/2, delete_rate/3, delete_rate/4
        ,get_rate/2
        ,get_rates/1, get_rates/2
        ,get_rates_by_prefix/2, get_rates_by_prefix/3

        ,assign_service_plan/3
        ,rate_account_did/3
        ]).

-include("properly.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-spec upload_rate(pqc_cb_api:state(), kzd_rates:doc()) -> {'ok', kz_term:api_ne_binary()}.
upload_rate(API, RateDoc) ->
    upload_rates(API, [RateDoc]).

-spec upload_rates(pqc_cb_api:state(), [kzd_rates:doc()]) -> {'ok', kz_term:api_ne_binary()}.
upload_rates(API, RateDocs) when is_list(RateDocs) ->
    lager:info("uploading rates ~p", [RateDocs]),
    CSV = kz_csv:from_jobjs(kz_doc:public_fields(RateDocs, 'false')),

    upload_csv(API, CSV).

-spec upload_csv(pqc_cb_api:state(), iolist()) ->
          {'ok', kz_term:api_ne_binary()}.
upload_csv(API, CSV) ->
    CreateResp = pqc_cb_tasks:create(API, "category=rates&action=import", CSV),
    TaskId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>]
                                        ,kz_json:decode(CreateResp)
                                        ),
    _ExecResp = pqc_cb_tasks:execute(API, TaskId),

    _DelResp = wait_for_task(API, TaskId),

    {'ok', TaskId}.

-spec delete_rates_task(pqc_cb_api:state(), [kzd_rates:doc()]) -> {'ok', kz_term:api_ne_binary()}.
delete_rates_task(API, RateDocs) when is_list(RateDocs) ->
    lager:info("deleting rates ~p", [RateDocs]),
    CSV = kz_csv:from_jobjs(kz_doc:public_fields(RateDocs, 'false')),

    delete_csv(API, CSV).

-spec delete_csv(pqc_cb_api:state(), iolist()) ->
          {'ok', kz_term:api_ne_binary()}.
delete_csv(API, CSV) ->
    CreateResp = pqc_cb_tasks:create(API, "category=rates&action=delete", CSV),
    TaskId = kz_json:get_ne_binary_value([<<"metadata">>, <<"id">>]
                                        ,kz_json:decode(CreateResp)
                                        ),
    _ExecResp = pqc_cb_tasks:execute(API, TaskId),

    _DelResp = wait_for_task(API, TaskId),

    {'ok', TaskId}.

-spec assign_service_plan(pqc_cb_api:state(), kz_term:api_ne_binary() | proper_types:type(), kz_term:ne_binary()) ->
          pqc_cb_api:response().
assign_service_plan(_API, 'undefined', _RatedeckId) ->
    lager:info("no account to assign ~s to", [_RatedeckId]),
    ?FAILED_RESPONSE;
assign_service_plan(API, AccountId, RatedeckId) ->
    lager:info("attempting to assign service plan for ~s to ~s", [RatedeckId, AccountId]),
    ServicePlanId = seq_rates:service_plan_id(RatedeckId),
    pqc_cb_services:assign_service_plan(API, AccountId, ServicePlanId).

-spec rate_account_did(pqc_cb_api:state(), kz_term:api_ne_binary() | proper_types:type(), kz_term:ne_binary()) ->
          kz_term:api_number().
rate_account_did(_API, 'undefined', _DID) ->
    lager:info("account doesn't exist to rate DID ~p", [_DID]),
    ?FAILED_RESPONSE;
rate_account_did(API, AccountId, DID) ->
    lager:info("rating DID ~p against account ~p", [DID, AccountId]),
    URL = string:join([pqc_cb_crud:entity_url(API, AccountId, <<"rates">>, <<"number">>)
                      ,kz_term:to_list(DID)
                      ], "/"),
    make_rating_request(API, URL).

wait_for_task(API, TaskId) ->
    GetResp = pqc_cb_tasks:fetch(API, TaskId),
    lager:info("task ~s fetch: ~s", [TaskId, GetResp]),
    GetJObj = kz_json:decode(GetResp),

    case kz_json:get_value([<<"metadata">>, <<"status">>]
                          ,GetJObj
                          )
    of
        <<"success">> ->
            %% fetch csv
            lager:info("task fininshed: ~s", [GetResp]),
            get_csvs(API, TaskId, kz_json:get_list_value([<<"metadata">>, <<"csvs">>], GetJObj, [])),
            pqc_cb_tasks:delete(API, TaskId);
        _Status ->
            lager:info("wrong status(~s) for task in ~s", [_Status, GetResp]),
            timer:sleep(1000),
            wait_for_task(API, TaskId)
    end.

-spec create_rate(pqc_cb_api:state(), kzd_rates:doc()) -> pqc_cb_api:response().
create_rate(API, RateDoc) ->
    create_rate(API, RateDoc, ?KZ_RATES_DB).

-spec create_rate(pqc_cb_api:state(), kzd_rates:doc(), kz_term:ne_binary()) -> pqc_cb_api:response().
create_rate(API, RateDoc, RatedeckId) ->
    lager:info("creating rate ~s for ratedeck ~s", [kz_doc:id(RateDoc), RatedeckId]),
    Envelope = pqc_cb_api:create_envelope(RateDoc),
    pqc_cb_crud:create(API, rates_url() ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId), Envelope).

get_csvs(_API, _TaskId, []) -> 'ok';
get_csvs(API, TaskId, [CSV|CSVs]) ->
    _ = get_csv(API, TaskId, CSV),
    get_csvs(API, TaskId, CSVs).

get_csv(API, TaskId, CSV) ->
    FetchResp = pqc_cb_tasks:fetch_csv(API, TaskId, CSV),
    lager:info("fetching ~s(~s): ~s", [TaskId, CSV, FetchResp]).

-spec delete_rate(pqc_cb_api:state(), kz_term:ne_binary() | kzd_rates:doc()) -> pqc_cb_api:response().
delete_rate(API, Rate) ->
    delete_rate(API, Rate, 'false').

-spec delete_rate(pqc_cb_api:state(), kz_term:ne_binary() | kzd_rates:doc(), boolean()) -> pqc_cb_api:response().
delete_rate(API, <<_/binary>>=RatedeckId, ShouldSoftDelete) ->
    RateId = kz_doc:id(seq_rates:rate_doc(RatedeckId, 1.0)),
    delete_rate(API, RateId, RatedeckId, ShouldSoftDelete);
delete_rate(API, RateDoc, ShouldSoftDelete) ->
    delete_rate(API, kz_doc:id(RateDoc), kzd_rates:ratedeck_id(RateDoc), ShouldSoftDelete).

-spec delete_rate(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), boolean()) -> pqc_cb_api:response().
delete_rate(API, ID, <<_/binary>>=RatedeckId, ShouldSoftDelete) ->
    lager:info("deleting rate ~s from ~s", [ID, RatedeckId]),

    URL = rate_url(ID, RatedeckId, ShouldSoftDelete),
    Expectations = [pqc_cb_expect:codes([200, 404])],
    pqc_cb_crud:delete(API, URL, Expectations).

-spec get_rate(pqc_cb_api:state(), kzd_rates:doc()) -> pqc_cb_api:response().
get_rate(API, RateDoc) ->
    ID = kz_doc:id(RateDoc),

    lager:info("getting rate info for ~s in ~s", [ID, kzd_rates:ratedeck_id(RateDoc)]),

    URL = rate_url(ID, kzd_rates:ratedeck_id(RateDoc, ?KZ_RATES_DB)),
    Expectations = [pqc_cb_expect:codes([200,404])],
    pqc_cb_crud:fetch(API, URL, Expectations).

-spec get_rates(pqc_cb_api:state()) -> pqc_cb_api:response().
get_rates(API) ->
    get_rates(API, ?KZ_RATES_DB).

-spec get_rates(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
get_rates(API, RatedeckId) ->
    lager:info("getting rates for ratedeck ~s", [RatedeckId]),
    URL = rates_url() ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId),
    pqc_cb_crud:summary(API, URL).

-spec get_rates_by_prefix(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
get_rates_by_prefix(API, Prefix) ->
    get_rates_by_prefix(API, Prefix, ?KZ_RATES_DB).

-spec get_rates_by_prefix(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
get_rates_by_prefix(API, Prefix, RatedeckId) ->
    lager:info("getting rates for ratedeck ~s by prefix ~s", [RatedeckId, Prefix]),
    URL = rates_url()
        ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId)
        ++ "&prefix=" ++ kz_term:to_list(Prefix),

    pqc_cb_crud:summary(API, URL).

-spec rate_did(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:api_number().
rate_did(API, RatedeckId, DID) ->
    lager:info("rating DID ~s using ~s", [DID, RatedeckId]),
    URL = rate_number_url(RatedeckId, DID),

    make_rating_request(API, URL).

-spec make_rating_request(pqc_cb_api:state(), string()) -> kz_term:api_number().
make_rating_request(API, URL) ->
    Expectations = [pqc_cb_expect:codes([200, 500])],

    Resp = pqc_cb_crud:fetch(API, URL, Expectations),
    lager:info("rating response: ~s", [Resp]),
    RespJObj = kz_json:decode(Resp),
    case kz_json:get_ne_binary_value(<<"status">>, RespJObj) of
        <<"error">> -> 'undefined';
        <<"success">> ->
            Cost = kz_json:get_float_value([<<"data">>, <<"Base-Cost">>], RespJObj),
            lager:info("rate cost: ~p: ~p", [Cost, RespJObj]),
            Cost
    end.

rates_url() ->
    string:join([pqc_cb_api:v2_base_url(), "rates"], "/").

rate_number_url(RatedeckId, DID) ->
    rate_did_url(pqc_cb_api:v2_base_url(), DID) ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId).

rate_url(ID, RatedeckId) ->
    string:join([pqc_cb_api:v2_base_url(), "rates", kz_term:to_list(ID)], "/")
        ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId).

rate_url(ID, RatedeckId, 'false') ->
    rate_url(ID, RatedeckId) ++ "&should_soft_delete=false";
rate_url(ID, RatedeckId, 'true') ->
    rate_url(ID, RatedeckId).

rate_did_url(Base, DID) ->
    string:join([Base, "rates", "number", kz_term:to_list(kz_http_util:urlencode(DID))], "/").

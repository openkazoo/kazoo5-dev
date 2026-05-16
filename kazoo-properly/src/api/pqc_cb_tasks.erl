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
-module(pqc_cb_tasks).

-export([create/2, create/3
        ,create_account/3, create_account/4
        ,execute/2, execute/3
        ,fetch/2, fetch/3, fetch/4
        ,fetch_csv/3, fetch_csv/4
        ,delete/2, delete/3
        ,query/3
        ]).

-include("properly.hrl").

%%------------------------------------------------------------------------------
%% @doc Craete a noinput task
%% @end
%%------------------------------------------------------------------------------
-spec create(pqc_cb_api:state(), string()) -> pqc_cb_api:response().
create(API, QueryString) ->
    TaskURL = tasks_url(API, QueryString),
    Expectations = [pqc_cb_expect:codes([201, 404, 409])],

    pqc_cb_crud:create(API, TaskURL, <<>>, Expectations).

%%------------------------------------------------------------------------------
%% @doc Craete an input task with CSV request body
%% @end
%%------------------------------------------------------------------------------
-spec create(pqc_cb_api:state(), string(), iolist()) -> pqc_cb_api:response().
create(API, QueryString, CSV) ->
    TaskURL = tasks_url(API, QueryString),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "text/csv"}]),
    Expectations = [pqc_cb_expect:codes([201, 404, 409])],

    pqc_cb_crud:create(API, TaskURL, CSV, Expectations, RequestHeaders).

%%------------------------------------------------------------------------------
%% @doc Craete a noinput task for an account
%% @end
%%------------------------------------------------------------------------------
-spec create_account(pqc_cb_api:state(), kz_term:ne_binary(), string()) -> pqc_cb_api:response().
create_account(API, AccountId, QueryString) ->
    TaskURL = tasks_url(API, AccountId, QueryString),
    Expectations = [pqc_cb_expect:codes([201, 404, 409])],

    pqc_cb_crud:create(API, TaskURL, <<>>, Expectations).

%%------------------------------------------------------------------------------
%% @doc Craete an input task with CSV request body for an account
%% @end
%%------------------------------------------------------------------------------
-spec create_account(pqc_cb_api:state(), kz_term:ne_binary(), string(), iolist()) -> pqc_cb_api:response().
create_account(API, AccountId, QueryString, CSV) ->
    TaskURL = tasks_url(API, AccountId, QueryString),
    RequestHeaders = pqc_cb_api:request_headers(API, [{<<"content-type">>, "text/csv"}]),
    Expectations = [pqc_cb_expect:codes([201, 404, 409])],

    pqc_cb_crud:create(API, TaskURL, CSV, Expectations, RequestHeaders).

-spec execute(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
execute(API, TaskId) ->
    pqc_cb_crud:patch(API, task_url(API, TaskId)).

-spec execute(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
execute(API, AccountId, TaskId) ->
    pqc_cb_crud:patch(API, task_url(API, AccountId, TaskId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, TaskId) ->
    pqc_cb_crud:fetch(API, task_url(API, TaskId)).

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch(API, AccountId, TaskId) ->
    fetch(API, AccountId, TaskId, 'undefined').

-spec fetch(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), pqc_util:querystring() | 'undefined') ->
          pqc_cb_api:response().
fetch(API, AccountId, TaskId, QueryString) ->
    pqc_cb_crud:fetch(API, task_url(API, AccountId, TaskId, QueryString)).

-spec fetch_csv(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_csv(API, TaskId, CSV) ->
    Expectations = [pqc_cb_expect:codes_and_headers([200], [{"content-type", "text/csv"}])
                   ,pqc_cb_expect:code(204)
                   ],
    pqc_cb_crud:fetch(API
                     ,task_csv_url(API, TaskId, CSV)
                     ,Expectations
                     ,pqc_cb_api:request_headers(API, [{<<"accept">>, "text/csv"}])
                     ).

-spec fetch_csv(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
fetch_csv(API, AccountId, TaskId, CSV) ->
    Expectations = [pqc_cb_expect:codes_and_headers([200], [{"content-type", "text/csv"}])
                   ,pqc_cb_expect:code(204)
                   ],
    pqc_cb_crud:fetch(API
                     ,task_csv_url(API, AccountId, TaskId, CSV)
                     ,Expectations
                     ,pqc_cb_api:request_headers(API, [{<<"accept">>, "text/csv"}])
                     ).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, TaskId) ->
    pqc_cb_crud:delete(API, task_url(API, TaskId)).

-spec delete(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
delete(API, AccountId, TaskId) ->
    pqc_cb_crud:delete(API, task_url(API, AccountId, TaskId)).

-spec query(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> pqc_cb_api:response().
query(API, Category, Action) ->
    TaskURL = tasks_url(API, ["category=", kz_term:to_list(Category)
                             ,"&action=", kz_term:to_list(Action)
                             ]
                       ),
    pqc_cb_crud:delete(API, TaskURL).

-spec task_csv_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
task_csv_url(API, TaskId, CSV) ->
    task_url(API, TaskId) ++ "?csv_name=" ++ kz_term:to_list(CSV).

-spec task_csv_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          string().
task_csv_url(API, AccountId, TaskId, CSV) ->
    task_url(API, AccountId, TaskId) ++ "?csv_name=" ++ kz_term:to_list(CSV).

-spec task_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
task_url(API, TaskId) ->
    pqc_cb_crud:entity_url(API, <<"tasks">>, TaskId).

-spec task_url(pqc_cb_api:state(), kz_term:ne_binary(), kz_term:ne_binary()) -> string().
task_url(API, AccountId, TaskId) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"tasks">>, TaskId).

task_url(API, AccountId, TaskId, 'undefined') ->
    task_url(API, AccountId, TaskId);
task_url(API, AccountId, TaskId, QueryString) ->
    task_url(API, AccountId, TaskId) ++
        [$? | pqc_util:to_querystring(QueryString)].

-spec tasks_url(pqc_cb_api:state(), iolist()) -> iolist().
tasks_url(API, QueryString) ->
    pqc_cb_crud:collection_url(API, <<"tasks">>) ++ [$? | QueryString].

-spec tasks_url(pqc_cb_api:state(), kz_term:ne_binary(), iolist()) -> iolist().
tasks_url(API, AccountId, QueryString) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"tasks">>) ++ [$? | QueryString].

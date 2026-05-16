%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2013-2025, 2600Hz
%%% @doc Handle rolling over presence at the start of the month
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(kt_presence_rollover).

%% behaviour: tasks_provider

-export([init/0]).

%% Triggerables
-export([handle_req/0]).

-export([rollover_accounts/2]).

-include("tasks.hrl").

-define(MOD_CAT, <<(?CONFIG_CAT)/binary, ".presence_rollover">>).

-spec init() -> 'ok'.
init() ->
    _ = tasks_bindings:bind(?TRIGGER_DAILY, ?MODULE, 'handle_req').

-spec handle_req() -> 'ok'.
handle_req() ->
    handle_req(erlang:date()).

-spec handle_req(kz_time:date()) -> 'ok'.
handle_req({Year, Month, 1}) ->
    _P = kz_process:spawn(fun rollover_accounts/2, [Year, Month]),
    lager:info("its a new month ~p-~p, rolling over presence in ~p", [Year, Month, _P]);
handle_req({_Year, _Month, _Day}) -> 'ok'.

-spec rollover_accounts(kz_time:year(), kz_time:month()) -> 'ok'.
rollover_accounts(Year, Month) ->
    rollover_accounts(Year, Month, get_page('undefined')).

-spec rollover_accounts(kz_time:year(), kz_time:month(), kz_datamgr:paginated_results()) -> 'ok'.
rollover_accounts(Year, Month, {'ok', Accounts, 'undefined'}) ->
    _ = [kzd_presence:rollover(kz_doc:id(Account), Year, Month) || Account <- Accounts],
    lager:info("finished rolling over accounts");
rollover_accounts(Year, Month, {'ok', Accounts, NextPageKey}) ->
    _ = [kzd_presence:rollover(kz_doc:id(Account), Year, Month) || Account <- Accounts],
    rollover_accounts(Year, Month, get_page(NextPageKey));
rollover_accounts(_Year, _Month, {'error', _E}) ->
    lager:error("failed to query account listing during rollover: ~p", [_E]).

-spec get_page(kz_json:api_json_term()) -> kz_datamgr:paginated_results().
get_page(NextStartKey) ->
    get_page(NextStartKey, kapps_config:get_integer(?MOD_CAT, <<"rollover_in_parallel">>, 10)).

-spec get_page(kz_json:api_json_term(), pos_integer()) -> kz_datamgr:paginated_results().
get_page('undefined', PageSize) ->
    query([{'page_size', PageSize}]);
get_page(NextStartKey, PageSize) ->
    query([{'startkey', NextStartKey}
          ,{'page_size', PageSize}
          ]).

-spec query(kz_datamgr:view_options()) -> kz_datamgr:paginated_results().
query(ViewOptions) ->
    kz_datamgr:paginate_results(?KZ_ACCOUNTS_DB
                               ,<<"accounts/listing_by_id">>
                               ,ViewOptions
                               ).

%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(pqc_ips).
-behaviour(proper_statem).

-export([command/1
        ,initial_state/0
        ,next_state/3
        ,postcondition/3
        ,precondition/2

        ,correct/0
        ,correct_parallel/0
        ]).

-export_type([dedicated/0]).

-define(ACCOUNT_NAMES, [<<?MODULE_STRING>>]).
-define(DEDICATED_IPS, [?DEDICATED(<<"1.2.3.4">>, <<"a.host.com">>, <<"zone-1">>)]).

-include_lib("proper/include/proper.hrl").
-include("properly.hrl").

-elvis([{elvis_style, no_debug_call, disable}]).

-type dedicated() :: #dedicated{}.

-spec command(any()) -> proper_types:type().
command(Model) ->
    command(Model, pqc_kazoo_model:has_accounts(Model)).

command(Model, 'false') ->
    AccountName = account_name(),
    pqc_accounts:command(Model, AccountName);
command(Model, 'true') ->
    API = pqc_kazoo_model:api(Model),

    AccountName = account_name(),
    AccountId = pqc_accounts:symbolic_account_id(Model, AccountName),

    oneof([{'call', ?MODULE, 'list_ips', [API]}
          ,{'call', ?MODULE, 'assign_ips', [API, AccountId, ips()]}
          ,{'call', ?MODULE, 'remove_ip', [API, AccountId, ip()]}
          ,{'call', ?MODULE, 'fetch_ip', [API, AccountId, ip()]}
          ,{'call', ?MODULE, 'assign_ip', [API, AccountId, ip()]}
          ,{'call', ?MODULE, 'fetch_hosts', [API]}
          ,{'call', ?MODULE, 'fetch_zones', [API]}
          ,{'call', ?MODULE, 'fetch_assigned', [API, AccountId]}
          ,{'call', ?MODULE, 'create_ip', [API, ip()]}
          ,{'call', ?MODULE, 'delete_ip', [API, ip()]}
          ]
         ).

account_name() ->
    oneof(?ACCOUNT_NAMES).

ip() ->
    oneof(?DEDICATED_IPS).

ips() ->
    non_empty(ip()).

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    API = pqc_cb_api:authenticate(),
    ?INFO("state initialized to ~p", [API]),
    pqc_kazoo_model:new(API).

-spec next_state(pqc_kazoo_model:model(), any(), any()) -> pqc_kazoo_model:model().
next_state(Model, APIResp, {'call', _, 'create_account', _Args}=Call) ->
    pqc_accounts:next_state(Model, APIResp, Call);
next_state(Model, _APIResp, {'call', ?MODULE, 'list_ips', [_API]}) ->
    Model;
next_state(Model, _APIResp, {'call', ?MODULE, 'assign_ips', [_API, AccountId, Dedicateds]}) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_account_exist/2, [AccountId]}
                           ,{fun do_dedicated_ips_exist/2, [Dedicateds]}
                           ,{fun are_dedicated_ips_unassigned/2, [Dedicateds]}
                           ,{fun assign_dedicated_ips/3, [AccountId, Dedicateds]}
                           ]
                          );
next_state(Model, _APIResp, {'call', ?MODULE, 'remove_ip', [_API, AccountId, ?DEDICATED(IP, _, _)]}) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_account_exist/2, [AccountId]}
                           ,{fun pqc_kazoo_model:does_ip_exist/2, [IP]}
                           ,{fun pqc_kazoo_model:is_ip_assigned/3, [AccountId, IP]}
                           ,{fun pqc_kazoo_model:unassign_dedicated_ip/2, [IP]}
                           ]
                          );
next_state(Model, _APIResp, {'call', ?MODULE, 'fetch_ip', [_API, _AccountId, _Dedicated]}) ->
    Model;
next_state(Model, _APIResp, {'call', ?MODULE, 'assign_ip', [_API, AccountId, ?DEDICATED(IP, _, _)]}) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_account_exist/2, [AccountId]}
                           ,{fun pqc_kazoo_model:does_ip_exist/2, [IP]}
                           ,{fun pqc_kazoo_model:is_ip_unassigned/2, [IP]}
                           ,{fun pqc_kazoo_model:assign_dedicated_ip/3, [AccountId, IP]}
                           ]
                          );
next_state(Model, _APIResp, {'call', ?MODULE, 'fetch_hosts', [_API]}) ->
    Model;
next_state(Model, _APIResp, {'call', ?MODULE, 'fetch_zones', [_API]}) ->
    Model;
next_state(Model, _APIResp, {'call', ?MODULE, 'fetch_assigned', [_API, _AccountId]}) ->
    Model;
next_state(Model, _APIResp, {'call', ?MODULE, 'create_ip', [_API, ?DEDICATED(IP, Host, Zone)]}) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:is_ip_missing/2, [IP]}
                           ,{fun pqc_kazoo_model:add_dedicated_ip/4, [IP, Host, Zone]}
                           ]
                          );
next_state(Model, _APIResp, {'call', ?MODULE, 'delete_ip', [_API, ?DEDICATED(IP, _Host, _Zone)]}) ->
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_ip_exist/2, [IP]}
                           ,{fun pqc_kazoo_model:remove_dedicated_ip/2, [IP]}
                           ]
                          ).

-spec precondition(pqc_kazoo_model:model(), any()) -> boolean().
precondition(_Model, _Call) -> 'true'.

-spec postcondition(pqc_kazoo_model:model(), any(), any()) -> boolean().
postcondition(Model, {'call', _, 'create_account', _Args}=Call, APIResult) ->
    pqc_accounts:postcondition(Model, Call, APIResult);
postcondition(Model, {'call', ?MODULE, 'list_ips', [_API]}, {'ok', []}) ->
    [] =:= pqc_kazoo_model:dedicated_ips(Model);
postcondition(Model, {'call', ?MODULE, 'list_ips', [_API]}, {'ok', ListedIPs}) ->
    are_all_ips_listed(pqc_kazoo_model:dedicated_ips(Model), ListedIPs, 'false');
postcondition(Model, {'call', ?MODULE, 'list_ips', [_API]}, {'error', 'not_found'}) ->
    [] =:= pqc_kazoo_model:dedicated_ips(Model);

postcondition(Model
             ,{'call', ?MODULE, 'assign_ips', [_API, AccountId, Dedicateds]}
             ,{'ok', ListedIPs}
             ) ->
    lists:all(fun({IP, IPInfo}) ->
                      not is_ip_listed(IP, IPInfo, ListedIPs)
              end
             ,pqc_kazoo_model:account_ips(Model, AccountId)
             )
        andalso all_requested_are_listed(AccountId, Dedicateds, ListedIPs);
postcondition(_Model
             ,{'call', ?MODULE, 'assign_ips', [_API, _AccountId, _Dedicateds]}
             ,{'error', 'not_found'}
             ) -> 'true';
postcondition(Model
             ,{'call', ?MODULE, 'remove_ip', [_API, AccountId, ?DEDICATED(IP, Host, Zone)]}
             ,{'ok', RemovedIP}
             ) ->
    pqc_kazoo_model:is_ip_assigned(Model, AccountId, IP)
        andalso IP =:= kz_json:get_ne_binary_value(<<"ip">>, RemovedIP)
        andalso Host =:= kz_json:get_ne_binary_value(<<"host">>, RemovedIP)
        andalso Zone =:= kz_json:get_ne_binary_value(<<"zone">>, RemovedIP)
        andalso 'true' =:= kz_json:is_true([<<"_read_only">>, <<"deleted">>], RemovedIP);
postcondition(Model
             ,{'call', ?MODULE, 'remove_ip', [_API, AccountId, ?DEDICATED(IP, _Host, _Zone)]}
             ,{'error', 'not_found'}
             ) ->
    not pqc_kazoo_model:is_ip_assigned(Model, AccountId, IP);
postcondition(Model, {'call', ?MODULE, 'fetch_ip', [_API, AccountId, ?DEDICATED(IP, _Host, _Zone)=Dedicated]}, {'ok', FetchedIP}) ->
    pqc_kazoo_model:is_ip_assigned(Model, AccountId, IP)
        andalso is_assigned(AccountId, Dedicated, FetchedIP);
postcondition(Model, {'call', ?MODULE, 'fetch_ip', [_API, AccountId, ?DEDICATED(IP, _Host, _Zone)]}, {'error', 'not_found'}) ->
    not pqc_kazoo_model:is_ip_assigned(Model, AccountId, IP);
postcondition(Model, {'call', ?MODULE, 'assign_ip', [_API, AccountId, ?DEDICATED(_, _, _)=Dedicated]}, {'ok', AssignedIP}) ->
    lists:all(fun({IP, IPInfo}) ->
                      not is_ip_listed(IP, IPInfo, [AssignedIP])
              end
             ,pqc_kazoo_model:account_ips(Model, AccountId)
             )
        andalso all_requested_are_listed(AccountId, [Dedicated], [AssignedIP]);
postcondition(_Model, {'call', ?MODULE, 'assign_ip', [_API, _AccountId, _Dedicated]}, {'error', 'not_found'}) -> 'true';
postcondition(Model, {'call', ?MODULE, 'fetch_zones', [_API]}, {'ok', Zones}) ->
    lists:usort(Zones) =:= lists:usort(pqc_kazoo_model:dedicated_zones(Model));
postcondition(Model, {'call', ?MODULE, 'fetch_zones', [_API]}, {'error', 'not_found'}) ->
    [] =:= pqc_kazoo_model:dedicated_zones(Model);
postcondition(Model, {'call', ?MODULE, 'fetch_hosts', [_API]}, {'ok', Hosts}) ->
    lists:usort(Hosts) =:= lists:usort(pqc_kazoo_model:dedicated_hosts(Model));
postcondition(Model, {'call', ?MODULE, 'fetch_hosts', [_API]}, {'error', 'not_found'}) ->
    [] =:= pqc_kazoo_model:dedicated_hosts(Model);

postcondition(_Model, {'call', ?MODULE, 'fetch_assigned', [_API, 'undefined']}, {'error', 'not_found'}) ->
    'true';
postcondition(Model, {'call', ?MODULE, 'fetch_assigned', [_API, AccountId]}, {'ok', []}) ->
    [] =:= pqc_kazoo_model:account_ips(Model, AccountId);
postcondition(Model, {'call', ?MODULE, 'fetch_assigned', [_API, AccountId]}, {'ok', ListedIPs}) ->
    lists:all(fun({IP, IPInfo}) ->
                      is_ip_listed(IP, IPInfo, ListedIPs)
              end
             ,pqc_kazoo_model:account_ips(Model, AccountId)
             );
postcondition(Model, {'call', ?MODULE, 'fetch_assigned', [_API, AccountId]}, {'error', 'not_found'}) ->
    [] =:= pqc_kazoo_model:account_ips(Model, AccountId);
postcondition(Model, {'call', ?MODULE, 'create_ip', [_API, ?DEDICATED(IP, _, _)]}, {'ok', _CreatedIP}) ->
    'undefined' =:= pqc_kazoo_model:dedicated_ip(Model, IP);
postcondition(Model, {'call', ?MODULE, 'create_ip', [_API, ?DEDICATED(IP, _, _)]}, {'error', 'conflict'}) ->
    'undefined' =/= pqc_kazoo_model:dedicated_ip(Model, IP);
postcondition(Model, {'call', ?MODULE, 'delete_ip', [_API, ?DEDICATED(IP, _, _)]}, {'ok', _Deleted}) ->
    'undefined' =/= pqc_kazoo_model:dedicated_ip(Model, IP);
postcondition(Model, {'call', ?MODULE, 'delete_ip', [_API, ?DEDICATED(IP, _, _)]}, {'error', 'not_found'}) ->
    'undefined' =:= pqc_kazoo_model:dedicated_ip(Model, IP).

-spec correct() -> any().
correct() ->
    ?FORALL(Cmds
           ,commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   timer:sleep(1000),
                   try run_commands(?MODULE, Cmds) of
                       {History, Model, Result} ->
                           _ = seq_ips:cleanup(pqc_kazoo_model:api(Model)),
                           ?WHENFAIL(io:format("Final Model:~n~p~n~nFailing Cmds:~n~p~n"
                                              ,[pqc_kazoo_model:pp(Model), zip(Cmds, History)]
                                              )
                                    ,aggregate(command_names(Cmds), Result =:= 'ok')
                                    )
                   catch
                       ?STACKTRACE(_E, _R, ST)
                       io:format("exception running commands: ~s:~p~n", [_E, _R]),
                       [io:format("~p~n", [S]) || S <- ST],
                       _ = seq_ips:cleanup(),
                       'false'
                       end

               end
              )
           ).

-spec correct_parallel() -> any().
correct_parallel() ->
    ?FORALL(Cmds
           ,parallel_commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   {Sequential, Parallel, Result} = run_parallel_commands(?MODULE, Cmds),
                   _ = seq_ips:cleanup(),

                   ?WHENFAIL(io:format("S: ~p~nP: ~p~n", [Sequential, Parallel])
                            ,aggregate(command_names(Cmds), Result =:= 'ok')
                            )
               end
              )
           ).

%%% Helpers
-spec do_dedicated_ips_exist(pqc_kazoo_model:model(), [dedicated()]) ->
          boolean().
do_dedicated_ips_exist(Model, Dedicateds) ->
    lists:all(fun(?DEDICATED(IP, _, _)) -> pqc_kazoo_model:does_ip_exist(Model, IP) end
             ,Dedicateds
             ).

-spec are_dedicated_ips_unassigned(pqc_kazoo_model:model(), [dedicated()]) ->
          boolean().
are_dedicated_ips_unassigned(Model, Dedicateds) ->
    lists:all(fun(?DEDICATED(IP, _, _)) -> pqc_kazoo_model:is_ip_unassigned(Model, IP) end
             ,Dedicateds
             ).

-spec assign_dedicated_ips(pqc_kazoo_model:model(), seq_accounts:account_id(), [dedicated()]) ->
          pqc_kazoo_model:model().
assign_dedicated_ips(Model, AccountId, Dedicateds) ->
    lists:foldl(fun(?DEDICATED(IP, _, _), Mdl) ->
                        pqc_kazoo_model:assign_dedicated_ip(Mdl, AccountId, IP)
                end
               ,Model
               ,Dedicateds
               ).

-spec are_all_ips_listed([{kz_term:ne_binary(), pqc_kazoo_model:dedicated_ip()}], kz_json:objects(), boolean()) ->
          boolean().
are_all_ips_listed([], [], _CheckHost) -> 'true';
are_all_ips_listed(_ModelIPs, [], _CheckHost) -> 'false';
are_all_ips_listed([], _ListedIPs, _CheckHost) -> 'false';
are_all_ips_listed(ModelIPs, ListedIPs, CheckHost) ->
    lists:all(fun({IP, IPInfo}) ->
                      is_ip_listed(IP, IPInfo, ListedIPs, CheckHost)
              end
             ,ModelIPs
             ).

-spec is_ip_listed(kz_term:ne_binary(), pqc_kazoo_model:dedicated_ip(), kz_json:objects()) ->
          boolean().
is_ip_listed(IP, IPInfo, ListedIPs) ->
    is_ip_listed(IP, IPInfo, ListedIPs, 'true').

is_ip_listed(IP, IPInfo, ListedIPs, CheckHost) ->
    Host = maps:get('host', IPInfo, 'undefined'),
    Zone = maps:get('zone', IPInfo, 'undefined'),

    lists:any(fun(ListedIP) ->
                      IP =:= kz_json:get_ne_binary_value(<<"ip">>, ListedIP)
                          andalso Zone =:= kz_json:get_ne_binary_value(<<"zone">>, ListedIP)
                          andalso (CheckHost =:= 'false'
                                   orelse Host =:= kz_json:get_ne_binary_value(<<"host">>, ListedIP)
                                  )
              end
             ,ListedIPs
             ).

-spec all_requested_are_listed(kz_term:ne_binary(), [dedicated()], kz_json:objects()) -> boolean().
all_requested_are_listed(AccountId, Dedicateds, ListedIPs) ->
    [] =:= lists:foldl(fun(ListedIP, Ds) ->
                               IP = kz_json:get_ne_binary_value(<<"ip">>, ListedIP),

                               case lists:keytake(IP, #dedicated.ip, Dedicateds) of
                                   'false' -> Ds;
                                   {'value', D, Ds1} ->
                                       case is_assigned(AccountId, D, ListedIP) of
                                           'true' -> Ds1;
                                           'false' -> Ds
                                       end
                               end
                       end
                      ,Dedicateds
                      ,ListedIPs
                      ).

-spec is_assigned(kz_term:ne_binary(), dedicated(), kz_json:object()) -> boolean().
is_assigned(AccountId, ?DEDICATED(DIP, DHost, DZone), ListedIP) ->
    IP = kz_json:get_ne_binary_value(<<"ip">>, ListedIP),
    Host = kz_json:get_ne_binary_value(<<"host">>, ListedIP),
    Zone = kz_json:get_ne_binary_value(<<"zone">>, ListedIP),
    AssignedTo = kz_json:get_ne_binary_value(<<"assigned_to">>, ListedIP),
    Status = kz_json:get_ne_binary_value(<<"status">>, ListedIP),

    AccountId =:= AssignedTo
        andalso <<"assigned">> =:= Status
        andalso IP =:= DIP
        andalso Host =:= DHost
        andalso Zone =:= DZone.

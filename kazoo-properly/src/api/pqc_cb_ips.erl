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
-module(pqc_cb_ips).

%% Crossbar API requests
-export([list_ips/1
        ,assign_ips/3
        ,remove_ip/3
        ,fetch_ip/3
        ,assign_ip/3
        ,fetch_hosts/1
        ,fetch_zones/1
        ,fetch_assigned/2
        ,create_ip/2
        ,delete_ip/2
        ]).

-export([ips_url/1, ips_url/2]).

-include("properly.hrl").

-spec ips_url(pqc_cb_api:state()) -> string().
ips_url(API) ->
    pqc_cb_crud:collection_url(API, <<"ips">>).

-spec ips_url(pqc_cb_api:state(), seq_accounts:account_id()) -> string().
ips_url(API, AccountId) ->
    pqc_cb_crud:collection_url(API, AccountId, <<"ips">>).

-spec ip_url(pqc_cb_api:state(), kz_term:ne_binary()) -> string().
ip_url(API, IP) ->
    pqc_cb_crud:entity_url(API, <<"ips">>, IP).

-spec ip_url(pqc_cb_api:state(), seq_accounts:account_id(), kz_term:ne_binary()) -> string().
ip_url(API, AccountId, IP) ->
    pqc_cb_crud:entity_url(API, AccountId, <<"ips">>, IP).

-spec list_ips(pqc_cb_api:state()) ->
          {'ok', kz_json:objects()} |
          {'error', 'not_found'}.
list_ips(API) ->
    case pqc_cb_crud:summary(API, ips_url(API)) of
        {'error', _E} ->
            lager:debug("listing IPs errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            lager:debug("listing IPs: ~s", [Response]),
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec assign_ips(pqc_cb_api:state(), seq_accounts:account_id(), [pqc_ips:dedicated()]) ->
          {'ok', kz_json:objects()} |
          {'error', 'not_found'}.
assign_ips(_API, 'undefined', _Dedicateds) ->
    {'error', 'not_found'};
assign_ips(API, AccountId, Dedicateds) ->
    IPs = [IP || ?DEDICATED(IP, _, _) <- Dedicateds],
    Envelope = pqc_cb_api:create_envelope(IPs),
    case pqc_cb_crud:update(API, ips_url(API, AccountId), Envelope) of
        {'error', _E} ->
            lager:debug("assigning IPs errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.


-spec remove_ip(pqc_cb_api:state(), seq_accounts:account_id(), pqc_ips:dedicated()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
remove_ip(_API, 'undefined', _Dedicated) ->
    {'error', 'not_found'};
remove_ip(API, AccountId, ?DEDICATED(IP, _, _)) ->
    case pqc_cb_crud:delete(API, ip_url(API, AccountId, IP), [pqc_cb_expect:codes([200, 404])]) of
        {'error', _E} ->
            lager:debug("removing IP errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_json_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch_ip(pqc_cb_api:state(), seq_accounts:account_id(), pqc_ips:dedicated()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
fetch_ip(_API, 'undefined', _Dedicated) ->
    {'error', 'not_found'};
fetch_ip(API, AccountId, ?DEDICATED(IP, _, _)) ->
    case pqc_cb_crud:fetch(API, ip_url(API, AccountId, IP)) of
        {'error', _E} ->
            lager:debug("fetching IP errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_json_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec assign_ip(pqc_cb_api:state(), seq_accounts:account_id(), pqc_ips:dedicated()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
assign_ip(_API, 'undefined', _Dedicated) ->
    {'error', 'not_found'};
assign_ip(API, AccountId, ?DEDICATED(IP, _, _)) ->
    Envelope = pqc_cb_api:create_envelope(kz_json:new()),
    case pqc_cb_crud:update(API, ip_url(API, AccountId, IP), Envelope) of
        {'error', _E} ->
            lager:debug("assigning IP errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_json_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch_hosts(pqc_cb_api:state()) ->
          {'ok', kz_term:ne_binaries()} |
          {'error', 'not_found'}.
fetch_hosts(API) ->
    case pqc_cb_crud:fetch(API, ip_url(API, <<"hosts">>)) of
        {'error', _E} ->
            lager:debug("fetch hosts errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch_zones(pqc_cb_api:state()) ->
          {'ok', kz_term:ne_binaries()} |
          {'error', 'not_found'}.
fetch_zones(API) ->
    case pqc_cb_crud:fetch(API, ip_url(API, <<"zones">>)) of
        {'error', _E} ->
            lager:debug("fetch zones errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec fetch_assigned(pqc_cb_api:state(), seq_accounts:account_id()) ->
          {'ok', kz_json:objects()} |
          {'error', 'not_found'}.
fetch_assigned(_API, 'undefined') ->
    {'error', 'not_found'};
fetch_assigned(API, AccountId) ->
    case pqc_cb_crud:fetch(API, ip_url(API, AccountId, <<"assigned">>)) of
        {'error', _E} ->
            lager:debug("fetch zones errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            {'ok', kz_json:get_list_value(<<"data">>, kz_json:decode(Response))}
    end.

-spec create_ip(pqc_cb_api:state(), pqc_ips:dedicated()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found' | 'conflict'}.
create_ip(API, ?DEDICATED(IP, Host, Zone)) ->
    Data = kz_json:from_list([{<<"ip">>, IP}
                             ,{<<"host">>, Host}
                             ,{<<"zone">>, Zone}
                             ]),
    Envelope = pqc_cb_api:create_envelope(Data),
    case pqc_cb_crud:create(API, ips_url(API), Envelope, [pqc_cb_expect:codes([201, 409])]) of
        {'error', _E} ->
            lager:debug("create ip errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            JObj = kz_json:decode(Response),
            case kz_json:get_integer_value(<<"error">>, JObj) of
                'undefined' ->
                    {'ok', kz_json:get_json_value([<<"metadata">>], JObj)};
                409 ->
                    {'error', 'conflict'}
            end
    end.

-spec delete_ip(pqc_cb_api:state(), pqc_ips:dedicated()) ->
          {'ok', kz_json:object()} |
          {'error', 'not_found'}.
delete_ip(API, ?DEDICATED(IP, _Host, _Zone)) ->
    case pqc_cb_crud:delete(API, ip_url(API, IP), [pqc_cb_expect:codes([200, 404])]) of
        {'error', _E} ->
            lager:debug("delete ip errored: ~p", [_E]),
            {'error', 'not_found'};
        Response ->
            JObj = kz_json:decode(Response),
            case kz_json:get_integer_value(<<"error">>, JObj) of
                404 -> {'error', 'not_found'};
                _ -> {'ok', kz_json:get_list_value(<<"data">>, JObj)}
            end
    end.

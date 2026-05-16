%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_devices_utils_tests).
-include_lib("eunit/include/eunit.hrl").

extract_ip_test_() ->
    Test = fun(CIDRs) -> cb_devices_utils:extract_ip(<<>>, CIDRs, []) end,
    Expected = fun(IP) -> kz_json:from_list([{<<"ip">>, [IP]}]) end,
    ManyIPs = [<<"192.168.1.70/32">>, <<"192.168.1.71/32">>, <<"192.168.1.72/32">>],

    SingleCIDR = build_value([<<"192.168.1.69/32">>]),
    ManyCIDRs = build_value(ManyIPs),

    ResultManyCIDRs = Test(ManyCIDRs),

    [{"When only 1 IP is provided, it should return a 1 element's list"
     ,?_assertEqual([Expected(<<"192.168.1.69/32">>)], Test(SingleCIDR))
     }
    ,{"When N IPs are provided, it should return a N element's list"
     ,[?_assertEqual(length(ManyIPs), length(ResultManyCIDRs))
      | [?_assert(lists:member(Expected(IP), ResultManyCIDRs)) || IP <- ManyIPs]
      ]
     }
    ].

-spec build_value(kz_term:ne_binaries()) -> kz_json:object().
build_value(CIDRs) ->
    kz_json:from_list([{<<"type">>, <<"allow">>}
                      ,{<<"network-list-name">>, <<"authoritative">>}
                      ,{<<"cidr">>, CIDRs}
                      ,{<<"ports">>, [5060, 7000]}
                      ]).

%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(api_resource_tests).

-ifdef(PROPER).
-include_lib("proper/include/proper.hrl").
-endif.

-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

get_range_test_() ->
    FullBinary = <<"abcdefg">>,
    [?_assertEqual({<<"a">>, 0, 0, 1, 7}, api_resource:get_range(FullBinary, <<"bytes=0-0">>))
    ,?_assertEqual({<<"bcd">>, 1, 3, 3, 7}, api_resource:get_range(FullBinary, <<"bytes=1-3">>))
    ,?_assertEqual({<<"g">>, 6, 6, 1, 7}, api_resource:get_range(FullBinary, <<"bytes=6-6">>))
    ,?_assertEqual({FullBinary, 0, 6, 7, 7}, api_resource:get_range(FullBinary, <<"bytes=0-6">>))
     %% Invalid should give full size
    ,?_assertEqual({FullBinary, 0, 6, 7, 7}, api_resource:get_range(FullBinary, <<"bytes=0-9">>))
    ,?_assertEqual({FullBinary, 0, 6, 7, 7}, api_resource:get_range(FullBinary, <<>>))
    ].

-ifdef(PROPER).

proper_test_() ->
    {"Runs " ?MODULE_STRING " PropEr tests"
    ,[{'timeout'
      ,10 * ?MILLISECONDS_IN_SECOND
      ,{kz_term:to_list(F)
       ,fun () ->
                ?assert(proper:quickcheck(?MODULE:F(), [{'to_file', 'user'}
                                                       ,{'numtests', 500}
                                                       ]))
        end
       }
      }
      || {F, 0} <- ?MODULE:module_info('exports'),
         F > 'prop_',
         F < 'prop`'
     ]
    }.

prop_generate_etag() ->
    Setup = fun() ->
                    meck:new('api_util'),
                    meck:expect('api_util', 'create_event_name', fun (_, _) -> <<>> end),

                    meck:new('crossbar_bindings'),
                    meck:expect('crossbar_bindings', 'fold', fun (_, Payload) -> Payload end),

                    fun cleanup/0
            end,

    ?SETUP(
       Setup
      ,?FORALL(
          {RespETag, Envelope}
         ,{cb_context:resp_etag(), resize(10, kz_json_generators:deep_object())}
         ,begin
              meck:expect('api_util', 'create_resp_envelope', fun (_) -> Envelope end),

              Context = cb_context:set_resp_etag(cb_context:new(), RespETag),
              Ret = api_resource:generate_etag(#{}, Context),

              generate_etag_ret_is_valid(RespETag, Ret)
          end
         )
      ).

generate_etag_ret_is_valid('automatic', {ETag, _, Context}) ->
    ETag =:= <<"W/\"", (cb_context:resp_etag(Context))/binary, $">>;
generate_etag_ret_is_valid('undefined', {ETag, _, Context}) ->
    ETag =:= 'undefined'
        andalso cb_context:resp_etag(Context) =:= 'undefined';
generate_etag_ret_is_valid(RespETag, {ETag, _, Context}) ->
    ETag =:= <<$", RespETag/binary, $">>
        andalso cb_context:resp_etag(Context) =:= RespETag.

cleanup() ->
    meck:unload(),
    'ok'.

-endif.

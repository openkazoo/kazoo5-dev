%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2014-2023, 2600Hz
%%% @doc Plays tones to the caller
%%%
%%% A tone object is made up of a list of tones and duration-on/off times.
%%% Optionally set repeat and volume
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_tones).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2
        ,convert_tones/1
        ]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    kapps_call_command:answer(Call),

    Tones = kz_json:get_list_value(<<"tones">>, Data),
    case play_tones(Tones, Call) of
        {'error', 'channel_hungup'} ->
            lager:info("channel hungup during tones"),
            cf_exe:stop(Call);
        {'error', _E} ->
            lager:info("channel error ~p during tones", [_E]),
            cf_exe:continue(Call);
        {'ok', _} ->
            lager:info("tones have finished"),
            cf_exe:continue(Call)
    end.

-spec play_tones(kz_json:objects(), kapps_call:call()) ->
          {'ok', kz_json:object()} |
          {'error', atom()}.
play_tones(Tones, Call) ->
    _ = kapps_call_command:tones(convert_tones(Tones), Call),
    kapps_call_command:b_noop(Call).

-spec convert_tones(kz_json:objects()) -> kz_json:objects().
convert_tones(Tones) ->
    [convert_tone(Tone) || Tone <- Tones].

%% @doc convert foo_bar to amqp api Foo-Bar
-spec convert_tone(kz_json:object()) -> kz_json:object().
convert_tone(Tone) ->
    kz_json:map(fun convert_tone_key/2, Tone).

convert_tone_key(<<"duration_on">>, Value) ->
    {<<"Duration-ON">>, Value};
convert_tone_key(<<"duration_off">>, Value) ->
    {<<"Duration-OFF">>, Value};
convert_tone_key(Key, Value) ->
    Segments = binary:split(Key, <<"_">>, ['global']),
    {kz_binary:join(lists:map(fun kz_binary:ucfirst/1, Segments), <<"-">>)
    ,Value
    }.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
convert_token_key_test_() ->
    Tone = kz_json:from_list([{<<"Frequencies">>, [<<"440">>]}
                             ,{<<"Duration-ON">>, <<"500">>}
                             ,{<<"Duration-OFF">>, <<"100">>}
                             ,{<<"Volume">>, 3}
                             ,{<<"Repeat">>, 5}
                             ]),
    DataTone = kz_json:from_list([{<<"frequencies">>, [<<"440">>]}
                                 ,{<<"duration_ON">>, <<"500">>}
                                 ,{<<"Duration-OFF">>, <<"100">>}
                                 ,{<<"Volume">>, 3}
                                 ,{<<"Repeat">>, 5}
                                 ]),
    [?_assert(kz_json:are_equal(Tone, convert_tone(DataTone)))].
-endif.

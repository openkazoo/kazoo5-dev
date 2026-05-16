%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc Handles starting/stopping speech detection.
%%% @author Luis Azedo
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_detect_speech).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------

-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    handle(Data, Call, get_action(Data)).

-spec handle(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
handle(Data, Call, <<"start">>) ->
    Options = asr_options(Data),
    kapps_call_command:start_detect_speech(Options, Call),
    cf_exe:continue(Call);

handle(_Data, Call, <<"stop">>) ->
    kapps_call_command:stop_detect_speech(Call),
    cf_exe:continue(Call).

-spec get_action(kz_json:object()) -> kz_term:ne_binary().
get_action(Data) ->
    case kz_json:get_ne_binary_value(<<"action">>, Data) of
        <<"stop">> -> <<"stop">>;
        _ -> <<"start">>
    end.

asr_options(Data) ->
    Props = [{<<"ASR-Engine">>, kz_json:get_ne_binary_value(<<"asr_engine">>, Data)}
            ,{<<"ASR-Engine-Settings">>, kz_json:get_json_value(<<"asr_settings">>, Data)}
            ,{<<"ASR-Engine-Params">>, kz_json:get_json_value(<<"asr_params">>, Data)}
            ],
    props:filter_undefined(Props).

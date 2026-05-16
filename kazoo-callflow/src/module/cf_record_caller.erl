%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2023, 2600Hz
%%% @doc Handles starting/stopping a call recording.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`time_limit'</dt>
%%%   <dd>How long to record the call, in seconds. Default is 600 seconds.</dd>
%%%
%%%   <dt>`format'</dt>
%%%   <dd>What format to store the recording in, e.g. `mp3' or `wav'.</dd>
%%%
%%%   <dt>`url'</dt>
%%%   <dd>What URL to PUT the file to.</dd>
%%% </dl>
%%%
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_record_caller).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call0) ->
    Call1 = cf_record_call:handle(Data, Call0, <<"start">>),
    wait_for_record_stop(Data, Call1).

wait_for_record_stop(Data, Call) ->
    TimeoutS = kapps_call_recording:get_timelimit(Data),
    WaitMs = (TimeoutS * ?MILLISECONDS_IN_SECOND) + (2 * ?MILLISECONDS_IN_SECOND),
    _ = kapps_call_command:wait_for_headless_application(<<"record">>, <<"RECORD_STOP">>, <<"call_event">>, WaitMs),
    cf_exe:continue(Call).

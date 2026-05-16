%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc Bridge the caller to an existing Call-ID
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`target_call_id'</dt>
%%%   <dd>The Call-ID to bridge the caller to</dd>
%%% </dl>
%%%
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_call_pickup).

-behaviour(gen_cf_action).

-export([handle/2]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call0) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),
    kapps_call_command:pickup(target_call_id(Data), Call),
    _ = kapps_call_command:wait_for_hangup(),
    cf_exe:stop(Call).

target_call_id(Data) ->
    <<TargetCallId/binary>> = kz_json:get_ne_binary_value(<<"target_call_id">>, Data),
    lager:info("targeting call ~s for pickup", [TargetCallId]),
    TargetCallId.

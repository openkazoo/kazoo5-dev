%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc Webhook handler behaviour.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(gen_webhook).

-callback init() -> 'ok'.

-callback bindings_and_responders() ->
    {gen_listener:bindings(), listener_utils:responder_start_params()}.

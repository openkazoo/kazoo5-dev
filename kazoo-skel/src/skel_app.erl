%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(skel_app).

-behaviour(application).

-include("skel.hrl").

-define(INTEGRATION_MODULES, [{'cb_skels', 'crossbar_maintenance', 'start_module'}
                             ,{'webhooks_skel', 'webhooks_maintenance', 'start_module'}
                             ,{'bh_skel', 'blackhole_maintenance', 'start_module'}
                             ]).

-export([start/2, stop/1]).

%%------------------------------------------------------------------------------
%% @doc Implement the application start behaviour.
%% @end
%%------------------------------------------------------------------------------
-spec start(application:start_type(), any()) -> kz_types:startapp_ret().
start(_Type, _Args) ->
    %% Ensure all AMQP exchanges needed by the app are declared
    _ = declare_exchanges(),

    %% Ensure any JSON schema(s) are updated in the schema database
    kz_datamgr:revise_docs_from_folder(?KZ_SCHEMA_DB, 'skel', <<"schemas">>),

    %% Ensure CouchDB views are updating when maintenance refresh/migrate is run
    _ = kapps_maintenance:bind_and_register_views(?APP, 'skel_maintenance', 'register_views'),

    %% Ensure integrations to other applications (eg API modules for Crossbar) are ready
    kz_module:application_integrations(?INTEGRATION_MODULES),

    %% Start application's top-level supervisor
    skel_sup:start_link().

%%------------------------------------------------------------------------------
%% @doc Implement the application stop behaviour.
%% @end
%%------------------------------------------------------------------------------
-spec stop(any()) -> any().
stop(_State) ->
    'ok'.

-spec declare_exchanges() -> 'ok'.
declare_exchanges() ->
    kapi_self:declare_exchanges().

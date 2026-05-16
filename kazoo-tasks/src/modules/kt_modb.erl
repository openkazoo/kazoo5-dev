%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%% @author James Aimonetti
%%% @author Pierre Fenoll
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(kt_modb).

%% behaviour: tasks_provider

-export([init/0]).

%% Triggerables
-export([clean_modb/1]).

-include("tasks.hrl").

-define(SHOULD_ARCHIVE_MODBS
       ,kapps_config:get_is_true(?CONFIG_CAT, <<"should_archive_modbs">>, 'false')
       ).

-define(ARCHIVE_MODB_BEFORE_DELETE
       ,kapps_config:get_is_true(?CONFIG_CAT, <<"archive_modb_before_delete">>, 'true')
       ).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    case ?SHOULD_ARCHIVE_MODBS of
        'false' -> 'ok';
        'true' -> tasks_bindings:bind(?TRIGGER_ACCOUNT_MOD, ?MODULE, 'clean_modb')
    end.

%%% Triggerables

-spec clean_modb(kz_term:ne_binary()) -> 'ok'.
clean_modb(AccountMODb) ->
    kazoo_modb:maybe_archive_modb(AccountMODb, ?ARCHIVE_MODB_BEFORE_DELETE).

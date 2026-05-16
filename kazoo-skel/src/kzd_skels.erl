%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc Accessors for `skels' document.
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(kzd_skels).

-export([new/0]).
-export([type/0
        ,schema/0
        ]).

-include_lib("kazoo_documents/src/kz_documents.hrl").

-type doc() :: kz_json:object().
-export_type([doc/0]).

-define(PVT_TYPE, <<"skel">>).
-define(SCHEMA, <<"skels">>).

-spec new() -> doc().
new() ->
    kz_json_schema:default_object(?SCHEMA).

-spec type() -> kz_term:ne_binary().
type() -> ?PVT_TYPE.

-spec schema() -> kz_term:ne_binary().
schema() -> ?SCHEMA.

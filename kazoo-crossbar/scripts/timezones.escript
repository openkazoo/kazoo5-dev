#!/usr/bin/env escript
%%! +A0
%% -*- coding: utf-8 -*-

-mode(compile).
-export([main/1]).

-define(OUT, "priv/couchdb/schemas/timezone.json").
-define(IN, ?OUT ++ ".src").

-include_lib("qdate_localtime/include/tz_database.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

main(_) ->
    {'ok', SchemaBin} = file:read_file(?IN),
    SchemaJObj = kz_json:decode(SchemaBin),
    TZEnumPath = [<<"enum">>],
    Enum = unique_values(?tz_database),
    NewSchemaJObj = kz_json:set_value(TZEnumPath, Enum, SchemaJObj),
    'ok' = file:write_file(?OUT, kz_json:encode(NewSchemaJObj)).

-spec unique_values(list(tuple())) -> kz_term:ne_binaries().
unique_values(TZDB) ->
    lists:usort([kz_term:to_binary(element(1, Tuple)) || Tuple <- TZDB]).

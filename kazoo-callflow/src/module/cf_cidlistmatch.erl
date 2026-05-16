%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2024, 2600Hz
%%% @doc Handles inspection of incoming caller ID and branching to a child
%%% callflow node accordingly.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`id'</dt>
%%%   <dd>Document ID of the match list</dd>
%%% </dl>
%%%
%%% Sample for children section of Callflow:
%%% ```
%%%     "children": {
%%%         "match": { // callflow node to branch to when absolute mode is false and regex matches },
%%%         "nomatch": { // callflow node to branch to when regex does not match or no child node defined for incoming caller id },
%%%     }
%%% '''
%%%
%%%
%%% @author Kozlov Yakov
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_cidlistmatch).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    CallerIdNumber = kapps_call:caller_id_number(Call),
    ListId = kz_json:get_ne_binary_value(<<"id">>, Data),
    AccountDb = kapps_call:account_db(Call),
    lager:debug("comparing caller id ~s with match list ~s entries in ~s", [CallerIdNumber, ListId, AccountDb]),
    case is_matching_prefix(AccountDb, ListId, CallerIdNumber)
        orelse is_matching_regexp(AccountDb, ListId, CallerIdNumber)
    of
        'true' -> handle_match(Call);
        'false' -> handle_no_match(Call)
    end.

-spec is_matching_prefix(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_matching_prefix(AccountDb, ListId, Number) ->
    NumberPrefixes = build_keys(Number),
    Keys = [[ListId, X] || X <- NumberPrefixes],
    case kz_datamgr:get_results(AccountDb, <<"contacts/match_prefix_in_list">>, [{'keys', Keys}]) of
        {'ok', [_ | _]} ->
            lager:debug("found matching prefix"),
            'true';
        _ ->
            lager:debug("unable to find matching prefix"),
            'false'
    end.

-spec is_matching_regexp(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_matching_regexp(AccountDb, ListId, Number) ->
    case kz_datamgr:get_results(AccountDb, <<"contacts/regexps_in_list">>, [{'key', ListId}]) of
        {'ok', [Entry]} ->
            Doc = kz_json:get_json_value(<<"value">>, Entry),
            Regexp = kz_json:get_ne_binary_value(<<"regexp">>, Doc),
            lager:debug("regexp ~s in match list ~s",[Regexp, ListId]),
            match_regexp(Regexp, Number);
        _ ->
            'false'
    end.

-spec match_regexp(kz_term:api_ne_binary(), kz_term:ne_binary()) -> boolean().
match_regexp('undefined', _Number) ->
    'false';
match_regexp(Pattern, Number) ->
    case re:run(Number, Pattern) of
        {'match', _} ->
            lager:debug("found matching regexp ~s for caller id ~s",[Pattern, Number]),
            'true';
        'nomatch' ->
            lager:debug("unable to find matching regexp for caller id ~s",[Number]),
            'false'
    end.

%% TODO: this function from hon_util, may be place it somewhere in library?
-spec build_keys(binary()) -> kz_term:binaries().
build_keys(<<"+", E164/binary>>) ->
    build_keys(E164);
build_keys(<<D:1/binary, Rest/binary>>) ->
    build_keys(Rest, D, [D]).

-spec build_keys(binary(), binary(), kz_term:binaries()) -> kz_term:binaries().
build_keys(<<D:1/binary, Rest/binary>>, Prefix, Acc) ->
    build_keys(Rest, <<Prefix/binary, D/binary>>, [<<Prefix/binary, D/binary>> | Acc]);
build_keys(<<>>, _, Acc) -> Acc.

%%------------------------------------------------------------------------------
%% @doc Handle a caller id "match" condition
%% @end
%%------------------------------------------------------------------------------
-spec handle_match(kapps_call:call()) -> 'ok'.
handle_match(Call) ->
    case is_callflow_child(<<"match">>, Call) of
        'true' -> 'ok';
        'false' -> cf_exe:continue(Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Handle a caller id "no match" condition
%% @end
%%------------------------------------------------------------------------------
-spec handle_no_match(kapps_call:call()) -> 'ok'.
handle_no_match(Call) ->
    case is_callflow_child(<<"nomatch">>, Call) of
        'true' -> 'ok';
        'false' -> cf_exe:continue(Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Check if the given node name is a callflow child
%% @end
%%------------------------------------------------------------------------------
-spec is_callflow_child(kz_term:ne_binary(), kapps_call:call()) -> boolean().
is_callflow_child(Name, Call) ->
    lager:debug("looking for callflow child ~s", [Name]),
    case cf_exe:attempt(Name, Call) of
        {'attempt_resp', 'ok'} ->
            lager:debug("found callflow child"),
            'true';
        {'attempt_resp', {'error', _}} ->
            lager:debug("failed to find callflow child"),
            'false'
    end.

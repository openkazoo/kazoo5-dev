%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2024, 2600Hz
%%% @doc This module looks up the Caller ID Name by matching
%%% numbers/patters with the provided lists.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`lists'</dt>
%%%   <dd>ID of list document to use.</dd>
%%% </dl>
%%%
%%% @author Sponsored by Conversant Ltd, Implemented by SIPLABS, LLC (Ilya Ashchepkov)
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_lookupcidname).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

-type match_number_result() :: {'stop', kz_term:api_binary()} | 'continue'.

-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    CallerNumber = kapps_call:caller_id_number(Call),
    ListIds = kz_json:get_value(<<"lists">>, Data, []),
    AccountDb = kapps_call:account_db(Call),
    lager:debug("matching ~p in ~p", [CallerNumber, AccountDb]),
    CallerName = case match_number_in_lists(AccountDb, CallerNumber, ListIds) of
                     'continue' ->
                         lager:debug("matching regexps"),
                         match_regexp_in_lists(AccountDb, CallerNumber, ListIds);
                     {'stop', Name} -> Name
                 end,
    handle_caller_name(Call, CallerName).

-spec handle_caller_name(kapps_call:call(), kz_term:api_ne_binary()) -> 'ok'.
handle_caller_name(Call, 'undefined') ->
    cf_exe:continue(Call);
handle_caller_name(Call, CallerName) ->
    lager:info("setting caller name to ~p", [CallerName]),
    cf_exe:continue(kapps_call:set_caller_id_name(CallerName, Call)).


-spec match_number_in_lists(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binaries()) ->
          match_number_result().
match_number_in_lists(AccountDb, Number, Lists) ->
    Prefixes = build_keys(Number),
    match_prefixes_in_lists(AccountDb, Prefixes, Lists).

-spec match_prefixes_in_lists(kz_term:ne_binary(), kz_term:ne_binaries(), kz_term:ne_binaries()) ->
          match_number_result().
match_prefixes_in_lists(AccountDb, Prefixes, [ListId | Rest]) ->
    case match_prefixes_in_list(AccountDb, Prefixes, ListId) of
        {'stop', _Name} = Result -> Result;
        'continue' -> match_prefixes_in_lists(AccountDb, Prefixes, Rest)
    end;
match_prefixes_in_lists(_AccountDb, _Number, []) ->
    lager:debug("no matching prefix"),
    'continue'.

-spec match_prefixes_in_list(kz_term:ne_binary(), kz_term:ne_binaries(), kz_term:ne_binary()) ->
          match_number_result().
match_prefixes_in_list(AccountDb, Prefixes, ListId) ->
    Keys = [[ListId, Prefix] || Prefix <- Prefixes],
    ViewOptions = [{'keys', Keys}],
    case kz_datamgr:get_results(AccountDb , <<"contacts/match_prefix_in_list">>, ViewOptions) of
        {'ok', []} ->
            lager:debug("no matching prefixes in list ~p", [ListId]),
            'continue';
        {'ok', [Entry]} ->
            Doc = kz_json:get_json_value(<<"value">>, Entry),
            Name = kz_json:get_ne_binary_value(<<"name">>, Doc),
            Number = kz_json:get_ne_binary_value(<<"number">>, Doc),

            lager:debug("matched prefix ~p", [Number]),

            {'stop', Name};
        {'error', Error} ->
            lager:warning("error while matching prefixes in list ~p: ~p", [ListId, Error]),
            'continue'
    end.

%% TODO: this function from hon_util, may be place it somewhere in library?
-spec build_keys(kz_term:ne_binary()) -> kz_term:binaries().
build_keys(<<"+", E164/binary>>) ->
    build_keys(E164);
build_keys(<<D:1/binary, Rest/binary>>) ->
    build_keys(Rest, D, [D]).

-spec build_keys(binary(), binary(), kz_term:ne_binaries()) -> kz_term:ne_binaries().
build_keys(<<D:1/binary, Rest/binary>>, Prefix, Acc) ->
    build_keys(Rest, <<Prefix/binary, D/binary>>, [<<Prefix/binary, D/binary>> | Acc]);
build_keys(<<>>, _, Acc) -> Acc.

-spec match_regexp_in_lists(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary() | kz_term:ne_binaries()) ->
          kz_term:api_ne_binary().
match_regexp_in_lists(_, _, []) ->
    'undefined';
match_regexp_in_lists(AccountDb, Number, ListIds) ->
    ViewOptions = [{'keys', ListIds}],
    case kz_datamgr:get_results(AccountDb, <<"contacts/regexps_in_list">>, ViewOptions) of
        {'ok', Entries} ->
            match_regexp(Entries, Number);
        Error ->
            lager:warning("getting regexps error: ~p", [Error]),
            'continue'
    end.

-spec match_regexp(kz_json:objects(), kz_term:ne_binary()) ->
          kz_term:api_ne_binary().
match_regexp([Entry| Entries], Number) ->
    Doc = kz_json:get_json_value(<<"value">>, Entry),
    Regexp = kz_json:get_ne_binary_value(<<"regexp">>, Doc),
    case Regexp =/= 'undefined'
        andalso re:run(Number, Regexp)
    of
        'false' -> match_regexp(Entries, Number);
        'nomatch' -> match_regexp(Entries, Number);
        {'match', _} ->
            lager:debug("matched regexp ~p", [Regexp]),
            kz_json:get_ne_binary_value(<<"name">>, Doc)
    end;
match_regexp([], _Number) ->
    lager:warning("no matching regexp"),
    'undefined'.

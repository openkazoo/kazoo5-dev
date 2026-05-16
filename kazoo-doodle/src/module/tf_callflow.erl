%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Callflow action to branch the Im to another textflow.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`id'</dt>
%%%   <dd>The Id of the Callflow to branch.</dd>
%%% </dl>
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(tf_callflow).

-include("doodle.hrl").

-export([handle/2]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_im:im()) -> 'ok'.
handle(Data, Im) ->
    Id = kz_json:get_ne_binary_value(<<"id">>, Data),
    Flow = kz_json:get_ne_json_value(<<"flow">>, Data),
    DocId = kz_json:get_ne_binary_value(<<"doc_id">>, Data),
    Path = normalize_path(kz_json:get_ne_binary_value(<<"path">>, Data)),
    handle_callflow(Id, Flow, DocId, Path, Im).


%%------------------------------------------------------------------------------
%% @doc handle the various use cases
%% @end
%%------------------------------------------------------------------------------
-spec handle_callflow(kz_term:api_binary(), kz_term:api_object(), kz_term:api_binary(), kz_json:get_key(), kapps_im:im()) -> 'ok'.
handle_callflow(Id, 'undefined', 'undefined', 'undefined', Im) -> handle_id(Id, Im);
handle_callflow('undefined', Flow, 'undefined', 'undefined', Im) -> handle_flow(Flow, Im);
handle_callflow('undefined', 'undefined', DocId, Path, Im) -> handle_path(DocId, Path, Im);
handle_callflow(_Id, _Flow, _DocId, _Path, Im) ->
    lager:error("invalid data in module - id: ~p flow: ~p doc_id: ~p path: ~p", [_Id, _Flow, _DocId, _Path]),
    tf_exe:continue(Im).

%%------------------------------------------------------------------------------
%% @doc og case, branches to the callfow defined referenced by Id
%% @end
%%------------------------------------------------------------------------------
-spec handle_id(kz_term:ne_binary(), kapps_im:im()) -> 'ok'.
handle_id(Id, Im) ->
    lager:info("trying to branch to callflow ~s", [Id]),
    case kz_datamgr:open_cache_doc(kapps_im:account_id(Im), Id) of
        {'error', R} ->
            lager:info("could not branch to callflow ~s, ~p", [Id, R]),
            tf_exe:continue(Im);
        {'ok', JObj} ->
            lager:info("branching to new callflow ~s", [Id]),
            Flow = kzd_callflows:flow(JObj, kz_json:new()),
            tf_exe:branch(Flow, Im)
    end.

%%------------------------------------------------------------------------------
%% @doc branches to the callfow defined inline in the module Data
%% @end
%%------------------------------------------------------------------------------
-spec handle_flow(kz_json:object(), kapps_im:im()) -> 'ok'.
handle_flow(Flow, Im) ->
    lager:info("branching to inline callflow"),
    tf_exe:branch(Flow, Im).

%%------------------------------------------------------------------------------
%% @doc branches to a callflow whose id is defined in a variable on an allowed
%% doc type
%% @end
%%------------------------------------------------------------------------------
-spec handle_path(kz_term:ne_binary(), kz_json:get_key(), kapps_im:im()) -> 'ok'.
handle_path(DocId, Path, Im) ->
    lager:info("searching for path ~s in doc: ~s", [Path, DocId]),
    case get_path(DocId, Path, Im) of
        'undefined' ->
            lager:info("could not find path ~s in doc: ~s", [Path, DocId]),
            tf_exe:continue(Im);
        CallFlowId ->
            lager:info("branching to callflow id: ~p", [CallFlowId]),
            maybe_branch(kz_datamgr:open_cache_doc(kapps_im:account_id(Im), CallFlowId), Im)
    end.

%%------------------------------------------------------------------------------
%% @doc Try to branch to the callflow
%% @end
%%------------------------------------------------------------------------------
-spec maybe_branch({'error', any()}|{'ok', kz_json:object()}, kapps_im:im()) -> 'ok'.
maybe_branch({'error', R}, Im) ->
    lager:error("could not branch to callflow ~p", [R]),
    tf_exe:continue(Im);
maybe_branch({'ok', JObj}, Im) ->
    maybe_branch(kz_doc:type(JObj), JObj, Im).

maybe_branch(<<"callflow">>, JObj, Im) ->
    Flow = kzd_callflows:flow(JObj, kz_json:new()),
    tf_exe:branch(Flow, Im);
maybe_branch(_Type, _, Im) ->
    lager:error("failed to branch due to invalid doc type ~s", [_Type]),
    tf_exe:continue(Im).

%%------------------------------------------------------------------------------
%% @doc Open the document DocId to find the value of the path which a callflow id
%% @end
%%------------------------------------------------------------------------------
-spec get_path(kz_term:api_binary(), kz_json:get_key(), kapps_im:im()) -> kz_term:api_binary().
get_path('undefined', _Path, _Call) ->
    lager:error("could not find document for user with undefined doc id"),
    'undefined';
get_path(DocId, Path, Im) ->
    lager:info("fetch doc ~p from db ~p", [DocId, kapps_im:account_id(Im)]),
    case kz_datamgr:open_cache_doc(kapps_im:account_id(Im), DocId) of
        {error, Error} ->
            lager:error("failed to open user doc ~s in account ~s => ~s", [DocId, kapps_im:account_id(Im), kz_term:to_binary(Error)]),
            'undefined';
        {ok, JObj} ->
            kz_json:get_ne_binary_value(Path, JObj)
    end.

%%------------------------------------------------------------------------------
%% @doc Normalize path. Path is a json path, so we should accept
%% binary, or a path and ignore others, since the schema requires this to be a string
%% this also supports a dot.delimited.path  which is converted to a list
%% So if ones wants to look into a deep json object, path `[<<"v1">>, <<"v2">>]'
%% can be used to get the value.
%% @end
%%------------------------------------------------------------------------------
-spec normalize_path(kz_json:get_key()) -> kz_json:get_key() | 'undefined'.
normalize_path('undefined') ->
    'undefined';
normalize_path(Path) when is_list(Path) ->
    [kz_json:normalize_key(V) || V <- Path, not kz_term:is_empty(V)];
normalize_path(?NE_BINARY = Path) ->
    normalize_path(binary:split(Path, <<".">>, ['global']));
normalize_path(_JObj) ->
    lager:debug("unsupported path name"),
    'undefined'.

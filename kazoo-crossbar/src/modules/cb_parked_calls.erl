%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%%
%%% @author Roman Galeev
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_parked_calls).

-include("crossbar.hrl").

-export([init/0
        ,allowed_methods/0
        ,resource_exists/0
        ,validate/1
        ]).

-define(PARKED_CALLS_VIEW, <<"parking/parked_calls">>).
-define(PARKED_CALL_DOC_TYPE, <<"parked_call">>).
-define(SLOT_DOC_ID(A), <<"parking-slot-", A/binary>>).

-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.parked_calls">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.parked_calls">>, ?MODULE, 'resource_exists'),
    crossbar_bindings:bind(<<"*.validate.parked_calls">>, ?MODULE, 'validate').

-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_GET].

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    Options = parked_options(),
    Context1 = crossbar_view:load(Context, ?PARKED_CALLS_VIEW, Options),
    case cb_context:resp_status(Context) of
        'success' -> cb_context:set_resp_data(Context1, build_slots(cb_context:doc(Context1)));
        _ -> Context1
    end.

parked_options() ->
    [{'mapper', fun normalize_view_results/2}
    ,{'doc_type', ?PARKED_CALL_DOC_TYPE}
    ,{'field_key', 'filtermap'}
    ,'include_docs'
    ].

-spec build_slots(kz_json:objects()) -> kz_json:object().
build_slots([]) ->
    kz_json:from_list([{<<"slots">> , kz_json:new()}]);
build_slots(Slots) ->
    kz_json:from_list([{<<"slots">>, kz_json:merge(Slots)}]).

-spec normalize_view_results(kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_view_results(JObj, Acc) ->
    Slot = kz_json:get_value([<<"doc">>, <<"slot">>], JObj),
    ?SLOT_DOC_ID(SlotNumber) = kz_doc:id(JObj),
    [kz_json:from_list([{SlotNumber, kz_json:normalize_jobj(Slot)}]) | Acc].

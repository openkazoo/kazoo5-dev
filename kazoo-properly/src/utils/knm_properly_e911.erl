%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc Handle properly e911 provisioning
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(knm_properly_e911).
-behaviour(knm_gen_provider).

-export([save/1]).
-export([delete/1]).

-include_lib("kazoo_numbers/src/knm.hrl").

%%------------------------------------------------------------------------------
%% @doc This function is called each time a number is saved, and will
%% provision e911 or remove the number depending on the state
%% @end
%%------------------------------------------------------------------------------

-spec save(knm_phone_number:pn_record()) ->
          knm_phone_number:pn_record().
save(PN) ->
    State = knm_phone_number:state(PN),
    save(PN, State).

-spec save(knm_phone_number:pn_record(), kz_term:api_binary()) ->
          knm_phone_number:pn_record().
save(PN, ?NUMBER_STATE_RESERVED) ->
    update_e911(PN);
save(PN, ?NUMBER_STATE_IN_SERVICE) ->
    update_e911(PN);
save(PN, ?NUMBER_STATE_PORT_IN) ->
    update_e911(PN);
save(PN, _State) ->
    delete(PN).

%%------------------------------------------------------------------------------
%% @doc This function is called each time a number is deleted, and will
%% provision e911 or remove the number depending on the state
%% @end
%%------------------------------------------------------------------------------
-spec delete(knm_phone_number:pn_record()) ->
          knm_phone_number:pn_record().
delete(PN) ->
    case knm_phone_number:feature(PN, ?FEATURE_E911) of
        'undefined' -> PN;
        _Else ->
            lager:debug("removing e911 information from ~s"
                       ,[knm_phone_number:number(PN)]),
            knm_providers:deactivate_feature(PN, ?FEATURE_E911)
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec update_e911(knm_phone_number:pn_record()) -> knm_phone_number:pn_record().
update_e911(PN) ->
    CurrentE911 = knm_phone_number:feature(PN, ?FEATURE_E911),
    E911 = kz_json:get_ne_value(?FEATURE_E911, knm_phone_number:doc(PN)),
    NotChanged = kz_json:are_equal(CurrentE911, E911),
    case kz_term:is_empty(E911) of
        'true' ->
            lager:debug("information has been removed"),
            knm_providers:deactivate_feature(PN, ?FEATURE_E911);
        'false' when NotChanged  ->
            PN;
        'false' ->
            lager:debug("information has been changed: ~s", [kz_json:encode(E911)]),
            NewDoc = kz_json:set_value(?FEATURE_E911, E911, knm_phone_number:doc(PN)),
            NewPN = knm_phone_number:reset_doc(PN, NewDoc),
            knm_providers:activate_feature(NewPN, {?FEATURE_E911, E911})
    end.

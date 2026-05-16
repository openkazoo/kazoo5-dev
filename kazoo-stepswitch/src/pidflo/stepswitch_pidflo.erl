%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2023, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%% @end
%%%-----------------------------------------------------------------------------
-module(stepswitch_pidflo).

-include_lib("xmerl/include/xmerl.hrl").

-export([emergency_address_to_xml/2]).


-spec emergency_address_to_xml(kz_json:api_object(), kz_term:ne_binary()) -> kz_term:api_ne_binary().
emergency_address_to_xml('undefined', _BridgeFromURI) ->
    'undefined';
emergency_address_to_xml(JObj, BridgeFromURI) ->
    GeoprivEl = geopriv_el([location_info_el([civic_address_el(civic_address_content(JObj))
                                              %%,point_el([pos_el("47.6400 -122.1297")])
                                             ])
                           ,usage_rules_el([retransmission_allowed_el()])
                           ,method_el()
                           ]),
    PresenceEl = presence_el(BridgeFromURI, [tuple_el([status_el([GeoprivEl])])]),

    {'ok', PIDFLO_XML} = {'ok', xmerl:export([PresenceEl], 'pidflo_xml')},
    PIDFLOBin = erlang:iolist_to_binary(PIDFLO_XML),

    <<"application/pidf+xml:", PIDFLOBin/binary>>.


%% Helpers (Internal functions)

-spec presence_el(kz_types:xml_attrib_value(), kz_types:xml_els()) -> kz_types:xml_el().
presence_el(Entity, Content) ->
    #xmlElement{name='presence'
               ,attributes=[xml_attrib('xmlns:xsd', <<"http://www.w3.org/2001/XMLSchema">>)
                           ,xml_attrib('xmlns:xsi', <<"http://www.w3.org/2001/XMLSchema-instance">>)
                           ,xml_attrib('entity', Entity)
                           ,xml_attrib('xmlns', <<"urn:ietf:params:xml:ns:pidf">>)
                           ]
               ,content=Content
               }.

-spec tuple_el(kz_types:xml_els()) -> kz_types:xml_el().
tuple_el(Content) ->
    tuple_el(Content, <<"tuple0">>).

-spec tuple_el(kz_types:xml_els(), kz_types:xml_attrib_value()) -> kz_types:xml_el().
tuple_el(Content, Id) ->
    #xmlElement{name='tuple'
               ,attributes=[xml_attrib('id', Id)]
               ,content=Content
               }.

-spec status_el(kz_types:xml_els()) -> kz_types:xml_el().
status_el(Content) ->
    #xmlElement{name='status'
               ,content=Content
               }.

-spec geopriv_el(kz_types:xml_els()) -> kz_types:xml_el().
geopriv_el(Content) ->
    #xmlElement{name='geopriv'
               ,attributes=[xml_attrib('xmlns', <<"urn:ietf:params:xml:ns:pidf:geopriv10">>)]
               ,content=Content
               }.

-spec location_info_el(kz_types:xml_els()) -> kz_types:xml_el().
location_info_el(Content) ->
    #xmlElement{name='location-info'
               ,content=Content
               }.

%% Not conclusion yet on the implementation of the following 2 functions. Commented out for now.
%%-spec point_el(kz_types:xml_els()) -> kz_types:xml_el().
%%point_el(Content) ->
%%    #xmlElement{name='point'
%%               ,attributes=[xml_attrib('srsName', <<"urn:ogc:def:crs:EPSG::4326">>)
%%                           ,xml_attrib('xmlns', <<"http://www.opengis.net/gml">>)
%%                           ]
%%               ,content=Content
%%               }.
%%
%%-spec pos_el(iolist()) -> kz_types:xml_el().
%%pos_el(Content) ->
%%    #xmlElement{name='pos'
%%               ,content=[text_el(Content)]
%%               }.

-spec civic_address_el(kz_types:xml_els()) -> kz_types:xml_el().
civic_address_el(Content) ->
    #xmlElement{name='civicAddress'
               ,attributes=[xml_attrib('xmlns', <<"urn:ietf:params:xml:ns:pidf:geopriv10:civicAddr">>)]
               ,content=Content
               }.

-spec civic_address_content(kz_json:object()) -> kz_types:xml_els().
civic_address_content(JObj) ->
    [%% A1 (rfc4119): National subdivisions (state, region, province, prefecture). Example: New York.
     named_el('A1', text_el(kz_json:get_string_value(<<"region">>, JObj)))
     %% A2 (rfc4119): County, parish, gun (JP), district (IN). Example: King's County.
    ,named_el('A2', text_el(kz_json:get_string_value(<<"county">>, JObj, "")))
     %% A3 (rfc4119): City, township, shi (JP). Example: New York.
    ,named_el('A3', text_el(kz_json:get_string_value(<<"locality">>, JObj)))
     %% country (rfc4119): The country is identified by the two-letter ISO 3166 code. Example: US.
    ,named_el('country', text_el(kz_json:get_string_value(<<"country">>, JObj)))
     %% ELIN: Each telephone line in the United States has a unique 10-digit number known as an E911 location identifier (ELIN).
    ,named_el('ELIN', text_el(kz_json:get_string_value(<<"location_identifier">>, JObj, "")))
     %% FLR (rfc4776): Floor. Example: 4.
    ,named_el('FLR', text_el(kz_json:get_string_value(<<"floor">>, JObj, "")))
     %% HNO (rfc4119): House number, numeric part only. Example: 123.
    ,named_el('HNO', text_el(kz_json:get_string_value(<<"house_number">>, JObj)))
     %% HNS (rfc4119): House number suffix. Example: A, 1/2.
    ,named_el('HNS', text_el(kz_json:get_string_value(<<"house_number_suffix">>, JObj, "")))
     %% LOC (rfc4119): Additional location information. Example: Room 543.
    ,named_el('LOC', text_el(kz_json:get_string_value(<<"additional_information">>, JObj, "")))
     %% NAM (rfc4119): Name (residence, business or office occupant). Example: Joe's Barbershop.
    ,named_el('NAM', text_el(kz_json:get_string_value(<<"name">>, JObj)))
     %% PC (rfc4119): Postal code. Example: 10027-0401.
    ,named_el('PC', text_el(kz_json:get_string_value(<<"postal_code">>, JObj)))
     %% POD (rfc4119): Trailing street suffix. Example: SW.
    ,named_el('POD', text_el(kz_json:get_string_value(<<"street_suffix">>, JObj, "")))
     %% PRD (rfc4119): Leading street direction. Example: N, W.
    ,named_el('PRD', text_el(kz_json:get_string_value(<<"street_direction">>, JObj, "")))
     %% RD (rfc5139): Primary road or street. Example: Broadway.
    ,named_el('RD', text_el(kz_json:get_string_value(<<"street">>, JObj)))
     %% STS (rfc4119): Street type. Example: Avenue, Platz, Street.
    ,named_el('STS', text_el(kz_json:get_string_value(<<"street_type">>, JObj, "")))
    ].

-spec named_el(atom(), kz_types:xml_els() | kz_types:xml_text() | kz_types:xml_texts()) -> kz_types:xml_el().
named_el(Name, #xmlText{}=Children) ->
    named_el(Name, [Children]);
named_el(Name, Children) ->
    #xmlElement{name=Name
               ,content=Children
               }.

-spec text_el(iolist()) -> kz_types:xml_text().
text_el(Value) ->
    #xmlText{value=kz_term:to_list(Value)}.

-spec usage_rules_el(kz_types:xml_els()) -> kz_types:xml_el().
usage_rules_el(Content) ->
    #xmlElement{name='usage-rules'
               ,content=Content
               }.

-spec retransmission_allowed_el() -> kz_types:xml_el().
retransmission_allowed_el() ->
    #xmlElement{name='retransmission-allowed'
               ,attributes=[xml_attrib('xmlns', <<"urn:ietf:params:xml:ns:pidf:geopriv10:basicPolicy">>)]
               ,content=[text_el("true")]
               }.

-spec method_el() -> kz_types:xml_el().
method_el() ->
    #xmlElement{name='method'
               ,content=[text_el("LIS")]
               }.

-spec xml_attrib(kz_types:xml_attrib_name(), kz_types:xml_attrib_value()) -> kz_types:xml_attrib().
xml_attrib(Name, Value) when is_atom(Name) ->
    #xmlAttribute{name=Name, value=kz_term:to_list(Value)}.

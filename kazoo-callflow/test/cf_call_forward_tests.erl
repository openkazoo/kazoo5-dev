-module(cf_call_forward_tests).

-include_lib("eunit/include/eunit.hrl").

-record(cf_test, {title, existing, set_enabled, set_number, expected}).

update_forwards_test_() ->
    Number = kz_binary:rand_hex(5),
    UpdateNumber = kz_binary:rand_hex(5),

    Enabled = random_boolean(),

    %% ?debugFmt("~nnumber: ~s~nupdate: ~s~nenabled: ~p~n~n"
    %%          ,[Number, UpdateNumber, Enabled]
    %%          ),

    TestArgs = [#cf_test{title="Adding first cfwd rule"
                        ,existing='undefined'
                        ,set_enabled=Enabled
                        ,set_number=Number
                        ,expected=legacy_cfwd(Enabled, Number)
                        }

               ,#cf_test{title="Toggle legacy cfwd rule enablement"
                        ,existing=legacy_cfwd(not Enabled, Number)
                        ,set_enabled=Enabled
                        ,set_number='undefined'
                        ,expected=legacy_cfwd(Enabled, Number)
                        }
               ,#cf_test{title="Toggle legacy cfwd rule enablement and number"
                        ,existing=legacy_cfwd(not Enabled, Number)
                        ,set_enabled=Enabled
                        ,set_number=UpdateNumber
                        ,expected=legacy_cfwd(Enabled, UpdateNumber)
                        }
               ,#cf_test{title="No-op on current cfwd version"
                        ,existing=unconditional_cfwd(Enabled, Number)
                        ,set_enabled=Enabled
                        ,set_number=Number
                        ,expected=unconditional_cfwd(Enabled, Number)
                        }
               ,#cf_test{title="Toggle existing enhanced cfwd rule"
                        ,existing=unconditional_cfwd(Enabled, Number)
                        ,set_enabled=not Enabled
                        ,set_number=Number
                        ,expected=unconditional_cfwd(not Enabled, Number)
                        }
               ,#cf_test{title="Update existing enhanced cfwd number"
                        ,existing=unconditional_cfwd(Enabled, Number)
                        ,set_enabled=Enabled
                        ,set_number=UpdateNumber
                        ,expected=unconditional_cfwd(Enabled, UpdateNumber)
                        }
               ],
    lists:map(fun run_it/1, TestArgs).

unconditional_cfwd(Enabled, Number) ->
    Updates = [{fun kzd_call_forward:set_enabled/2, Enabled}
              ,{fun kzd_call_forward:set_number/2, Number}
              ],
    Cfwd = kz_doc:setters(kz_json:new(), Updates),
    kzd_call_forward_types:set_unconditional(kz_json:new(), Cfwd).

legacy_cfwd(Enabled, Number) ->
    Updates = [{fun kzd_call_forward:set_enabled/2, Enabled}
              ,{fun kzd_call_forward:set_number/2, Number}
              ],
    kz_doc:setters(kz_json:new(), Updates).

run_it(#cf_test{title=Title
               ,existing=Existing
               ,set_enabled=Enabled
               ,set_number=Number
               ,expected=Expected
               }
      ) ->
    {Title
    ,?_assert(kz_json:are_equal(Expected
                               ,cf_call_forward:update_call_forward(Existing, Enabled, Number)
                               )
             )
    }.

random_boolean() ->
    rand:uniform() < 0.5.

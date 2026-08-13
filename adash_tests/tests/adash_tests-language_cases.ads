with AUnit.Test_Cases;

--  Tests for the language core: types, values, symbols and scopes.
--
--  These lock down decisions rather than implementations. Whether an Integer
--  may be used where a Float is expected, whether `1 = "1"` is False or a
--  refusal, whether `Count` and `COUNT` are one name -- each is a choice that
--  Phases 4 to 7 will build on, and each would be expensive to change later
--  because it is the sort of thing users write programs against.
package Adash_Tests.Language_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  Name shown by the reporter.
   --
   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  Register the routines of this case.
   --
   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

end Adash_Tests.Language_Cases;

with AUnit.Test_Cases;

--  Tests for what the shell can ask about a path.
--
--  Two things are pinned: that each question answers about the thing it names
--  rather than about any file, and that a path nobody can reach is answered
--  rather than raised. The second is the contract that lets a predicate be
--  written inside a condition without a second question beside it.
package Adash_Tests.Filesystem_Cases is

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

end Adash_Tests.Filesystem_Cases;

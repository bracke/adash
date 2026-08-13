with AUnit.Test_Cases;

--  Tests for the execution subsystem.
--
--  These run real programs. A pipeline that is only unit-tested against a fake
--  host proves the wiring is self-consistent, not that it works: the failures
--  that matter here -- a pipe end the parent forgot to close, a descriptor that
--  leaked into the wrong child, a status that came back as the wrong kind --
--  are all invisible until something actually runs.
--
--  The programs used are ones every host running these tests has, chosen for
--  behaviour rather than convenience, and each test says which property it is
--  pinning down.
package Adash_Tests.Execution_Cases is

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

end Adash_Tests.Execution_Cases;

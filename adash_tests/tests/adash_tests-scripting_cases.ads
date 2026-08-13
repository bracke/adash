with AUnit.Test_Cases;

--  Tests for scripting and startup.
--
--  The properties here are about policy rather than computation: what happens
--  when a file is missing, unreadable, or loads itself, and what a shell does
--  when its startup file is broken. Each is a decision that only shows up on a
--  bad day, which is exactly when nobody is in a position to debug it.
package Adash_Tests.Scripting_Cases is

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

   procedure The_Source_Command_Runs_A_Script
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Source_Without_A_Runner_Refuses
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Script_Cannot_Source_Itself
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Scripting_Cases;

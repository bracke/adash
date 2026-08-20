with AUnit.Test_Cases;

--  What a session does with input nobody would write on purpose.
--
--  Two properties, and the second is the one that matters: a submission either
--  runs or says what is wrong with it -- it never takes the session down -- and
--  whatever it did, the session still works afterwards. A shell that survives a
--  bad line but cannot run a good one after it has failed in the way users
--  actually meet, which is how the carried-value defect behaved: one variable
--  holding a newline and every submission after it answered "this string
--  literal is not closed".
package Adash_Tests.Hostile_Cases is

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

end Adash_Tests.Hostile_Cases;

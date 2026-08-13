with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;

with Adash_Tests.Suite;

--  The AUnit runner.
--
--  One deterministic suite, run in a fixed order, with no dependence on the
--  filesystem's enumeration order, the locale, the wall clock or a random
--  seed. A test that needs any of those states it and controls it; a test
--  that merely happens to pass because of one is a test that will fail on
--  somebody else's machine and be called flaky rather than wrong.
procedure Adash_Tests_Main is

   function Run_Suite is new AUnit.Run.Test_Runner_With_Status (Adash_Tests.Suite.Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;

   use type AUnit.Status;

begin
   --  The exit status is the point: a test run whose failures do not reach
   --  the caller is a test run that CI reports as green.
   if Run_Suite (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Adash_Tests_Main;

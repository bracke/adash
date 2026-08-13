--  A fixture, not a package this repository builds.
--
--  It exists to prove Check_No_Prose_As_Text can fail. A check that has only
--  ever been run against a repository that passes is a check nobody has seen
--  work, and the repository suite already learnt that lesson once with
--  fixtures/not-a-repository.
--
--  The literal below is the defect the check is for: a sentence a user would
--  read, written in Ada rather than in the catalog. `in out` beside it is
--  Ada's own spelling and must not be reported.
package Probe is

   Sentence : constant String := "the arithmetic does not hold";
   Spelling : constant String := "in out";

end Probe;

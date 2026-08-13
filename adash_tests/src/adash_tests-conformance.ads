private with Ada.Containers.Vectors;

--  Visible rather than private: both appear in Result, which a caller reads.
with Ada.Strings.Unbounded;

--  The conformance suite: what a user can observe, pinned down.
--
--  A conformance case describes **externally observable behaviour** and never
--  how Adash is built. It runs the real binary, feeds it a script, and compares
--  the exit status, what came out on standard output and what came out on
--  standard error. That is worth more than a unit test when the two disagree,
--  because it is what somebody actually experiences.
--
--  **Diagnostics are compared as identifiers, not as sentences.** The runner
--  points the message catalog at a path that does not exist, so every message
--  renders in its fallback form -- `!error.name_undeclared{name=zzz}!` -- which
--  is the stable identifier and its arguments. A suite that asserted on English
--  would break on every wording change, would be untranslatable, and would quietly
--  stop testing anything the day somebody localized the build.
--
--  **Cases are data, not code.** They live in `conformance/cases/*.toml`, read
--  through tomllib. A case that had to be compiled would be a case nobody adds
--  when they find a bug, and the point of the suite is that adding one is
--  cheaper than arguing about the behaviour.
--
--  The format, one file per group:
--
--      suite = "exit-status"
--
--      [[case]]
--      id = "exit.explicit"
--      requirement = "quit ends the session with the status it was given"
--      script = "quit (7);"
--      exit_status = 7
--      output = []
--      diagnostics = []
--
--  `script` is fed on standard input. `arguments` is passed on the command
--  line. `output` and `diagnostics` are the exact lines expected, in order and
--  exhaustively.
--
--  **An absent key and an empty one are different assertions.** Leaving
--  `diagnostics` out says nothing about standard error; writing
--  `diagnostics = []` says that nothing came out of it. Treating the two the
--  same would make one of them inexpressible, and it would be the useful one:
--  asserting that a stream is empty is how a case pins down that diagnostics
--  never leak into standard output.
--
--  `platforms` limits a case to the hosts it applies to, and a case that does
--  not apply is skipped rather than passed, so a report can say how much was
--  actually checked.
package Adash_Tests.Conformance is

   --  A case's stable identity, and the detail of a failure. Both are written
   --  into a report a person reads.
   subtype Case_Name is Ada.Strings.Unbounded.Unbounded_String;
   subtype Detail_Text is Ada.Strings.Unbounded.Unbounded_String;

   --  What became of one case.
   type Verdict is
     (
      --  Everything matched.
      Passed,

      --  Something did not. See Detail.
      Failed,

      --  Not applicable to this host. Counted separately from a pass, because
      --  a suite that reported skipped cases as passing would look complete on
      --  a machine where half of it never ran.
      Skipped,

      --  The case itself is wrong: a missing field, an unreadable file. A
      --  fault in the suite rather than in Adash, and it must not be reported
      --  as a failure of the thing under test.
      Malformed);

   --  One case's outcome.
   type Result is record
      Identity : Case_Name;
      Outcome  : Verdict := Passed;

      --  What went wrong, in enough detail to act on: which stream, which
      --  line, what was expected and what arrived.
      Detail : Detail_Text;
   end record;

   --  What a run produced.
   type Report is tagged limited private;

   --  @param Item Report to measure.
   --  @return How many cases ran, including skipped ones.
   function Count (Item : Report) return Natural;

   --  @param Item Report to read.
   --  @param Index Which case, from one.
   --  @return Its result.
   function Element (Item : Report; Index : Positive) return Result;

   --  @param Item Report to measure.
   --  @param Outcome Which verdict.
   --  @return How many cases got it.
   function Count_Of (Item : Report; Outcome : Verdict) return Natural;

   --  @param Item Report to judge.
   --  @return True when nothing failed and nothing was malformed. Skipped
   --          cases do not fail a run; a host that cannot exercise a case has
   --          not disproved it.
   function Passed (Item : Report) return Boolean;

   --  Run every case under a directory.
   --
   --  @param Root The repository root. Cases are read from
   --         `<Root>/conformance/cases`, and the binary under test is
   --         `<Root>/bin/adash`.
   --  @param Into Where results go. Not cleared.
   procedure Run (Root : String; Into : in out Report);

   --  Run the examples as conformance cases.
   --
   --  An example is a case whose input is a file somebody is meant to read.
   --  Running them through the same machinery is what stops the documentation
   --  drifting: an example that no longer produces what it claims fails here
   --  rather than being discovered by a reader.
   --
   --  @param Root The repository root. Examples are read from
   --         `<Root>/examples`.
   --  @param Into Where results go. Not cleared.
   procedure Run_Examples (Root : String; Into : in out Report);

private

   package Result_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Result);

   type Report is tagged limited record
      Results : Result_Vectors.Vector;
   end record;

end Adash_Tests.Conformance;

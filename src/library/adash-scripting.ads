private with Ada.Containers.Vectors;

--  Visible rather than private: Module_Path is part of the public contract, so
--  the unit defining it has to be too.
with Ada.Strings.Unbounded;

with Adash.Diagnostics;
with Adash.Commands;
with Adash.Engine;
with Adash.Execution;

--  Running source that nobody is typing.
--
--  A script goes through the same engine an interactive line does. There is no
--  script interpreter here and there will not be one: a shell with two ways to
--  run its own language eventually has two languages, and the difference is
--  found by users rather than by tests. What this package adds is everything
--  around the running -- finding the file, validating it, keeping track of what
--  is already being loaded, and deciding what a failure means.
--
--  A script is one submission. That follows from how statements are lowered:
--  they share an activation record, so a file's declarations have to be
--  analysed and lowered together. It also inherits the engine's rule that a
--  submission is commands or statements and not both, which for a script means
--  a file of commands or a file of program -- stated here because a user will
--  meet it.
--
--  Loading is tracked so that a file cannot load itself. A cycle is not a hang
--  to be discovered but a refusal with the path that closed it, because the
--  alternative is a shell that stops responding and gives no reason.
package Adash.Scripting is

   --  A resolved path to a script.
   subtype Module_Path is Ada.Strings.Unbounded.Unbounded_String;

   --  What became of running a script.
   type Outcome is
     (
      --  It ran. Whether it *succeeded* is the status, separately: a script
      --  that ran and failed is not the same as one that could not be read.
      Script_Ran,

      --  No such file.
      Script_Not_Found,

      --  It exists and could not be read, or is not valid UTF-8.
      Script_Unreadable,

      --  It is already being loaded further up the chain.
      Script_Cycle,

      --  It was read and did not parse, or was illegal.
      Script_Rejected);

   --  What is currently being loaded.
   --
   --  Passed down through nested loads so a cycle can be seen. Limited: it is
   --  the state of one loading chain, and a copy would be a second chain that
   --  agrees with the first only by accident.
   type Loading is tagged limited private;

   --  How deep the chain is: zero at the top, one inside a script, and so on.
   --
   --  @param Item Chain to measure.
   --  @return Its depth.
   function Depth (Item : Loading) return Natural;

   --  Whether a path is already being loaded.
   --
   --  @param Item Chain to search.
   --  @param Path The path, already resolved.
   --  @return True when loading it would close a cycle.
   function Is_Active (Item : Loading; Path : String) return Boolean;

   --  The script currently being loaded, innermost first.
   --
   --  What a bare name is resolved relative to: a set of scripts that ship
   --  together should find each other without any of them knowing where they
   --  were installed.
   --
   --  @param Item Chain to inspect.
   --  @return Its innermost path, or "" at the top level, where there is
   --          nothing to be beside.
   function Innermost (Item : Loading) return String;

   --  Run a script file.
   --
   --  @param Session The session it runs in. Its state -- environment, exit
   --         request -- is the session's, so a script may `set` a variable that
   --         outlives it, which is the point of sourcing one.
   --  @param Path The file.
   --  @param Context The loading chain, for cycle detection. A caller starting
   --         a fresh chain passes a default-initialised one.
   --  @param Result What became of it.
   --  @param Status Its exit status, meaningful when Result is Script_Ran.
   --  @param Report Where diagnostics go.
   procedure Run_File
     (Session : in out Adash.Engine.Session;
      Path    : String;
      Context : in out Loading;
      Result  : out Outcome;
      Status  : out Adash.Execution.Exit_Status;
      Report  : in out Adash.Diagnostics.List;
      On_Output : Adash.Engine.Output_Sink_Access := null);

   --  Run source that has no file behind it.
   --
   --  For a startup fragment held in configuration, and for tests. The name is
   --  what diagnostics will call it.
   --
   --  @param Session The session it runs in.
   --  @param Text The source.
   --  @param Name What to call it in diagnostics.
   --  @param Result What became of it.
   --  @param Status Its exit status.
   --  @param Report Where diagnostics go.
   procedure Run_Text
     (Session : in out Adash.Engine.Session;
      Text    : String;
      Name    : String;
      Result  : out Outcome;
      Status  : out Adash.Execution.Exit_Status;
      Report  : in out Adash.Diagnostics.List;
      On_Output : Adash.Engine.Output_Sink_Access := null;

      --  How many bytes the session put in front of this text. Needed only by
      --  a caller that assembled the text itself and has to say which of its
      --  own bytes a diagnostic is about; see Run_File, which reads one script
      --  into another.
      Carried : out Natural);

   ---------------------------------------------------------------------
   --  Running a script from inside a command.
   --
   --  `source` is a command, and commands are called by the engine, so the
   --  command cannot reach the engine itself. Adash.Commands declares the
   --  capability it needs as an interface; this is the implementation, and it
   --  lives here because this is the package that already knows how to run a
   --  file in a session.
   ---------------------------------------------------------------------

   --  A runner bound to one session and one loading chain.
   --
   --  The chain is shared with whatever started the outermost script, which is
   --  what lets a file that sources itself be refused instead of looping.
   type Runner
     (Session : not null access Adash.Engine.Session;
      Context : not null access Loading;
      Report  : not null access Adash.Diagnostics.List;
      Output  : Adash.Engine.Output_Sink_Access)
   is limited new Adash.Commands.Script_Runner with null record;

   overriding procedure Run_Script
     (Runner : in out Scripting.Runner;
      Path   : String;
      Status : out Adash.Execution.Exit_Status;
      Failed : out Boolean);

private

   package Path_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "="          => Ada.Strings.Unbounded."=");

   type Loading is tagged limited record
      --  Resolved paths, outermost first. A vector rather than a set: a chain
      --  is a handful of entries deep, and the order is what a diagnostic
      --  needs to show how the cycle was reached.
      Active : Path_Vectors.Vector;
   end record;

end Adash.Scripting;

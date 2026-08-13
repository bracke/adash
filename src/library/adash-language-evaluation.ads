with Adash.Diagnostics;
with Adash.Language.Semantics;
with Adash.Language.Values;
with Adash.Language.Syntax;
with Adash.Source;

--  Running a program.
--
--  The last pass. Adash lexed, parsed and analysed the program itself; here the
--  analysed tree becomes instructions and `Adash.Machine` runs them.
--
--  The instruction set is what this package emits and nothing else. That is the
--  point of owning the machine: an opcode exists because a construct needs it,
--  so there is no encoding to get right against somebody else's compiler and no
--  table to populate on their behalf. `docs/hac-assessment.md` records the
--  dependency this replaced and why it ended.
--
--  Three consequences worth stating, because all three are visible from
--  outside:
--
--  A program is refused unless it both parsed and analysed. Running something
--  known to be illegal would produce a failure from the machine rather than the
--  diagnostic the user needs, and the diagnostic already exists by the time
--  this is called.
--
--  Every one of the five types is emitted: Integer, Boolean, Character, String
--  and Float. What cannot be lowered is reported as a structured failure naming
--  the construct rather than passed to the machine, which would otherwise
--  execute something the emitter did not mean.
--
--  A call is matched to its callee's parameters here as well as in the
--  analyser, through `Adash.Language.Semantics.Match_Arguments`. A call may
--  name its arguments or leave defaulted ones out, so position in the call is
--  not position in the profile; asking the same function twice is what keeps
--  the two passes from disagreeing about which argument is which.
package Adash.Language.Evaluation is

   --  What became of a run.
   type Outcome is
     (
      --  The program ran to completion.
      Evaluated,

      --  It was refused before anything ran: the tree did not parse, or
      --  analysis found it illegal. The diagnostics for that were reported by
      --  whichever pass found it, and this adds none.
      Refused,

      --  It is legal Adash and the lowering cannot yet emit it. Distinct from
      --  Refused because the program is not wrong -- Adash is incomplete -- and
      --  a user deserves to be told which of the two it is.
      Not_Lowerable,

      --  It ran and raised an exception the program did not handle.
      Raised,

      --  It was stopped from outside while it was running. Distinct from
      --  Raised because nothing went wrong with the program: somebody asked
      --  for it to stop, and a shell that reported an interrupted loop as a
      --  failure would be one whose scripts could not tell the two apart.
      Cancelled);

   --  Something that can be asked, while a program is running, whether it
   --  should stop.
   --
   --  A program can loop forever -- `loop null; end loop;` is legal -- so
   --  without this there is no way back from one. Asked between instructions
   --  by the machine, at whatever interval it chooses; a caller must not
   --  assume it is asked promptly, only that it is asked.
   type Cancellation_Source is limited interface;

   --  @param Source The caller's flag.
   --  @return True when the program should stop.
   function Is_Cancelled (Source : Cancellation_Source) return Boolean
     is abstract;

   --  A source to hand to Run.
   type Cancellation_Access is access all Cancellation_Source'Class;

   ---------------------------------------------------------------------
   --  Running a shell command from inside a lowered program.
   --
   --  A command changes the shell's own state, so it cannot run on the virtual
   --  machine: it has to run here, in this process, at the point the program
   --  reaches it. `Adash.Machine.Host` is exactly that -- an Ada subprogram a
   --  running program can call out to -- and the lowering emits the call.
   --
   --  What this package will *not* do is call Adash.Commands itself. Commands
   --  belong to the execution subsystem and this belongs to the language, and
   --  an edge from here to there would put the shell's vocabulary inside the
   --  compiler. Instead the caller supplies a sink, and Adash.Engine -- which
   --  already owns both -- implements it.
   ---------------------------------------------------------------------

   --  What a lowered program calls when it reaches a command.
   type Command_Sink is limited interface;

   --  Run one command.
   --
   --  @param Sink The caller's dispatcher.
   --  @param Name The command, as the program spelled it.
   --  @param Argument Its one argument, as the value the machine computed.
   --
   --         A value rather than text: the type the program wrote is the type
   --         the command receives, so nothing converts anything back and
   --         forth and `quit (3)` cannot arrive as the characters "3".
   --
   --         One argument, because no command available in this build takes
   --         more than one. A command that took two would need this widened,
   --         and the lowering refuses such a call rather than passing the
   --         first and losing the rest.
   --  @param Present False when the program called the command with no
   --         argument, which several accept.
   --  @param Failed True when the command reported a failure. The program
   --         carries on regardless; a command that fails is not an exception,
   --         and neither Ada nor a POSIX shell ends a sequence over one.
   --  @param Halt True when the command ended the session -- `quit` is the
   --         one that does. The program stops there rather than running the
   --         statements after it, which is what anybody writing `quit` means.
   --         Distinct from Failed because quitting is not a failure: `quit (0)`
   --         succeeds and still stops.
   --  Most arguments a command call can carry from a program.
   --
   --  A bound rather than a list, because the activation record the machine
   --  builds for the call has a fixed shape: every slot is pushed on every
   --  call, so the number of them is decided when the stub is built and not
   --  when a call is written. Five, because a call answered by the shell spends
   --  the first slot on the name of what is being asked for: `Output_Of
   --  ("git", "rev-parse", "HEAD")` is a program and two arguments *after*
   --  that name. A command spends none, and `start ("ls", "-l", "/tmp")` is
   --  three.
   Max_Command_Arguments : constant := 5;

   type Argument_Values is
     array (1 .. Max_Command_Arguments) of Adash.Language.Values.Value;

   --  @param Arguments What the call was given, by position.
   --  @param Count How many of them are meaningful.
   procedure Invoke
     (Sink      : in out Command_Sink;
      Name      : String;
      Arguments : Argument_Values;
      Count     : Natural;
      Failed    : out Boolean;
      Halt      : out Boolean) is abstract;

   --  Something the shell knows, asked for from inside a program.
   --
   --  Until this existed the language could obtain nothing from outside itself:
   --  every predefined entity was a type, a Boolean literal or a way to write
   --  output, so a program computed from literals and could not read an
   --  environment variable or anything else the session knew. `cd (Home)` was
   --  unwritable.
   --
   --  The answer comes back through a parameter the machine passes by
   --  reference, which is the only direction that works: the record a call is
   --  given is popped when it returns, so a value written into it would be gone
   --  by the time anything could read it.
   --
   --  @param Sink The implementation.
   --  @param Named What is being asked for.
   --  What the answer's type is decides which cell it travels back in, so a
   --  sink answering with the wrong type is answering the wrong question. The
   --  argument is typed for the same reason: a whole number reduced to its
   --  image and parsed back would be a second place for the two sides to
   --  disagree about what was asked.
   --
   --  @param Arguments What the call was given, by position.
   --  @param Count How many of them are meaningful.
   --  @param Answer What the shell knows, or the empty string when it knows
   --         nothing of that name -- which is not an error: an unset variable
   --         is empty, as it is in every shell.
   procedure Ask
     (Sink      : in out Command_Sink;
      Named     : String;
      Arguments : Argument_Values;
      Count     : Natural;
      Answer    : out Adash.Language.Values.Value) is null;

   --  A variable's value, on its way out of the machine as the program ends.
   --
   --  Its own operation rather than a call to a reserved command name. The
   --  value travels the road a command call travels -- that road already
   --  carries a name and typed values out of the machine, and a second one
   --  would be a second thing to keep in step -- but it arrives here, so a
   --  sink that only cares about commands is not handed something that is not
   --  one. A test probe counting command calls found the difference first.
   --
   --  Null by default: a caller that does not carry values between submissions
   --  need not say so.
   --
   --  @param Sink The implementation.
   --  @param Named The variable.
   --  @param Shape How it was declared -- its type, and `constant` when it was
   --         one, so a constant does not come back assignable.
   --  @param Given Its value as text: `'Image` for a scalar, the contents for
   --         a String.
   procedure Keep_Value
     (Sink  : in out Command_Sink;
      Named : String;
      Shape : String;
      Given : String) is null;

   --  A sink to hand to Run.
   type Sink_Access is access all Command_Sink'Class;

   --  Lower a program and run it.
   --
   --  @param Tree The parsed program.
   --  @param Analysis Its analysis, from Adash.Language.Semantics.
   --  @param Origin Where the source came from, for diagnostics.
   --  @param Result What became of the run.
   --  @param Report Where diagnostics go.
   --  @param On_Command Where a command call goes. Null means a program may
   --         not call one, and a call is refused rather than ignored: a caller
   --         that did not supply a sink is one that cannot run commands, and
   --         silently skipping them would make the program mean something else.
   procedure Run
     (Tree     : Adash.Language.Syntax.Tree;
      Analysis : Adash.Language.Semantics.Analysis;
      Origin   : Adash.Source.Origin;
      Result   : out Outcome;
      Report   : in out Adash.Diagnostics.List;
      On_Command : Sink_Access := null;
      Cancel     : Cancellation_Access := null);

   --  How many instructions the last lowering emitted.
   --
   --  For a test that wants to know code was produced rather than that nothing
   --  happened quietly, and for a benchmark. Zero before anything is lowered.
   --
   --  @return The instruction count of the most recent Run.
   function Last_Instruction_Count return Natural;

end Adash.Language.Evaluation;

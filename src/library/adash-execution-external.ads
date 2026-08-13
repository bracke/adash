with Hostkit.Spawn;

with Adash.Errors;
with Adash.Execution.Commands;

--  Finding and starting external programs.
--
--  Resolution is deterministic and is documented here because a shell that
--  cannot say where a command came from is a shell nobody can debug:
--
--    * A program containing a path separator is a path. It is used as given,
--      relative to the working directory of the invocation, and is never looked
--      up on PATH -- so `./build` runs the one here and not one that happens to
--      be installed.
--    * Anything else is looked up on the PATH of the *invocation's* environment,
--      not of the shell's own. A command run with a modified PATH must be found
--      with it; that is what a user who set it meant.
--    * The lookup is the host's, through hostkit, so Windows finds a name with
--      any of its PATHEXT suffixes and POSIX does not invent that behaviour.
--
--  There is no caching. A resolution cache is the classic shell bug -- a
--  program installed while the shell is running is not found, or one removed is
--  still "found" and then fails to start -- and it buys nothing until profiling
--  says it does. If one is added it needs an invalidation rule documented here
--  alongside these three.
package Adash.Execution.External is

   --  Where a program was found, if it was.
   type Resolution is record
      Found : Boolean := False;

      --  The path it resolved to, meaningful only when Found.
      Path : Adash.Execution.Commands.UString;

      --  True when the program named a path rather than being looked up. Worth
      --  reporting: "no such file" and "not on PATH" are different mistakes and
      --  a user can act on the difference.
      Was_Path : Boolean := False;
   end record;

   --  Find a program without starting it.
   --
   --  For completion, for `type`-style inspection, and for reporting "command
   --  not found" before anything irreversible happens. It is not what Start
   --  relies on: see the note there.
   --
   --  @param Item The invocation whose program and environment to use.
   --  @return Where it was found.
   function Resolve
     (Item : Adash.Execution.Commands.Invocation) return Resolution;

   --  Start a program.
   --
   --  Start does not consult Resolve. The host looks the program up itself, as
   --  part of the same call that runs it, so there is no window between the two
   --  in which the answer could change -- and no chance of the shell reporting
   --  a path it then did not run. Resolve exists for the questions that are not
   --  "run this".
   --
   --  The invocation's owned stream endpoints are released before this returns,
   --  whether it succeeded or not: the child has its copies by then, and the
   --  shell holding on is what stops a pipeline from ever finishing.
   --
   --  @param Item What to run. Released before returning.
   --  @param Process The started process, valid only when this returns True.
   --  @param Error Why it could not start, when this returns False.
   --  @return True when the program started.
   function Start
     (Item    : in out Adash.Execution.Commands.Invocation;
      Process : out Hostkit.Spawn.Process_Handle;
      Error   : out Adash.Errors.Error_Info) return Boolean;

   --  Start a program in a process group, for job control.
   --
   --  @param Item What to run. Released before returning.
   --  @param Join_Group The group to join, or 0 to lead a new one.
   --  @param Process The started process, valid only when this returns True.
   --  @param Error Why it could not start, when this returns False.
   --  @return True when the program started.
   function Start_In_Group
     (Item       : in out Adash.Execution.Commands.Invocation;
      Join_Group : Integer;
      Process    : out Hostkit.Spawn.Process_Handle;
      Error      : out Adash.Errors.Error_Info) return Boolean;

   --  What one ask about a process found.
   --
   --  Four answers, not two. A suspended program has neither finished nor is
   --  it running, and answering "not finished" for both is what made a
   --  suspended job indistinguishable from a busy one -- which left every part
   --  of this shell that knew about suspended jobs unable to see one.
   --
   --  Suspending and resuming are *events*: the host reports each once, and a
   --  later ask about a program that is still suspended answers Running. A
   --  caller that wants the state rather than the event remembers what it was
   --  last told, which is what Adash.Execution.Pipelines does.
   type Observation is
     (
      --  Running, or suspended and already reported as such.
      Observed_Running,

      --  It has just stopped, and can be resumed.
      Observed_Suspended,

      --  It has just been resumed.
      Observed_Resumed,

      --  It is over; see the status.
      Observed_Ended);

   --  Wait for a started program and report what became of it.
   --
   --  @param Process The process to wait for.
   --  @param Blocking True to wait, False to poll.
   --  @param Status What became of it, meaningful only for Observed_Ended.
   --  @return What this ask found.
   function Wait
     (Process  : Hostkit.Spawn.Process_Handle;
      Blocking : Boolean;
      Status   : out Adash.Execution.Exit_Status) return Observation;

end Adash.Execution.External;

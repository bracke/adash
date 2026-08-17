with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Hostkit.Spawn;

with Adash.Errors;
with Adash.Filesystem;
with Adash.Execution.Cancellation;
with Adash.Execution.Commands;

--  Wiring commands to each other.
--
--  Planning is separate from execution, as with redirection and for a stronger
--  reason: by the time the second stage is started the first is already
--  running, and there is no undo. Everything that can be decided beforehand is.
--
--  Starting is separate from waiting, which is what makes a background job
--  possible at all: the shell starts every stage, and then either waits (a
--  foreground job) or does not (a background one) while keeping enough to ask
--  later. A design that only offered "run to completion" could not express the
--  second, and bolting it on afterwards is how a shell ends up with two
--  execution paths that disagree.
--
--  The order the wiring happens in is the whole difficulty, and every part of
--  it has been a real bug in some shell:
--
--    * A pipe is made, a stage is started with its write end, and then the
--      parent closes its own copy. Skipping the last step leaves a live writer
--      for ever and the reader downstream never sees end-of-file: the pipeline
--      hangs, and only sometimes.
--    * Each stage's read end comes from the previous stage's pipe and is
--      likewise closed by the parent once handed over.
--    * Every descriptor is close-on-exec and is opened up for exactly the child
--      that should have it, so stage three does not inherit stage one's pipe.
--    * Stages share one process group, so a single Ctrl-C reaches all of them.
--      Signalling only the leader leaves the rest running.
--
--  A pipeline's status is its last stage's. That is the convention every script
--  already depends on; the earlier stages' statuses are kept as well, because a
--  shell has to be able to say which stage actually failed.
package Adash.Execution.Pipelines is

   --  A pipeline being built.
   type Plan is private;

   --  @return A plan with no stages.
   function Empty_Plan return Plan;

   --  Add a stage. The first reads the shell's input; each later one reads the
   --  previous stage's output.
   --
   --  @param Item Plan to extend.
   --  @param Stage The command for this stage.
   procedure Add_Stage
     (Item  : in out Plan;
      Stage : Adash.Execution.Commands.Invocation);

   --  @param Item Plan to inspect.
   --  @return Stage count.
   function Length (Item : Plan) return Natural;

   --  A pipeline whose stages have been started.
   --
   --  Copyable, so a job table can hold one. It refers to processes rather than
   --  owning them: two copies would both report what became of the same
   --  children, which is harmless, but only one of them should be the one a
   --  shell keeps.
   type Running is private;

   --  @param Item Running pipeline to inspect.
   --  @return How many stages it has.
   function Stage_Count (Item : Running) return Natural;

   --  The process group the stages were placed in, or -1 where the host has
   --  none. What a signal and a job table are given.
   --
   --  @param Item Running pipeline to inspect.
   --  @return Its process group.
   function Group (Item : Running) return Integer;

   --  What became of every stage, in order.
   package Status_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Adash.Execution.Exit_Status);

   --  The result of running a pipeline.
   type Outcome is record
      --  The status of the last stage, which is the pipeline's own.
      Status : Adash.Execution.Exit_Status;

      --  Every stage's status, in order.
      Stages : Status_Vectors.Vector;

      --  The process group, or -1.
      Group : Integer := -1;
   end record;

   --  The terminal, handed to a job for as long as it runs.
   --
   --  A child is started in a process group of its own -- that is what makes a
   --  job a job, and what lets a signal reach the job rather than the shell.
   --  The cost of it is that the group is not the terminal's foreground one,
   --  and a POSIX terminal stops any program in another group that reads it.
   --  So a program that asks a question was stopped where it asked, and a
   --  shell running `cat` looked like a shell that had hung.
   --
   --  Giving the terminal to the job is what every shell does about that, and
   --  taking it back afterwards is the other half: a shell that forgot would
   --  leave the terminal owned by a group with nothing in it, and its own next
   --  read would stop it.
   --
   --  Safe to call from a shell that has ignored Signal_Background_Write. The
   --  handover itself raises that signal at a process that does not own the
   --  terminal, and a shell that had not refused it would stop itself in the
   --  act of reclaiming its own terminal -- which is the failure hostkit warns
   --  about where it declares this.
   --  @param Group The job's process group, or -1 to do nothing.
   --  @param Taken Whoever had the terminal before, to give it back to, or -1
   --         where nothing was handed over.
   procedure Hand_The_Terminal_To (Group : Integer; Taken : out Integer);

   --  Give it back to whoever had it.
   --
   --  @param Group What Hand_The_Terminal_To reported, or -1 to do nothing.
   procedure Take_The_Terminal_Back (Group : Integer);

   --  Start every stage, waiting for none of them.
   --
   --  Waiting on the first before starting the second would deadlock the moment
   --  the first filled a pipe nobody was reading, so this starts them all or
   --  fails having reaped whatever it had already started.
   --
   --  @param Item The pipeline to start. Its stages are consumed.
   --  @param Started The started pipeline, valid only when this returns True.
   --  @param Error Why it could not be started.
   --  @return True when every stage started.
   function Start
     (Item    : in out Plan;
      Started : out Running;
      Error   : out Adash.Errors.Error_Info) return Boolean;

   --  Ask the host what has become of each stage, without blocking.
   --
   --  What a shell calls before printing a prompt, to find the background job
   --  that finished while the user was typing.
   --
   --  @param Item Running pipeline to update.
   procedure Refresh (Item : in out Running);

   --  Whether every stage has finished.
   --
   --  @param Item Running pipeline to inspect.
   --  @return True when nothing is left running or stopped.
   function Is_Finished (Item : Running) return Boolean;

   --  Whether any stage is stopped and could be resumed.
   --
   --  A stopped pipeline has not finished and must not be reported as though it
   --  had -- that is how a shell loses a suspended job.
   --
   --  @param Item Running pipeline to inspect.
   --  @return True when a stage is stopped.
   function Is_Stopped (Item : Running) return Boolean;

   --  What has been observed so far.
   --
   --  Meaningful once Is_Finished. Before that, stages that have not ended
   --  carry a running status.
   --
   --  @param Item Running pipeline to inspect.
   --  @return Its outcome.
   function Result (Item : Running) return Outcome;

   --  Wait for every stage, honouring a cancellation request.
   --
   --  When the token is asked to stop, the whole process group is asked to
   --  terminate -- the group, not the leader, or the rest of the pipeline keeps
   --  running. The wait then continues until the stages actually end, because
   --  returning while children are still alive would leave them unreaped and
   --  the shell unable to say what became of them.
   --
   --  @param Item Running pipeline to wait for.
   --  @param Cancel Asked periodically. Pass Cancellation.Never to wait
   --         uninterruptibly, which also takes the cheaper blocking path.
   --  @param Final What became of it.
   --  @return True when it finished; False when it stopped rather than ended,
   --          in which case the caller has a suspended job rather than a
   --          finished one.
   function Wait
     (Item   : in out Running;
      Cancel : access Adash.Execution.Cancellation.Token;
      Final  : out Outcome) return Boolean;

   --  Start a pipeline and wait for it.
   --
   --  @param Item The pipeline to run. Its stages are consumed.
   --  @param Cancel Asked periodically while waiting.
   --  @param Final What became of it.
   --  @param Error Why it could not be started. A stage that ran and failed is
   --         not an error -- that is Final.
   --  @return True when every stage started and the pipeline ended.
   --  Run a plan and collect what its last stage wrote.
   --
   --  What command substitution is made of: the shell reads a program's output
   --  as a value rather than letting it reach the terminal. The last stage
   --  writes into a pipe this reads to end of file *before* waiting -- a
   --  program that wrote more than a pipe holds would block for ever if the
   --  shell waited first, which is the classic way to deadlock a shell.
   --
   --  Standard error is not collected. It belongs to the user: a program that
   --  explains why it failed should be heard, not swallowed into a value the
   --  script is about to compare against something.
   --
   --  What comes back is bytes, exactly as written, with nothing trimmed.
   --  Dropping the final newline is a convention of whoever asked and not of
   --  running a program.
   --
   --  @param Item The plan; emptied, as Start empties it.
   --  @param Cancel How the user asks it to stop, or null.
   --  @param Written What the last stage wrote.
   --  @param Final What became of the stages.
   --  @param Error Why it could not be started.
   --  @return True when it ran.
   --  @param Limit The most this will collect, in bytes. A program that
   --         writes more is stopped and the capture refused: the shell holds
   --         what it captures in one String, so a program that never stops
   --         writing -- or one asked for a disk image -- would otherwise grow
   --         the session until the host ended it. Refused whole rather than
   --         truncated, because a script handed the first however-many bytes
   --         of an answer has no way to know that is what it got.
   --  Which of a program's streams a capture collects.
   type Captured_Streams is
     (
      --  What the program said. What a capture usually means.
      Only_Output,

      --  What it complained about, leaving its output where it was going.
      Only_Errors,

      --  Both, through one pipe, in the order the program wrote them.
      --
      --  Not the default and not a replacement for the other two: what a
      --  program says and what it complains about are two streams because they
      --  are two things, and a script that compares output against something
      --  does not want a warning in the middle of it. What this is for is the
      --  other case -- a record of what happened, in order, which is what a
      --  build log is.
      Everything);

   --  @param From Which of the last stage's streams to collect.
   function Capture
     (Item    : in out Plan;
      Cancel  : access Adash.Execution.Cancellation.Token;
      Written : out Ada.Strings.Unbounded.Unbounded_String;
      Final   : out Outcome;
      Error   : out Adash.Errors.Error_Info;
      Limit   : Natural := Adash.Filesystem.Default_Limit;
      From    : Captured_Streams := Only_Output) return Boolean;

   function Run
     (Item   : in out Plan;
      Cancel : access Adash.Execution.Cancellation.Token;
      Final  : out Outcome;
      Error  : out Adash.Errors.Error_Info) return Boolean;

private

   --  Ada.Containers.Vectors wants the element's "=" directly visible, and
   --  Invocation's is composed from components whose types are private to other
   --  packages. Making it visible here is enough; writing an equality for
   --  Invocation would be a function nothing calls, that something would
   --  eventually get wrong.
   use type Adash.Execution.Commands.Invocation;

   package Stage_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Adash.Execution.Commands.Invocation);

   --  One started stage, and what has been observed of it.
   type Stage_State is record
      Process  : Hostkit.Spawn.Process_Handle := Hostkit.Spawn.Invalid_Process;
      Status   : Adash.Execution.Exit_Status;
      Finished : Boolean := False;
      Stopped  : Boolean := False;
   end record;

   package State_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Stage_State);

   type Plan is record
      Stages : Stage_Vectors.Vector;
   end record;

   type Running is record
      States : State_Vectors.Vector;
      Group  : Integer := -1;

      --  True once a cancellation has been turned into a signal, so it is not
      --  sent again on every poll.
      Cancel_Signalled : Boolean := False;
   end record;

end Adash.Execution.Pipelines;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Messages;
with Adash.Execution.Cancellation;
with Adash.Execution.Pipelines;

--  What the shell is running, and what it was.
--
--  A job is a pipeline the shell is keeping track of. Foreground jobs are
--  tracked too, not only background ones: the shell has to be able to say what
--  it is waiting for, and a design that only records background work has to
--  invent a second representation the moment Ctrl-Z turns a foreground job into
--  a background one.
--
--  Identity is the shell's own, not the host's. A job number is small, stable
--  for the life of the session, and is what a user types; a process id is
--  reused by the kernel as soon as the process is reaped, so a table keyed by
--  one would eventually answer about the wrong program. The two are kept
--  together and only the job number is offered to users.
--
--  Numbers are not reused within a session, even after a job is removed. A user
--  who backgrounds a job, waits, and then refers to it by number must not reach
--  a different job that has since taken the number -- and the cost of never
--  reusing is a counter.
--
--  Nothing here writes to a terminal. A job that finishes while the user is
--  typing has to be reported, but *when* and *where* is the interactive
--  frontend's decision -- printing from here would corrupt a half-typed line.
--  This records that a change is unreported and lets the frontend collect it.
package Adash.Execution.Jobs is

   --  A job's identity within this session.
   type Job_Id is new Positive;

   --  A list of job numbers, for listing and for reporting changes.
   package Id_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Job_Id);

   --  What a job is doing.
   type Job_State is
     (
      --  At least one stage is still running.
      Job_Running,

      --  Suspended, and resumable.
      Job_Stopped,

      --  Every stage has ended.
      Job_Completed);

   --  What a state is called, in words.
   --
   --  `Job_State'Image` answers `JOB_RUNNING`, which is an identifier and was
   --  shown to users by `jobs` for as long as `jobs` has existed.
   --
   --  @param Item State to name.
   --  @return The message that says what it is.
   function Message (Item : Job_State) return Adash.Messages.Message_Id;

   --  Whether the shell is waiting for a job.
   type Job_Placement is (Placement_Foreground, Placement_Background);

   --  The shell's job table.
   --
   --  Limited: it owns running processes, and a copy would be a second table
   --  believing it was responsible for the same children.
   type Table is limited private;

   --  Take on a started pipeline as a job.
   --
   --  @param Item Table to add to.
   --  @param Pipeline The started pipeline. Consumed by the table.
   --  @param Description What the user typed, for a job listing. Text, but not
   --         a message: it is the user's own words echoed back, and there is
   --         nothing in it to translate.
   --  @param Placement Whether the shell will wait for it.
   --  @return The new job's number.
   --  The number of the job most recently added.
   --
   --  For a script that has just started something and wants to wait for it:
   --  `start` and `pipe_start` say the number on the shell's output, which is
   --  where a person reads it and nowhere a script can. Guessing is what the
   --  alternative amounts to -- the numbers count every job the session has
   --  run, foreground ones included, so the answer is knowable only by having
   --  counted along.
   --
   --  Still answered after the job has been forgotten: what a caller asked is
   --  which number was given out, and a job that has already ended is a
   --  reasonable thing to have missed.
   --
   --  @param Item The table.
   --  @return The number, or 0 where nothing has been started.
   function Most_Recent (Item : Table) return Natural;

   function Add
     (Item        : in out Table;
      Pipeline    : Adash.Execution.Pipelines.Running;
      Description : String;
      Placement   : Job_Placement) return Job_Id;

   --  Ask the host what has become of every job, without blocking.
   --
   --  What a shell calls before printing a prompt. Jobs that changed state
   --  become unreported, for the frontend to collect.
   --
   --  @param Item Table to update.
   procedure Refresh (Item : in out Table);

   --  How many jobs the table holds, finished ones included until they are
   --  reaped.
   --
   --  @param Item Table to inspect.
   --  @return Job count.
   function Length (Item : Table) return Natural;

   --  Whether a job number names a job this table holds.
   --
   --  @param Item Table to inspect.
   --  @param Id Job number.
   --  @return True when it is present.
   function Contains (Item : Table; Id : Job_Id) return Boolean;

   --  Every job number the table holds, in the order the jobs were added.
   --
   --  Deterministic, so a listing does not reorder itself between prompts.
   --
   --  @param Item Table to inspect.
   --  @return The job numbers.
   function Ids (Item : Table) return Id_Vectors.Vector;

   --  @param Item Table to inspect.
   --  @param Id Job to ask about.
   --  @return Its state, or Job_Completed for a job that is not there.
   function State (Item : Table; Id : Job_Id) return Job_State;

   --  @param Item Table to inspect.
   --  @param Id Job to ask about.
   --  @return Whether the shell is waiting for it.
   function Placement (Item : Table; Id : Job_Id) return Job_Placement;

   --  @param Item Table to inspect.
   --  @param Id Job to ask about.
   --  @return What the user typed for it.
   function Description (Item : Table; Id : Job_Id) return String;

   --  @param Item Table to inspect.
   --  @param Id Job to ask about.
   --  @return Its process group, or -1 where the host has none.
   function Group (Item : Table; Id : Job_Id) return Integer;

   --  What became of a job. Meaningful once its state is Job_Completed.
   --
   --  @param Item Table to inspect.
   --  @param Id Job to ask about.
   --  @return Its outcome.
   function Result
     (Item : Table; Id : Job_Id) return Adash.Execution.Pipelines.Outcome;

   --  Wait for a job to finish or stop, honouring cancellation.
   --
   --  @param Item Table holding the job.
   --  @param Id Job to wait for.
   --  @param Cancel Asked periodically while waiting.
   --  @param Error Why it could not be waited for -- an unknown job number.
   --  @return True when the job finished; False when it stopped instead, or
   --          when Error is set.
   function Wait
     (Item   : in out Table;
      Id     : Job_Id;
      Cancel : access Adash.Execution.Cancellation.Token;
      Error  : out Adash.Errors.Error_Info) return Boolean;

   --  Ask a job's whole process group to stop.
   --
   --  Sent to the group rather than to the leader, or the rest of the pipeline
   --  keeps running.
   --
   --  @param Item Table holding the job.
   --  @param Id Job to signal.
   --  @param Error Why it could not be signalled.
   --  @return True when the request reached the job.
   function Terminate_Job
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean;

   --  Ask a running job to stop, keeping it resumable.
   --
   --  The terminal's stop rather than the uncatchable one, which is what makes
   --  it the counterpart of Resume_In_Background: a program may notice this
   --  one and put itself in order first. A job stopped this way is still in
   --  the table and still owns its children -- that is the difference between
   --  stopping a job and ending it.
   --
   --  @param Item Table holding the job.
   --  @param Id Job to stop.
   --  @param Error Why it could not be stopped.
   --  @return True when the job was asked to stop.
   function Suspend
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean;

   --  Resume a stopped job, in the background.
   --
   --  @param Item Table holding the job.
   --  @param Id Job to resume.
   --  @param Error Why it could not be resumed.
   --  @return True when the job was asked to continue.
   function Resume_In_Background
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean;

   --  Jobs whose state changed since the last collection.
   --
   --  Collecting clears the flag, so each change is reported once. The frontend
   --  decides when and how; nothing here writes to a terminal, because a job
   --  finishing while the user is typing must not corrupt a half-typed line.
   --
   --  @param Item Table to collect from.
   --  @return The job numbers whose state changed.
   function Take_Unreported (Item : in out Table) return Id_Vectors.Vector;

   --  Remove every completed job whose change has been reported.
   --
   --  Kept until then on purpose: a job that finished must still be namable
   --  long enough for the shell to say so.
   --
   --  @param Item Table to prune.
   procedure Reap (Item : in out Table);

   --  Remove one job, reported or not.
   --
   --  What a foreground program needs. Reap keeps a finished job until its
   --  change has been announced, so that a background job is never removed
   --  before the shell has said it ended -- but a program run in the foreground
   --  has already been reported by the command that waited for it, and is not
   --  something a user tracks. Marking every job reported to get rid of one
   --  would swallow the notification a background job is still waiting to give.
   --
   --  @param Item Table holding the job.
   --  @param Id Job to remove; nothing happens when there is no such job.
   procedure Forget (Item : in out Table; Id : Job_Id);

private

   type Job is record
      Id          : Job_Id := 1;
      Pipeline    : Adash.Execution.Pipelines.Running;
      Description : Ada.Strings.Unbounded.Unbounded_String;
      Placement   : Job_Placement := Placement_Foreground;
      State       : Job_State := Job_Running;
      Unreported  : Boolean := False;
   end record;

   package Job_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Job);

   type Table is limited record
      Jobs : Job_Vectors.Vector;

      --  Never decreases, so a number is not reused within a session.
      Next_Id : Job_Id := 1;

      --  The last one handed out, so a caller can name what it just started.
      --
      --  A count rather than a Job_Id, because a Job_Id starts at one and the
      --  honest answer before anything has run is none at all.
      Last_Given : Natural := 0;
   end record;

end Adash.Execution.Jobs;

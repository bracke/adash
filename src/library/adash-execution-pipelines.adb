with Ada.Streams;

with Hostkit.Descriptors;
with Hostkit.Signals;

with Adash.Execution.External;
with Adash.Execution.Signals;

with Hostkit.Terminal_Control;
use type Adash.Execution.External.Observation;
with Adash.Execution.Streams;
with Adash.Platform;

package body Adash.Execution.Pipelines is

   package D renames Hostkit.Descriptors;
   package S renames Adash.Execution.Streams;
   package C renames Adash.Execution.Commands;

   --  How long to sleep between polls while waiting on a cancellable pipeline.
   --
   --  Only used on the cancellable path: without a token the wait blocks in the
   --  host and costs nothing. Short enough that a Ctrl-C feels immediate, long
   --  enough that a pipeline running for minutes does not spin a core. The
   --  alternative -- waking on SIGCHLD -- needs a handler, and hostkit
   --  deliberately offers only default and ignore.
   Poll_Interval : constant Duration := 0.005;

   ------------------
   -- Empty_Plan --
   ------------------

   function Empty_Plan return Plan is
      Result : Plan;
   begin
      return Result;
   end Empty_Plan;

   ---------------
   -- Add_Stage --
   ---------------

   procedure Add_Stage
     (Item  : in out Plan;
      Stage : Adash.Execution.Commands.Invocation)
   is
   begin
      Item.Stages.Append (Stage);
   end Add_Stage;

   ------------
   -- Length --
   ------------

   function Length (Item : Plan) return Natural is
   begin
      return Natural (Item.Stages.Length);
   end Length;

   -----------------
   -- Stage_Count --
   -----------------

   function Stage_Count (Item : Running) return Natural is
   begin
      return Natural (Item.States.Length);
   end Stage_Count;

   -----------
   -- Group --
   -----------

   function Group (Item : Running) return Integer is
   begin
      return Item.Group;
   end Group;

   -----------
   -- Start --
   -----------

   function Start
     (Item    : in out Plan;
      Started : out Running;
      Error   : out Adash.Errors.Error_Info) return Boolean
   is
      Count : constant Natural := Natural (Item.Stages.Length);

      --  The read end the next stage inherits, carried between iterations.
      Carried : S.Endpoint;

      Group_Leader : Integer := 0;
      Use_Groups   : constant Boolean :=
        Adash.Platform.Is_Available (Adash.Platform.Capability_Job_Control);

      procedure Reap_Started;

      --  A stage failed to start after earlier ones were already running. They
      --  cannot be un-started, so they are waited for rather than left as
      --  zombies. Their pipes are already closed, so each sees end-of-file and
      --  finishes on its own.
      procedure Reap_Started is
         Ignored : Adash.Execution.Exit_Status;
         Unused  : Adash.Execution.External.Observation;
      begin
         for State of Started.States loop
            Unused := Adash.Execution.External.Wait
              (State.Process, True, Ignored);
         end loop;

         Started.States.Clear;
      end Reap_Started;

   begin
      Started := (States           => State_Vectors.Empty_Vector,
                  Group            => -1,
                  Cancel_Signalled => False);
      Error := Adash.Errors.Success;

      if Count = 0 then
         --  An empty pipeline is not a failure and is not something to run.
         return True;
      end if;

      Carried := S.Inherited (S.Role_Input);

      for Index in 1 .. Count loop
         declare
            Stage : C.Invocation := Item.Stages.Element (Index);
            Ends  : D.Pipe_Ends;
            Last  : constant Boolean := Index = Count;
            State : Stage_State;
         begin
            --  The first stage reads the shell's input; every later one reads
            --  what the previous stage wrote -- unless the caller attached
            --  something itself, which is what a redirected input is. Taking
            --  it away was silent: the program ran, read nothing, and reported
            --  an empty file.
            if S.Is_Owned (Stage.Input) then
               S.Release (Carried);
            else
               Stage.Input := Carried;
            end if;

            if not Last then
               if not D.Create_Pipe (Ends) then
                  S.Release (Carried);
                  C.Release (Stage);
                  Reap_Started;
                  Error := Adash.Errors.Failure
                    (Adash.Errors.Error_Pipe_Creation_Failed);
                  return False;
               end if;

               Stage.Output := S.Owned (Ends.Write_End);
            end if;

            declare
               Ok : Boolean;
            begin
               if Use_Groups then
                  Ok := Adash.Execution.External.Start_In_Group
                    (Stage, Group_Leader, State.Process, Error);
               else
                  Ok := Adash.Execution.External.Start
                    (Stage, State.Process, Error);
               end if;

               --  Start released this stage's endpoints, including the write
               --  end just handed over and the read end carried in. That is the
               --  parent letting go, and without it the reader downstream would
               --  wait for a writer that has already exited.
               if not Ok then
                  if not Last then
                     D.Close (Ends.Read_End);
                  end if;

                  Reap_Started;
                  return False;
               end if;

               Started.States.Append (State);
            end;

            if Use_Groups and then Index = 1 then
               --  The first stage leads the group the rest will join.
               Group_Leader := Hostkit.Spawn.Group_Id (State.Process);
               Started.Group := Group_Leader;
            end if;

            if Last then
               Carried := S.Inherited (S.Role_Input);
            else
               --  Owned: released on the next iteration, once the next stage
               --  has been given it.
               Carried := S.Owned (Ends.Read_End);
            end if;
         end;
      end loop;

      Item.Stages.Clear;
      return True;
   end Start;

   -------------
   -- Refresh --
   -------------

   procedure Refresh (Item : in out Running) is
   begin
      for Index in 1 .. Natural (Item.States.Length) loop
         declare
            State : Stage_State := Item.States.Element (Index);
         begin
            if not State.Finished then
               --  A non-blocking ask. Suspending and resuming are events the
               --  host reports once, so what is remembered here is the state:
               --  a stage that has stopped stays stopped until it is seen to
               --  resume or to end. Asking again and believing the answer
               --  would make a suspended job look busy from the second poll
               --  onwards.
               case Adash.Execution.External.Wait
                      (State.Process, False, State.Status)
               is
                  when Adash.Execution.External.Observed_Ended =>
                     State.Finished := True;
                     State.Stopped  := False;

                  when Adash.Execution.External.Observed_Suspended =>
                     State.Stopped := True;

                  when Adash.Execution.External.Observed_Resumed =>
                     State.Stopped := False;

                  when Adash.Execution.External.Observed_Running =>
                     null;
               end case;

               Item.States.Replace_Element (Index, State);
            end if;
         end;
      end loop;
   end Refresh;

   ------------------
   -- Is_Finished --
   ------------------

   function Is_Finished (Item : Running) return Boolean is
   begin
      for State of Item.States loop
         if not State.Finished then
            return False;
         end if;
      end loop;

      return True;
   end Is_Finished;

   -----------------
   -- Is_Stopped --
   -----------------

   function Is_Stopped (Item : Running) return Boolean is
   begin
      for State of Item.States loop
         if State.Stopped then
            return True;
         end if;
      end loop;

      return False;
   end Is_Stopped;

   ------------
   -- Result --
   ------------

   function Result (Item : Running) return Outcome is
      Final : Outcome;
   begin
      Final.Group := Item.Group;

      for State of Item.States loop
         Final.Stages.Append (State.Status);
      end loop;

      if not Final.Stages.Is_Empty then
         --  The last stage's, which is the convention every script depends on.
         Final.Status := Final.Stages.Last_Element;
      end if;

      return Final;
   end Result;

   ----------
   -- Wait --
   ----------

   function Wait
     (Item   : in out Running;
      Cancel : access Adash.Execution.Cancellation.Token;
      Final  : out Outcome) return Boolean
   is
      Cancellable : constant Boolean := Cancel /= null;
   begin
      if Item.States.Is_Empty then
         Final := Result (Item);
         return True;
      end if;

      if not Cancellable then
         --  A suspended stage is never waited for, whether the caller can
         --  interrupt or not. The host reports a stop once; a blocking wait
         --  afterwards has no event left to return and waits for an ending
         --  that a suspended program will never reach. The polling path below
         --  has always refused to wait for one, and this is the same rule.
         Refresh (Item);

         if Is_Stopped (Item) then
            Final := Result (Item);
            return False;
         end if;

         --  Nobody can ask this to stop, so block in the host rather than
         --  spin. One blocking wait per stage, in order; the order does not
         --  matter because every stage is already running.
         for Index in 1 .. Natural (Item.States.Length) loop
            declare
               State : Stage_State := Item.States.Element (Index);
            begin
               if not State.Finished then
                  if Adash.Execution.External.Wait
                       (State.Process, True, State.Status)
                     = Adash.Execution.External.Observed_Ended
                  then
                     State.Finished := True;
                     State.Stopped  := False;
                  end if;

                  Item.States.Replace_Element (Index, State);
               end if;
            end;
         end loop;

         Final := Result (Item);
         return True;
      end if;

      loop
         Refresh (Item);

         exit when Is_Finished (Item);

         if Cancel.Is_Requested and then not Item.Cancel_Signalled then
            --  Sent to the group, not to the leader: signalling only the first
            --  stage leaves the rest of the pipeline running, which is what a
            --  half-implemented Ctrl-C looks like.
            --
            --  The wait then continues rather than returning. Children that
            --  have been asked to stop are still alive, and returning now would
            --  leave them unreaped and the shell unable to say what became of
            --  them.
            if Item.Group > 0 then
               declare
                  Ignored : Boolean;
               begin
                  Ignored := Hostkit.Signals.Send_To_Group
                    (Item.Group, Hostkit.Signals.Signal_Terminate);
               end;
            else
               --  No process group -- a host without job control. Each stage is
               --  asked individually, which is the best this host can do and is
               --  why the capability is reported rather than assumed.
               for State of Item.States loop
                  if not State.Finished then
                     declare
                        Ignored : Boolean;
                     begin
                        Ignored := Hostkit.Signals.Send_To_Process
                          (Hostkit.Spawn.Process_Id (State.Process),
                           Hostkit.Signals.Signal_Terminate);
                     end;
                  end if;
               end loop;
            end if;

            Item.Cancel_Signalled := True;
         end if;

         if Is_Stopped (Item) then
            --  Suspended rather than finished. The caller has a job to put in a
            --  table, not a result to report.
            Final := Result (Item);
            return False;
         end if;

         delay Poll_Interval;
      end loop;

      Final := Result (Item);

      if Item.Cancel_Signalled then
         --  However the stages actually died, the pipeline was cancelled, and
         --  that is what a script branching on the result has to see. Reporting
         --  the terminating signal instead would say the program failed on its
         --  own.
         Final.Status := (Kind => Adash.Execution.Exit_Cancelled, others => <>);
      end if;

      return True;
   end Wait;

   ---------
   -- Run --
   ---------

   -------------
   -- Capture --
   -------------

   procedure Hand_The_Terminal_To (Group : Integer; Taken : out Integer) is
      Ours : Integer;
   begin
      Taken := -1;

      if Group < 0
        or else not Hostkit.Terminal_Control.Supports_Foreground_Group
        or else not D.Is_Terminal (D.Standard_Input)
      then
         return;
      end if;

      --  Whoever has it now, which is this shell in an ordinary session and
      --  something else in a shell that was itself started by one.
      if not Hostkit.Terminal_Control.Foreground_Group
               (D.Standard_Input, Ours)
      then
         return;
      end if;

      if Hostkit.Terminal_Control.Set_Foreground_Group
           (D.Standard_Input, Group)
      then
         Taken := Ours;
      end if;
   end Hand_The_Terminal_To;

   procedure Take_The_Terminal_Back (Group : Integer) is
      Ignored : Boolean;
   begin
      if Group < 0 then
         return;
      end if;

      Ignored :=
        Hostkit.Terminal_Control.Set_Foreground_Group
          (D.Standard_Input, Group);
   end Take_The_Terminal_Back;

   function Capture
     (Item    : in out Plan;
      Cancel  : access Adash.Execution.Cancellation.Token;
      Written : out Ada.Strings.Unbounded.Unbounded_String;
      Final   : out Outcome;
      Error   : out Adash.Errors.Error_Info;
      Limit   : Natural := Adash.Filesystem.Default_Limit) return Boolean
   is
      Count   : constant Natural := Natural (Item.Stages.Length);
      Ends    : D.Pipe_Ends;
      Started : Running;
      Ignored : Boolean;

      --  Whoever owned the terminal before this program was given it.
      Held_By_Us : Integer := -1;

      --  Whether the program wrote more than the caller will hold.
      Too_Much : Boolean := False;

      --  Taken before anything runs. A plan hands its stages over when it
      --  starts, so asking afterwards asks an empty one -- which raised where
      --  the refusal below was being reported, and only for the program that
      --  wrote too much, which is the least likely thing anybody runs twice.
      Named : constant String :=
        (if Count > 0
         then Adash.Execution.Commands.Program (Item.Stages.Element (1))
         else "");
   begin
      Written := Ada.Strings.Unbounded.Null_Unbounded_String;
      Final := (Status => Adash.Execution.Success,
                Stages => Status_Vectors.Empty_Vector,
                Group  => -1);
      Error := Adash.Errors.Success;

      if Count = 0 then
         return True;
      end if;

      if not D.Create_Pipe (Ends) then
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Pipe_Creation_Failed);
         return False;
      end if;

      --  The last stage writes into the pipe instead of to the shell's own
      --  output. Start attaches the pipes *between* stages and leaves the last
      --  one's output as the caller set it, which is the same door a redirected
      --  pipeline goes through.
      declare
         Last : C.Invocation := Item.Stages.Element (Count);
      begin
         Last.Output := S.Owned (Ends.Write_End);
         Item.Stages.Replace_Element (Count, Last);
      end;

      if not Start (Item, Started, Error) then
         D.Close (Ends.Read_End);
         return False;
      end if;

      --  The terminal, for as long as these programs have it. Their output is
      --  a pipe, which is what makes this a capture -- their *input* is still
      --  the terminal, and a program reading a line from a console the shell
      --  is holding raw for its own reasons is a program whose user cannot see
      --  what they type.
      Adash.Execution.Signals.Hand_Over_Terminal;
      Hand_The_Terminal_To (Group (Started), Held_By_Us);

      --  Read to end of file before waiting. A program that writes more than a
      --  pipe holds blocks until somebody drains it, and a shell that waited
      --  first would be that somebody -- waiting for a program that is waiting
      --  for the shell.
      declare
         Chunk   : Ada.Streams.Stream_Element_Array (1 .. 4096);
         Last    : Ada.Streams.Stream_Element_Offset;
         Outcome : D.Transfer_Outcome;

         --  Only worth asking when somebody can ask it to stop. Where the host
         --  cannot express it -- Windows anonymous pipes -- the read blocks and
         --  the interrupt is noticed at the wait instead, which is the best
         --  that host offers rather than a pretence.
         Watching : constant Boolean :=
           Cancel /= null
             and then D.Set_Non_Blocking (Ends.Read_End, True);
      begin
         loop
            Outcome := D.Read (Ends.Read_End, Chunk, Last);

            case Outcome is
               when D.Transfer_Ok =>
                  --  Counted before it is kept. A shell that noticed
                  --  afterwards would already be holding what it was trying
                  --  not to hold.
                  if Ada.Strings.Unbounded.Length (Written) + Natural (Last)
                     > Limit
                  then
                     Too_Much := True;
                     exit;
                  end if;

                  for Index in Chunk'First .. Last loop
                     Ada.Strings.Unbounded.Append
                       (Written, Character'Val (Natural (Chunk (Index))));
                  end loop;

               when D.Transfer_End_Of_File =>
                  exit;

               when D.Transfer_Interrupted =>
                  --  A signal arrived before anything was read. Retrying is
                  --  what the contract asks for; the interrupt itself is seen
                  --  below.
                  null;

               when D.Transfer_Would_Block =>
                  exit when Watching and then Cancel.Is_Requested;
                  delay Poll_Interval;

               when others =>
                  --  Broken, or the host refused. Whatever was read is what
                  --  there is; the wait below says what became of the program.
                  exit;
            end case;
         end loop;
      end;

      --  Closed here whether or not this read everything, and that is how a
      --  program that will not stop writing is stopped: the next write into a
      --  pipe nobody holds open fails, and the program ends with it. No signal
      --  is involved, which matters on the host that has none.
      D.Close (Ends.Read_End);

      Ignored := Wait (Started, Cancel, Final);

      Take_The_Terminal_Back (Held_By_Us);
      Adash.Execution.Signals.Take_Terminal_Back;

      if Too_Much then
         --  Nothing rather than the first part of something: a script handed
         --  the beginning of an answer has no way to tell that is what it got.
         Written := Ada.Strings.Unbounded.Null_Unbounded_String;
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Output_Too_Large,
            [1 => Adash.Messages.Named ("program", Named)]);
         return False;
      end if;

      return True;
   end Capture;

   ---------
   -- Run --
   ---------

   function Run
     (Item   : in out Plan;
      Cancel : access Adash.Execution.Cancellation.Token;
      Final  : out Outcome;
      Error  : out Adash.Errors.Error_Info) return Boolean
   is
      Started : Running;
      Ignored : Boolean;
   begin
      Final := (Status => Adash.Execution.Success,
                Stages => Status_Vectors.Empty_Vector,
                Group  => -1);

      if not Start (Item, Started, Error) then
         return False;
      end if;

      --  The terminal, for as long as this program has it, in both senses.
      --
      --  On a host where the shell watches its terminal for Ctrl-C, watching
      --  means holding it raw, and a program handed a raw console is one
      --  nobody can type a line into. On a host with process groups, the job
      --  is in a group of its own and a terminal stops any other group that
      --  reads it. Neither is the other, and a program that asks a question
      --  needs both.
      Adash.Execution.Signals.Hand_Over_Terminal;

      declare
         Ours : Integer;
      begin
         Hand_The_Terminal_To (Group (Started), Ours);

         Ignored := Wait (Started, Cancel, Final);

         Take_The_Terminal_Back (Ours);
      end;

      Adash.Execution.Signals.Take_Terminal_Back;
      return True;
   end Run;

end Adash.Execution.Pipelines;

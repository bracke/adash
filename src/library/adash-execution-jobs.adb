with Hostkit.Signals;

with Adash.Platform;

package body Adash.Execution.Jobs is

   use Ada.Strings.Unbounded;

   package P renames Adash.Execution.Pipelines;

   -------------
   -- Message --
   -------------

   function Message (Item : Job_State) return Adash.Messages.Message_Id is
   begin
      case Item is
         when Job_Running   => return Adash.Messages.Msg_Job_State_Running;
         when Job_Stopped   => return Adash.Messages.Msg_Job_State_Stopped;
         when Job_Completed => return Adash.Messages.Msg_Job_State_Completed;
      end case;
   end Message;

   function Find (Item : Table; Id : Job_Id) return Natural;
   --  The index of a job, or 0 when it is not there.

   function Unknown (Id : Job_Id) return Adash.Errors.Error_Info;
   --  The failure for a job number nothing answers to.

   function Observed_State (Pipeline : P.Running) return Job_State;
   --  What a pipeline's stages say the job is doing.

   ----------
   -- Find --
   ----------

   function Find (Item : Table; Id : Job_Id) return Natural is
   begin
      for Index in 1 .. Natural (Item.Jobs.Length) loop
         if Item.Jobs.Element (Index).Id = Id then
            return Index;
         end if;
      end loop;

      return 0;
   end Find;

   -------------
   -- Unknown --
   -------------

   function Unknown (Id : Job_Id) return Adash.Errors.Error_Info is
      Image : constant String := Job_Id'Image (Id);
   begin
      return Adash.Errors.Failure
        (Adash.Errors.Error_Job_Unknown,
         [1 => Adash.Messages.Named
                 ("job", Image (Image'First + 1 .. Image'Last))]);
   end Unknown;

   ---------------------
   -- Observed_State --
   ---------------------

   function Observed_State (Pipeline : P.Running) return Job_State is
   begin
      --  Stopped is checked first. A pipeline with one suspended stage and the
      --  rest finished is a suspended job, not a completed one -- reporting it
      --  as completed is how a shell loses a job a user could have resumed.
      if P.Is_Stopped (Pipeline) then
         return Job_Stopped;
      elsif P.Is_Finished (Pipeline) then
         return Job_Completed;
      else
         return Job_Running;
      end if;
   end Observed_State;

   ---------
   -- Add --
   ---------

   -------------------
   -- Most_Recent --
   -------------------

   function Most_Recent (Item : Table) return Natural is
   begin
      return Item.Last_Given;
   end Most_Recent;

   function Add
     (Item        : in out Table;
      Pipeline    : P.Running;
      Description : String;
      Placement   : Job_Placement) return Job_Id
   is
      New_Job : Job;
   begin
      New_Job.Id          := Item.Next_Id;
      New_Job.Pipeline    := Pipeline;
      New_Job.Description := To_Unbounded_String (Description);
      New_Job.Placement   := Placement;
      New_Job.State       := Observed_State (Pipeline);
      New_Job.Unreported  := False;

      Item.Jobs.Append (New_Job);

      --  Never reused, even after Reap. A user who backgrounds a job, waits,
      --  and then names it by number must not reach a different job that has
      --  taken the number since.
      Item.Last_Given := Natural (New_Job.Id);
      Item.Next_Id := Item.Next_Id + 1;

      return New_Job.Id;
   end Add;

   -------------
   -- Refresh --
   -------------

   procedure Refresh (Item : in out Table) is
   begin
      for Index in 1 .. Natural (Item.Jobs.Length) loop
         declare
            Current : Job := Item.Jobs.Element (Index);
            Before  : constant Job_State := Current.State;
         begin
            if Current.State /= Job_Completed then
               P.Refresh (Current.Pipeline);
               Current.State := Observed_State (Current.Pipeline);

               --  Only a change is worth telling the user about. Marking every
               --  poll unreported would make a prompt announce a job that has
               --  been running quietly for an hour.
               if Current.State /= Before then
                  Current.Unreported := True;
               end if;

               Item.Jobs.Replace_Element (Index, Current);
            end if;
         end;
      end loop;
   end Refresh;

   ------------
   -- Length --
   ------------

   function Length (Item : Table) return Natural is
   begin
      return Natural (Item.Jobs.Length);
   end Length;

   --------------
   -- Contains --
   --------------

   function Contains (Item : Table; Id : Job_Id) return Boolean is
   begin
      return Find (Item, Id) /= 0;
   end Contains;

   ---------
   -- Ids --
   ---------

   function Ids (Item : Table) return Id_Vectors.Vector is
      Result : Id_Vectors.Vector;
   begin
      for Current of Item.Jobs loop
         Result.Append (Current.Id);
      end loop;

      return Result;
   end Ids;

   -----------
   -- State --
   -----------

   function State (Item : Table; Id : Job_Id) return Job_State is
      Index : constant Natural := Find (Item, Id);
   begin
      if Index = 0 then
         --  A job that is not there is not running. Callers that need to tell
         --  "gone" from "finished" ask Contains, which is why this does not
         --  raise: a stale job number is something a user types, not a defect.
         return Job_Completed;
      end if;

      return Item.Jobs.Element (Index).State;
   end State;

   ---------------
   -- Placement --
   ---------------

   function Placement (Item : Table; Id : Job_Id) return Job_Placement is
      Index : constant Natural := Find (Item, Id);
   begin
      if Index = 0 then
         return Placement_Foreground;
      end if;

      return Item.Jobs.Element (Index).Placement;
   end Placement;

   -----------------
   -- Description --
   -----------------

   function Description (Item : Table; Id : Job_Id) return String is
      Index : constant Natural := Find (Item, Id);
   begin
      if Index = 0 then
         return "";
      end if;

      return To_String (Item.Jobs.Element (Index).Description);
   end Description;

   -----------
   -- Group --
   -----------

   function Group (Item : Table; Id : Job_Id) return Integer is
      Index : constant Natural := Find (Item, Id);
   begin
      if Index = 0 then
         return -1;
      end if;

      return P.Group (Item.Jobs.Element (Index).Pipeline);
   end Group;

   ------------
   -- Result --
   ------------

   function Result (Item : Table; Id : Job_Id) return P.Outcome is
      Index : constant Natural := Find (Item, Id);
   begin
      if Index = 0 then
         return (Status => Adash.Execution.Success,
                 Stages => P.Status_Vectors.Empty_Vector,
                 Group  => -1);
      end if;

      return P.Result (Item.Jobs.Element (Index).Pipeline);
   end Result;

   ----------
   -- Wait --
   ----------

   function Wait
     (Item   : in out Table;
      Id     : Job_Id;
      Cancel : access Adash.Execution.Cancellation.Token;
      Error  : out Adash.Errors.Error_Info) return Boolean
   is
      Index : constant Natural := Find (Item, Id);
   begin
      Error := Adash.Errors.Success;

      if Index = 0 then
         Error := Unknown (Id);
         return False;
      end if;

      declare
         Current  : Job := Item.Jobs.Element (Index);
         Final    : P.Outcome;
         Finished : constant Boolean := P.Wait (Current.Pipeline, Cancel, Final);
         Before   : constant Job_State := Current.State;
      begin
         Current.State := Observed_State (Current.Pipeline);

         if Current.State /= Before then
            Current.Unreported := True;
         end if;

         Item.Jobs.Replace_Element (Index, Current);
         return Finished;
      end;
   end Wait;

   --------------------
   -- Terminate_Job --
   --------------------

   function Terminate_Job
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
      Index : constant Natural := Find (Item, Id);
   begin
      Error := Adash.Errors.Success;

      if Index = 0 then
         Error := Unknown (Id);
         return False;
      end if;

      declare
         Current : constant Job := Item.Jobs.Element (Index);
         Job_Group : constant Integer := P.Group (Current.Pipeline);
      begin
         if Job_Group <= 0 then
            --  No process group: a host without job control, where a job is not
            --  a thing that can be signalled as one. Reported rather than
            --  half-done by signalling only the leader.
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Capability_Unavailable,
               Adash.Messages.No_Arguments,
               Quoted =>
                 Adash.Platform.Message (Adash.Platform.Capability_Job_Control),
               Fills => "capability");
            return False;
         end if;

         return Hostkit.Signals.Send_To_Group
           (Job_Group, Hostkit.Signals.Signal_Terminate);
      end;
   end Terminate_Job;

   ------------
   -- Settle --
   ------------

   --  Wait a short while for a job to reach the state it was asked for.
   --
   --  Stopping and continuing are asks, not effects: the host carries them out
   --  when it does, and a program may catch a terminal stop and go on running.
   --  Polling briefly is what lets the shell report what happened rather than
   --  what it requested -- and what makes the answer the same on a machine
   --  under load as on an idle one.
   --
   --  The bound is short enough that a shell never feels stuck and long enough
   --  that a scheduler delay does not decide the answer. A job that has not
   --  reached the state by then is reported as whatever it is, which for a
   --  program that caught the signal is the truth.
   procedure Settle
     (Item   : in out Table;
      Index  : Positive;
      Wanted : Job_State);

   procedure Settle
     (Item   : in out Table;
      Index  : Positive;
      Wanted : Job_State)
   is
      Step  : constant Duration := 0.005;
      Tries : constant Natural := 100;
   begin
      for Unused in 1 .. Tries loop
         declare
            Current : Job := Item.Jobs.Element (Index);
         begin
            P.Refresh (Current.Pipeline);
            Current.State := Observed_State (Current.Pipeline);
            Item.Jobs.Replace_Element (Index, Current);

            exit when Current.State = Wanted
              or else Current.State = Job_Completed;
         end;

         delay Step;
      end loop;
   end Settle;

   -------------
   -- Suspend --
   -------------

   function Suspend
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
      Index : constant Natural := Find (Item, Id);
   begin
      Error := Adash.Errors.Success;

      if Index = 0 then
         Error := Unknown (Id);
         return False;
      end if;

      declare
         Current   : constant Job := Item.Jobs.Element (Index);
         Job_Group : constant Integer := P.Group (Current.Pipeline);
      begin
         if Job_Group <= 0 then
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Capability_Unavailable,
               Adash.Messages.No_Arguments,
               Quoted =>
                 Adash.Platform.Message (Adash.Platform.Capability_Job_Control),
               Fills => "capability");
            return False;
         end if;

         if not Hostkit.Signals.Send_To_Group
           (Job_Group, Hostkit.Signals.Signal_Terminal_Stop)
         then
            return False;
         end if;

         --  Asked, then confirmed. A shell that said `stopped` the instant it
         --  sent the signal would be reporting its own intention: the host
         --  delivers it when it delivers it, and the program may catch it and
         --  keep going. Waiting a short while for the children to actually
         --  stop is what makes the answer true.
         Settle (Item, Index, Job_Stopped);
         return True;
      end;
   end Suspend;

   ----------------------------
   -- Resume_In_Background --
   ----------------------------

   --  The two resumptions differ in one field and in who waits.
   function Resume (Item : in out Table;
                    Id : Job_Id;
                    Into : Job_Placement;
                    Error : out Adash.Errors.Error_Info) return Boolean;

   function Resume (Item : in out Table;
                    Id : Job_Id;
                    Into : Job_Placement;
                    Error : out Adash.Errors.Error_Info) return Boolean
   is
      Index : constant Natural := Find (Item, Id);
   begin
      Error := Adash.Errors.Success;

      if Index = 0 then
         Error := Unknown (Id);
         return False;
      end if;

      declare
         Current   : Job := Item.Jobs.Element (Index);
         Job_Group : constant Integer := P.Group (Current.Pipeline);
      begin
         if Job_Group <= 0 then
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Capability_Unavailable,
               Adash.Messages.No_Arguments,
               Quoted =>
                 Adash.Platform.Message (Adash.Platform.Capability_Job_Control),
               Fills => "capability");
            return False;
         end if;

         if not Hostkit.Signals.Send_To_Group
           (Job_Group, Hostkit.Signals.Signal_Continue)
         then
            return False;
         end if;

         Current.Placement := Into;
         Item.Jobs.Replace_Element (Index, Current);

         --  Confirmed for the same reason a stop is.
         Settle (Item, Index, Job_Running);
         return True;
      end;
   end Resume;

   ------------------------------
   -- Resume_In_Foreground --
   ------------------------------

   function Resume_In_Foreground
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
   begin
      return Resume (Item, Id, Placement_Foreground, Error);
   end Resume_In_Foreground;

   function Resume_In_Background
     (Item  : in out Table;
      Id    : Job_Id;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
   begin
      return Resume (Item, Id, Placement_Background, Error);
   end Resume_In_Background;

   --------------------------
   -- Take_Unreported --
   --------------------------

   function Take_Unreported (Item : in out Table) return Id_Vectors.Vector is
      Result : Id_Vectors.Vector;
   begin
      for Index in 1 .. Natural (Item.Jobs.Length) loop
         declare
            Current : Job := Item.Jobs.Element (Index);
         begin
            if Current.Unreported then
               Result.Append (Current.Id);

               --  Cleared as it is collected, so each change is reported once.
               Current.Unreported := False;
               Item.Jobs.Replace_Element (Index, Current);
            end if;
         end;
      end loop;

      return Result;
   end Take_Unreported;

   ----------
   -- Reap --
   ----------

   ------------
   -- Forget --
   ------------

   procedure Forget (Item : in out Table; Id : Job_Id) is
   begin
      for Index in 1 .. Natural (Item.Jobs.Length) loop
         if Item.Jobs.Element (Index).Id = Id then
            Item.Jobs.Delete (Index);
            return;
         end if;
      end loop;
   end Forget;

   procedure Reap (Item : in out Table) is
      Index : Natural := 1;
   begin
      while Index <= Natural (Item.Jobs.Length) loop
         declare
            Current : constant Job := Item.Jobs.Element (Index);
         begin
            --  Only once the change has been reported. A job that finished must
            --  stay namable long enough for the shell to say so.
            if Current.State = Job_Completed and then not Current.Unreported then
               Item.Jobs.Delete (Index);
            else
               Index := Index + 1;
            end if;
         end;
      end loop;
   end Reap;

end Adash.Execution.Jobs;

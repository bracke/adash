with Ada.Characters.Latin_1;
with Ada.Finalization;
with Ada.Streams;
with Ada.Strings.Unbounded;

with Adash.Execution.Signals;

with Hostkit.Terminal_Control;
with Hostkit.Fs;

package body Adash.Execution.Streams is

   package D renames Hostkit.Descriptors;

   ----------
   -- Name --
   ----------

   function Name (Item : Stream_Role) return String is
   begin
      case Item is
         when Role_Input  => return "INPUT";
         when Role_Output => return "OUTPUT";
         when Role_Error  => return "ERROR";
      end case;
   end Name;

   ---------------
   -- Inherited --
   ---------------

   function Inherited (Role : Stream_Role) return Endpoint is
   begin
      return (Handle =>
                (case Role is
                    when Role_Input  => D.Standard_Input,
                    when Role_Output => D.Standard_Output,
                    when Role_Error  => D.Standard_Error),
              Owned  => False);
   end Inherited;

   -----------
   -- Owned --
   -----------

   function Owned (Handle : D.Descriptor) return Endpoint is
   begin
      return (Handle => Handle, Owned => True);
   end Owned;

   --------------
   -- Borrowed --
   --------------

   function Borrowed (Handle : D.Descriptor) return Endpoint is
   begin
      return (Handle => Handle, Owned => False);
   end Borrowed;

   ------------
   -- Handle --
   ------------

   function Handle (Item : Endpoint) return D.Descriptor is
   begin
      return Item.Handle;
   end Handle;

   --------------
   -- Is_Owned --
   --------------

   function Is_Owned (Item : Endpoint) return Boolean is
   begin
      return Item.Owned;
   end Is_Owned;

   -----------------------
   -- Prepare_For_Child --
   -----------------------

   function Prepare_For_Child (Item : Endpoint) return Boolean is
   begin
      if not D.Is_Valid (Item.Handle) then
         return False;
      end if;

      return D.Set_Inheritable (Item.Handle, True);
   end Prepare_For_Child;

   -------------
   -- Release --
   -------------

   procedure Release (Item : in out Endpoint) is
   begin
      if Item.Owned then
         D.Close (Item.Handle);
      end if;

      --  Forgotten whether or not it was owned. A borrowed endpoint released
      --  twice must not be handed to anything a third time, and an owned one
      --  is already invalid after Close.
      Item := (Handle => D.Invalid, Owned => False);
   end Release;

   --  Whether a write to this program's output has failed. See the note in
   --  the specification: an ending that runs finalization cannot be allowed
   --  after this.
   Gone : Boolean := False;
   pragma Atomic (Gone);

   -------------------------
   -- Note_Output_Gone --
   -------------------------

   procedure Note_Output_Gone is
   begin
      Gone := True;
   end Note_Output_Gone;

   -----------------------
   -- Output_Is_Gone --
   -----------------------

   function Output_Is_Gone return Boolean is
   begin
      return Gone;
   end Output_Is_Gone;

   -----------------------
   -- Background_Input --
   -----------------------

   function Background_Input (Given : Endpoint) return Endpoint is
      Nothing : Hostkit.Descriptors.Descriptor;
   begin
      if Is_Owned (Given)
        or else not Adash.Execution.Signals.Watching
        or else Hostkit.Fs.Null_Device = ""
      then
         return Given;
      end if;

      if not Hostkit.Descriptors.Open_File
               (Hostkit.Fs.Null_Device,
                Hostkit.Descriptors.Open_Read, Nothing)
      then
         --  The device is named and would not open, which is a host in a state
         --  this cannot improve on. The job runs with what it had.
         return Given;
      end if;

      return Owned (Nothing);
   end Background_Input;

   ----------------
   -- Read_Line --
   ----------------

   --  What has been read and not yet handed out, and whether the host has said
   --  there is no more. Package state because there is one standard input:
   --  two buffers over one descriptor would each hold half of somebody's line.
   Held    : Ada.Strings.Unbounded.Unbounded_String;
   Drained : Boolean := False;

   function Read_Line
     (Ended : out Boolean;
      Limit : Positive := Adash.Filesystem.Default_Limit) return String
   is
      use Ada.Strings.Unbounded;

      --  The terminal, for as long as this read takes.
      --
      --  On a host where the shell watches its own terminal for Ctrl-C,
      --  watching means holding it raw -- and a raw terminal echoes nothing
      --  and ends a line with a carriage return, so a user answering a
      --  script's question would see nothing they typed and the read would
      --  wait for a line feed that never comes. Handed back for the duration
      --  and taken again afterwards, which is what a program the shell runs
      --  gets too.
      --
      --  A no-op everywhere else, and on the same host whenever nothing is
      --  being watched.
      type Borrowed_Terminal is new Ada.Finalization.Limited_Controlled with
        null record;

      overriding procedure Initialize (Item : in out Borrowed_Terminal);
      overriding procedure Finalize (Item : in out Borrowed_Terminal);

      overriding procedure Initialize (Item : in out Borrowed_Terminal) is
         pragma Unreferenced (Item);
      begin
         Adash.Execution.Signals.Hand_Over_Terminal;
      end Initialize;

      overriding procedure Finalize (Item : in out Borrowed_Terminal) is
         pragma Unreferenced (Item);
      begin
         Adash.Execution.Signals.Take_Terminal_Back;
      end Finalize;

      --  Declared before anything that returns, so every way out of this
      --  function puts the terminal back -- including the ones that raise.
      Borrowed : Borrowed_Terminal;
      pragma Unreferenced (Borrowed);

      --  Where the first line ends in what is held, or zero when no terminator
      --  has arrived yet.
      function Break return Natural;

      function Break return Natural is
      begin
         for Index in 1 .. Length (Held) loop
            if Element (Held, Index) = Ada.Characters.Latin_1.LF then
               return Index;
            end if;
         end loop;

         return 0;
      end Break;

      Chunk : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      Ended := False;

      loop
         declare
            At_Break : constant Natural := Break;
         begin
            if At_Break > 0 then
               declare
                  --  A CR before the newline belongs to the terminator. A file
                  --  written on another host is still a file this shell reads.
                  Stop : Natural := At_Break - 1;
               begin
                  if Stop > 0
                    and then Element (Held, Stop) = Ada.Characters.Latin_1.CR
                  then
                     Stop := Stop - 1;
                  end if;

                  return Line : constant String := Slice (Held, 1, Stop) do
                     Delete (Held, 1, At_Break);
                  end return;
               end;
            end if;
         end;

         --  As much as will be held, handed over as a line of its own. See the
         --  note in the specification: dropping it would lose input that
         --  cannot be asked for again.
         if Length (Held) >= Limit then
            return Line : constant String := Slice (Held, 1, Limit) do
               Delete (Held, 1, Limit);
            end return;
         end if;

         exit when Drained;

         --  Waited for rather than blocked on, in fifths of a second.
         --
         --  A blocking read cannot be interrupted here: the host restarts it
         --  when a signal arrives -- that is what `signal` asks for and what
         --  every caller of this library otherwise wants -- so a script
         --  waiting for input read again for ever, and the handler it had
         --  registered for `terminate` ran when the input finally came. For a
         --  pipe nobody is writing to, that is never.
         --
         --  A host that will not answer readiness gets the blocking read it
         --  always got: refusing to answer is not a reason to stop reading,
         --  and spinning on a question this host cannot answer would be worse
         --  than waiting.
         --  Nothing is read until the host says there is something.
         --
         --  A blocking read cannot be interrupted here: the host restarts it
         --  when a signal arrives -- which is what `signal` asks for and what
         --  every other caller wants -- so a script waiting for input read
         --  again for ever, and the handler it had registered for `terminate`
         --  ran when the input finally came. For a pipe nobody is writing to,
         --  that is never.
         --
         --  So the wait happens in the poll, in fifths of a second, and the
         --  read is only ever made when it will not wait. Between polls the
         --  shell can notice that it has been asked to stop.
         if not Hostkit.Descriptors.Wait_Readable
                  (Hostkit.Descriptors.Standard_Input, 200)
         then
            if Adash.Execution.Signals.Interrupt_Pending
              or else Adash.Execution.Signals.Winding_Up
            then
               Ended := True;
               return "";
            end if;

            goto Continue;
         end if;

         case Hostkit.Descriptors.Read
                (Hostkit.Descriptors.Standard_Input, Chunk, Last)
         is
            when Hostkit.Descriptors.Transfer_Ok =>
               for Index in Chunk'First .. Last loop
                  Append (Held, Character'Val (Natural (Chunk (Index))));
               end loop;

            when Hostkit.Descriptors.Transfer_Interrupted =>
               --  A signal arrived in the middle of the read.
               --
               --  Read again, unless it was one that means stop: a script
               --  waiting for input when a `terminate` arrives used to read
               --  again for ever, so the handler it had registered ran when
               --  the input finally came -- which for a pipe nobody is writing
               --  to is never. Giving up here lets the machine notice at its
               --  next instruction, which stops the submission and runs the
               --  handlers.
               if Adash.Execution.Signals.Interrupt_Pending
                 or else Adash.Execution.Signals.Winding_Up
               then
                  Ended := True;
                  return "";
               end if;

            when others =>
               --  End of file, or a host that will not answer. Either way
               --  nothing more is coming, and what is held is the last line
               --  whether or not it was terminated.
               Drained := True;
         end case;

         <<Continue>>
      end loop;

      --  Drained, with something held: a last line with no terminator.
      if Length (Held) > 0 then
         return Line : constant String := To_String (Held) do
            Held := Null_Unbounded_String;
         end return;
      end if;

      Ended := True;
      return "";
   end Read_Line;

   --------------------------
   -- Read_Line_Within --
   --------------------------

   function Read_Line_Within
     (Seconds   : Duration;
      Ended     : out Boolean;
      Timed_Out : out Boolean;
      Limit     : Positive := Adash.Filesystem.Default_Limit) return String
   is
      use Ada.Strings.Unbounded;

      --  The terminal for as long as this read takes, as Read_Line does and
      --  for the same reason: a shell watching its own terminal holds it raw,
      --  and a raw terminal echoes nothing and ends a line with a carriage
      --  return.
      type Borrowed_Terminal is new Ada.Finalization.Limited_Controlled with
        null record;

      overriding procedure Initialize (Item : in out Borrowed_Terminal);
      overriding procedure Finalize (Item : in out Borrowed_Terminal);

      overriding procedure Initialize (Item : in out Borrowed_Terminal) is
         pragma Unreferenced (Item);
      begin
         Adash.Execution.Signals.Hand_Over_Terminal;
      end Initialize;

      overriding procedure Finalize (Item : in out Borrowed_Terminal) is
         pragma Unreferenced (Item);
      begin
         Adash.Execution.Signals.Take_Terminal_Back;
      end Finalize;

      Borrowed : Borrowed_Terminal;
      pragma Unreferenced (Borrowed);

      function Break return Natural;

      function Break return Natural is
      begin
         for Index in 1 .. Length (Held) loop
            if Element (Held, Index) = Ada.Characters.Latin_1.LF then
               return Index;
            end if;
         end loop;

         return 0;
      end Break;

      Milliseconds : constant Integer :=
        (if Seconds <= 0.0 then 0 else Integer (Seconds * 1_000.0));

      Chunk : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      Ended := False;
      Timed_Out := False;

      loop
         declare
            At_Break : constant Natural := Break;
         begin
            if At_Break > 0 then
               declare
                  Stop : Natural := At_Break - 1;
               begin
                  if Stop > 0
                    and then Element (Held, Stop) = Ada.Characters.Latin_1.CR
                  then
                     Stop := Stop - 1;
                  end if;

                  return Line : constant String := Slice (Held, 1, Stop) do
                     Delete (Held, 1, At_Break);
                  end return;
               end;
            end if;
         end;

         if Length (Held) >= Limit then
            return Line : constant String := Slice (Held, 1, Limit) do
               Delete (Held, 1, Limit);
            end return;
         end if;

         exit when Drained;

         --  The wait, which is what this has and Read_Line does not. A
         --  refusal from the host is a timeout here: a caller that read
         --  anyway would block, which is the one thing this exists to avoid.
         if not Hostkit.Descriptors.Wait_Readable
                  (Hostkit.Descriptors.Standard_Input, Milliseconds)
         then
            Timed_Out := True;
            return "";
         end if;

         case Hostkit.Descriptors.Read
                (Hostkit.Descriptors.Standard_Input, Chunk, Last)
         is
            when Hostkit.Descriptors.Transfer_Ok =>
               for Index in Chunk'First .. Last loop
                  Append (Held, Character'Val (Natural (Chunk (Index))));
               end loop;

            when Hostkit.Descriptors.Transfer_Interrupted
               | Hostkit.Descriptors.Transfer_Would_Block =>
               --  As in Read_Line: read again unless the shell has been asked
               --  to stop, in which case waiting longer is waiting for
               --  something nobody will send.
               if Adash.Execution.Signals.Interrupt_Pending
                 or else Adash.Execution.Signals.Winding_Up
               then
                  Ended := True;
                  return "";
               end if;

            when others =>
               Drained := True;
         end case;
      end loop;

      if Length (Held) > 0 then
         return Line : constant String := To_String (Held) do
            Held := Null_Unbounded_String;
         end return;
      end if;

      Ended := True;
      return "";
   end Read_Line_Within;

   ----------------
   -- Read_Key --
   ----------------

   function Read_Key (Ended : out Boolean) return String is
      use Ada.Strings.Unbounded;

      --  Raw for the read, so that a character arrives when it is typed
      --  rather than when a line is finished, and put back afterwards --
      --  including on the way out of a read that failed.
      type Raw_While_Reading is new Ada.Finalization.Limited_Controlled with
        record
           Held_Mode : Hostkit.Terminal_Control.Mode;
           Have_Mode : Boolean := False;
        end record;

      overriding procedure Initialize (Item : in out Raw_While_Reading);
      overriding procedure Finalize (Item : in out Raw_While_Reading);

      overriding procedure Initialize (Item : in out Raw_While_Reading) is
      begin
         Adash.Execution.Signals.Hand_Over_Terminal;

         if Hostkit.Descriptors.Is_Terminal
              (Hostkit.Descriptors.Standard_Input)
         then
            Item.Have_Mode :=
              Hostkit.Terminal_Control.Save_Mode
                (Hostkit.Descriptors.Standard_Input, Item.Held_Mode);

            if Item.Have_Mode then
               Item.Have_Mode :=
                 Hostkit.Terminal_Control.Set_Raw
                   (Hostkit.Descriptors.Standard_Input);
            end if;
         end if;
      end Initialize;

      overriding procedure Finalize (Item : in out Raw_While_Reading) is
         Put_Back : Boolean;
      begin
         if Item.Have_Mode then
            Put_Back :=
              Hostkit.Terminal_Control.Restore_Mode
                (Hostkit.Descriptors.Standard_Input, Item.Held_Mode);
            pragma Unreferenced (Put_Back);
            Item.Have_Mode := False;
         end if;

         Adash.Execution.Signals.Take_Terminal_Back;
      end Finalize;

      Raw : Raw_While_Reading;
      pragma Unreferenced (Raw);

      Chunk : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      Ended := False;

      --  What a previous read left over comes first: there is one standard
      --  input, and a character already taken from it is a character this
      --  would otherwise skip.
      if Length (Held) > 0 then
         return Item : constant String := Slice (Held, 1, 1) do
            Delete (Held, 1, 1);
         end return;
      end if;

      if Drained then
         Ended := True;
         return "";
      end if;

      loop
         case Hostkit.Descriptors.Read
                (Hostkit.Descriptors.Standard_Input, Chunk, Last)
         is
            when Hostkit.Descriptors.Transfer_Ok =>
               if Ada.Streams."<=" (Chunk'First, Last) then
                  return [1 => Character'Val (Natural (Chunk (Chunk'First)))];
               end if;

            when Hostkit.Descriptors.Transfer_Interrupted =>
               if Adash.Execution.Signals.Interrupt_Pending
                 or else Adash.Execution.Signals.Winding_Up
               then
                  Ended := True;
                  return "";
               end if;

            when others =>
               Drained := True;
               Ended := True;
               return "";
         end case;
      end loop;
   end Read_Key;

   -----------------
   -- Take_Held --
   -----------------

   function Take_Held return String is
      use Ada.Strings.Unbounded;
   begin
      return Taken : constant String := To_String (Held) do
         Held := Null_Unbounded_String;
      end return;
   end Take_Held;

   ----------------
   -- Put_Back --
   ----------------

   procedure Put_Back (Bytes : String) is
      use Ada.Strings.Unbounded;
   begin
      if Bytes'Length > 0 then
         Held := To_Unbounded_String (Bytes) & Held;
      end if;
   end Put_Back;

end Adash.Execution.Streams;

with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Real_Time;
with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Filesystem;
with Adash.Patterns;
with Adash.Language.Values;
with Adash.Version;

with Hostkit;
with Hostkit.Process;
with Hostkit.Signals;
with Hostkit.Fs;
with Hostkit.Limits;
with Adash.Configuration;
with Adash.Configuration.Files;
with Adash.Persistence;
with Adash.Platform;

with Adash.Execution.Commands;
with Adash.Execution.Jobs;
with Adash.Execution.Pipelines;
with Adash.Execution.Redirection;
with Adash.Execution.Signals;
with Adash.Execution.Streams;

package body Adash.Commands.Builtins is

   package M renames Adash.Messages;

   --  A number as a user reads it, without the space Integer'Image leads with.
   function Trim (Value : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (Value), Ada.Strings.Both));

   package Env renames Adash.Execution.Environment;

   use Ada.Strings.Unbounded;

   --  A command's argument as text.
   --
   --  Image rather than Text: Text answers only for a String and gives "" for
   --  everything else, which would turn `quit (3)` into `quit ("")` silently.
   --  Image is the canonical text of any value, and a String images as its own
   --  contents without quotes.

   --  Where the `=` is in an assignment, or zero when there is none.
   --
   --  `set` decides what an assignment looks like -- NAME=VALUE, with a name
   --  before the first `=` -- and this is the same question asked twice, so it
   --  is asked in one place.
   function Assignment_Split (Text : String) return Natural;

   function Assignment_Split (Text : String) return Natural is
   begin
      for Index in Text'Range loop
         if Text (Index) = '=' then
            return (if Index > Text'First then Index else 0);
         end if;
      end loop;

      return 0;
   end Assignment_Split;

   --  Whether an argument is an assignment rather than a program or one of its
   --  arguments. What separates the two in `run_with ("A=1", "B=2", "sort")`.
   function Is_An_Assignment (Text : String) return Boolean
   is (Assignment_Split (Text) > 0);

   --  The same text in lower case, for names a host spells in capitals.
   function Lowered (Text : String) return String;

   function Lowered (Text : String) return String is
      Result : String := Text;
   begin
      for Index in Result'Range loop
         if Result (Index) in 'A' .. 'Z' then
            Result (Index) :=
              Character'Val (Character'Pos (Result (Index))
                             - Character'Pos ('A') + Character'Pos ('a'));
         end if;
      end loop;

      return Result;
   end Lowered;

   --  A mask as a shell writes one: octal, no prefix.
   function Octal (Value : Natural) return String;

   function Octal (Value : Natural) return String is
      Digits_Held : String (1 .. 8) := [others => '0'];
      Left        : Natural := Value;
      At_Position : Natural := Digits_Held'Last;
      First_Kept  : Natural := Digits_Held'Last;
   begin
      while Left > 0 and then At_Position >= Digits_Held'First loop
         Digits_Held (At_Position) :=
           Character'Val (Character'Pos ('0') + (Left mod 8));
         First_Kept := At_Position;
         Left := Left / 8;
         At_Position := At_Position - 1;
      end loop;

      --  A mask of zero is written as one digit rather than as nothing.
      return Digits_Held (First_Kept .. Digits_Held'Last);
   end Octal;

   --  Read one, refusing anything that is not octal digits.
   --
   --  A shell that read `0o22` or `22x` as twenty-two would set a mask nobody
   --  asked for, and a mask is the one setting whose mistake is invisible
   --  until somebody else reads a file they should not have been able to.
   function Octal_Value (Text : String; Value : out Natural) return Boolean;

   function Octal_Value (Text : String; Value : out Natural) return Boolean is
   begin
      Value := 0;

      if Text'Length = 0 or else Text'Length > 7 then
         return False;
      end if;

      for Index in Text'Range loop
         if Text (Index) not in '0' .. '7' then
            return False;
         end if;

         Value := Value * 8
           + (Character'Pos (Text (Index)) - Character'Pos ('0'));
      end loop;

      return True;
   end Octal_Value;
   --  The name a user types for a resource.
   --
   --  Derived from the type rather than written out, so a resource hostkit
   --  gains is one this shell lists and accepts without a second table to keep
   --  in step -- and there is no list here that could disagree with that one.
   function Resource_Name (Item : Hostkit.Limits.Resource) return String;

   function Resource_Name (Item : Hostkit.Limits.Resource) return String is
      Named : constant String := Hostkit.Limits.Resource'Image (Item);
      Lower : String := Named;
   begin
      for Index in Lower'Range loop
         if Lower (Index) in 'A' .. 'Z' then
            Lower (Index) :=
              Character'Val (Character'Pos (Lower (Index))
                             - Character'Pos ('A') + Character'Pos ('a'));
         end if;
      end loop;

      return Lower;
   end Resource_Name;

   --  Which resource a word names, if any.
   function Resource_Named
     (Text : String; Item : out Hostkit.Limits.Resource) return Boolean;

   function Resource_Named
     (Text : String; Item : out Hostkit.Limits.Resource) return Boolean is
   begin
      Item := Hostkit.Limits.Resource'First;

      for Candidate in Hostkit.Limits.Resource loop
         if Resource_Name (Candidate) = Text then
            Item := Candidate;
            return True;
         end if;
      end loop;

      return False;
   end Resource_Named;

   --  The word for a limit with nothing behind it.
   --
   --  Typed rather than printed: what a user sees for an absent limit comes
   --  from the catalog like every other line, and this is only what they may
   --  type. It is spelled the way every other shell spells it.
   Unlimited_Word : constant String := "unlimited";

   --  A limit as a user writes one: digits, or the word above.
   function Limit_Value
     (Text : String; Value : out Hostkit.Limits.Amount) return Boolean;

   function Limit_Value
     (Text : String; Value : out Hostkit.Limits.Amount) return Boolean
   is
      use type Hostkit.Limits.Amount;
   begin
      Value := 0;

      if Text = Unlimited_Word then
         Value := Hostkit.Limits.Unbounded;
         return True;
      end if;

      --  Twenty digits is what an unsigned 64-bit number takes, and refusing
      --  anything longer keeps the accumulation below from wrapping round to a
      --  small limit somebody would then be surprised by.
      if Text'Length = 0 or else Text'Length > 20 then
         return False;
      end if;

      for Index in Text'Range loop
         if Text (Index) not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Hostkit.Limits.Amount :=
              Hostkit.Limits.Amount
                (Character'Pos (Text (Index)) - Character'Pos ('0'));
         begin
            --  Refused rather than wrapped: a limit that overflowed into a
            --  small number is a limit a script would run under.
            if Value > (Hostkit.Limits.Amount'Last - Digit) / 10 then
               return False;
            end if;

            Value := Value * 10 + Digit;
         end;
      end loop;

      --  A number that happens to be Amount'Last is the value this shell uses
      --  for "no limit", so it is not a number a user can set to mean itself.
      --  Saying so is better than setting something else.
      return Value /= Hostkit.Limits.Unbounded;
   end Limit_Value;

   --  A limit as a line shows one: digits, with no leading space.
   function Amount_Image (Value : Hostkit.Limits.Amount) return String;

   function Amount_Image (Value : Hostkit.Limits.Amount) return String is
      Written : constant String := Hostkit.Limits.Amount'Image (Value);
   begin
      return Ada.Strings.Fixed.Trim (Written, Ada.Strings.Both);
   end Amount_Image;

   function Argument
     (Arguments : Argument_Set; Index : Positive) return String
   is (if Index <= Arguments.Count
       then Adash.Language.Values.Image (Arguments.Given (Index)) else "");

   --  Whether a command's argument is a String.
   --
   --  Asked of the value rather than of the profile, because the parameter
   --  takes whatever it is given: `forget (3)` and `forget ("git push")` are
   --  the same command told which entry two different ways.
   function Text_Argument
     (Arguments : Argument_Set; Index : Positive) return Boolean
   is (Index <= Arguments.Count
       and then Adash.Language.Types."="
                  (Adash.Language.Values.Kind (Arguments.Given (Index)),
                   Adash.Language.Types.Type_String));

   --  A command's argument as a whole number.
   --
   --  @return False when there is no such argument or it is not an Integer.
   --          The analyser has already checked the type against the command's
   --          profile, so False here means a caller built the argument set by
   --          hand and got it wrong -- which is worth reporting rather than
   --          defaulting.
   function Whole_Argument
     (Arguments : Argument_Set; Index : Positive; Into : out Integer)
      return Boolean
   is (Index <= Arguments.Count
       and then Adash.Language.Values.Get (Arguments.Given (Index), Into));

   ---------
   -- Run --
   ---------

   function Run
     (Id        : Command_Id;
      Arguments : Argument_Set;
      Shell     : in out State;
      Produced  : in out Output;
      Report    : in out Adash.Diagnostics.List)
      return Adash.Execution.Exit_Status
   is
      Given : constant Natural := Arguments.Count;

      --  Report a message directly.
      --
      --  The configuration messages are addressed by identifier rather than
      --  through an error code -- Adash.Configuration.Files raises them the
      --  same way -- so a command that reports one says so in the same terms
      --  rather than inventing a code that means "one of those".
      function Refused
        (Message : M.Message_Id;
         Args    : M.Argument_List;
         Quoted  : M.Message_Id := M.Msg_Error_None;
         Given   : M.Argument_List := M.No_Arguments)
         return Adash.Execution.Exit_Status;

      function Refused
        (Message : M.Message_Id;
         Args    : M.Argument_List;
         Quoted  : M.Message_Id := M.Msg_Error_None;
         Given   : M.Argument_List := M.No_Arguments)
         return Adash.Execution.Exit_Status
      is
      begin
         Report.Emit
           (Adash.Diagnostics.Make
              (Message   => Message,
               Level     => Adash.Diagnostics.Severity_Error,
               Of_Kind   => Adash.Diagnostics.Category_Configuration,
               Raised_By => Adash.Diagnostics.Owner_Commands,
               Arguments => Args,
               Quoted    => Quoted,
               Fills     => "detail",
               Quoted_Arguments => Given));

         return (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end Refused;

      function Failed
        (Code   : Adash.Errors.Error_Code;
         Args   : M.Argument_List;
         Quoted : M.Message_Id := M.Msg_Error_None;
         Fills  : String := "") return Adash.Execution.Exit_Status
      is
      begin
         Report.Emit
           (Adash.Diagnostics.From_Error
              (Adash.Errors.Failure (Code, Args, Quoted, Fills),
               Level     => Adash.Diagnostics.Severity_Error,
               Of_Kind   => Adash.Diagnostics.Category_Execution,
               Raised_By => Adash.Diagnostics.Owner_Commands));

         return (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end Failed;

      --  What a command is called, asked of the table rather than worked out
      --  from the identifier's position in it: the two agree today and nothing
      --  says they must, and a trace naming the wrong command would be worse
      --  than no trace at all.
      function Spelling_Of (Which : Command_Id) return String;

      function Spelling_Of (Which : Command_Id) return String is
      begin
         for Index in 1 .. Adash.Commands.Count loop
            if Adash.Commands.Entry_At (Index).Id = Which then
               return M.Value (Adash.Commands.Entry_At (Index).Name);
            end if;
         end loop;

         return "";
      end Spelling_Of;

   begin
      --  Announced before it runs, where the user asked for that.
      --
      --  On standard error and as a note, so the output a script produces is
      --  still the output a script produces -- `set -x` writing into a
      --  pipeline's data is a thing every shell user has been bitten by once.
      --  What is said is the command and what it was given, which is what a
      --  reader is trying to see.
      if Adash.Configuration.Boolean_Value
           (Shell.Chosen, Adash.Configuration.Trace_Setting)
      then
         declare
            Said : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Spelling_Of (Id));
         begin
            for Position in 1 .. Given loop
               Ada.Strings.Unbounded.Append
                 (Said, " " & Argument (Arguments, Position));
            end loop;

            Report.Emit
              (Adash.Diagnostics.Make
                 (Message   => M.Msg_Line_Traced,
                  Level     => Adash.Diagnostics.Severity_Note,
                  Of_Kind   => Adash.Diagnostics.Category_Execution,
                  Raised_By => Adash.Diagnostics.Owner_Commands,
                  Arguments =>
                    [1 => M.Named
                            ("command",
                             Ada.Strings.Unbounded.To_String (Said))]));
         end;
      end if;

      case Id is

         when Command_Change_Directory =>
            declare
               --  With no argument, the home directory -- asked of hostkit,
               --  which knows where a host keeps one, rather than read from
               --  HOME, which a spawned process can set to anything.
               Target : constant String :=
                 (if Given = 0 then Hostkit.Fs.Home_Directory
                  else Adash.Filesystem.Expanded (Argument (Arguments, 1)));
            begin
               if Target = "" then
                  return Failed (Adash.Errors.Error_Directory_Not_Found,
                                 [1 => M.Named ("path", Target)]);
               end if;

               begin
                  --  The process's own directory, so there is one answer and a
                  --  child inherits the real one without being told.
                  Ada.Directories.Set_Directory (Target);
               exception
                  when Ada.IO_Exceptions.Name_Error =>
                     return Failed (Adash.Errors.Error_Directory_Not_Found,
                                    [1 => M.Named ("path", Target)]);
                  when Ada.IO_Exceptions.Use_Error =>
                     return Failed (Adash.Errors.Error_Directory_Denied,
                                    [1 => M.Named ("path", Target)]);
               end;

               return Adash.Execution.Success;
            end;

         when Command_Print_Directory =>
            Say (Produced, M.Msg_Line_Directory,
                 [1 => M.Named ("path", Ada.Directories.Current_Directory)]);
            return Adash.Execution.Success;

         when Command_Exit =>
            Shell.Exit_Requested := True;

            if Given = 1 then
               declare
                  Status : Integer;
               begin
                  --  No Integer'Value on something the user typed. The status
                  --  is an Integer by the time it reaches here, because the
                  --  analyser checked it against quit's profile before
                  --  anything ran -- which is the whole point of commands
                  --  having typed profiles.
                  if Whole_Argument (Arguments, 1, Status) then
                     Shell.Exit_Status :=
                       Adash.Execution.From_External_Code (Status);
                  else
                     --  Not an Integer. The analyser would have refused it, so
                     --  reaching here means a caller built the argument set by
                     --  hand and got it wrong. The session still ends, because
                     --  that is what was asked for.
                     Shell.Exit_Status :=
                       (Kind => Adash.Execution.Exit_Internal_Failure,
                        others => <>);
                     return Failed
                       (Adash.Errors.Error_Command_Wrong_Arguments,
                        [M.Named ("name", "quit"),
                         M.Named ("found", Argument (Arguments, 1))]);
                  end if;
               end;
            else
               Shell.Exit_Status := Adash.Execution.Success;
            end if;

            return Shell.Exit_Status;

         when Command_Set =>
            declare
               Text  : constant String := Argument (Arguments, 1);
               Split : Natural := 0;
            begin
               for Index in Text'Range loop
                  if Text (Index) = '=' then
                     Split := Index;
                     exit;
                  end if;
               end loop;

               --  NAME=VALUE and nothing else. A `set` that accepted a bare
               --  name would have to decide what it meant -- empty, or unset --
               --  and either choice surprises half its users.
               if Split <= Text'First then
                  return Failed (Adash.Errors.Error_Command_Bad_Assignment,
                                 [1 => M.Named ("text", Text)]);
               end if;

               Env.Set (Shell.Environment,
                        Text (Text'First .. Split - 1),
                        Text (Split + 1 .. Text'Last));
               return Adash.Execution.Success;
            end;

         when Command_Unset =>
            Env.Unset (Shell.Environment, Argument (Arguments, 1));
            return Adash.Execution.Success;

         when Command_Environment =>
            --  Sorted, because Adash.Execution.Environment keeps it that way.
            --  A listing that changed order between runs would be one nobody
            --  could diff.
            for Entry_Text of Env.To_Vector (Shell.Environment) loop
               declare
                  Text  : constant String := To_String (Entry_Text);
                  Split : Natural := Text'First - 1;
               begin
                  for Index in Text'Range loop
                     if Text (Index) = '=' then
                        Split := Index;
                        exit;
                     end if;
                  end loop;

                  if Split >= Text'First then
                     Say (Produced, M.Msg_Line_Variable,
                          [M.Named ("name", Text (Text'First .. Split - 1)),
                           M.Named ("value", Text (Split + 1 .. Text'Last))]);
                  end if;
               end;
            end loop;

            return Adash.Execution.Success;

         when Command_Jobs =>
            --  What has finished since anyone last looked is noticed here
            --  rather than in the background: nothing polls, so a job's state
            --  is only as fresh as the last question asked about it.
            Adash.Execution.Jobs.Refresh (Shell.Jobs);

            for Id of Adash.Execution.Jobs.Ids (Shell.Jobs) loop
               Say (Produced, M.Msg_Line_Job,
                    [M.Named ("job", Trim (Integer (Id))),
                     M.Named
                       ("description",
                        Adash.Execution.Jobs.Description (Shell.Jobs, Id))],
                    Quoted =>
                      Adash.Execution.Jobs.Message
                        (Adash.Execution.Jobs.State (Shell.Jobs, Id)),
                    Fills  => "state");
            end loop;

            return Adash.Execution.Success;

         when Command_Pipe =>
            declare
               Args : Hostkit.String_Vectors.Vector;
            begin
               for Position in 2 .. Given loop
                  Args.Append
                    (Ada.Strings.Unbounded.To_Unbounded_String
                       (Argument (Arguments, Position)));
               end loop;

               declare
                  Stage : Adash.Execution.Commands.Invocation :=
                    Adash.Execution.Commands.Make
                      (Argument (Arguments, 1), Args);
               begin
                  --  The session's variables. A stage of a pipeline is a child
                  --  like the one `run` starts, and both of them are what
                  --  `set` means by "children".
                  Stage.Environment := Shell.Environment;
                  Adash.Execution.Pipelines.Add_Stage (Shell.Pending, Stage);
               end;

               return Adash.Execution.Success;
            end;

         when Command_Pipe_From | Command_Pipe_From_Text =>
            --  Recorded, not run. See the note where this is registered.
            declare
               --  The text goes into a file the session holds. Held there
               --  rather than here because a pipeline is built by one
               --  submission and run by another, and a file removed when this
               --  command returned would be gone before anything read it; the
               --  session's copy lasts until the next `pipe_from_text` or the
               --  end of the session, which is also what a pipeline placed in
               --  the background needs.
               Put_There : Adash.Filesystem.Written :=
                 Adash.Filesystem.Write_Ok;

               use type Adash.Filesystem.Written;

               Attach  : Adash.Execution.Redirection.Plan;
               Refused : Adash.Errors.Error_Info;
            begin
               if Adash.Execution.Pipelines.Length (Shell.Pending) = 0 then
                  --  Nothing built yet. Refused rather than remembered for
                  --  whatever is built next: a file named before the first
                  --  program is a line in the wrong order, and a shell that
                  --  quietly applied it later would be guessing.
                  return Failed (Adash.Errors.Error_Empty_Pipeline,
                                 M.No_Arguments);
               end if;

               if Id = Command_Pipe_From_Text then
                  Adash.Filesystem.Hold
                    (Shell.Pipeline_Input, Argument (Arguments, 1), Put_There);

                  if Put_There /= Adash.Filesystem.Write_Ok then
                     return Failed
                       (Adash.Errors.Error_Input_Text_Not_Held,
                        [1 => M.Named
                                ("reason",
                                 Adash.Filesystem.Written'Image (Put_There))]);
                  end if;
               end if;

               declare
                  Asked : constant Adash.Execution.Redirection.Redirection :=
                    (Role => Adash.Execution.Streams.Role_Input,
                     Kind => Adash.Execution.Redirection.Redirect_From_File,
                     Path =>
                       Ada.Strings.Unbounded.To_Unbounded_String
                         (if Id = Command_Pipe_From_Text
                          then Adash.Filesystem.Path (Shell.Pipeline_Input)
                          else Argument (Arguments, 1)));
               begin
                  if not Adash.Execution.Redirection.Add (Attach, Asked, Refused)
                    or else not Adash.Execution.Pipelines.Redirect_First
                                  (Shell.Pending, Attach, Refused)
                  then
                     Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

                     Report.Emit
                       (Adash.Diagnostics.From_Error
                          (Refused, Adash.Diagnostics.Severity_Error,
                           Adash.Diagnostics.Category_Execution,
                           Adash.Diagnostics.Owner_Commands));

                     return Adash.Execution.From_Start_Error (Refused.Code);
                  end if;
               end;

               return Adash.Execution.Success;
            end;

         when Command_Pipe_Into | Command_Pipe_Append | Command_Pipe_New
            | Command_Pipe_Errors_Into | Command_Pipe_Errors_Append
            | Command_Pipe_Errors_New | Command_Pipe_All_Into
            | Command_Pipe_All_Append | Command_Pipe_All_New =>
            --  Recorded, not run, as pipe_from is.
            --
            --  These said where the output goes *and* ran the pipeline, which
            --  meant a pipeline could be given a file to read or a file to
            --  write and never both, and could not be placed and left running
            --  at the same time -- `pipe_start` took no file, so "run this in
            --  the background with its output in a log", which is the
            --  commonest reason to background anything, could not be said.
            --
            --  Saying and running are two things, so they are two commands:
            --  these say, and `pipe_run` or `pipe_start` runs.
            declare
               Asked : constant Adash.Execution.Redirection.Redirection :=
                 (Role =>
                    (if Id in Command_Pipe_Errors_Into
                            | Command_Pipe_Errors_Append
                            | Command_Pipe_Errors_New
                     then Adash.Execution.Streams.Role_Error
                     else Adash.Execution.Streams.Role_Output),
                  Kind =>
                    (case Id is
                        when Command_Pipe_Append
                           | Command_Pipe_Errors_Append
                           | Command_Pipe_All_Append =>
                          Adash.Execution.Redirection.Redirect_Append_File,
                        when Command_Pipe_New | Command_Pipe_Errors_New
                           | Command_Pipe_All_New =>
                          Adash.Execution.Redirection.Redirect_To_New_File,
                        when others =>
                          Adash.Execution.Redirection.Redirect_To_File),
                  Path =>
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Argument (Arguments, 1)));

               Joined : constant Adash.Execution.Redirection.Redirection :=
                 (Role => Adash.Execution.Streams.Role_Error,
                  Kind => Adash.Execution.Redirection.Redirect_Join_Output,
                  Path => Ada.Strings.Unbounded.Null_Unbounded_String);

               Both : constant Boolean :=
                 Id in Command_Pipe_All_Into | Command_Pipe_All_Append
                     | Command_Pipe_All_New;

               Attach  : Adash.Execution.Redirection.Plan;
               Refused : Adash.Errors.Error_Info;
            begin
               if Adash.Execution.Pipelines.Length (Shell.Pending) = 0 then
                  return Failed (Adash.Errors.Error_Empty_Pipeline,
                                 M.No_Arguments);
               end if;

               if not Adash.Execution.Redirection.Add (Attach, Asked, Refused)
                 or else (Both
                          and then not Adash.Execution.Redirection.Add
                                         (Attach, Joined, Refused))
                 or else not Adash.Execution.Pipelines.Redirect_Last
                               (Shell.Pending, Attach, Refused)
               then
                  Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

                  Report.Emit
                    (Adash.Diagnostics.From_Error
                       (Refused, Adash.Diagnostics.Severity_Error,
                        Adash.Diagnostics.Category_Execution,
                        Adash.Diagnostics.Owner_Commands));

                  return Adash.Execution.From_Start_Error (Refused.Code);
               end if;

               return Adash.Execution.Success;
            end;

         when Command_Pipe_Run | Command_Pipe_Start =>
            declare
               Running : Adash.Execution.Pipelines.Running;
               Error   : Adash.Errors.Error_Info;

               --  Waited for, unless it was started into the background.
               Waits : constant Boolean := Id /= Command_Pipe_Start;
            begin
               if Adash.Execution.Pipelines.Length (Shell.Pending) = 0
               then
                  --  Nothing was added. Refused rather than treated as a
                  --  pipeline of nothing, which would succeed and look like it
                  --  had run something.
                  return Failed (Adash.Errors.Error_Empty_Pipeline,
                                 M.No_Arguments);
               end if;

               if not Waits then
                  --  A background pipeline does not share the keyboard, for
                  --  the reason a background program does not: see
                  --  Adash.Execution.Streams.Background_Input.
                  Adash.Execution.Pipelines.Take_Background_Input
                    (Shell.Pending);
               end if;

               if not Adash.Execution.Pipelines.Start
                        (Shell.Pending, Running, Error)
               then
                  --  Cleared even when it would not start. Leaving the stages
                  --  behind would put them at the front of whatever the user
                  --  built next, which is the last thing somebody fixing a
                  --  mistyped program name wants.
                  Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

                  Report.Emit
                    (Adash.Diagnostics.From_Error
                       (Error, Adash.Diagnostics.Severity_Error,
                        Adash.Diagnostics.Category_Execution,
                        Adash.Diagnostics.Owner_Commands));

                  return Adash.Execution.From_Start_Error (Error.Code);
               end if;

               Shell.Pending := Adash.Execution.Pipelines.Empty_Plan;

               declare
                  Started : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Add
                      (Shell.Jobs, Running, "pipeline",
                       (if Waits
                        then Adash.Execution.Jobs.Placement_Foreground
                        else Adash.Execution.Jobs.Placement_Background));

                  Wait_Error : Adash.Errors.Error_Info;

                  --  The terminal, as a waited-for program gets it. A
                  --  pipeline waits here rather than in Pipelines.Run, so it
                  --  needs its own handover -- without which a stage that
                  --  asked a question was stopped where it asked.
                  Ours : Integer;

                  Finished : Boolean;
               begin
                  if not Waits then
                     --  Said, as `start` says it: a job nobody is waiting for
                     --  is one the user has to be able to name afterwards.
                     Say (Produced, M.Msg_Line_Job_Started,
                          [M.Named ("id", Trim (Integer (Started))),
                           M.Named ("what", "pipeline")]);

                     return Adash.Execution.Success;
                  end if;

                  Adash.Execution.Signals.Hand_Over_Terminal;
                  Adash.Execution.Pipelines.Hand_The_Terminal_To
                    (Adash.Execution.Pipelines.Group (Running), Ours);

                  Finished :=
                    Adash.Execution.Jobs.Wait
                      (Shell.Jobs, Started, Shell.Interrupt, Wait_Error);

                  Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                  Adash.Execution.Signals.Take_Terminal_Back;

                  if not Finished then
                     declare
                        Stop_Error : Adash.Errors.Error_Info;
                        Asked      : constant Boolean :=
                          Adash.Execution.Jobs.Terminate_Job
                            (Shell.Jobs, Started, Stop_Error);
                     begin
                        pragma Unreferenced (Asked);
                     end;

                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);
                     return (Kind => Adash.Execution.Exit_Cancelled,
                             others => <>);
                  end if;

                  declare
                     --  The last stage's status is the pipeline's, which is
                     --  what every shell reports and what a reader means by
                     --  "did it work".
                     Ended : constant Adash.Execution.Exit_Status :=
                       Adash.Execution.Jobs.Result (Shell.Jobs, Started).Status;
                  begin
                     --  What each stage said, for the question `Status` cannot
                     --  answer: a failure in the middle of a pipeline.
                     Shell.Stage_Statuses :=
                       Adash.Execution.Jobs.Result (Shell.Jobs, Started).Stages;

                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);
                     return Ended;
                  end;
               end;
            end;

         when Command_Run | Command_Run_Matching | Command_Run_Into
            | Command_Run_From
            | Command_Run_From_Text | Command_Run_With | Command_Start_With
            | Command_Time
            | Command_Run_Append | Command_Run_New | Command_Run_Errors_Into
            | Command_Run_Errors_Append | Command_Run_Errors_New
            | Command_Run_All_Into | Command_Run_All_Append
            | Command_Run_All_New | Command_Start =>
            declare
               Waits : constant Boolean :=
                 Id not in Command_Start | Command_Start_With;

               --  The first argument names a file when one of the program's
               --  streams is going to it, so the program starts one later.
               Redirects : constant Boolean :=
                 Id in Command_Run_Into | Command_Run_From
                     | Command_Run_From_Text
                     | Command_Run_Append | Command_Run_New
                     | Command_Run_Errors_Into | Command_Run_Errors_Append
                     | Command_Run_Errors_New | Command_Run_All_Into
                     | Command_Run_All_Append | Command_Run_All_New;

               Sets_Variables : constant Boolean :=
                 Id in Command_Run_With | Command_Start_With;

               --  When this program started, for the one command that reports
               --  it. Read before anything is opened or resolved, so what is
               --  reported is what a user waited for rather than what the
               --  spawn took.
               Began : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;

               --  Where an assignment stops and the program begins.
               --
               --  Every command here that carries something of its own -- a
               --  file, the text -- carries exactly one of it, so the program
               --  is the second word. Assignments are the exception: a caller
               --  may write several, and what ends them is the first argument
               --  that is not one. The rule is stated where the command is
               --  registered, together with its single exception.
               function Program_Starts_At return Positive;

               function Program_Starts_At return Positive is
               begin
                  if not Sets_Variables then
                     return (if Redirects then 2 else 1);
                  end if;

                  for Position in 1 .. Given loop
                     if not Is_An_Assignment (Argument (Arguments, Position))
                     then
                        return Position;
                     end if;
                  end loop;

                  --  Nothing but assignments. Refused below; the value here
                  --  only has to be in range.
                  return Given;
               end Program_Starts_At;

               First_Word : constant Positive := Program_Starts_At;

               --  What the file is attached as, said in the terms the
               --  redirection subsystem uses rather than in open modes. That
               --  package owns opening: it knows that appending is a property
               --  of the open file rather than a seek, that refusing an
               --  existing file has to be the open itself and not a prior
               --  check, and that a command which will not run must not have
               --  half-created its output. Opening the file here would be a
               --  second, quietly different copy of all three.
               Attach : Adash.Execution.Redirection.Plan;

               Line : Adash.Execution.Pipelines.Plan :=
                 Adash.Execution.Pipelines.Empty_Plan;
               Args : Hostkit.String_Vectors.Vector;
               Running : Adash.Execution.Pipelines.Running;
               Error   : Adash.Errors.Error_Info;
               Told    : Ada.Strings.Unbounded.Unbounded_String :=
                 Ada.Strings.Unbounded.To_Unbounded_String
                   (Argument (Arguments, First_Word));

               --  Where the text goes for a program to read it. Holds nothing
               --  for every other command in this branch, and removes what it
               --  holds when this declaration goes out of scope -- which is
               --  every way out of here, including the dozen that report a
               --  failure and the one where the user interrupted the program.
               Input : Adash.Filesystem.Held_Text;

               Put_There : Adash.Filesystem.Written :=
                 Adash.Filesystem.Write_Ok;

               use type Adash.Filesystem.Written;
            begin
               if Sets_Variables then
                  --  Checked before anything runs: a command that took
                  --  `LC_ALL` and quietly ran without it would be worse than
                  --  one that refuses.
                  --
                  --  The first argument must be an assignment, or the caller
                  --  wrote `run_with ("sort")` and meant `run`. Everything up
                  --  to the program is one by construction -- that is what
                  --  chose the program -- so what is left to refuse is a call
                  --  that is nothing but assignments.
                  if not Is_An_Assignment (Argument (Arguments, 1)) then
                     return Failed
                       (Adash.Errors.Error_Command_Bad_Assignment,
                        [1 => M.Named ("text", Argument (Arguments, 1))]);
                  end if;

                  if First_Word > Given
                    or else Is_An_Assignment (Argument (Arguments, First_Word))
                  then
                     return Failed
                       (Adash.Errors.Error_Command_Bad_Assignment,
                        [1 => M.Named
                                ("text", Argument (Arguments, Given))]);
                  end if;
               end if;

               if Id = Command_Run_From_Text then
                  Adash.Filesystem.Hold
                    (Input, Argument (Arguments, 1), Put_There);

                  if Put_There /= Adash.Filesystem.Write_Ok then
                     return Failed
                       (Adash.Errors.Error_Input_Text_Not_Held,
                        [1 => M.Named
                                ("reason",
                                 Adash.Filesystem.Written'Image (Put_There))]);
                  end if;
               end if;

               if Redirects then
                  declare
                     Asked : constant Adash.Execution.Redirection.Redirection :=
                       (Role =>
                          (case Id is
                              when Command_Run_From | Command_Run_From_Text =>
                                Adash.Execution.Streams.Role_Input,
                              when Command_Run_Errors_Into
                                 | Command_Run_Errors_Append
                                 | Command_Run_Errors_New =>
                                Adash.Execution.Streams.Role_Error,
                              when others =>
                                Adash.Execution.Streams.Role_Output),
                        Kind =>
                          (case Id is
                              when Command_Run_From | Command_Run_From_Text =>
                                Adash.Execution.Redirection.Redirect_From_File,
                              when Command_Run_Append
                                 | Command_Run_Errors_Append
                                 | Command_Run_All_Append =>
                                Adash.Execution.Redirection.Redirect_Append_File,
                              when Command_Run_New | Command_Run_Errors_New
                                 | Command_Run_All_New =>
                                Adash.Execution.Redirection.Redirect_To_New_File,
                              when others =>
                                Adash.Execution.Redirection.Redirect_To_File),
                        --  The first argument names a file for every other
                        --  command here and *is* the input for this one, so
                        --  what goes into the plan is the file the text was
                        --  put in.
                        Path =>
                          Ada.Strings.Unbounded.To_Unbounded_String
                            (if Id = Command_Run_From_Text
                             then Adash.Filesystem.Path (Input)
                             else Argument (Arguments, 1)));

                     --  Both streams, where the command is one of the three
                     --  that says so: the output redirection above opens the
                     --  file, and this one follows it into the same open file
                     --  rather than a second one.
                     Joined : constant Adash.Execution.Redirection.Redirection :=
                       (Role => Adash.Execution.Streams.Role_Error,
                        Kind =>
                          Adash.Execution.Redirection.Redirect_Join_Output,
                        Path => Ada.Strings.Unbounded.Null_Unbounded_String);

                     Both : constant Boolean :=
                       Id in Command_Run_All_Into | Command_Run_All_Append
                           | Command_Run_All_New;

                     Refused : Adash.Errors.Error_Info;
                  begin
                     if Both
                       and then not Adash.Execution.Redirection.Add
                                      (Attach, Joined, Refused)
                     then
                        Report.Emit
                          (Adash.Diagnostics.From_Error
                             (Refused, Adash.Diagnostics.Severity_Error,
                              Adash.Diagnostics.Category_Execution,
                              Adash.Diagnostics.Owner_Commands));

                        return (Kind => Adash.Execution.Exit_Internal_Failure,
                                others => <>);
                     end if;

                     if not Adash.Execution.Redirection.Add
                              (Attach, Asked, Refused)
                     then
                        Report.Emit
                          (Adash.Diagnostics.From_Error
                             (Refused, Adash.Diagnostics.Severity_Error,
                              Adash.Diagnostics.Category_Execution,
                              Adash.Diagnostics.Owner_Commands));

                        return (Kind => Adash.Execution.Exit_Internal_Failure,
                                others => <>);
                     end if;
                  end;
               end if;

               for Position in First_Word + 1 .. Given loop
                  declare
                     Word : constant String := Argument (Arguments, Position);

                     --  Only one command expands, and only an argument that
                     --  holds a pattern. Everything else is passed along as
                     --  the caller wrote it, which is what lets a flag and a
                     --  pattern stand side by side.
                     Expanding : constant Boolean :=
                       Id = Command_Run_Matching
                         and then Adash.Patterns.Holds_A_Pattern (Word);
                  begin
                     if not Expanding then
                        Args.Append
                          (Ada.Strings.Unbounded.To_Unbounded_String (Word));
                        Ada.Strings.Unbounded.Append (Told, " " & Word);
                     else
                        declare
                           Found : constant Natural :=
                             Adash.Filesystem.Match_Count (Word);
                        begin
                           if Found = 0 then
                              --  Two ways to name nothing, and they are not
                              --  the same mistake: a pattern nobody meant, and
                              --  a directory somebody else filled.
                              if Adash.Filesystem.Match_Refused (Word) then
                                 return Failed
                                   (Adash.Errors.Error_Too_Many_Matches,
                                    [M.Named ("pattern", Word),
                                     M.Named
                                       ("limit",
                                        Trim
                                          (Adash.Filesystem.Maximum_Matches))]);
                              end if;

                              return Failed
                                (Adash.Errors.Error_No_Matching_Files,
                                 [1 => M.Named ("pattern", Word)]);
                           end if;

                           for Match in 1 .. Found loop
                              declare
                                 Path : constant String :=
                                   Adash.Filesystem.Match_At (Word, Match);
                              begin
                                 Args.Append
                                   (Ada.Strings.Unbounded.To_Unbounded_String
                                      (Path));
                                 Ada.Strings.Unbounded.Append
                                   (Told, " " & Path);
                              end;
                           end loop;
                        end;
                     end if;
                  end;
               end loop;

               declare
                  Stage : Adash.Execution.Commands.Invocation :=
                    Adash.Execution.Commands.Make
                      (Argument (Arguments, First_Word), Args);

                  Attached : Adash.Errors.Error_Info;
               begin
                  --  What the session says a child inherits.
                  --
                  --  This was the process's own environment, and `set`
                  --  changed the session's -- so `set ("A=1")` put A in what
                  --  `env` listed, in what `Env_Value` answered, and in
                  --  nothing a program could see. The catalog has said "a
                  --  variable children will inherit" since the command
                  --  existed, and until now no child inherited one.
                  Stage.Environment := Shell.Environment;
                  --  Opened now, not when the redirection was named: the file
                  --  is created at the moment the program is about to run, so
                  --  a command refused for any other reason has not touched it.
                  if Adash.Execution.Redirection.Length (Attach) > 0
                    and then not Adash.Execution.Redirection.Apply
                                   (Attach, Stage, Attached)
                  then
                     Report.Emit
                       (Adash.Diagnostics.From_Error
                          (Attached, Adash.Diagnostics.Severity_Error,
                           Adash.Diagnostics.Category_Execution,
                           Adash.Diagnostics.Owner_Commands));

                     return (Kind => Adash.Execution.Exit_Internal_Failure,
                             others => <>);
                  end if;

                  --  The one variable, over what the child would have had.
                  --  Started from the environment it inherits rather than
                  --  from an empty block: a program run with `LC_ALL=C` still
                  --  needs its PATH, and a shell that answered a request for
                  --  one variable by taking away the rest would be answering a
                  --  question nobody asked.
                  if Sets_Variables then
                     for Position in 1 .. First_Word - 1 loop
                        declare
                           Text  : constant String :=
                             Argument (Arguments, Position);
                           Split : constant Natural := Assignment_Split (Text);
                        begin
                           Env.Set (Stage.Environment,
                                    Text (Text'First .. Split - 1),
                                    Text (Split + 1 .. Text'Last));
                        end;
                     end loop;
                  end if;

                  --  A background job does not share the keyboard. What it
                  --  gets instead, and why, is Streams.Background_Input --
                  --  which is where the rule lives so that a test can ask it
                  --  rather than having to arrange a whole job to watch.
                  if not Waits then
                     Stage.Input :=
                       Adash.Execution.Streams.Background_Input (Stage.Input);
                  end if;

                  Adash.Execution.Pipelines.Add_Stage (Line, Stage);
               end;

               if not Adash.Execution.Pipelines.Start (Line, Running, Error) then
                  --  Reported as the pipeline described it: which program, and
                  --  what the host said about it.
                  Report.Emit
                    (Adash.Diagnostics.From_Error
                       (Error, Adash.Diagnostics.Severity_Error,
                        Adash.Diagnostics.Category_Execution,
                        Adash.Diagnostics.Owner_Commands));

                  return Adash.Execution.From_Start_Error (Error.Code);
               end if;

               declare
                  Started : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Add
                      (Shell.Jobs, Running,
                       Ada.Strings.Unbounded.To_String (Told),
                       (if Waits then Adash.Execution.Jobs.Placement_Foreground
                        else Adash.Execution.Jobs.Placement_Background));
               begin
                  if not Waits then
                     Say (Produced, M.Msg_Line_Job_Started,
                          [M.Named ("id", Trim (Integer (Started))),
                           M.Named ("what",
                                    Ada.Strings.Unbounded.To_String (Told))]);

                     return Adash.Execution.Success;
                  end if;

                  --  Waited for, which is what makes this the foreground. The
                  --  session's interrupt goes with it: the child is in a
                  --  process group of its own, so Ctrl-C does not reach it by
                  --  itself, and a wait that ignored the interrupt would leave
                  --  a user with no way out of a program that will not end.
                  declare
                     Wait_Error : Adash.Errors.Error_Info;
                     Ended      : Adash.Execution.Exit_Status;

                     --  The terminal, for as long as this program runs.
                     --
                     --  Both halves, as in Pipelines.Run: the console mode
                     --  where the shell watches its terminal, and the
                     --  terminal's foreground group where the host has them.
                     --  This is the path a user types -- `run ("cat")` --
                     --  and it waits here rather than in Pipelines.Run, so it
                     --  needs its own handover rather than inheriting one.
                     Ours : Integer;

                     Finished : Boolean;
                  begin
                     Adash.Execution.Signals.Hand_Over_Terminal;
                     Adash.Execution.Pipelines.Hand_The_Terminal_To
                       (Adash.Execution.Pipelines.Group (Running), Ours);

                     Finished :=
                       Adash.Execution.Jobs.Wait
                         (Shell.Jobs, Started, Shell.Interrupt, Wait_Error);

                     Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                     Adash.Execution.Signals.Take_Terminal_Back;

                     if not Finished then
                        --  Interrupted, or stopped. Asked to end so that a
                        --  program the user walked away from does not outlive
                        --  the line that started it.
                        declare
                           Stop_Error : Adash.Errors.Error_Info;
                           Asked      : constant Boolean :=
                             Adash.Execution.Jobs.Terminate_Job
                               (Shell.Jobs, Started, Stop_Error);
                        begin
                           pragma Unreferenced (Asked);
                        end;

                        Adash.Execution.Jobs.Forget (Shell.Jobs, Started);

                        return (Kind => Adash.Execution.Exit_Cancelled,
                                others => <>);
                     end if;

                     Ended := Adash.Execution.Jobs.Result
                       (Shell.Jobs, Started).Status;

                     if Id = Command_Time then
                        declare
                           use type Ada.Real_Time.Time;

                           Took : constant Duration :=
                             Ada.Real_Time.To_Duration
                               (Ada.Real_Time.Clock - Began);

                           --  Milliseconds, printed as seconds with three
                           --  decimals. Ada's image of a Duration carries nine,
                           --  and six of them here are the clock rather than
                           --  anything a user waited for.
                           Thousandths : constant Long_Long_Integer :=
                             Long_Long_Integer (Took * 1000);
                        begin
                           Say (Produced, M.Msg_Line_Took,
                                [M.Named ("what",
                                          Ada.Strings.Unbounded.To_String
                                            (Told)),
                                 M.Named
                                   ("seconds",
                                    Trim (Integer (Thousandths / 1000))
                                    & "."
                                    & (if Thousandths mod 1000 < 100
                                       then "0" else "")
                                    & (if Thousandths mod 1000 < 10
                                       then "0" else "")
                                    & Trim
                                        (Integer (Thousandths mod 1000)))]);
                        end;
                     end if;

                     --  Forgotten once its status has been taken. A foreground
                     --  program is not a job a user tracks, and leaving it in
                     --  the table would make `jobs` a list of everything ever
                     --  run.
                     Adash.Execution.Jobs.Forget (Shell.Jobs, Started);

                     return Ended;
                  end;
               end;
            end;

         when Command_Wait =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted < 1
                 or else not Adash.Execution.Jobs.Contains
                               (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted))
               then
                  return Failed (Adash.Errors.Error_Job_Unknown,
                                 [1 => M.Named ("job", Trim (Wanted))]);
               end if;

               declare
                  Error : Adash.Errors.Error_Info;
                  Ended : Adash.Execution.Exit_Status;

                  --  Waiting for a job is putting it in the foreground, in the
                  --  only sense a user means by the word: nothing else runs
                  --  until it ends. So it gets the terminal for as long as
                  --  that takes, exactly as a program started by `run` does --
                  --  a job asked a question while the shell held the terminal
                  --  would be stopped where it asked.
                  Ours : Integer;

                  Done : Boolean;
               begin
                  Adash.Execution.Signals.Hand_Over_Terminal;
                  Adash.Execution.Pipelines.Hand_The_Terminal_To
                    (Adash.Execution.Jobs.Group
                       (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted)),
                     Ours);

                  Done :=
                    Adash.Execution.Jobs.Wait
                      (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted),
                       Cancel => null, Error => Error);

                  Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                  Adash.Execution.Signals.Take_Terminal_Back;

                  if not Done then
                     --  Suspended rather than finished. Said plainly: waiting
                     --  for it would wait for an ending it cannot reach while
                     --  it is stopped, and `no such job` sent the reader
                     --  looking for a job that is right there.
                     return Failed
                       ((if Adash.Execution.Jobs."="
                             (Adash.Execution.Jobs.State
                                (Shell.Jobs,
                                 Adash.Execution.Jobs.Job_Id (Wanted)),
                              Adash.Execution.Jobs.Job_Stopped)
                         then Adash.Errors.Error_Job_Is_Suspended
                         else Adash.Errors.Error_Job_Unknown),
                        [1 => M.Named ("job", Trim (Wanted))]);
                  end if;

                  --  The last stage's status is the pipeline's own, which is
                  --  the one a caller means by "how did the job end".
                  Ended := Adash.Execution.Jobs.Result
                    (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted)).Status;

                  --  A job the host killed has no exit code: Code is only
                  --  meaningful for a program that chose one, and reporting it
                  --  anyway said "status 0" for something that was terminated.
                  if Adash.Execution."=" (Ended.Kind,
                                          Adash.Execution.Exit_Signalled)
                    and then Ended.Signal_Known
                  then
                     Say (Produced, M.Msg_Line_Job_Signalled,
                          [1 => M.Named ("id", Trim (Wanted))],
                          Quoted =>
                            Adash.Execution.Message
                              (Ended.Terminating_Signal),
                          Fills  => "signal");
                  else
                     Say (Produced, M.Msg_Line_Job_Finished,
                          [M.Named ("id", Trim (Wanted)),
                           M.Named ("status", Trim (Ended.Code))]);
                  end if;

                  --  The job's own status, so `wait` on a failing job fails.
                  return Ended;
               end;
            end;

         when Command_Foreground =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted < 1
                 or else not Adash.Execution.Jobs.Contains
                               (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted))
               then
                  return Failed (Adash.Errors.Error_Job_Unknown,
                                 [1 => M.Named ("job", Trim (Wanted))]);
               end if;

               declare
                  Which : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Job_Id (Wanted);

                  Error : Adash.Errors.Error_Info;
               begin
                  --  Resumed first, and then waited for exactly as a program
                  --  started in front is waited for -- the terminal handed
                  --  over, the interrupt able to reach it, and the terminal
                  --  taken back afterwards. A job brought to the front that
                  --  could not be typed at would be half of what was asked.
                  if not Adash.Execution.Jobs.Resume_In_Foreground
                           (Shell.Jobs, Which, Error)
                  then
                     Report.Emit
                       (Adash.Diagnostics.From_Error
                          (Error, Adash.Diagnostics.Severity_Error,
                           Adash.Diagnostics.Category_Execution,
                           Adash.Diagnostics.Owner_Commands));

                     return (Kind => Adash.Execution.Exit_Internal_Failure,
                             others => <>);
                  end if;

                  declare
                     Wait_Error : Adash.Errors.Error_Info;
                     Ours       : Integer;
                     Finished   : Boolean;
                  begin
                     Adash.Execution.Signals.Hand_Over_Terminal;
                     Adash.Execution.Pipelines.Hand_The_Terminal_To
                       (Adash.Execution.Jobs.Group (Shell.Jobs, Which), Ours);

                     Finished :=
                       Adash.Execution.Jobs.Wait
                         (Shell.Jobs, Which, Shell.Interrupt, Wait_Error);

                     Adash.Execution.Pipelines.Take_The_Terminal_Back (Ours);
                     Adash.Execution.Signals.Take_Terminal_Back;

                     if not Finished then
                        --  Stopped again, or interrupted. Left in the table
                        --  either way: a job a user suspended twice is still
                        --  a job they can name.
                        return (Kind => Adash.Execution.Exit_Cancelled,
                                others => <>);
                     end if;

                     declare
                        Ended : constant Adash.Execution.Exit_Status :=
                          Adash.Execution.Jobs.Result (Shell.Jobs, Which).Status;
                     begin
                        Adash.Execution.Jobs.Forget (Shell.Jobs, Which);
                        return Ended;
                     end;
                  end;
               end;
            end;

         when Command_Complete_With =>
            declare
               Program : constant String := Argument (Arguments, 1);
               Name    : constant String := Argument (Arguments, 2);
            begin
               if Program = "" or else Name = "" then
                  return Failed (Adash.Errors.Error_Command_Wrong_Arguments,
                                 [M.Named ("name", "complete_with"),
                                  M.Named ("found", Trim (Given))]);
               end if;

               --  Prepended as a pair, so the most recent registration for a
               --  program is the one found: teaching Tab something new about
               --  a program should not require unteaching the old thing first.
               Shell.Completions.Prepend
                 (Ada.Strings.Unbounded.To_Unbounded_String (Name));
               Shell.Completions.Prepend
                 (Ada.Strings.Unbounded.To_Unbounded_String (Program));

               return Adash.Execution.Success;
            end;

         when Command_Umask =>
            declare
               Held : Natural;
            begin
               if Given = 0 then
                  if not Hostkit.Fs.Creation_Mask (Held) then
                     return Failed (Adash.Errors.Error_No_Creation_Mask,
                                    M.No_Arguments);
                  end if;

                  Say (Produced, M.Msg_Line_Creation_Mask,
                       [1 => M.Named ("mask", Octal (Held))]);
                  return Adash.Execution.Success;
               end if;

               declare
                  Text   : constant String := Argument (Arguments, 1);
                  Wanted : Natural;
                  Before : Natural;
               begin
                  --  Octal, because that is how a mask is written everywhere
                  --  and a shell that read 22 as twenty-two would set
                  --  something nobody asked for.
                  if not Octal_Value (Text, Wanted) then
                     return Failed (Adash.Errors.Error_Mask_Not_Octal,
                                    [1 => M.Named ("text", Text)]);
                  end if;

                  if not Hostkit.Fs.Set_Creation_Mask (Wanted, Before) then
                     return Failed (Adash.Errors.Error_No_Creation_Mask,
                                    M.No_Arguments);
                  end if;

                  return Adash.Execution.Success;
               end;
            end;

         when Command_Resource_Limit | Command_Resource_Ceiling =>
            declare
               use type Hostkit.Limits.Amount;

               --  Which of the host's two numbers this command sets. Reading
               --  shows both either way: somebody asking what a limit is
               --  wants to know how far it could be raised, and the ceiling
               --  is the answer to that.
               Which : constant Hostkit.Limits.Bound :=
                 (if Id = Command_Resource_Limit
                  then Hostkit.Limits.Soft
                  else Hostkit.Limits.Hard);

               procedure Report (Item : Hostkit.Limits.Resource);

               procedure Report (Item : Hostkit.Limits.Resource) is
                  Value : Hostkit.Limits.Amount;
               begin
                  if Id = Command_Resource_Limit
                    and then Hostkit.Limits.Limit
                               (Item, Hostkit.Limits.Soft, Value)
                  then
                     if Value = Hostkit.Limits.Unbounded then
                        Say (Produced, M.Msg_Line_Limit_Unbounded,
                             [1 => M.Named ("resource", Resource_Name (Item))]);
                     else
                        Say (Produced, M.Msg_Line_Limit,
                             [M.Named ("resource", Resource_Name (Item)),
                              M.Named ("value", Amount_Image (Value))]);
                     end if;
                  end if;

                  if Hostkit.Limits.Limit (Item, Hostkit.Limits.Hard, Value)
                  then
                     if Value = Hostkit.Limits.Unbounded then
                        Say (Produced, M.Msg_Line_Limit_Ceiling_Unbounded,
                             [1 => M.Named ("resource", Resource_Name (Item))]);
                     else
                        Say (Produced, M.Msg_Line_Limit_Ceiling,
                             [M.Named ("resource", Resource_Name (Item)),
                              M.Named ("value", Amount_Image (Value))]);
                     end if;
                  end if;
               end Report;

               Wanted : Hostkit.Limits.Resource;
            begin
               --  Nothing named: every limit this host has. A host with none
               --  says so rather than printing an empty list, which a script
               --  could not tell from a host whose limits were all unset.
               if Given = 0 then
                  if not Hostkit.Limits.Applies
                           (Hostkit.Limits.Resource'First)
                  then
                     return Failed (Adash.Errors.Error_No_Resource_Limits,
                                    M.No_Arguments);
                  end if;

                  for Item in Hostkit.Limits.Resource loop
                     if Hostkit.Limits.Applies (Item) then
                        Report (Item);
                     end if;
                  end loop;

                  return Adash.Execution.Success;
               end if;

               declare
                  Named : constant String := Argument (Arguments, 1);
               begin
                  if not Resource_Named (Named, Wanted) then
                     return Failed (Adash.Errors.Error_Unknown_Resource,
                                    [1 => M.Named ("resource", Named)]);
                  end if;

                  if not Hostkit.Limits.Applies (Wanted) then
                     return Failed (Adash.Errors.Error_No_Resource_Limits,
                                    M.No_Arguments);
                  end if;

                  if Given = 1 then
                     Report (Wanted);
                     return Adash.Execution.Success;
                  end if;

                  declare
                     Text  : constant String := Argument (Arguments, 2);
                     Value : Hostkit.Limits.Amount;
                  begin
                     if not Limit_Value (Text, Value) then
                        return Failed
                          (Adash.Errors.Error_Limit_Not_A_Number,
                           [1 => M.Named ("text", Text)]);
                     end if;

                     --  The host refuses a soft limit above the ceiling and a
                     --  ceiling raised without privilege, and does not say
                     --  which -- so neither does this.
                     if not Hostkit.Limits.Set_Limit (Wanted, Which, Value)
                     then
                        return Failed
                          (Adash.Errors.Error_Limit_Refused,
                           [1 => M.Named ("resource", Named)]);
                     end if;

                     return Adash.Execution.Success;
                  end;
               end;
            end;

         when Command_Stop_Process =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted <= 0
               then
                  return Failed
                    (Adash.Errors.Error_Process_Would_Not_Stop,
                     [1 => M.Named ("process", Trim (Wanted))]);
               end if;

               --  Asked of the host, which is the only thing that knows what
               --  a process id means here. A refusal is not told apart from a
               --  process that has already gone: the host does not say which,
               --  and inventing the difference would be a claim.
               if not Hostkit.Process.Request_Stop (Wanted) then
                  return Failed
                    (Adash.Errors.Error_Process_Would_Not_Stop,
                     [1 => M.Named ("process", Trim (Wanted))]);
               end if;

               return Adash.Execution.Success;
            end;

         when Command_Stop | Command_Suspend | Command_Resume =>
            declare
               Wanted : Integer;
            begin
               if not Whole_Argument (Arguments, 1, Wanted)
                 or else Wanted < 1
                 or else not Adash.Execution.Jobs.Contains
                               (Shell.Jobs, Adash.Execution.Jobs.Job_Id (Wanted))
               then
                  return Failed (Adash.Errors.Error_Job_Unknown,
                                 [1 => M.Named ("job", Trim (Wanted))]);
               end if;

               declare
                  Which : constant Adash.Execution.Jobs.Job_Id :=
                    Adash.Execution.Jobs.Job_Id (Wanted);

                  Error : Adash.Errors.Error_Info;

                  --  Three ways to signal one job, and one shape for all of
                  --  them: which job, what to ask of it, and what the table
                  --  said when it could not.
                  Asked : constant Boolean :=
                    (case Id is
                        when Command_Suspend =>
                          Adash.Execution.Jobs.Suspend
                            (Shell.Jobs, Which, Error),
                        when Command_Resume =>
                          Adash.Execution.Jobs.Resume_In_Background
                            (Shell.Jobs, Which, Error),
                        when others =>
                          Adash.Execution.Jobs.Terminate_Job
                            (Shell.Jobs, Which, Error));
               begin
                  if not Asked then
                     --  Reported as the job table described it. This used to
                     --  answer `no job control here` whatever went wrong,
                     --  which is a guess: a host that refused the signal and a
                     --  host that has no groups at all are different answers
                     --  and the reader is owed whichever applies.
                     if Adash.Errors.Is_Failure (Error) then
                        Report.Emit
                          (Adash.Diagnostics.From_Error
                             (Error, Adash.Diagnostics.Severity_Error,
                              Adash.Diagnostics.Category_Execution,
                              Adash.Diagnostics.Owner_Commands));

                        return (Kind => Adash.Execution.Exit_Internal_Failure,
                                others => <>);
                     end if;

                     return Failed (Adash.Errors.Error_Capability_Unavailable,
                                    M.No_Arguments,
                                    Quoted =>
                                      Adash.Platform.Message
                                        (Adash.Platform.Capability_Job_Control),
                                    Fills => "capability");
                  end if;

                  --  What became of it. `stop` ends a job and `wait` reports
                  --  that; suspending and resuming leave it in the table, so
                  --  the line naming its new state is the only word the user
                  --  would otherwise get.
                  if Id /= Command_Stop then
                     --  Not refreshed again here: the table has already waited
                     --  for the job to reach the state it was asked for, and
                     --  polling once more would read a moment later than the
                     --  one that was confirmed.
                     Say (Produced, M.Msg_Line_Job,
                          [M.Named ("job", Trim (Wanted)),
                           M.Named
                             ("description",
                              Adash.Execution.Jobs.Description
                                (Shell.Jobs, Which))],
                          Quoted =>
                            Adash.Execution.Jobs.Message
                              (Adash.Execution.Jobs.State (Shell.Jobs, Which)),
                          Fills  => "state");
                  end if;

                  return Adash.Execution.Success;
               end;
            end;

         when Command_Settings =>
            declare
               package Config renames Adash.Configuration;

               --  A setting's value, as the user would type it back.
               function Written (Which : Config.Setting_Id) return String;

               function Written (Which : Config.Setting_Id) return String is
               begin
                  case Config.Kind (Which) is
                     when Config.Boolean_Setting =>
                        --  Ada spells these True and False, and so does the
                        --  language this shell speaks. The configuration file
                        --  is TOML and spells them lower case; what is shown
                        --  is what the file holds, because that is what a user
                        --  who goes to edit it will see.
                        return (if Shell.Chosen.Boolean_Value (Which)
                                then "true" else "false");

                     when Config.Integer_Setting =>
                        return Trim
                          (Integer (Shell.Chosen.Integer_Value (Which)));

                     when Config.Choice_Setting =>
                        return Shell.Chosen.Choice_Value (Which);

                     when Config.Text_Setting =>
                        return Shell.Chosen.Text_Value (Which);
                  end case;
               end Written;
            begin
               if Given = 0 then
                  for Which in Config.Setting_Id loop
                     Say (Produced, M.Msg_Line_Setting,
                          [M.Named ("key", Config.Key (Which)),
                           M.Named ("value", Written (Which))],
                          Quoted => Config.Description (Which),
                          Fills  => "summary");
                  end loop;

                  return Adash.Execution.Success;
               end if;

               if Given /= 2 then
                  --  A name with no value is a question this command cannot
                  --  answer differently from the listing, and a value with no
                  --  name is nothing at all.
                  return Failed (Adash.Errors.Error_Command_Wrong_Arguments,
                                 [M.Named ("name", "settings"),
                                  M.Named ("found", Trim (Given))]);
               end if;

               declare
                  Which : Config.Setting_Id;
                  Named_As : constant String := Argument (Arguments, 1);
                  Wanted   : constant String := Argument (Arguments, 2);
               begin
                  if not Config.Find (Named_As, Which) then
                     --  Its own message rather than the file reader's. That
                     --  one says the key `was ignored`, which is true of a
                     --  line in a file nobody is watching and wrong for
                     --  something a user has just typed.
                     return Refused
                       (M.Msg_Setting_Unknown,
                        [1 => M.Named ("key", Named_As)]);
                  end if;

                  case Config.Kind (Which) is
                     when Config.Boolean_Setting =>
                        --  Only the two words the file uses. Accepting `yes`
                        --  or `1` here would make the shell and the file
                        --  disagree about what a Boolean looks like.
                        if Wanted = "true" then
                           Shell.Chosen.Set_Boolean (Which, True);
                        elsif Wanted = "false" then
                           Shell.Chosen.Set_Boolean (Which, False);
                        else
                           return Refused
                             (M.Msg_Config_Wrong_Type,
                              [1 => M.Named ("key", Named_As)],
                              M.Msg_Config_Wants_Truth);
                        end if;

                     when Config.Integer_Setting =>
                        declare
                           Value : Long_Long_Integer;
                        begin
                           Value := Long_Long_Integer'Value (Wanted);

                           if not Shell.Chosen.Set_Integer (Which, Value) then
                              return Refused
                                (M.Msg_Config_Out_Of_Range,
                                 [1 => M.Named ("key", Named_As)],
                                 M.Msg_Config_Wants_Range,
                                 [M.Named
                                    ("low",
                                     Trim (Integer (Config.Minimum (Which)))),
                                  M.Named
                                    ("high",
                                     Trim
                                       (Integer
                                          (Config.Maximum (Which))))]);
                           end if;
                        exception
                           when Constraint_Error =>
                              return Refused
                                (M.Msg_Config_Wrong_Type,
                                 [1 => M.Named ("key", Named_As)],
                                 M.Msg_Config_Wants_Whole);
                        end;

                     when Config.Choice_Setting =>
                        if not Shell.Chosen.Set_Choice (Which, Wanted) then
                           --  What it would have accepted, so the reader does
                           --  not have to go and find the list.
                           declare
                              Allowed : Ada.Strings.Unbounded.Unbounded_String;
                           begin
                              for Index in 1 .. Config.Choice_Count (Which) loop
                                 if Index > 1 then
                                    Ada.Strings.Unbounded.Append
                                      (Allowed, ", ");
                                 end if;

                                 Ada.Strings.Unbounded.Append
                                   (Allowed, Config.Choice_At (Which, Index));
                              end loop;

                              return Refused
                                (M.Msg_Config_Bad_Choice,
                                 [M.Named ("key", Named_As),
                                  M.Named
                                    ("detail",
                                     Ada.Strings.Unbounded.To_String
                                       (Allowed))]);
                           end;
                        end if;

                     when Config.Text_Setting =>
                        if not Shell.Chosen.Set_Text (Which, Wanted) then
                           --  Too long, or holding something a terminal would
                           --  read as an instruction rather than as text.
                           return Refused
                             (M.Msg_Config_Wrong_Type,
                              [1 => M.Named ("key", Named_As)],
                              M.Msg_Config_Wants_Text,
                              [1 => M.Named
                                      ("limit", Trim (Config.Maximum_Text))]);
                        end if;
                  end case;

                  --  Said back, so a user sees what the shell now holds rather
                  --  than trusting that it took.
                  Say (Produced, M.Msg_Line_Setting,
                       [M.Named ("key", Config.Key (Which)),
                        M.Named ("value", Written (Which))],
                       Quoted => Config.Description (Which),
                       Fills  => "summary");

                  return Adash.Execution.Success;
               end;
            end;

         when Command_Write_File | Command_Append_File =>
            declare
               What : constant String := Argument (Arguments, 1);
               Path : constant String := Argument (Arguments, 2);
               Done : Adash.Filesystem.Written;
            begin
               if Id = Command_Write_File then
                  Adash.Filesystem.Write (Path, What, Done);
               else
                  Adash.Filesystem.Append (Path, What, Done);
               end if;

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Ok =>
                     --  Silent. A command that announced each write would put
                     --  its own lines into the script's output, so a script
                     --  that saves a file and prints a result could not have
                     --  its output read by anything. `Status` says it worked;
                     --  a failure says so on standard error.
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_On_Interrupt =>
            declare
               Name : constant String := Argument (Arguments, 1);
            begin
               if Name = "" then
                  return Failed (Adash.Errors.Error_Command_Wrong_Arguments,
                                 [1 => M.Named ("name", "on_interrupt")]);
               end if;

               --  Most recent first, as cleanups are, and for the same
               --  reason: what was set up last is undone first.
               Shell.Interrupt_Handlers.Prepend
                 (Ada.Strings.Unbounded.To_Unbounded_String (Name));

               return Adash.Execution.Success;
            end;

         when Command_On_Signal | Command_Signal_Process =>
            declare
               --  The signal a word names, if any. The host's own names in
               --  lower case, so the list a user reads and the list this
               --  matches against are one list.
               function Signal_Named
                 (Text : String;
                  Item : out Hostkit.Signals.Signal) return Boolean;

               function Signal_Named
                 (Text : String;
                  Item : out Hostkit.Signals.Signal) return Boolean is
               begin
                  Item := Hostkit.Signals.Signal'First;

                  for Candidate in Hostkit.Signals.Signal loop
                     if Lowered (Hostkit.Signals.Name (Candidate)) = Text then
                        Item := Candidate;
                        return True;
                     end if;
                  end loop;

                  return False;
               end Signal_Named;

               Which : Hostkit.Signals.Signal;
            begin
               if Id = Command_On_Signal then
                  declare
                     Named   : constant String := Argument (Arguments, 1);
                     Handler : constant String := Argument (Arguments, 2);
                  begin
                     if Handler = "" then
                        return Failed
                          (Adash.Errors.Error_Command_Wrong_Arguments,
                           [1 => M.Named ("name", "on_signal")]);
                     end if;

                     if not Signal_Named (Named, Which) then
                        return Failed (Adash.Errors.Error_Unknown_Signal,
                                       [1 => M.Named ("signal", Named)]);
                     end if;

                     --  Asked of the host, which is the only thing that knows
                     --  whether it can report this one arriving: Kill and Stop
                     --  nowhere, and on Windows nothing but the interrupt.
                     if not Adash.Execution.Signals.Record_Signal (Which) then
                        return Failed
                          (Adash.Errors.Error_Signal_Not_Catchable,
                           [1 => M.Named ("signal", Named)]);
                     end if;

                     --  Most recent first, as the interrupt handlers are.
                     Shell.Signal_Handlers.Prepend
                       (Ada.Strings.Unbounded.To_Unbounded_String (Handler));
                     Shell.Signal_Handlers.Prepend
                       (Ada.Strings.Unbounded.To_Unbounded_String
                          (Lowered (Hostkit.Signals.Name (Which))));

                     return Adash.Execution.Success;
                  end;
               end if;

               declare
                  Wanted : Integer;
                  Named  : constant String := Argument (Arguments, 2);
               begin
                  if not Whole_Argument (Arguments, 1, Wanted)
                    or else Wanted <= 0
                  then
                     return Failed
                       (Adash.Errors.Error_Signal_Refused,
                        [M.Named ("signal", Named),
                         M.Named ("process", Argument (Arguments, 1))]);
                  end if;

                  if not Signal_Named (Named, Which) then
                     return Failed (Adash.Errors.Error_Unknown_Signal,
                                    [1 => M.Named ("signal", Named)]);
                  end if;

                  if not Hostkit.Signals.Send_To_Process (Wanted, Which) then
                     return Failed
                       (Adash.Errors.Error_Signal_Refused,
                        [M.Named ("signal", Named),
                         M.Named ("process", Trim (Wanted))]);
                  end if;

                  return Adash.Execution.Success;
               end;
            end;

         when Command_On_Exit =>
            declare
               Name : constant String := Argument (Arguments, 1);
            begin
               if Name = "" then
                  return Failed (Adash.Errors.Error_Command_Wrong_Arguments,
                                 [1 => M.Named ("name", "on_exit")]);
               end if;

               --  Most recent first, so that cleanups undo in the order that
               --  matches how they were set up: a script that makes a
               --  directory and then a file in it removes the file first.
               Shell.Cleanups.Prepend
                 (Ada.Strings.Unbounded.To_Unbounded_String (Name));

               return Adash.Execution.Success;
            end;

         when Command_Remove_File | Command_Remove_Directory =>
            declare
               Path : constant String := Argument (Arguments, 1);
               Done : Adash.Filesystem.Written;
            begin
               if Id = Command_Remove_File then
                  Adash.Filesystem.Remove_File (Path, Done);
               else
                  Adash.Filesystem.Remove_Directory (Path, Done);
               end if;

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Ok =>
                     --  Silent, as writing is: what became of it is Status.
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_Rename | Command_Copy_File =>
            declare
               From : constant String := Argument (Arguments, 1);
               To   : constant String := Argument (Arguments, 2);
               Done : Adash.Filesystem.Written;
            begin
               if Id = Command_Rename then
                  Adash.Filesystem.Rename (From, To, Done);
               else
                  Adash.Filesystem.Copy_File (From, To, Done);
               end if;

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     --  Named by where it was going, which is where the
                     --  refusal usually is: something is already there.
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", To)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", To)]);

                  when Adash.Filesystem.Write_Ok =>
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_Make_Directory =>
            declare
               Path : constant String := Argument (Arguments, 1);
               Done : Adash.Filesystem.Written;
            begin
               Adash.Filesystem.Make_Directory (Path, Done);

               case Done is
                  when Adash.Filesystem.Write_Refused =>
                     return Failed (Adash.Errors.Error_File_Not_Writable,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Failed =>
                     return Failed (Adash.Errors.Error_File_Write_Failed,
                                    [1 => M.Named ("path", Path)]);

                  when Adash.Filesystem.Write_Ok =>
                     --  Silent, like writing: a command that announced itself
                     --  would put its own lines into a script's output.
                     return Adash.Execution.Success;
               end case;
            end;

         when Command_Save_Settings =>
            declare
               Result : Adash.Persistence.Outcome;
            begin
               Adash.Configuration.Files.Save (Shell.Chosen, Result);

               if not Adash.Persistence.Succeeded (Result) then
                  return Refused
                    (M.Msg_Config_Unreadable,
                     [1 => M.Named
                             ("path", Adash.Configuration.Files.Path)]);
               end if;

               Say (Produced, M.Msg_Line_Settings_Saved,
                    [1 => M.Named
                            ("path", Adash.Configuration.Files.Path)]);

               return Adash.Execution.Success;
            end;

         when Command_Help =>
            if Given = 1 then
               declare
                  Wanted : Command_Id;
               begin
                  if not Find (Argument (Arguments, 1), Wanted) then
                     return Failed (Adash.Errors.Error_Command_Unavailable,
                                    [1 => M.Named ("name",
                                                   Argument (Arguments, 1))]);
                  end if;

                  Say (Produced, Describe (Wanted).Documentation);
                  return Adash.Execution.Success;
               end;
            end if;

            for Index in 1 .. Count loop
               declare
                  About : constant Metadata := Entry_At (Index);
               begin
                  --  What the command is for, quoted rather than rendered:
                  --  this package has no catalog and must not have one. The
                  --  summary was an empty string here for as long as `help`
                  --  has existed, so the listing was a column of names beside
                  --  a column of nothing.
                  Say (Produced, M.Msg_Line_Command_Entry,
                       [1 => M.Named ("name", M.Value (About.Name))],
                       Quoted => About.Documentation,
                       Fills  => "summary");
               end;
            end loop;

            return Adash.Execution.Success;

         when Command_Version =>
            Say (Produced, M.Msg_Line_Version,
                 [M.Named ("name", Adash.Version.Crate_Name),
                  M.Named ("version", Adash.Version.Number)]);
            return Adash.Execution.Success;

         when Command_Source =>
            declare
               Path   : constant String := Argument (Arguments, 1);
               Status : Adash.Execution.Exit_Status;
               Failed_To_Run : Boolean;
            begin
               if Shell.Scripts = null then
                  --  Nothing here can run one. Refused rather than ignored:
                  --  a `source` that quietly did nothing would look like a
                  --  file that was empty.
                  return Failed
                    (Adash.Errors.Error_Command_Unavailable,
                     [1 => M.Named ("name", M.Value (Describe (Id).Name))]);
               end if;

               Shell.Scripts.Run_Script (Path, Status, Failed_To_Run);

               if Failed_To_Run then
                  --  The runner has already said what was wrong with the file.
                  return (Kind => Adash.Execution.Exit_Internal_Failure,
                          others => <>);
               end if;

               --  The script's own status, so `source failing.adash` is a
               --  failure here too.
               return Status;
            end;

         when Command_Forget =>
            declare
               Wanted    : Integer := 1;
               Forgotten : Natural;
               Failed_To : Boolean;
            begin
               if Shell.History = null then
                  --  Nothing is keeping track, so there is nothing to take
                  --  out. The same answer `history` gives, for the same
                  --  reason: this session has no log, and that is not a
                  --  missing feature.
                  return Failed (Adash.Errors.Error_No_History_Here,
                                 M.No_Arguments);
               end if;

               --  Two ways of saying which entry, told apart by what was
               --  given rather than by a second command: a number is how many
               --  of the most recent, and a line of text is that line wherever
               --  it is -- including in the file, beyond what this session
               --  ever read back.
               if Given >= 1 and then Text_Argument (Arguments, 1) then
                  Shell.History.Forget_Line
                    (Text => Argument (Arguments, 1),
                     Forgotten => Forgotten,
                     Failed => Failed_To);

               else
                  --  A count that is not a positive number is refused rather
                  --  than read as "all of it". `history (0)` listing
                  --  everything costs a screen; `forget (0)` taking everything
                  --  would cost the history, and a command that destroys more
                  --  than it was asked to must not be reachable by a typing
                  --  mistake.
                  if Given >= 1
                    and then (not Whole_Argument (Arguments, 1, Wanted)
                              or else Wanted < 1)
                  then
                     return Failed
                       (Adash.Errors.Error_Command_Wrong_Arguments,
                        [1 => M.Named ("name", M.Value (Describe (Id).Name))]);
                  end if;

                  Shell.History.Forget_Recent
                    (Count => Positive (Wanted),
                     Forgotten => Forgotten,
                     Failed => Failed_To);
               end if;

               if Failed_To then
                  --  The session has forgotten it and the file has not, which
                  --  is the half that matters. Reported rather than counted as
                  --  done: a user told "2 forgotten" would stop looking.
                  return Failed (Adash.Errors.Error_History_Not_Forgotten,
                                 M.No_Arguments);
               end if;

               Say (Produced, M.Msg_Line_Forgotten,
                    [1 => M.Named ("count", Trim (Forgotten))]);

               return Adash.Execution.Success;
            end;

         when Command_History =>
            declare
               Wanted : Integer;
               Held   : Natural;
               First  : Positive;
            begin
               if Shell.History = null then
                  --  Nothing is keeping track. Not the same as an empty
                  --  history, and reporting no lines would say the session had
                  --  typed nothing.
                  return Failed (Adash.Errors.Error_No_History_Here,
                                 M.No_Arguments);
               end if;

               Held := Shell.History.Recorded;

               if Held = 0 then
                  return Adash.Execution.Success;
               end if;

               --  With a count, the last that many. Without one, all of them.
               --  A count larger than the log is not an error: the user asked
               --  for the last twenty and there are nine, and nine is the
               --  answer to that.
               if Given = 1 and then Whole_Argument (Arguments, 1, Wanted)
                 and then Wanted > 0
                 and then Wanted < Held
               then
                  First := Held - Wanted + 1;
               else
                  First := 1;
               end if;

               for Index in First .. Held loop
                  Say (Produced, M.Msg_Line_History_Entry,
                       [M.Named ("number", Trim (Index)),
                        M.Named ("line", Shell.History.Recorded_Line (Index))]);
               end loop;

               return Adash.Execution.Success;
            end;

      end case;
   end Run;

end Adash.Commands.Builtins;

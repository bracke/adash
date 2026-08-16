with Ada.Strings.Fixed;

with Adash.Commands.Builtins;
with Adash.Errors;
with Adash.Language.Symbols;

package body Adash.Commands is

   package M renames Adash.Messages;

   function Named (Text : String) return M.Argument
   is (M.Named ("name", Text));

   Any_Number : constant Natural := Natural'Last;

   --  The registry. Order is for readability only; nothing depends on it.
   --  Profile constructors, so the table below reads as a list of commands
   --  rather than as a list of aggregates.
   function Text (Of_Name : String) return Parameter is
     (Name => Named (Of_Name), Of_Type => Adash.Language.Types.Type_String);

   function Whole (Of_Name : String) return Parameter is
     (Name => Named (Of_Name), Of_Type => Adash.Language.Types.Type_Integer);

   --  A parameter with a name and no type: it takes whatever it is given, and
   --  the command decides what to do from the value's own kind. `put_line` has
   --  had one since the beginning; `forget` has one because a count and a line
   --  of text are two ways of saying which entry, and two commands for that
   --  would be two things to learn.
   function Anything (Of_Name : String) return Parameter is
     (Name => Named (Of_Name), Of_Type => Adash.Language.Types.Type_None);

   Nothing : constant Parameter :=
     (Name => Named (""), Of_Type => Adash.Language.Types.Type_None);

   No_Parameters : constant Parameter_List := [others => Nothing];

   Registry : constant array (Positive range <>) of Metadata :=
     [(Command_Change_Directory, Named ("cd"), 0, 1, [1 => Text ("Directory"), others => Nothing],
       Changes_State,
       M.Msg_Command_Cd_Doc, M.Msg_Command_Hint, Available),
      (Command_Print_Directory, Named ("pwd"), 0, 0, No_Parameters,
       Reports_Only,
       M.Msg_Command_Pwd_Doc, M.Msg_Command_Hint, Available),
      (Command_Exit, Named ("quit"), 0, 1, [1 => Whole ("Status"), others => Nothing],
       Ends_Session,
       M.Msg_Command_Exit_Doc, M.Msg_Command_Hint, Available),
      (Command_Set, Named ("set"), 1, 1, [1 => Text ("Assignment"), others => Nothing],
       Changes_State,
       M.Msg_Command_Set_Doc, M.Msg_Command_Hint, Available),
      (Command_Unset, Named ("unset"), 1, 1, [1 => Text ("Name"), others => Nothing],
       Changes_State,
       M.Msg_Command_Unset_Doc, M.Msg_Command_Hint, Available),
      (Command_Environment, Named ("env"), 0, 0, No_Parameters,
       Reports_Only,
       M.Msg_Command_Env_Doc, M.Msg_Command_Hint, Available),
      (Command_Jobs, Named ("jobs"), 0, 0, No_Parameters,
       Reports_Only,
       M.Msg_Command_Jobs_Doc, M.Msg_Command_Hint, Available),
      (Command_Help, Named ("help"), 0, 1, [1 => Text ("Topic"), others => Nothing],
       Reports_Only,
       M.Msg_Command_Help_Doc, M.Msg_Command_Hint, Available),
      (Command_Version, Named ("version"), 0, 0, No_Parameters,
       Reports_Only,
       M.Msg_Command_Version_Doc, M.Msg_Command_Hint, Available),

      (Command_History, Named ("history"), 0, Any_Number, [1 => Whole ("Count"), others => Nothing],
       Reports_Only,
       M.Msg_Command_History_Doc, M.Msg_Command_Hint, Available),
      (Command_Forget, Named ("forget"), 0, Any_Number, [1 => Anything ("What"), others => Nothing],
       Changes_State,
       M.Msg_Command_Forget_Doc, M.Msg_Command_Hint, Available),
      (Command_Source, Named ("source"), 1, 1, [1 => Text ("Path"), others => Nothing],
       Changes_State,
       M.Msg_Command_Source_Doc, M.Msg_Command_Hint, Available),

      --  Running a program and waiting for it, which is the thing a shell is
      --  for. `start` is the same act without the waiting.
      (Command_Run, Named ("run"), 1, Any_Number,
       [1 => Text ("Program"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Doc, M.Msg_Command_Hint, Available),

      --  The same, with one of the program's streams attached to a file. The
      --  file comes first because the arguments after it belong to the program
      --  and there is no other place to put a boundary between them: this
      --  language has no `>` and will not grow one, because a second notation
      --  for running things is a second command language.
      (Command_Run_Into, Named ("run_into"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Into_Doc, M.Msg_Command_Hint, Available),
      (Command_Run_From, Named ("run_from"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_From_Doc, M.Msg_Command_Hint, Available),
      (Command_Run_Append, Named ("run_append"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Append_Doc, M.Msg_Command_Hint, Available),
      (Command_Run_New, Named ("run_new"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_New_Doc, M.Msg_Command_Hint, Available),

      --  A pipeline, built a stage at a time and then run. Two commands rather
      --  than one because a pipeline is a list of command lines, and a single
      --  call would have to carry a boundary between them inside its arguments.
      (Command_Pipe, Named ("pipe"), 1, Any_Number,
       [1 => Text ("Program"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Pipe_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_Run, Named ("pipe_run"), 0, 0, No_Parameters,
       Changes_State,
       M.Msg_Command_Pipe_Run_Doc, M.Msg_Command_Hint, Available),

      --  Job control. `start` names a program and its arguments separately
      --  rather than taking a command line: a filename with a space in it is
      --  one argument, and splitting a string here would invent a quoting rule
      --  this language does not have.
      (Command_Start, Named ("start"), 1, Any_Number,
       [1 => Text ("Program"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Start_Doc, M.Msg_Command_Hint, Available),
      (Command_Wait, Named ("wait"), 1, 1, [1 => Whole ("Job"), others => Nothing],
       Changes_State,
       M.Msg_Command_Wait_Doc, M.Msg_Command_Hint, Available),
      (Command_Stop, Named ("stop"), 1, 1, [1 => Whole ("Job"), others => Nothing],
       Changes_State,
       M.Msg_Command_Stop_Doc, M.Msg_Command_Hint, Available),
      (Command_Suspend, Named ("suspend"), 1, 1,
       [1 => Whole ("Job"), others => Nothing],
       Changes_State,
       M.Msg_Command_Suspend_Doc, M.Msg_Command_Hint, Available),
      (Command_Resume, Named ("resume"), 1, 1,
       [1 => Whole ("Job"), others => Nothing],
       Changes_State,
       M.Msg_Command_Resume_Doc, M.Msg_Command_Hint, Available),
      --  Text first, file second, matching assignment rather than `run_into`:
      --  nothing follows the text, so there is no boundary to protect, and
      --  `write_file (Report, "out.txt")` reads in the order it happens.
      (Command_Write_File, Named ("write_file"), 2, 2,
       [1 => Text ("Text"), 2 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Write_File_Doc, M.Msg_Command_Hint, Available),

      --  A command rather than a function, for the same reason writing is:
      --  making a directory has consequences, and a reader should see it
      --  happen rather than find it inside a condition.
      (Command_Make_Directory, Named ("make_directory"), 1, 1,
       [1 => Text ("Directory"), others => Nothing],
       Changes_State,
       M.Msg_Command_Make_Directory_Doc, M.Msg_Command_Hint, Available),
      (Command_Append_File, Named ("append_file"), 2, 2,
       [1 => Text ("Text"), 2 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Append_File_Doc, M.Msg_Command_Hint, Available),

      (Command_Settings, Named ("settings"), 0, 2,
       [1 => Text ("Setting"), 2 => Text ("Value"), others => Nothing],
       Changes_State,
       M.Msg_Command_Settings_Doc, M.Msg_Command_Hint, Available),
      (Command_Save_Settings, Named ("save_settings"), 0, 0,
       [others => Nothing],
       Changes_State,
       M.Msg_Command_Save_Settings_Doc, M.Msg_Command_Hint, Available)];

   ------------
   -- Length --
   ------------

   function Length (Item : Text_List) return Natural is
   begin
      return Natural (Item.Items.Length);
   end Length;

   -------------
   -- Element --
   -------------

   function Element (Item : Text_List; Index : Positive) return String is
   begin
      if Index > Natural (Item.Items.Length) then
         return "";
      end if;

      return Ada.Strings.Unbounded.To_String (Item.Items.Element (Index));
   end Element;

   ------------
   -- Append --
   ------------

   procedure Append (Item : in out Text_List; Value : String) is
   begin
      Item.Items.Append (Ada.Strings.Unbounded.To_Unbounded_String (Value));
   end Append;

   -----------
   -- Count --
   -----------

   function Count return Natural is
   begin
      return Registry'Length;
   end Count;

   --------------
   -- Entry_At --
   --------------

   function Entry_At (Index : Positive) return Metadata is
   begin
      return Registry (Registry'First + Index - 1);
   end Entry_At;

   --------------
   -- Describe --
   --------------

   function Describe (Id : Command_Id) return Metadata is
   begin
      for Current of Registry loop
         if Current.Id = Id then
            return Current;
         end if;
      end loop;

      return Registry (Registry'First);
   end Describe;

   ----------
   -- Find --
   ----------

   function Find (Name : String; Id : out Command_Id) return Boolean is
      Wanted : constant String := Adash.Language.Symbols.Fold (Name);
   begin
      Id := Command_Help;

      for Current of Registry loop
         if Adash.Language.Symbols.Fold (M.Value (Current.Name)) = Wanted then
            Id := Current.Id;
            return True;
         end if;
      end loop;

      return False;
   end Find;

   -------------
   -- Message --
   -------------

   function Message (Item : Line) return M.Message_Id is
   begin
      return Item.Message;
   end Message;

   ---------------
   -- Arguments --
   ---------------

   function Arguments (Item : Line) return M.Argument_List is
   begin
      return Item.Arguments (1 .. Item.Argument_Count);
   end Arguments;

   ------------
   -- Detail --
   ------------

   function Detail (Item : Line) return M.Message_Id is
   begin
      return Item.Detail;
   end Detail;

   -------------------------
   -- Detail_Placeholder --
   -------------------------

   function Detail_Placeholder (Item : Line) return String is
   begin
      return Ada.Strings.Unbounded.To_String (Item.Fills);
   end Detail_Placeholder;

   -----------
   -- Count --
   -----------

   function Count (Item : Output) return Natural is
   begin
      return Natural (Item.Lines.Length);
   end Count;

   -------------
   -- Element --
   -------------

   function Element (Item : Output; Index : Positive) return Line is
   begin
      return Item.Lines.Element (Index);
   end Element;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Output) is
   begin
      Item.Lines.Clear;
   end Clear;

   ---------
   -- Say --
   ---------

   procedure Say
     (Item      : in out Output;
      Message   : M.Message_Id;
      Arguments : M.Argument_List := M.No_Arguments;
      Quoted    : M.Message_Id := M.Msg_Error_None;
      Fills     : String := "")
   is
      Added : Line;
   begin
      Added.Message := Message;
      Added.Detail  := Quoted;
      Added.Fills   := Ada.Strings.Unbounded.To_Unbounded_String (Fills);
      Added.Argument_Count := Natural'Min (Arguments'Length, Max_Line_Arguments);

      for Index in 1 .. Added.Argument_Count loop
         Added.Arguments (Index) := Arguments (Arguments'First + Index - 1);
      end loop;

      Item.Lines.Append (Added);
   end Say;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Item : in out State) is
   begin
      --  A session starts from the shell's own environment; `set` after that
      --  changes what children inherit and not what this process has.
      Item.Environment    := Adash.Execution.Environment.Inherited;
      Item.Exit_Requested := False;
      Item.Exit_Status    := Adash.Execution.Success;
   end Initialize;

   -------------
   -- Execute --
   -------------

   function Execute
     (Id        : Command_Id;
      Arguments : Argument_Set;
      Shell     : in out State;
      Produced  : in out Output;
      Report    : in out Adash.Diagnostics.List)
      return Adash.Execution.Exit_Status
   is
      About : constant Metadata := Describe (Id);
      Given : constant Natural := Arguments.Count;

      function Refuse
        (Code : Adash.Errors.Error_Code;
         Args : M.Argument_List) return Adash.Execution.Exit_Status
      is
      begin
         Report.Emit
           (Adash.Diagnostics.Make
              (Message   => Adash.Errors.Message (Code),
               Level     => Adash.Diagnostics.Severity_Error,
               Of_Kind   => Adash.Diagnostics.Category_Execution,
               Raised_By => Adash.Diagnostics.Owner_Commands,
               Arguments => Args));

         return (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end Refuse;

   begin
      --  Deliberately not cleared here. Several commands may run in one
      --  submission -- `pwd; version;` -- and each clearing would leave only
      --  the last one's output. The caller clears once per submission, which
      --  is the unit a user thinks in.
      if About.Status = Not_In_This_Build then
         --  "Not in this build" rather than "no such command". The difference
         --  is a missing feature against a typo, and only the shell knows
         --  which.
         return Refuse (Adash.Errors.Error_Command_Unavailable,
                        [1 => M.Named ("name", M.Value (About.Name))]);
      end if;

      if Given < About.Minimum_Arguments
        or else Given > About.Maximum_Arguments
      then
         return Refuse
           (Adash.Errors.Error_Command_Wrong_Arguments,
            [M.Named ("name", M.Value (About.Name)),
             M.Named ("found", Ada.Strings.Fixed.Trim
                                 (Natural'Image (Given), Ada.Strings.Both))]);
      end if;

      return Builtins.Run (Id, Arguments, Shell, Produced, Report);
   end Execute;

end Adash.Commands;

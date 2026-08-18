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
      --  The same, with the program's input coming from text this script
      --  computed rather than from a file it has.
      --
      --  The gap this closes is one every shell script meets: `printf %s
      --  "$json" | tool` has no spelling here, because a pipeline reads from a
      --  program and a redirection reads from a file, and a String was neither.
      --  A script that had worked something out and wanted to hand it to a
      --  program had to write a file first, choose where to put it, and
      --  remember to remove it -- three decisions nobody wanted to make.
      --
      --  The text comes first for the same reason a file does: what follows is
      --  the program and its arguments, and there is no other place to put a
      --  boundary between them.
      (Command_Run_From_Text, Named ("run_from_text"), 2, Any_Number,
       [1 => Text ("Input"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_From_Text_Doc, M.Msg_Command_Hint, Available),

      --  The same, with one variable set for that program and nothing else.
      --
      --  `LC_ALL=C sort` is the shape every shell has and this one did not:
      --  `set` changes the session, so a script wanting one variable for one
      --  program had to set it, run, and unset it -- and get that right on the
      --  path where the program failed, which is the path nobody writes.
      --
      --  One assignment, spelled the way `set` spells one, and the first
      --  argument for the same reason a file is: what follows is the program
      --  and its arguments, and a boundary a reader cannot see is worse than a
      --  limit they can. A command needing two variables sets one in the
      --  session; a rule that read assignments until something without an `=`
      --  in it would be a rule with an exception waiting for the first path
      --  that has one.
      (Command_Run_With, Named ("run_with"), 2, Any_Number,
       [1 => Text ("Assignment"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_With_Doc, M.Msg_Command_Hint, Available),

      (Command_Run_Append, Named ("run_append"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Append_Doc, M.Msg_Command_Hint, Available),
      (Command_Run_New, Named ("run_new"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_New_Doc, M.Msg_Command_Hint, Available),

      --  The other stream. Until this existed a script could put a program's
      --  output anywhere and its complaints nowhere: they went to the shell's
      --  own error stream and mixed with the shell's, which is a nuisance for
      --  a reader and worse for anything parsing what the shell says.
      (Command_Run_Errors_Into, Named ("run_errors_into"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Errors_Into_Doc, M.Msg_Command_Hint, Available),

      --  The same three forms the output side has. A log of what went wrong is
      --  the thing a script most often wants to add to rather than replace,
      --  and a file that must not already exist is how a script keeps two runs
      --  from writing over each other -- neither is less useful for being
      --  about the error stream, and a shell offering three forms for one
      --  stream and one for the other would have to explain why.
      (Command_Run_Errors_Append, Named ("run_errors_append"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Errors_Append_Doc, M.Msg_Command_Hint, Available),

      (Command_Run_Errors_New, Named ("run_errors_new"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_Errors_New_Doc, M.Msg_Command_Hint, Available),

      --  Both streams, one file, in the order the program wrote them.
      --
      --  What a build log is: a script that put output in a file and
      --  complaints in another could not tell which line came before which,
      --  and one that pointed both at the same name got two file positions
      --  writing over each other. One open file, and the error stream a copy
      --  of the descriptor rather than a second open, is the only arrangement
      --  in which the order survives.
      (Command_Run_All_Into, Named ("run_all_into"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_All_Into_Doc, M.Msg_Command_Hint, Available),

      (Command_Run_All_Append, Named ("run_all_append"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_All_Append_Doc, M.Msg_Command_Hint, Available),

      (Command_Run_All_New, Named ("run_all_new"), 2, Any_Number,
       [1 => Text ("File"), others => Text ("Argument")],
       Changes_State,
       M.Msg_Command_Run_All_New_Doc, M.Msg_Command_Hint, Available),

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

      --  A pipeline's streams, put where a single program's can be put.
      --
      --  Nine names rather than a flag, because they are the nine that already
      --  exist for one program and a reader who has learned those has learned
      --  these. The file comes first for the same reason it does there: the
      --  arguments after a program name belong to the program.
      --
      --  The last stage is the one redirected. The others are attached to the
      --  stage after them, and redirecting one of those would cut the pipeline
      --  in half.
      --  A pipeline into the background, as `start` puts one program there.
      --
      --  Without it a script that built a pipeline had to wait for it, which
      --  is the one direction the rest of this family left open: a pipeline
      --  could be given files to read and write and could not be left running
      --  while the script got on with something else.
      (Command_Pipe_Start, Named ("pipe_start"), 0, 0, No_Parameters,
       Changes_State,
       M.Msg_Command_Pipe_Start_Doc, M.Msg_Command_Hint, Available),

      --  Where the pipeline reads from, said while it is being built rather
      --  than when it runs.
      --
      --  Unlike the others in this family this one does not run anything: a
      --  pipeline that took its input from a file and put its output in
      --  another would otherwise be two commands each insisting on running,
      --  and only one of them could. So this records, and whichever of the
      --  running forms follows does the work.
      (Command_Pipe_From, Named ("pipe_from"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_From_Doc, M.Msg_Command_Hint, Available),

      --  The same, with the text this script computed rather than a file it
      --  has. `printf '%s' "$x" | tool | other` written here.
      --
      --  What `run_from_text` is for one program, this is for a pipeline --
      --  and with `Output_Of_Pipe` after it, for a pipeline whose answer the
      --  script wants back. Those three were the last of the shape: a script
      --  could compute a value and hand it to one program, and had to go
      --  through a file of its own making to hand it to two.
      (Command_Pipe_From_Text, Named ("pipe_from_text"), 1, 1,
       [1 => Text ("Input"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_From_Text_Doc, M.Msg_Command_Hint, Available),

      (Command_Pipe_Into, Named ("pipe_into"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_Into_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_Append, Named ("pipe_append"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_Append_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_New, Named ("pipe_new"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_New_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_Errors_Into, Named ("pipe_errors_into"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_Errors_Into_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_Errors_Append, Named ("pipe_errors_append"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_Errors_Append_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_Errors_New, Named ("pipe_errors_new"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_Errors_New_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_All_Into, Named ("pipe_all_into"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_All_Into_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_All_Append, Named ("pipe_all_append"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_All_Append_Doc, M.Msg_Command_Hint, Available),
      (Command_Pipe_All_New, Named ("pipe_all_new"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Pipe_All_New_Doc, M.Msg_Command_Hint, Available),

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

      --  The other half of suspending, which every other shell calls `fg`.
      --
      --  Named for what it does rather than for what it is short for: this
      --  language spells things out, and `foreground (1)` says where the job
      --  goes in a way `fg 1` never did. It resumes the job *and waits* for
      --  it, because those are one act from where a user stands -- the point
      --  of bringing something back is to be in front of it again.
      (Command_Foreground, Named ("foreground"), 1, 1,
       [1 => Whole ("Job"), others => Nothing],
       Changes_State,
       M.Msg_Command_Foreground_Doc, M.Msg_Command_Hint, Available),
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

      --  Taking things away, which was left to programs until the shell ran
      --  where those programs are not.
      --
      --  Commands rather than functions, like the ones that make things: a
      --  removal has consequences and belongs where a reader sees it happen.
      --  Removing a directory takes only an empty one -- see the note in
      --  Adash.Filesystem for why there is no recursive form and what a script
      --  that means it writes instead.
      (Command_Remove_File, Named ("remove_file"), 1, 1,
       [1 => Text ("File"), others => Nothing],
       Changes_State,
       M.Msg_Command_Remove_File_Doc, M.Msg_Command_Hint, Available),

      (Command_Remove_Directory, Named ("remove_directory"), 1, 1,
       [1 => Text ("Directory"), others => Nothing],
       Changes_State,
       M.Msg_Command_Remove_Directory_Doc, M.Msg_Command_Hint, Available),

      --  The old name first and the new one second, which is the order both
      --  `mv` and Ada's own Rename use, and the order a sentence has.
      (Command_Rename, Named ("rename"), 2, 2,
       [1 => Text ("From"), 2 => Text ("To"), others => Nothing],
       Changes_State,
       M.Msg_Command_Rename_Doc, M.Msg_Command_Hint, Available),

      (Command_Copy_File, Named ("copy_file"), 2, 2,
       [1 => Text ("From"), 2 => Text ("To"), others => Nothing],
       Changes_State,
       M.Msg_Command_Copy_File_Doc, M.Msg_Command_Hint, Available),

      --  What to run on the way out, which is `trap` under a name that says
      --  what it does.
      --
      --  The argument is the name of a subprogram this session declared. Held
      --  as text and resolved when it runs: a script that registers cleanup at
      --  the top and declares it below is written in an order nobody should
      --  have to defend.
      (Command_On_Exit, Named ("on_exit"), 1, 1,
       [1 => Text ("Subprogram"), others => Nothing],
       Changes_State,
       M.Msg_Command_On_Exit_Doc, M.Msg_Command_Hint, Available),
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

with Ada.Containers.Vectors;

with Adash.Commands;
with Adash.Errors;
with Adash.Language.Symbols;

--  Ready before this body is, because this body builds its table during its
--  own elaboration: the commands it names and the symbols it makes them into
--  have to be there first. Said rather than left to the binder to work out, so
--  that a change here fails to build instead of failing at start-up on
--  somebody else's machine. Scopes comes in through the specification, which is
--  elaborated before this body by the language rules.
pragma Elaborate_All (Adash.Commands);
pragma Elaborate_All (Adash.Language.Symbols);

package body Adash.Predefined is

   package Symbols renames Adash.Language.Symbols;
   package M renames Adash.Messages;

   function Named (Text : String) return M.Argument
   is (M.Named ("name", Text));

   No_Parameters : constant Parameter_List :=
     [others => (Name => Named (""), Of_Type => Types.Type_None)];

   --  A parameter that accepts any type, which the output procedures take:
   --  they image whatever they are given.
   function Any (Text : String) return Parameter
   is ((Name => Named (Text), Of_Type => Types.Type_None));

   --  The registry.
   --
   --  Read in one direction to install names and in another to answer
   --  questions; nothing depends on the order, so this table may be reordered
   --  for readability without changing behaviour. A test asserts that.
   Registry : constant array (Positive range <>) of Metadata :=
     [
      --  Types.
      (Id => Entity_Boolean, Name => Named ("Boolean"), Sort => Sort_Type,
       Of_Type => Types.Type_Boolean, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      (Id => Entity_Integer, Name => Named ("Integer"), Sort => Sort_Type,
       Of_Type => Types.Type_Integer, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      (Id => Entity_Float, Name => Named ("Float"), Sort => Sort_Type,
       Of_Type => Types.Type_Float, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      (Id => Entity_Character, Name => Named ("Character"), Sort => Sort_Type,
       Of_Type => Types.Type_Character, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      --  The seconds on the clock, from the session's own monotonic one: a
      --  program that measures an interval measures one whatever somebody does
      --  to the system time.
      (Id => Entity_Clock, Name => Named ("Clock"), Sort => Sort_Function,
       Of_Type => Types.Type_Float, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Clock_Doc,
       Description => M.Msg_Predefined_Clock_Hint, Status => Available),

      --  What `A'Identity` yields: which task, as something a program can
      --  hold. A task object cannot be copied, so an identity needs a type of
      --  its own to be kept in.
      (Id => Entity_Task_Id, Name => Named ("Task_Id"), Sort => Sort_Type,
       Of_Type => Types.Type_Task_Id, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      (Id => Entity_String, Name => Named ("String"), Sort => Sort_Type,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_Type_Doc,
       Description => M.Msg_Predefined_Type_Hint, Status => Available),

      --  The Boolean literals. Constants rather than keywords, which is why a
      --  program may not redeclare them in the outermost scope and may hide
      --  them in an inner one -- exactly as Ada has it.
      (Id => Entity_True, Name => Named ("True"), Sort => Sort_Constant,
       Of_Type => Types.Type_Boolean, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_True_Doc,
       Description => M.Msg_Predefined_Constant_Hint, Status => Available),

      (Id => Entity_False, Name => Named ("False"), Sort => Sort_Constant,
       Of_Type => Types.Type_Boolean, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => M.Msg_Predefined_False_Doc,
       Description => M.Msg_Predefined_Constant_Hint, Status => Available),

      --  Output. Side-effecting, and marked so: an expression a completer may
      --  evaluate speculatively must not be one that writes to the terminal.
      (Id => Entity_Put_Line, Name => Named ("Put_Line"), Sort => Sort_Procedure,
       Of_Type => Types.Type_None, Parameter_Count => 1,
       Parameters => [1 => Any ("Item"), others => Any ("")],
       Optional_Parameters => 0, Has_Side_Effects => True,
       Documentation => M.Msg_Predefined_Put_Line_Doc,
       Description => M.Msg_Predefined_Put_Line_Hint, Status => Available),

      (Id => Entity_Env_Value, Name => Named ("Env_Value"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Name"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Env_Value_Doc,
       Description => Adash.Messages.Msg_Predefined_Env_Value_Hint,
       Status => Available),
      (Id => Entity_Status, Name => Named ("Status"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Integer, Parameter_Count => 0,
       Parameters => No_Parameters,

       --  Reading it changes nothing, so a completer may evaluate it -- but
       --  what it answers changes as the session runs commands, which is a
       --  different property and not one this field is about.
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Status_Doc,
       Description => Adash.Messages.Msg_Predefined_Status_Hint,
       Status => Available),

      (Id => Entity_Argument_Count, Name => Named ("Argument_Count"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Integer, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Argument_Count_Doc,
       Description => Adash.Messages.Msg_Predefined_Argument_Count_Hint,
       Status => Available),

      (Id => Entity_Argument, Name => Named ("Argument"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Position"), Types.Type_Integer),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Argument_Doc,
       Description => Adash.Messages.Msg_Predefined_Argument_Hint,
       Status => Available),

      (Id => Entity_Output_Of, Name => Named ("Output_Of"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 4,
       Parameters => [1 => (Named ("Program"), Types.Type_String),
                      2 => (Named ("Argument_1"), Types.Type_String),
                      3 => (Named ("Argument_2"), Types.Type_String),
                      4 => (Named ("Argument_3"), Types.Type_String)],
       Optional_Parameters => 3,

       --  It runs a program. Nothing else here does, and a completer that
       --  evaluated it to show the user what it would say would be running
       --  whatever they had typed so far.
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_Output_Of_Doc,
       Description => Adash.Messages.Msg_Predefined_Output_Of_Hint,
       Status => Available),

      --  The same shape as Output_Of, and deliberately a separate function
      --  rather than a flag on that one: what a program says and what it
      --  complains about are two streams because they are two things, and a
      --  script that wanted both would want them apart.
      (Id => Entity_Error_Of, Name => Named ("Error_Of"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 4,
       Parameters => [1 => (Named ("Program"), Types.Type_String),
                      2 => (Named ("Argument_1"), Types.Type_String),
                      3 => (Named ("Argument_2"), Types.Type_String),
                      4 => (Named ("Argument_3"), Types.Type_String)],
       Optional_Parameters => 3,
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_Error_Of_Doc,
       Description => Adash.Messages.Msg_Predefined_Error_Of_Hint,
       Status => Available),

      --  Everything a program wrote, in the order it wrote it. The reading
      --  half of what run_all_into does for a file.
      (Id => Entity_All_Of, Name => Named ("All_Of"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 4,
       Parameters => [1 => (Named ("Program"), Types.Type_String),
                      2 => (Named ("Argument_1"), Types.Type_String),
                      3 => (Named ("Argument_2"), Types.Type_String),
                      4 => (Named ("Argument_3"), Types.Type_String)],
       Optional_Parameters => 3,
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_All_Of_Doc,
       Description => Adash.Messages.Msg_Predefined_All_Of_Hint,
       Status => Available),

      --  Which job the shell last started.
      --
      --  A question rather than a statement, and one whose answer moves as a
      --  session runs things -- which is Status's property too, and no more a
      --  side effect here than it is there.
      (Id => Entity_Last_Job, Name => Named ("Last_Job"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Integer, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Last_Job_Doc,
       Description => Adash.Messages.Msg_Predefined_Last_Job_Hint,
       Status => Available),

      --  The reading half of the pipe_* family: the pipeline a script has
      --  built, run for what it wrote rather than for where it wrote it.
      --
      --  No parameters, because the pipeline is already built -- `pipe` said
      --  what it is, one stage at a time, and these are the question asked of
      --  it. Which is also why they empty it: a pipeline that answered twice
      --  would run twice, and the second answer would be a surprise.
      (Id => Entity_Output_Of_Pipe, Name => Named ("Output_Of_Pipe"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0,
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_Output_Of_Pipe_Doc,
       Description => Adash.Messages.Msg_Predefined_Output_Of_Pipe_Hint,
       Status => Available),

      (Id => Entity_Error_Of_Pipe, Name => Named ("Error_Of_Pipe"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0,
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_Error_Of_Pipe_Doc,
       Description => Adash.Messages.Msg_Predefined_Error_Of_Pipe_Hint,
       Status => Available),

      (Id => Entity_All_Of_Pipe, Name => Named ("All_Of_Pipe"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0,
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_All_Of_Pipe_Doc,
       Description => Adash.Messages.Msg_Predefined_All_Of_Pipe_Hint,
       Status => Available),

      (Id => Entity_Read_Line, Name => Named ("Read_Line"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters, Optional_Parameters => 0,

       --  Reading consumes: the same call twice gives two different lines,
       --  and a completer that evaluated it would eat the user's input.
       Has_Side_Effects => True,
       Documentation => Adash.Messages.Msg_Predefined_Read_Line_Doc,
       Description => Adash.Messages.Msg_Predefined_Read_Line_Hint,
       Status => Available),

      (Id => Entity_Input_Ended, Name => Named ("Input_Ended"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 0,
       Parameters => No_Parameters, Optional_Parameters => 0,
       Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Input_Ended_Doc,
       Description => Adash.Messages.Msg_Predefined_Input_Ended_Hint,
       Status => Available),

      (Id => Entity_Exists, Name => Named ("Exists"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 1,
       Parameters => [1 => (Named ("Path"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0,

       --  Asking changes nothing, and asking twice answers twice: the
       --  filesystem is not this shell's to hold still.
       Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Exists_Doc,
       Description => Adash.Messages.Msg_Predefined_Exists_Hint,
       Status => Available),

      (Id => Entity_Is_Directory, Name => Named ("Is_Directory"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 1,
       Parameters => [1 => (Named ("Path"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0,

       --  Asking changes nothing, and asking twice answers twice: the
       --  filesystem is not this shell's to hold still.
       Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Is_Directory_Doc,
       Description => Adash.Messages.Msg_Predefined_Is_Directory_Hint,
       Status => Available),

      (Id => Entity_Is_Executable, Name => Named ("Is_Executable"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 1,
       Parameters => [1 => (Named ("Path"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0,

       --  Asking changes nothing, and asking twice answers twice: the
       --  filesystem is not this shell's to hold still.
       Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Is_Executable_Doc,
       Description => Adash.Messages.Msg_Predefined_Is_Executable_Hint,
       Status => Available),

      (Id => Entity_Read_File, Name => Named ("Read_File"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Path"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0,

       --  Reading changes nothing. A file that is not there reads as nothing,
       --  which is what a script appending to a log wants on its first turn --
       --  and what it would have got from `cat` on a host that has one.
       Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Read_File_Doc,
       Description => Adash.Messages.Msg_Predefined_Read_File_Hint,
       Status => Available),

      (Id => Entity_Current_Directory, Name => Named ("Current_Directory"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 0,
       Parameters => No_Parameters,

       --  A question, and one whose answer `cd` moves. Like Status, that it
       --  changes as the session runs is a different property from having
       --  consequences, and this field is about consequences.
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Current_Directory_Doc,
       Description => Adash.Messages.Msg_Predefined_Current_Directory_Hint,
       Status => Available),

      --  What is in a directory, which nothing here could see before.
      --
      --  Two functions rather than one that answers with a list: a String and
      --  an Integer are what this language's values are, and a loop from 1 to
      --  the count reads as what it is. They answer from one reading of the
      --  directory, so the loop sees a place that is not changing under it.
      (Id => Entity_File_Count, Name => Named ("File_Count"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Integer, Parameter_Count => 1,
       Parameters => [1 => (Named ("Directory"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_File_Count_Doc,
       Description => Adash.Messages.Msg_Predefined_File_Count_Hint,
       Status => Available),

      (Id => Entity_File_At, Name => Named ("File_At"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 2,
       Parameters => [1 => (Named ("Directory"), Types.Type_String),
                      2 => (Named ("Position"), Types.Type_Integer),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_File_At_Doc,
       Description => Adash.Messages.Msg_Predefined_File_At_Hint,
       Status => Available),

      --  Where a program is, which is what `which` answers elsewhere.
      --
      --  `Is_Executable` needs a path, so a script could ask about a program it
      --  already knew the location of and could not ask about one on the
      --  search path -- which is every program a user actually names. The
      --  answer is the host's own resolution rather than a split of PATH by
      --  this shell: on Windows a name matches with any of the PATHEXT
      --  suffixes, and `git` there is `git.exe`.
      (Id => Entity_Program_Path, Name => Named ("Program_Path"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Program"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Program_Path_Doc,
       Description => Adash.Messages.Msg_Predefined_Program_Path_Hint,
       Status => Available),

      (Id => Entity_Index, Name => Named ("Index"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Integer, Parameter_Count => 2,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      2 => (Named ("Piece"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Index_Doc,
       Description => Adash.Messages.Msg_Predefined_Index_Hint,
       Status => Available),

      (Id => Entity_Trim, Name => Named ("Trim"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Trim_Doc,
       Description => Adash.Messages.Msg_Predefined_Trim_Hint,
       Status => Available),

      (Id => Entity_To_Upper, Name => Named ("To_Upper"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_To_Upper_Doc,
       Description => Adash.Messages.Msg_Predefined_To_Upper_Hint,
       Status => Available),

      (Id => Entity_To_Lower, Name => Named ("To_Lower"),
       Sort => Sort_Function,
       Of_Type => Types.Type_String, Parameter_Count => 1,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_To_Lower_Doc,
       Description => Adash.Messages.Msg_Predefined_To_Lower_Hint,
       Status => Available),

      (Id => Entity_Starts_With, Name => Named ("Starts_With"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 2,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      2 => (Named ("Piece"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Starts_With_Doc,
       Description => Adash.Messages.Msg_Predefined_Starts_With_Hint,
       Status => Available),

      (Id => Entity_Ends_With, Name => Named ("Ends_With"),
       Sort => Sort_Function,
       Of_Type => Types.Type_Boolean, Parameter_Count => 2,
       Parameters => [1 => (Named ("Whole"), Types.Type_String),
                      2 => (Named ("Piece"), Types.Type_String),
                      others => (Named (""), Types.Type_None)],
       Optional_Parameters => 0, Has_Side_Effects => False,
       Documentation => Adash.Messages.Msg_Predefined_Ends_With_Doc,
       Description => Adash.Messages.Msg_Predefined_Ends_With_Hint,
       Status => Available),

      (Id => Entity_Put, Name => Named ("Put"), Sort => Sort_Procedure,
       Of_Type => Types.Type_None, Parameter_Count => 1,
       Parameters => [1 => Any ("Item"), others => Any ("")],
       Optional_Parameters => 0, Has_Side_Effects => True,
       Documentation => M.Msg_Predefined_Put_Doc,
       Description => M.Msg_Predefined_Put_Hint, Status => Available),

      (Id => Entity_New_Line, Name => Named ("New_Line"), Sort => Sort_Procedure,
       Of_Type => Types.Type_None, Parameter_Count => 0,
       Parameters => No_Parameters,
       Optional_Parameters => 0, Has_Side_Effects => True,
       Documentation => M.Msg_Predefined_New_Line_Doc,
       Description => M.Msg_Predefined_New_Line_Hint, Status => Available)];

   ----------------
   -- Profile_Of --
   ----------------

   --  What the machine raises, and nothing else. Four of Ada's own, plus the
   --  one Ada.Strings defines for an index outside a string -- which is what
   --  taking a String apart by a position it does not have is.
   --
   --  This list is the one a handler may name, so it has to be exactly what
   --  the machine raises: a name missing from it is an exception a program
   --  can be given and cannot catch, which is worse than one it can name and
   --  never sees.
   Exceptions : constant array (1 .. 5) of access constant String :=
     [1 => new String'("Constraint_Error"),
      2 => new String'("Program_Error"),
      3 => new String'("Storage_Error"),
      4 => new String'("Tasking_Error"),
      5 => new String'("Index_Error")];

   -------------------
   -- Is_Exception --
   -------------------

   function Is_Exception (Name : String) return Boolean is
   begin
      for Item of Exceptions loop
         if Adash.Language.Symbols.Fold (Item.all)
           = Adash.Language.Symbols.Fold (Name)
         then
            return True;
         end if;
      end loop;

      return False;
   end Is_Exception;

   --------------------
   -- Exception_At --
   --------------------

   function Exception_At (Index : Positive) return String is
   begin
      if Index > Exceptions'Last then
         return "";
      end if;

      return Exceptions (Index).all;
   end Exception_At;

   function Profile_Of (Name : String) return Profile is
      Which   : Entity_Id;
      Command : Adash.Commands.Command_Id;
   begin
      --  The language's own subprograms first. A command may not take a name
      --  the language already uses -- a test asserts it -- so the order only
      --  decides which lookup runs first, not which answer wins.
      if Find (Name, Which) then
         declare
            About : constant Metadata := Describe (Which);
         begin
            return (Known    => True,
                    Minimum  =>
                      About.Parameter_Count - About.Optional_Parameters,
                    Maximum  => About.Parameter_Count,
                    Types_Of => About.Parameters);
         end;
      end if;

      if Adash.Commands.Find (Name, Command) then
         declare
            About : constant Adash.Commands.Metadata :=
              Adash.Commands.Describe (Command);
            Result : Profile;
         begin
            Result.Known := True;
            Result.Minimum := About.Minimum_Arguments;
            Result.Maximum := About.Maximum_Arguments;

            --  Commands carry fewer positions than predefined subprograms may,
            --  so the rest of the list is left accepting anything. Nothing
            --  reads past Maximum, and leaving it undefined would be one more
            --  thing to be careful about.
            for Index in 1 .. Natural'Min
              (Adash.Commands.Max_Parameters, Max_Parameters)
            loop
               Result.Types_Of (Index) :=
                 (Name    => About.Parameters (Index).Name,
                  Of_Type => About.Parameters (Index).Of_Type);
            end loop;

            return Result;
         end;
      end if;

      return (Known => False, others => <>);
   end Profile_Of;

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

   function Describe (Id : Entity_Id) return Metadata is
   begin
      for Current of Registry loop
         if Current.Id = Id then
            return Current;
         end if;
      end loop;

      --  Unreachable while every literal has an entry, and the test that
      --  asserts exactly that is what makes this line dead rather than
      --  load-bearing.
      return Registry (Registry'First);
   end Describe;

   ----------
   -- Find --
   ----------

   function Find (Name : String; Id : out Entity_Id) return Boolean is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      Id := Entity_Boolean;

      for Current of Registry loop
         if Symbols.Fold (M.Value (Current.Name)) = Wanted then
            Id := Current.Id;
            return True;
         end if;
      end loop;

      return False;
   end Find;

   -------------
   -- Install --
   -------------

   --  The symbols this table becomes, built once.
   --
   --  Installing used to make eighty-seven symbols and declare each of them,
   --  and declaring asks whether the name is already there -- a scan of what
   --  has been declared so far, for each of the eighty-seven, on every
   --  analysis. That was most of what analysing a one-line submission cost:
   --  1.6 milliseconds, of which about 1.3 was fixed and none of it depended
   --  on the program.
   --
   --  The answers cannot change between one submission and the next, so they
   --  are worked out once. The check that two entities do not share a name is
   --  kept exactly as it was -- it runs here, against a chain of this
   --  package's own, and a table defect is still reported as a failure to
   --  install rather than as a diagnostic about somebody's program.
   package Symbol_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Symbols.Symbol,
      "=" => Symbols."=");

   --  Built while this package is elaborated, not on first use.
   --
   --  Lazily was the obvious way and it carried an assumption nobody had
   --  written down: that no two things analyse at once. That is true of the
   --  engine today -- a submission is analysed before it runs, and what runs
   --  is what has tasks -- but it is a property of a caller, held in a
   --  package that cannot see its callers, and two of them arriving together
   --  would each build the same vector into the same vector.
   --
   --  Elaboration has no such question in it. The table is a constant, the
   --  commands are a constant, and the answer is the same for the life of the
   --  process; Elaborate_All below says which packages have to be ready
   --  first.
   Sound : Boolean := False;

   function Prepare return Symbol_Lists.Vector;

   function Prepare return Symbol_Lists.Vector is
      Trial    : Adash.Language.Scopes.Chain;
      Error    : Adash.Errors.Error_Info;
      Building : Symbol_Lists.Vector;
   begin
      for Current of Registry loop
         declare
            Kind : constant Symbols.Symbol_Kind :=
              (case Current.Sort is
                  when Sort_Type      => Symbols.Symbol_Type,
                  when Sort_Constant  => Symbols.Symbol_Constant,
                  when Sort_Function  => Symbols.Symbol_Function,
                  when Sort_Procedure => Symbols.Symbol_Procedure);

            Made : constant Symbols.Symbol :=
              Symbols.Make (M.Value (Current.Name), Kind, Current.Of_Type,
                            Provided => True);
         begin
            if not Trial.Declare_Symbol (Made, Error) then
               --  A defect in the table above rather than in anybody's
               --  program. Reported through Install, which is where a caller
               --  is listening; what comes back from here is what was built
               --  before the clash, and Sound says not to use it.
               return Building;
            end if;

            Building.Append (Made);
         end;
      end loop;

      for Index in 1 .. Adash.Commands.Count loop
         declare
            About : constant Adash.Commands.Metadata :=
              Adash.Commands.Entry_At (Index);

            Made : constant Symbols.Symbol :=
              Symbols.Make (M.Value (About.Name), Symbols.Symbol_Procedure,
                            Types.Type_None, Provided => True);
         begin
            if not Trial.Declare_Symbol (Made, Error) then
               return Building;
            end if;

            Building.Append (Made);
         end;
      end loop;

      Sound := True;
      return Building;
   end Prepare;

   Prepared : constant Symbol_Lists.Vector := Prepare;

   function Install (Into : in out Adash.Language.Scopes.Chain) return Boolean is
      Error : Adash.Errors.Error_Info;
      pragma Unreferenced (Error);
   begin
      if not Sound then
         return False;
      end if;

      for Current of Prepared loop
         Into.Adopt (Current);
      end loop;

      return True;

   end Install;

end Adash.Predefined;

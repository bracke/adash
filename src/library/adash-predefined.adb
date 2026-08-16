with Adash.Commands;
with Adash.Errors;
with Adash.Language.Symbols;

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

   function Install (Into : in out Adash.Language.Scopes.Chain) return Boolean is
      Error : Adash.Errors.Error_Info;
   begin
      for Current of Registry loop
         declare
            Kind : constant Symbols.Symbol_Kind :=
              (case Current.Sort is
                  when Sort_Type      => Symbols.Symbol_Type,
                  when Sort_Constant  => Symbols.Symbol_Constant,
                  when Sort_Function  => Symbols.Symbol_Function,
                  when Sort_Procedure => Symbols.Symbol_Procedure);
         begin
            if not Into.Declare_Symbol
              (Symbols.Make (M.Value (Current.Name), Kind, Current.Of_Type,
                             Provided => True),
               Error)
            then
               --  Two entities share a name. That is a defect in the table
               --  above, not in whatever program is being analysed, so it is
               --  reported to the caller as a failure of installation rather
               --  than as a diagnostic about the source.
               return False;
            end if;
         end;
      end loop;

      --  The shell's internal commands, declared alongside the language's own
      --  subprograms rather than handled separately.
      --
      --  Before this they were invisible to the analyser: `quit` inside an
      --  `if` was reported as an undeclared name, which told the user they had
      --  made a typo when what had actually happened is that Adash cannot lower
      --  the call yet. A name the shell obviously knows should never be
      --  reported as unknown.
      for Index in 1 .. Adash.Commands.Count loop
         declare
            About : constant Adash.Commands.Metadata :=
              Adash.Commands.Entry_At (Index);
         begin
            if not Into.Declare_Symbol
              (Symbols.Make (M.Value (About.Name), Symbols.Symbol_Procedure,
                             Types.Type_None, Provided => True),
               Error)
            then
               --  A command shares a name with a predefined subprogram. Like
               --  the collision above, that is a defect in one of the two
               --  tables rather than in the program being analysed.
               return False;
            end if;
         end;
      end loop;

      return True;
   end Install;

end Adash.Predefined;

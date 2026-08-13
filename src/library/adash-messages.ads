--  Visible rather than private: Placeholder_Names is part of the public
--  contract, so the unit that defines its component type has to be too.
with Ada.Strings.Unbounded;

--  Stable message identifiers and their structured arguments.
--
--  This package is the vocabulary, not the text. Every user-visible string
--  Adash can produce is named here by an identifier that never changes, and
--  the words behind that identifier live in a message catalog that a
--  translator can edit and a checker can validate. Nothing below the
--  presentation boundary formats a sentence; subsystems report an identifier
--  and typed arguments, and Adash.Messages.Rendering turns the pair into
--  text, once, at the edge.
--
--  The reason is not only translation. A diagnostic that is assembled as a
--  string at the point it is detected cannot be tested for identity, cannot
--  be given a stable code in a conformance case, and cannot be re-rendered
--  for a different destination -- a terminal, a log, a structured report --
--  without being parsed back apart. An identifier plus arguments survives all
--  three.
--
--  Adding a message: add an enumeration literal, give it a key in Key, and
--  add that key to resources/messages/catalog.txt for every locale the
--  catalog carries. The Key case statement has no `others`, so an identifier
--  added without a key fails to compile rather than rendering as itself at
--  run time. Adash_Tests.Repository checks the other direction -- that every
--  key exists in the catalog.
package Adash.Messages is

   --  Every message Adash can address to a user.
   --
   --  Literals are grouped by the subsystem that raises them, and the
   --  grouping is a comment rather than a type: a message raised by two
   --  subsystems is still one message, and splitting the type would make it
   --  two.
   type Message_Id is
     (
      --  Product identity.
      Msg_Application_Name,
      Msg_Application_Summary,

      --  Version reporting.
      Msg_Version_Line,
      Msg_Version_Build,
      Msg_Version_Prerelease_Notice,

      --  Command-line usage.
      Msg_Usage,
      Msg_Usage_Options_Header,
      Msg_Usage_Option_Help,
      Msg_Usage_Option_Version,
      Msg_Usage_More,
      Msg_Usage_Script,

      --  Startup and command-line handling.
      Msg_Unknown_Option,
      Msg_Catalog_Unavailable,

      --  Operational failures. One per Adash.Errors.Error_Code; the mapping
      --  between the two lives in Adash.Errors.Message.
      Msg_Error_None,
      Msg_Command_Not_Found,
      Msg_Command_Not_Executable,
      Msg_Command_Denied,
      Msg_Command_Start_Failed,
      Msg_Redirection_Open_Failed,
      Msg_Redirection_Conflict,
      Msg_Pipe_Creation_Failed,
      Msg_Stream_Write_Failed,
      Msg_Stream_Read_Failed,
      Msg_File_Not_Writable,

      --  What the machine says when a program raises, or when the machine
      --  itself cannot go on. These are the detail beside an exception name,
      --  and they are messages rather than strings for the same reason
      --  everything else here is: a user reads them.
      Msg_Machine_Stack_Full,
      Msg_Machine_Stack_Empty,
      Msg_Machine_No_Place,
      Msg_Machine_No_Caller,
      Msg_Machine_Above_Ceiling,
      Msg_Machine_Blocking_In_Protected,
      Msg_Machine_Too_Many_Allowed,
      Msg_Machine_Queue_Too_Long,
      Msg_Machine_Too_Many_Alternatives,
      Msg_Machine_Task_Ran_Out,
      Msg_Machine_No_Store_Place,
      Msg_Machine_Swap_Empty,
      Msg_Machine_Not_A_Number,
      Msg_Machine_Arithmetic,
      Msg_Machine_Too_Many_Calls,
      Msg_Machine_No_Frame_Room,
      Msg_Machine_No_Return_To,
      Msg_Machine_No_Shell,
      Msg_Machine_Index_Outside,
      Msg_Machine_Slice_Outside,
      Msg_Machine_Slice_Lengths,
      Msg_Machine_Bad_Value_Text,
      Msg_Machine_Too_Many_Handlers,
      Msg_Machine_No_Return_Value,
      Msg_Machine_Not_A_Raise,
      Msg_Machine_Position_Outside,
      Msg_Machine_Outside_Bounds,
      Msg_Machine_Outside_Array,
      Msg_Machine_Too_Many_Tasks,
      Msg_Machine_Tasks_Stuck,
      Msg_Machine_Task_Finished,

      --  What the parser was looking for, when what it was looking for is a
      --  kind of thing rather than a token. A token's spelling is Ada's own
      --  and goes in as an argument; `an expression` is prose and a user
      --  reads it, so it comes from here like everything else they read.
      Msg_Expected_Expression,
      Msg_Expected_Statement,
      Msg_Expected_Type_Name,
      Msg_Expected_Literal_Name,
      Msg_Expected_Component_Name,
      Msg_Expected_Package_Name,
      Msg_Expected_Task_Name,
      Msg_Subtype_Not_Discrete,
      Msg_Subtype_Bound_Not_Static,
      Msg_Subtype_Range_Is_Empty,
      Msg_Part_Not_Simple,
      Msg_Part_Given_Twice,
      Msg_Record_Is_Empty,
      Msg_Array_Bound_Not_Static,
      Msg_Array_Is_Empty,
      Msg_Array_Too_Long,
      Msg_Not_A_Record,
      Msg_No_Such_Component,
      Msg_Not_An_Array,
      Msg_Aggregate_Wrong_Count,
      Msg_Aggregate_Not_Expected,
      Msg_Result_Not_Simple,
      Msg_Cannot_Write,
      Msg_Not_A_Package,
      Msg_Package_Not_Declared,
      Msg_Not_A_Generic,
      Msg_Generic_Wrong_Actuals,
      Msg_Generic_Not_Callable,
      Msg_Not_A_Task,
      Msg_Not_An_Entry,
      Msg_Accept_Differs,
      Msg_Protected_Entry_Parameters,
      Msg_Entry_Parameter_Not_Simple,
      Msg_Select_Alternative,
      Msg_Select_Trigger,
      Msg_Select_Waits_Twice,
      Msg_Discriminants_Need_A_Type,
      Msg_Discriminants_Wrong_Count,
      Msg_Nothing_To_Constrain,
      Msg_Count_Outside_Its_Unit,
      Msg_Is_A_Type,
      Msg_Requeue_Not_An_Entry,
      Msg_Requeue_Takes_Nothing,
      Msg_Family_Index_Not_Discrete,
      Msg_Family_Takes_Nothing,
      Msg_Not_A_Family,
      Msg_Family_Needs_A_Member,
      Msg_Cannot_Be_Copied,
      Msg_Identity_Needs_A_Task,
      Msg_Unknown_Pragma,
      Msg_Unknown_Restriction,
      Msg_Unknown_Policy,
      Msg_Unknown_Profile,
      Msg_Dispatching_Twice,
      Msg_Queuing_Twice,
      Msg_Terminate_Outside_Select,
      Msg_Ambiguous_Literal,
      Msg_Raise_Outside_A_Handler,
      Msg_Aggregate_Others_Covers_Nothing,
      Msg_Empty_Priority_Range,
      Msg_Restriction_Broken,
      Msg_Priority_Not_Static,
      Msg_Expected_Parameter_Name,
      Msg_Expected_Loop_Variable,
      Msg_Expected_Subprogram_Name,
      Msg_Expected_Exception_Name,
      Msg_Expected_Attribute_Name,
      Msg_Expected_Interpolation_Rest,
      Msg_Expected_End_Of_Input,

      --  What the lowering could not emit, and what a setting wanted. Both
      --  are quoted into a message rather than rendered where they are
      --  decided: the lowering and the command layer are below the
      --  presentation boundary and a user reads every one of these.
      Msg_Lower_Call_Wrong_Count,
      Msg_Lower_Write_Back_Not_Variable,
      Msg_Lower_Float_Literal,
      Msg_Lower_Unresolved_Name,
      Msg_Lower_Variable_Of_Type,
      Msg_Lower_Call_To,
      Msg_Lower_This_Operator,
      Msg_Lower_Arithmetic_On,
      Msg_Lower_Float_Operation,
      Msg_Lower_Joining_Letters,
      Msg_Lower_String_Operation,
      Msg_Lower_String_Concatenation,
      Msg_Lower_Value_Of,
      Msg_Lower_Image_Of,
      Msg_Lower_Procedure_As_Value,
      Msg_Lower_This_Expression,
      Msg_Lower_Call_In_Context,
      Msg_Lower_Command_Arguments,
      Msg_Lower_Argument_Of_Type,
      Msg_Lower_Declaration_Unresolved,
      Msg_Lower_String_No_Value,
      Msg_Lower_Assignment_Unresolved,
      Msg_Lower_Case_Choice,
      Msg_Lower_Exit_Outside_Loop,
      Msg_Lower_Return_With_Value,
      Msg_Lower_This_Statement,
      Msg_Lower_Writing_Type,
      Msg_Config_Wants_Truth,
      Msg_Config_Wants_Whole,
      Msg_Config_Wants_Range,
      Msg_Config_Wants_Choice,
      Msg_File_Write_Failed,
      Msg_Job_Unknown,
      Msg_Job_Is_Suspended,
      Msg_Execution_Cancelled,
      Msg_Capability_Unavailable,
      Msg_Directory_Not_Found,
      Msg_Directory_Denied,
      Msg_Source_Unreadable,
      Msg_Module_Not_Found,
      Msg_Module_Looked_As_Written,
      Msg_Module_Looked_Beside,
      Msg_Module_Looked_In_Modules,
      Msg_Source_Invalid_Encoding,
      Msg_Type_Mismatch,
      Msg_Name_Undeclared,
      Msg_Name_Already_Declared,
      Msg_Lexical_Stray_Character,
      Msg_Lexical_Unterminated_String,
      Msg_Lexical_Unterminated_Character,
      Msg_Lexical_Malformed_Number,
      Msg_Lexical_Malformed_Identifier,
      Msg_Lexical_Bad_Escape,
      Msg_Lexical_Brace_Unescaped,
      Msg_Lexical_Quote_In_Interpolation,
      Msg_Syntax_Unexpected,
      Msg_Syntax_Missing,
      Msg_Syntax_Mixed_Logical,
      Msg_Not_Assignable,
      Msg_Not_A_Type,
      Msg_Not_Callable,
      Msg_Not_An_Exception,
      Msg_Function_As_Statement,
      Msg_Exit_Outside_Loop,
      Msg_Nested_Subprogram,
      Msg_Actual_Not_Variable,
      Msg_Attribute_Not_Defined,
      Msg_Name_Is_Predefined,
      Msg_Body_Missing,
      Msg_No_Matching_Subprogram,
      Msg_Ambiguous_Call,
      Msg_Return_Without_Value,
      Msg_Return_With_Value,
      Msg_Condition_Not_Boolean,
      Msg_Operator_Not_Defined,
      Msg_Statement_Among_Declarations,
      Msg_String_Index_Malformed,
      Msg_Not_Taken_Apart,
      Msg_Case_Not_Discrete,
      Msg_Case_Choice_Not_Static,
      Msg_Case_Choice_Covered_Twice,
      Msg_Case_Range_Is_Empty,
      Msg_Case_Others_Not_Last,
      Msg_Case_Incomplete,
      Msg_Not_Lowerable,
      Msg_Program_Raised,
      Msg_Program_Raised_Detail,

      --  Predefined entities: what they are, and what completion shows.
      Msg_Predefined_Type_Doc,
      Msg_Predefined_Clock_Doc,
      Msg_Predefined_Clock_Hint,
      Msg_Predefined_True_Doc,
      Msg_Predefined_False_Doc,
      Msg_Predefined_Put_Line_Doc,
      Msg_Predefined_Put_Doc,
      Msg_Predefined_New_Line_Doc,
      Msg_Predefined_Env_Value_Doc,
      Msg_Predefined_Status_Doc,
      Msg_Predefined_Output_Of_Doc,
      Msg_Predefined_Read_Line_Doc,
      Msg_Predefined_Input_Ended_Doc,
      Msg_Predefined_Exists_Doc,
      Msg_Predefined_Is_Directory_Doc,
      Msg_Predefined_Is_Executable_Doc,
      Msg_Predefined_Index_Doc,
      Msg_Predefined_Trim_Doc,
      Msg_Predefined_To_Upper_Doc,
      Msg_Predefined_To_Lower_Doc,
      Msg_Predefined_Starts_With_Doc,
      Msg_Predefined_Ends_With_Doc,
      Msg_Predefined_Argument_Count_Doc,
      Msg_Predefined_Argument_Doc,
      Msg_Predefined_Type_Hint,
      Msg_Predefined_Constant_Hint,
      Msg_Predefined_Put_Line_Hint,
      Msg_Predefined_Put_Hint,
      Msg_Predefined_New_Line_Hint,
      Msg_Predefined_Env_Value_Hint,
      Msg_Predefined_Status_Hint,
      Msg_Predefined_Output_Of_Hint,
      Msg_Predefined_Read_Line_Hint,
      Msg_Predefined_Input_Ended_Hint,
      Msg_Predefined_Exists_Hint,
      Msg_Predefined_Is_Directory_Hint,
      Msg_Predefined_Is_Executable_Hint,
      Msg_Predefined_Index_Hint,
      Msg_Predefined_Trim_Hint,
      Msg_Predefined_To_Upper_Hint,
      Msg_Predefined_To_Lower_Hint,
      Msg_Predefined_Starts_With_Hint,
      Msg_Predefined_Ends_With_Hint,
      Msg_Predefined_Argument_Count_Hint,
      Msg_Predefined_Argument_Hint,

      --  Calls.
      Msg_Wrong_Argument_Count,
      Msg_No_Such_Parameter,
      Msg_Parameter_Given_Twice,
      Msg_Positional_After_Named,
      Msg_Parameter_Not_Given,
      Msg_Default_Not_Literal,
      Msg_Default_Not_In_Mode,
      Msg_Not_Runnable_Yet,

      --  Internal commands: what each is, what completion shows, and the
      --  lines they produce.
      Msg_Command_Cd_Doc, Msg_Command_Pwd_Doc, Msg_Command_Exit_Doc,
      Msg_Command_Set_Doc, Msg_Command_Unset_Doc, Msg_Command_Env_Doc,
      Msg_Command_Jobs_Doc, Msg_Command_Help_Doc, Msg_Command_Version_Doc,
      Msg_Command_History_Doc, Msg_Command_Source_Doc,
      Msg_Command_Run_Doc, Msg_Command_Run_Into_Doc,
      Msg_Command_Run_From_Doc, Msg_Command_Run_Append_Doc,
      Msg_Command_Run_New_Doc, Msg_Command_Pipe_Doc,
      Msg_Command_Pipe_Run_Doc, Msg_Command_Start_Doc, Msg_Command_Wait_Doc, Msg_Command_Stop_Doc,
      Msg_Command_Suspend_Doc, Msg_Command_Resume_Doc,
      Msg_Command_Settings_Doc, Msg_Command_Save_Settings_Doc,
      Msg_Command_Write_File_Doc, Msg_Command_Append_File_Doc,
      Msg_Command_Hint,

      --  Output lines.
      Msg_Line_Directory,
      Msg_Line_Variable,
      Msg_Line_Setting,
      Msg_Line_Settings_Saved,
      Msg_Line_Job,
      Msg_Line_History_Entry,
      Msg_Line_Job_Started,
      Msg_Line_Job_Finished,
      Msg_Line_Job_Signalled,
      Msg_Line_Command_Entry,
      Msg_Line_Version,

      --  Command failures.
      Msg_Command_Wrong_Arguments,
      Msg_Command_Unavailable,
      Msg_No_History_Here,
      Msg_Empty_Pipeline,
      Msg_Too_Many_Kept,
      Msg_Command_Bad_Assignment,
      Msg_Script_Cycle,

      --  What a name below the presentation boundary means in words.
      --
      --  A signal, a job's state, a capability, a reason a program would
      --  not start: each is an identifier where it is known and a phrase
      --  where it is read. These are the phrases.
      Msg_Signal_Interrupt,
      Msg_Signal_Quit,
      Msg_Signal_Terminate,
      Msg_Signal_Kill,
      Msg_Signal_Hangup,
      Msg_Signal_Stop,
      Msg_Signal_Terminal_Stop,
      Msg_Signal_Continue,
      Msg_Signal_Pipe,
      Msg_Signal_Background_Read,
      Msg_Signal_Background_Write,
      Msg_Signal_Window_Change,
      Msg_Signal_Child,
      Msg_Job_State_Running,
      Msg_Job_State_Stopped,
      Msg_Job_State_Completed,
      Msg_Capability_Signals,
      Msg_Capability_Job_Control,
      Msg_Capability_Pseudo_Terminal,
      Msg_Capability_Advisory_Locks,
      Msg_Start_Reason_Host_Refused,
      Msg_Start_Reason_Stream_Setup,

      --  Completion.
      Msg_Completion_Keyword,
      Msg_Completion_Path,

      --  The prompt.
      Msg_Prompt_Primary,
      Msg_Prompt_Continuation,
      Msg_Prompt_Failed,

      --  The interactive session.
      Msg_Interactive_Line_Editing_Unavailable,
      Msg_Interactive_Read_Failed,

      --  What each setting is for. Shown when the settings are listed, and by
      --  a diagnostic that names one.
      Msg_Setting_Color,
      Msg_Setting_History_Enabled,
      Msg_Setting_History_Limit,
      Msg_Setting_Prompt_Directory,
      Msg_Setting_Prompt_Failure,
      Msg_Setting_Editing,
      Msg_Setting_Session_File,
      Msg_Setting_History_Per_Session,

      --  Reading a configuration file.
      Msg_Config_Unknown_Key,
      Msg_Setting_Unknown,
      Msg_Config_Wrong_Type,
      Msg_Config_Out_Of_Range,
      Msg_Config_Bad_Choice,
      Msg_Config_Syntax,
      Msg_Config_Unreadable,
      Msg_Config_Not_Text,
      Msg_Config_Newer_Schema,
      Msg_Config_Migrated,

      --  Persisting history.
      Msg_History_Unreadable,
      Msg_History_Damaged_Lines,
      Msg_History_Not_Written);

   --  The catalog key for an identifier.
   --
   --  Keys are stable across releases: a key is part of the contract with
   --  translators and with conformance cases, so renaming one is a breaking
   --  change even when the English text is untouched.
   --
   --  @param Id Message identifier.
   --  @return Dotted catalog key, for example "version.line".
   function Key (Id : Message_Id) return String;

   --  Largest number of named arguments one message may take.
   --
   --  Bounded so that argument lists can live on the stack at the presentation
   --  boundary. Raising it is a source change, which is the point: a message
   --  wanting more than this many placeholders is usually two messages.
   Max_Arguments : constant := 8;

   --  The placeholder names a message expects, in the order the catalog
   --  entry uses them.
   type Placeholder_Names is
     array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   --  The placeholder list of a message that takes none.
   No_Placeholders : constant Placeholder_Names;

   --  Which placeholders a message expects.
   --
   --  This is the part of a message's contract that the catalog cannot
   --  enforce and the compiler cannot see. A caller passing "file" where the
   --  message says "path" produces a rendering failure at run time, in the
   --  error path, on the day something else has already gone wrong; declaring
   --  the names here lets a test render every message with its own
   --  placeholders and catch the drift at build time instead.
   --
   --  Like Key, this has no `others`: a new identifier must say what it
   --  takes, even when the answer is nothing.
   --
   --  @param Id Message identifier.
   --  @return Placeholder names, without braces.
   function Placeholders (Id : Message_Id) return Placeholder_Names;

   --  A placeholder's name, held without a container.
   --
   --  Fixed-width so that a failure can carry one without allocating: a
   --  failure is built in places that must not, and the names are short and
   --  written in this repository rather than by a user.
   subtype Placeholder_Name is String (1 .. 16);

   --  Pad a placeholder name to the fixed width.
   --
   --  @param Name The name, without braces.
   --  @return It, padded; the last 16 characters when it is longer, which
   --          cannot happen for a name written here and would be a defect.
   function To_Placeholder (Name : String) return Placeholder_Name;

   --  Trim a placeholder name back to what was written.
   --
   --  @param Name The padded name.
   --  @return It, without the padding.
   function From_Placeholder (Name : Placeholder_Name) return String;

   --  One named argument, as a message's placeholder spells it.
   type Argument is private;

   type Argument_List is array (Positive range <>) of Argument;

   --  The argument list of a message that takes none.
   No_Arguments : constant Argument_List;

   --  Build a named argument.
   --
   --  @param Name Placeholder name, without braces, as the catalog spells it.
   --  @param Value Replacement text, already in its final form.
   --  @return Argument ready to pass to Adash.Messages.Rendering.
   function Named (Name : String; Value : String) return Argument;

   --  The placeholder name of an argument.
   --
   --  @param Item Argument to inspect.
   --  @return Placeholder name.
   function Name (Item : Argument) return String;

   --  The replacement text of an argument.
   --
   --  @param Item Argument to inspect.
   --  @return Replacement text.
   function Value (Item : Argument) return String;

private

   type Argument is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   No_Arguments : constant Argument_List (1 .. 0) := [others => <>];

   No_Placeholders : constant Placeholder_Names (1 .. 0) := [others => <>];

end Adash.Messages;

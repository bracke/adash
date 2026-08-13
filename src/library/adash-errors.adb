package body Adash.Errors is

   ------------
   -- Domain --
   ------------

   function Domain (Code : Error_Code) return Error_Domain is
   begin
      --  No `others`: a code added without a domain is a compile error, which
      --  is the only moment anyone is still thinking about where it belongs.
      case Code is
         when Error_None =>
            return Domain_None;

         when Error_Command_Not_Found
            | Error_Command_Not_Executable
            | Error_Command_Denied
            | Error_Command_Start_Failed
            | Error_Redirection_Open_Failed
            | Error_Redirection_Conflict
            | Error_Pipe_Creation_Failed
            | Error_Stream_Write_Failed
            | Error_Stream_Read_Failed
            | Error_File_Not_Writable
            | Error_File_Write_Failed
            | Error_Job_Unknown
            | Error_Job_Is_Suspended
            | Error_Cancelled
            | Error_Directory_Not_Found
            | Error_Directory_Denied
            | Error_Command_Wrong_Arguments
            | Error_Command_Unavailable
            | Error_No_History_Here
            | Error_Empty_Pipeline
            | Error_Too_Many_Kept
            | Error_Command_Bad_Assignment
            | Error_Script_Cycle
            | Error_Module_Not_Found =>
            return Domain_Execution;

         when Error_Source_Unreadable
            | Error_Source_Invalid_Encoding
            | Error_Type_Mismatch
            | Error_Name_Undeclared
            | Error_Name_Already_Declared
            | Error_Lexical_Stray_Character
            | Error_Lexical_Unterminated_String
            | Error_Lexical_Unterminated_Character
            | Error_Lexical_Malformed_Number
            | Error_Lexical_Malformed_Identifier
            | Error_Lexical_Bad_Escape
            | Error_Lexical_Brace_Unescaped
            | Error_Lexical_Quote_In_Interpolation
            | Error_Syntax_Unexpected
            | Error_Syntax_Missing
            | Error_Syntax_Mixed_Logical_Operators
            | Error_Not_Assignable
            | Error_Not_A_Type
            | Error_Not_Callable
            | Error_Not_An_Exception
            | Error_Statement_Among_Declarations
            | Error_String_Index_Malformed
            | Error_Case_Not_Discrete
            | Error_Case_Choice_Not_Static
            | Error_Case_Choice_Covered_Twice
            | Error_Case_Range_Is_Empty
            | Error_Case_Others_Not_Last
            | Error_Case_Incomplete
            | Error_Function_As_Statement
            | Error_Exit_Outside_Loop
            | Error_Nested_Subprogram
            | Error_Actual_Not_Variable
            | Error_Attribute_Not_Defined
            | Error_Name_Is_Predefined
            | Error_Body_Missing
            | Error_No_Matching_Subprogram
            | Error_Ambiguous_Call
            | Error_Return_Without_Value
            | Error_Return_With_Value
            | Error_Condition_Not_Boolean
            | Error_Operator_Not_Defined
            | Error_Not_Lowerable
            | Error_Program_Raised
            | Error_Program_Raised_With_Detail
            | Error_Wrong_Argument_Count
            | Error_No_Such_Parameter
            | Error_Parameter_Given_Twice
            | Error_Positional_After_Named
            | Error_Parameter_Not_Given
            | Error_Default_Not_Literal
            | Error_Default_Not_In_Mode
            | Error_Subtype_Not_Discrete
            | Error_Subtype_Bound_Not_Static
            | Error_Subtype_Range_Is_Empty
            | Error_Part_Not_Simple
            | Error_Part_Given_Twice
            | Error_Record_Is_Empty
            | Error_Array_Bound_Not_Static
            | Error_Array_Is_Empty
            | Error_Array_Too_Long
            | Error_Not_A_Record
            | Error_No_Such_Component
            | Error_Not_An_Array
            | Error_Aggregate_Wrong_Count
            | Error_Aggregate_Not_Expected
            | Error_Result_Not_Simple
            | Error_Cannot_Write
            | Error_Not_A_Package
            | Error_Package_Not_Declared
            | Error_Not_A_Generic
            | Error_Generic_Wrong_Actuals
            | Error_Generic_Not_Callable
            | Error_Not_A_Task
            | Error_Not_An_Entry
            | Error_Accept_Differs
            | Error_Protected_Entry_Parameters
            | Error_Entry_Parameter_Not_Simple
            | Error_Select_Alternative
            | Error_Select_Trigger
            | Error_Select_Waits_Twice
            | Error_Discriminants_Need_A_Type
            | Error_Discriminants_Wrong_Count
            | Error_Nothing_To_Constrain
            | Error_Count_Outside_Its_Unit
            | Error_Is_A_Type
            | Error_Requeue_Not_An_Entry
            | Error_Requeue_Takes_Nothing
            | Error_Family_Index_Not_Discrete
            | Error_Family_Takes_Nothing
            | Error_Not_A_Family
            | Error_Family_Needs_A_Member
            | Error_Cannot_Be_Copied
            | Error_Identity_Needs_A_Task
            | Error_Unknown_Pragma
            | Error_Unknown_Restriction
            | Error_Unknown_Policy
            | Error_Unknown_Profile | Error_Dispatching_Twice
            | Error_Queuing_Twice | Error_Terminate_Outside_Select
            | Error_Ambiguous_Literal | Error_Raise_Outside_A_Handler
            | Error_Empty_Priority_Range
            | Error_Restriction_Broken
            | Error_Priority_Not_Static =>
            return Domain_Language;

         when Error_Capability_Unavailable =>
            return Domain_Platform;
      end case;
   end Domain;

   -------------
   -- Message --
   -------------

   function Message (Code : Error_Code) return Adash.Messages.Message_Id is
   begin
      case Code is
         when Error_None                   => return Adash.Messages.Msg_Error_None;
         when Error_Command_Not_Found      => return Adash.Messages.Msg_Command_Not_Found;
         when Error_Command_Not_Executable => return Adash.Messages.Msg_Command_Not_Executable;
         when Error_Command_Denied         => return Adash.Messages.Msg_Command_Denied;
         when Error_Command_Start_Failed   => return Adash.Messages.Msg_Command_Start_Failed;
         when Error_Redirection_Open_Failed => return Adash.Messages.Msg_Redirection_Open_Failed;
         when Error_Redirection_Conflict   => return Adash.Messages.Msg_Redirection_Conflict;
         when Error_Pipe_Creation_Failed   => return Adash.Messages.Msg_Pipe_Creation_Failed;
         when Error_Stream_Write_Failed    => return Adash.Messages.Msg_Stream_Write_Failed;
         when Error_Stream_Read_Failed     => return Adash.Messages.Msg_Stream_Read_Failed;
         when Error_File_Not_Writable      =>
            return Adash.Messages.Msg_File_Not_Writable;
         when Error_File_Write_Failed      =>
            return Adash.Messages.Msg_File_Write_Failed;
         when Error_Job_Unknown            => return Adash.Messages.Msg_Job_Unknown;
         when Error_Job_Is_Suspended       =>
            return Adash.Messages.Msg_Job_Is_Suspended;
         when Error_Cancelled              => return Adash.Messages.Msg_Execution_Cancelled;
         when Error_Capability_Unavailable => return Adash.Messages.Msg_Capability_Unavailable;
         when Error_Directory_Not_Found    => return Adash.Messages.Msg_Directory_Not_Found;
         when Error_Directory_Denied       => return Adash.Messages.Msg_Directory_Denied;
         when Error_Source_Unreadable      => return Adash.Messages.Msg_Source_Unreadable;
         when Error_Module_Not_Found       =>
            return Adash.Messages.Msg_Module_Not_Found;
         when Error_Source_Invalid_Encoding => return Adash.Messages.Msg_Source_Invalid_Encoding;
         when Error_Type_Mismatch          => return Adash.Messages.Msg_Type_Mismatch;
         when Error_Name_Undeclared        => return Adash.Messages.Msg_Name_Undeclared;
         when Error_Name_Already_Declared  => return Adash.Messages.Msg_Name_Already_Declared;
         when Error_Lexical_Stray_Character =>
            return Adash.Messages.Msg_Lexical_Stray_Character;
         when Error_Lexical_Unterminated_String =>
            return Adash.Messages.Msg_Lexical_Unterminated_String;
         when Error_Lexical_Unterminated_Character =>
            return Adash.Messages.Msg_Lexical_Unterminated_Character;
         when Error_Lexical_Malformed_Number =>
            return Adash.Messages.Msg_Lexical_Malformed_Number;
         when Error_Lexical_Malformed_Identifier =>
            return Adash.Messages.Msg_Lexical_Malformed_Identifier;
         when Error_Lexical_Bad_Escape     => return Adash.Messages.Msg_Lexical_Bad_Escape;
         when Error_Lexical_Brace_Unescaped =>
            return Adash.Messages.Msg_Lexical_Brace_Unescaped;
         when Error_Lexical_Quote_In_Interpolation =>
            return Adash.Messages.Msg_Lexical_Quote_In_Interpolation;
         when Error_Syntax_Unexpected      => return Adash.Messages.Msg_Syntax_Unexpected;
         when Error_Syntax_Missing         => return Adash.Messages.Msg_Syntax_Missing;
         when Error_Syntax_Mixed_Logical_Operators =>
            return Adash.Messages.Msg_Syntax_Mixed_Logical;
         when Error_Not_Assignable         => return Adash.Messages.Msg_Not_Assignable;
         when Error_Not_A_Type             => return Adash.Messages.Msg_Not_A_Type;
         when Error_Not_Callable           => return Adash.Messages.Msg_Not_Callable;
         when Error_Not_An_Exception       =>
            return Adash.Messages.Msg_Not_An_Exception;
         when Error_Statement_Among_Declarations =>
            return Adash.Messages.Msg_Statement_Among_Declarations;
         when Error_String_Index_Malformed =>
            return Adash.Messages.Msg_String_Index_Malformed;
         when Error_Case_Not_Discrete      =>
            return Adash.Messages.Msg_Case_Not_Discrete;
         when Error_Case_Choice_Not_Static =>
            return Adash.Messages.Msg_Case_Choice_Not_Static;
         when Error_Case_Choice_Covered_Twice =>
            return Adash.Messages.Msg_Case_Choice_Covered_Twice;
         when Error_Case_Range_Is_Empty    =>
            return Adash.Messages.Msg_Case_Range_Is_Empty;
         when Error_Case_Others_Not_Last   =>
            return Adash.Messages.Msg_Case_Others_Not_Last;
         when Error_Case_Incomplete        =>
            return Adash.Messages.Msg_Case_Incomplete;
         when Error_Function_As_Statement  =>
            return Adash.Messages.Msg_Function_As_Statement;
         when Error_Exit_Outside_Loop   => return Adash.Messages.Msg_Exit_Outside_Loop;
         when Error_Nested_Subprogram   => return Adash.Messages.Msg_Nested_Subprogram;
         when Error_Actual_Not_Variable =>
            return Adash.Messages.Msg_Actual_Not_Variable;
         when Error_Attribute_Not_Defined =>
            return Adash.Messages.Msg_Attribute_Not_Defined;
         when Error_Name_Is_Predefined  => return Adash.Messages.Msg_Name_Is_Predefined;
         when Error_Body_Missing        => return Adash.Messages.Msg_Body_Missing;
         when Error_No_Matching_Subprogram =>
            return Adash.Messages.Msg_No_Matching_Subprogram;
         when Error_Ambiguous_Call      => return Adash.Messages.Msg_Ambiguous_Call;
         when Error_Return_Without_Value =>
            return Adash.Messages.Msg_Return_Without_Value;
         when Error_Return_With_Value   => return Adash.Messages.Msg_Return_With_Value;
         when Error_Condition_Not_Boolean  => return Adash.Messages.Msg_Condition_Not_Boolean;
         when Error_Operator_Not_Defined   => return Adash.Messages.Msg_Operator_Not_Defined;
         when Error_Not_Lowerable          => return Adash.Messages.Msg_Not_Lowerable;
         when Error_Program_Raised         => return Adash.Messages.Msg_Program_Raised;
         when Error_Program_Raised_With_Detail =>
            return Adash.Messages.Msg_Program_Raised_Detail;
         when Error_Wrong_Argument_Count   => return Adash.Messages.Msg_Wrong_Argument_Count;
         when Error_No_Such_Parameter      =>
            return Adash.Messages.Msg_No_Such_Parameter;
         when Error_Parameter_Given_Twice  =>
            return Adash.Messages.Msg_Parameter_Given_Twice;
         when Error_Positional_After_Named =>
            return Adash.Messages.Msg_Positional_After_Named;
         when Error_Parameter_Not_Given    =>
            return Adash.Messages.Msg_Parameter_Not_Given;
         when Error_Default_Not_Literal    =>
            return Adash.Messages.Msg_Default_Not_Literal;
         when Error_Default_Not_In_Mode    =>
            return Adash.Messages.Msg_Default_Not_In_Mode;
         when Error_Subtype_Not_Discrete   =>
            return Adash.Messages.Msg_Subtype_Not_Discrete;
         when Error_Subtype_Bound_Not_Static =>
            return Adash.Messages.Msg_Subtype_Bound_Not_Static;
         when Error_Subtype_Range_Is_Empty =>
            return Adash.Messages.Msg_Subtype_Range_Is_Empty;
         when Error_Part_Not_Simple =>
            return Adash.Messages.Msg_Part_Not_Simple;
         when Error_Part_Given_Twice =>
            return Adash.Messages.Msg_Part_Given_Twice;
         when Error_Record_Is_Empty =>
            return Adash.Messages.Msg_Record_Is_Empty;
         when Error_Array_Bound_Not_Static =>
            return Adash.Messages.Msg_Array_Bound_Not_Static;
         when Error_Array_Is_Empty =>
            return Adash.Messages.Msg_Array_Is_Empty;
         when Error_Array_Too_Long =>
            return Adash.Messages.Msg_Array_Too_Long;
         when Error_Not_A_Record =>
            return Adash.Messages.Msg_Not_A_Record;
         when Error_No_Such_Component =>
            return Adash.Messages.Msg_No_Such_Component;
         when Error_Not_An_Array =>
            return Adash.Messages.Msg_Not_An_Array;
         when Error_Aggregate_Wrong_Count =>
            return Adash.Messages.Msg_Aggregate_Wrong_Count;
         when Error_Aggregate_Not_Expected =>
            return Adash.Messages.Msg_Aggregate_Not_Expected;
         when Error_Result_Not_Simple =>
            return Adash.Messages.Msg_Result_Not_Simple;
         when Error_Cannot_Write =>
            return Adash.Messages.Msg_Cannot_Write;
         when Error_Not_A_Package =>
            return Adash.Messages.Msg_Not_A_Package;
         when Error_Package_Not_Declared =>
            return Adash.Messages.Msg_Package_Not_Declared;
         when Error_Not_A_Generic =>
            return Adash.Messages.Msg_Not_A_Generic;
         when Error_Generic_Wrong_Actuals =>
            return Adash.Messages.Msg_Generic_Wrong_Actuals;
         when Error_Generic_Not_Callable =>
            return Adash.Messages.Msg_Generic_Not_Callable;
         when Error_Not_A_Task =>
            return Adash.Messages.Msg_Not_A_Task;
         when Error_Not_An_Entry =>
            return Adash.Messages.Msg_Not_An_Entry;
         when Error_Accept_Differs =>
            return Adash.Messages.Msg_Accept_Differs;
         when Error_Protected_Entry_Parameters =>
            return Adash.Messages.Msg_Protected_Entry_Parameters;
         when Error_Entry_Parameter_Not_Simple =>
            return Adash.Messages.Msg_Entry_Parameter_Not_Simple;
         when Error_Select_Alternative =>
            return Adash.Messages.Msg_Select_Alternative;
         when Error_Select_Trigger =>
            return Adash.Messages.Msg_Select_Trigger;
         when Error_Select_Waits_Twice =>
            return Adash.Messages.Msg_Select_Waits_Twice;
         when Error_Discriminants_Need_A_Type =>
            return Adash.Messages.Msg_Discriminants_Need_A_Type;
         when Error_Discriminants_Wrong_Count =>
            return Adash.Messages.Msg_Discriminants_Wrong_Count;
         when Error_Nothing_To_Constrain =>
            return Adash.Messages.Msg_Nothing_To_Constrain;
         when Error_Count_Outside_Its_Unit =>
            return Adash.Messages.Msg_Count_Outside_Its_Unit;
         when Error_Is_A_Type =>
            return Adash.Messages.Msg_Is_A_Type;
         when Error_Requeue_Not_An_Entry =>
            return Adash.Messages.Msg_Requeue_Not_An_Entry;
         when Error_Requeue_Takes_Nothing =>
            return Adash.Messages.Msg_Requeue_Takes_Nothing;
         when Error_Family_Index_Not_Discrete =>
            return Adash.Messages.Msg_Family_Index_Not_Discrete;
         when Error_Family_Takes_Nothing =>
            return Adash.Messages.Msg_Family_Takes_Nothing;
         when Error_Not_A_Family =>
            return Adash.Messages.Msg_Not_A_Family;
         when Error_Family_Needs_A_Member =>
            return Adash.Messages.Msg_Family_Needs_A_Member;
         when Error_Cannot_Be_Copied =>
            return Adash.Messages.Msg_Cannot_Be_Copied;
         when Error_Identity_Needs_A_Task =>
            return Adash.Messages.Msg_Identity_Needs_A_Task;
         when Error_Unknown_Pragma =>
            return Adash.Messages.Msg_Unknown_Pragma;
         when Error_Unknown_Restriction =>
            return Adash.Messages.Msg_Unknown_Restriction;
         when Error_Unknown_Policy =>
            return Adash.Messages.Msg_Unknown_Policy;
         when Error_Unknown_Profile =>
            return Adash.Messages.Msg_Unknown_Profile;
         when Error_Dispatching_Twice =>
            return Adash.Messages.Msg_Dispatching_Twice;
         when Error_Queuing_Twice =>
            return Adash.Messages.Msg_Queuing_Twice;
         when Error_Terminate_Outside_Select =>
            return Adash.Messages.Msg_Terminate_Outside_Select;
         when Error_Ambiguous_Literal =>
            return Adash.Messages.Msg_Ambiguous_Literal;
         when Error_Raise_Outside_A_Handler =>
            return Adash.Messages.Msg_Raise_Outside_A_Handler;
         when Error_Empty_Priority_Range =>
            return Adash.Messages.Msg_Empty_Priority_Range;
         when Error_Restriction_Broken =>
            return Adash.Messages.Msg_Restriction_Broken;
         when Error_Priority_Not_Static =>
            return Adash.Messages.Msg_Priority_Not_Static;
         when Error_Command_Wrong_Arguments =>
            return Adash.Messages.Msg_Command_Wrong_Arguments;
         when Error_Command_Unavailable    => return Adash.Messages.Msg_Command_Unavailable;
         when Error_No_History_Here        => return Adash.Messages.Msg_No_History_Here;
         when Error_Empty_Pipeline         => return Adash.Messages.Msg_Empty_Pipeline;
         when Error_Too_Many_Kept          => return Adash.Messages.Msg_Too_Many_Kept;
         when Error_Command_Bad_Assignment => return Adash.Messages.Msg_Command_Bad_Assignment;
         when Error_Script_Cycle           => return Adash.Messages.Msg_Script_Cycle;
      end case;
   end Message;

   ----------------
   -- Is_Failure --
   ----------------

   function Is_Failure (Item : Error_Info) return Boolean is
   begin
      return Item.Code /= Error_None;
   end Is_Failure;

   ---------------
   -- Arguments --
   ---------------

   function Arguments (Item : Error_Info) return Adash.Messages.Argument_List is
   begin
      return Item.Arguments
        (Item.Arguments'First .. Item.Arguments'First + Item.Argument_Count - 1);
   end Arguments;

   -------------
   -- Failure --
   -------------

   function Failure
     (Code      : Error_Code;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Quoted    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills     : String := "") return Error_Info
   is
      Result : Error_Info;
   begin
      Result.Code := Code;
      Result.Argument_Count := Arguments'Length;
      Result.Detail := Quoted;
      Result.Fills := Adash.Messages.To_Placeholder (Fills);

      for Index in Arguments'Range loop
         Result.Arguments (Result.Arguments'First + (Index - Arguments'First)) :=
           Arguments (Index);
      end loop;

      return Result;
   end Failure;

end Adash.Errors;

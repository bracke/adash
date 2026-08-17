package body Adash.Messages is

   package US renames Ada.Strings.Unbounded;

   ---------
   -- Key --
   ---------

   function Key (Id : Message_Id) return String is
   begin
      --  No `others`. An identifier added to Message_Id without a key here is
      --  a compile error, which is the only moment anyone is still thinking
      --  about that message.
      case Id is
         when Msg_Application_Name          => return "application.name";
         when Msg_Application_Summary       => return "application.summary";

         when Msg_Version_Line              => return "version.line";
         when Msg_Version_Build             => return "version.build";
         when Msg_Version_Prerelease_Notice => return "version.prerelease_notice";

         when Msg_Usage                     => return "usage.line";
         when Msg_Usage_Options_Header      => return "usage.options_header";
         when Msg_Usage_Option_Help         => return "usage.option.help";
         when Msg_Usage_Option_Version      => return "usage.option.version";
         when Msg_Usage_More                => return "usage.more";
         when Msg_Usage_Script              => return "usage.script";

         when Msg_Unknown_Option            => return "startup.unknown_option";
         when Msg_Catalog_Unavailable       => return "startup.catalog_unavailable";

         when Msg_Error_None                 => return "error.none";
         when Msg_Command_Not_Found          => return "error.command_not_found";
         when Msg_Command_Not_Executable     => return "error.command_not_executable";
         when Msg_Command_Denied             => return "error.command_denied";
         when Msg_Command_Start_Failed       => return "error.command_start_failed";
         when Msg_Redirection_Open_Failed    => return "error.redirection_open_failed";
         when Msg_Redirection_Conflict       => return "error.redirection_conflict";
         when Msg_Pipe_Creation_Failed       => return "error.pipe_creation_failed";
         when Msg_Stream_Write_Failed        => return "error.stream_write_failed";
         when Msg_Stream_Read_Failed         => return "error.stream_read_failed";
         when Msg_File_Not_Writable          => return "error.file_not_writable";
         when Msg_Machine_Stack_Full         => return "error.machine.stack_full";
         when Msg_Machine_Stack_Empty        => return "error.machine.stack_empty";
         when Msg_Machine_No_Place           => return "error.machine.no_place";
         when Msg_Machine_No_Value           => return "error.machine.no_value";
         when Msg_Machine_No_Caller          => return "error.machine.no_caller";
         when Msg_Machine_Above_Ceiling      =>
            return "error.machine.above_ceiling";
         when Msg_Machine_Blocking_In_Protected =>
            return "error.machine.blocking_in_protected";
         when Msg_Machine_Too_Many_Allowed =>
            return "error.machine.too_many_allowed";
         when Msg_Machine_Queue_Too_Long =>
            return "error.machine.queue_too_long";
         when Msg_Machine_Too_Many_Alternatives =>
            return "error.machine.too_many_alternatives";
         when Msg_Machine_Task_Ran_Out =>
            return "error.machine.task_ran_out";
         when Msg_Machine_No_Store_Place     =>
            return "error.machine.no_store_place";
         when Msg_Machine_Swap_Empty         => return "error.machine.swap_empty";
         when Msg_Machine_Not_A_Number       =>
            return "error.machine.not_a_number";
         when Msg_Machine_Arithmetic         => return "error.machine.arithmetic";
         when Msg_Machine_Too_Many_Calls     =>
            return "error.machine.too_many_calls";
         when Msg_Machine_No_Frame_Room      =>
            return "error.machine.no_frame_room";
         when Msg_Machine_No_Return_To       =>
            return "error.machine.no_return_to";
         when Msg_Machine_No_Shell           => return "error.machine.no_shell";
         when Msg_Machine_Index_Outside      =>
            return "error.machine.index_outside";
         when Msg_Machine_Slice_Outside      =>
            return "error.machine.slice_outside";
         when Msg_Machine_Slice_Lengths      =>
            return "error.machine.slice_lengths";
         when Msg_Machine_Bad_Value_Text     =>
            return "error.machine.bad_value_text";
         when Msg_Machine_Too_Many_Handlers  =>
            return "error.machine.too_many_handlers";
         when Msg_Machine_No_Return_Value    =>
            return "error.machine.no_return_value";
         when Msg_Machine_Not_A_Raise        =>
            return "error.machine.not_a_raise";
         when Msg_Machine_Position_Outside   =>
            return "error.machine.position_outside";
         when Msg_Machine_Outside_Bounds     =>
            return "error.machine.outside_bounds";
         when Msg_Machine_Outside_Array      =>
            return "error.machine.outside_array";
         when Msg_Machine_Too_Many_Tasks     =>
            return "error.machine.too_many_tasks";
         when Msg_Machine_Task_Finished      =>
            return "error.machine.task_finished";
         when Msg_Machine_Tasks_Stuck        =>
            return "error.machine.tasks_stuck";
         when Msg_Expected_Expression        => return "expected.expression";
         when Msg_Expected_Statement         => return "expected.statement";
         when Msg_Expected_Type_Name         => return "expected.type_name";
         when Msg_Expected_Literal_Name      =>
            return "expected.literal_name";
         when Msg_Expected_Component_Name    =>
            return "expected.component_name";
         when Msg_Expected_Task_Name         =>
            return "expected.task_name";
         when Msg_Expected_Package_Name      =>
            return "expected.package_name";
         when Msg_Subtype_Not_Discrete       =>
            return "error.subtype.not_discrete";
         when Msg_Subtype_Bound_Not_Static   =>
            return "error.subtype.bound_not_static";
         when Msg_Subtype_Range_Is_Empty     =>
            return "error.subtype.range_is_empty";
         when Msg_Part_Not_Simple =>
            return "error.part_not_simple";
         when Msg_Part_Given_Twice =>
            return "error.part_given_twice";
         when Msg_Record_Is_Empty =>
            return "error.record_is_empty";
         when Msg_Array_Bound_Not_Static =>
            return "error.array_bound_not_static";
         when Msg_Array_Is_Empty =>
            return "error.array_is_empty";
         when Msg_Array_Too_Long =>
            return "error.array_too_long";
         when Msg_Not_A_Record =>
            return "error.not_a_record";
         when Msg_No_Such_Component =>
            return "error.no_such_component";
         when Msg_Not_An_Array =>
            return "error.not_an_array";
         when Msg_Aggregate_Wrong_Count =>
            return "error.aggregate_wrong_count";
         when Msg_Aggregate_Not_Expected =>
            return "error.aggregate_not_expected";
         when Msg_Result_Not_Simple =>
            return "error.result_not_simple";
         when Msg_Cannot_Write =>
            return "error.cannot_write";
         when Msg_Not_A_Package =>
            return "error.not_a_package";
         when Msg_Package_Not_Declared =>
            return "error.package_not_declared";
         when Msg_Not_A_Generic =>
            return "error.not_a_generic";
         when Msg_Generic_Wrong_Actuals =>
            return "error.generic_wrong_actuals";
         when Msg_Generic_Not_Callable =>
            return "error.generic_not_callable";
         when Msg_Not_A_Task =>
            return "error.not_a_task";
         when Msg_Not_An_Entry =>
            return "error.not_an_entry";
         when Msg_Accept_Differs =>
            return "error.accept_differs";
         when Msg_Protected_Entry_Parameters =>
            return "error.protected_entry_parameters";
         when Msg_Entry_Parameter_Not_Simple =>
            return "error.entry_parameter_not_simple";
         when Msg_Select_Alternative =>
            return "error.select_alternative";
         when Msg_Select_Trigger =>
            return "error.select_trigger";
         when Msg_Select_Waits_Twice =>
            return "error.select_waits_twice";
         when Msg_Discriminants_Need_A_Type =>
            return "error.discriminants_need_a_type";
         when Msg_Discriminants_Wrong_Count =>
            return "error.discriminants_wrong_count";
         when Msg_Nothing_To_Constrain =>
            return "error.nothing_to_constrain";
         when Msg_Count_Outside_Its_Unit =>
            return "error.count_outside_its_unit";
         when Msg_Is_A_Type =>
            return "error.is_a_type";
         when Msg_Requeue_Not_An_Entry =>
            return "error.requeue_not_an_entry";
         when Msg_Requeue_Takes_Nothing =>
            return "error.requeue_takes_nothing";
         when Msg_Family_Index_Not_Discrete =>
            return "error.family_index_not_discrete";
         when Msg_Family_Takes_Nothing =>
            return "error.family_takes_nothing";
         when Msg_Not_A_Family =>
            return "error.not_a_family";
         when Msg_Family_Needs_A_Member =>
            return "error.family_needs_a_member";
         when Msg_Cannot_Be_Copied =>
            return "error.cannot_be_copied";
         when Msg_Identity_Needs_A_Task =>
            return "error.identity_needs_a_task";
         when Msg_Unknown_Pragma =>
            return "error.unknown_pragma";
         when Msg_Unknown_Restriction =>
            return "error.unknown_restriction";
         when Msg_Unknown_Policy =>
            return "error.unknown_policy";
         when Msg_Unknown_Profile =>
            return "error.unknown_profile";
         when Msg_Dispatching_Twice =>
            return "error.dispatching_twice";
         when Msg_Queuing_Twice =>
            return "error.queuing_twice";
         when Msg_Terminate_Outside_Select =>
            return "error.terminate_outside_select";
         when Msg_Ambiguous_Literal =>
            return "error.ambiguous_literal";
         when Msg_Raise_Outside_A_Handler =>
            return "error.raise_outside_a_handler";
         when Msg_Aggregate_Others_Covers_Nothing =>
            return "error.aggregate.others_covers_nothing";
         when Msg_Empty_Priority_Range =>
            return "error.empty_priority_range";
         when Msg_Restriction_Broken =>
            return "error.restriction_broken";
         when Msg_Priority_Not_Static =>
            return "error.priority_not_static";
         when Msg_Expected_Parameter_Name    =>
            return "expected.parameter_name";
         when Msg_Expected_Loop_Variable     =>
            return "expected.loop_variable";
         when Msg_Expected_Subprogram_Name   =>
            return "expected.subprogram_name";
         when Msg_Expected_Exception_Name    =>
            return "expected.exception_name";
         when Msg_Expected_Attribute_Name    =>
            return "expected.attribute_name";
         when Msg_Expected_Interpolation_Rest =>
            return "expected.interpolation_rest";
         when Msg_Expected_End_Of_Input      =>
            return "expected.end_of_input";
         when Msg_Lower_Call_Wrong_Count =>
            return "lower.call_wrong_count";
         when Msg_Lower_Write_Back_Not_Variable =>
            return "lower.write_back_not_variable";
         when Msg_Lower_Float_Literal =>
            return "lower.float_literal";
         when Msg_Lower_Unresolved_Name =>
            return "lower.unresolved_name";
         when Msg_Lower_Variable_Of_Type =>
            return "lower.variable_of_type";
         when Msg_Lower_Call_To =>
            return "lower.call_to";
         when Msg_Lower_This_Operator =>
            return "lower.this_operator";
         when Msg_Lower_Arithmetic_On =>
            return "lower.arithmetic_on";
         when Msg_Lower_Float_Operation =>
            return "lower.float_operation";
         when Msg_Lower_Joining_Letters =>
            return "lower.joining_letters";
         when Msg_Lower_String_Operation =>
            return "lower.string_operation";
         when Msg_Lower_String_Concatenation =>
            return "lower.string_concatenation";
         when Msg_Lower_Value_Of =>
            return "lower.value_of";
         when Msg_Lower_Image_Of =>
            return "lower.image_of";
         when Msg_Lower_Procedure_As_Value =>
            return "lower.procedure_as_value";
         when Msg_Lower_This_Expression =>
            return "lower.this_expression";
         when Msg_Lower_Call_In_Context =>
            return "lower.call_in_context";
         when Msg_Lower_Command_Arguments =>
            return "lower.command_arguments";
         when Msg_Lower_Argument_Of_Type =>
            return "lower.argument_of_type";
         when Msg_Lower_Declaration_Unresolved =>
            return "lower.declaration_unresolved";
         when Msg_Lower_String_No_Value =>
            return "lower.string_no_value";
         when Msg_Lower_Assignment_Unresolved =>
            return "lower.assignment_unresolved";
         when Msg_Lower_Case_Choice =>
            return "lower.case_choice";
         when Msg_Lower_Exit_Outside_Loop =>
            return "lower.exit_outside_loop";
         when Msg_Lower_Return_With_Value =>
            return "lower.return_with_value";
         when Msg_Lower_This_Statement =>
            return "lower.this_statement";
         when Msg_Lower_Writing_Type =>
            return "lower.writing_type";
         when Msg_Config_Wants_Truth =>
            return "config.wants.truth";
         when Msg_Config_Wants_Whole =>
            return "config.wants.whole";
         when Msg_Config_Wants_Range =>
            return "config.wants.range";
         when Msg_Config_Wants_Choice =>
            return "config.wants.choice";
         when Msg_File_Write_Failed          => return "error.file_write_failed";
         when Msg_File_Too_Large             => return "error.file_too_large";
         when Msg_Output_Too_Large           => return "error.output_too_large";
         when Msg_Job_Unknown                => return "error.job_unknown";
         when Msg_Job_Is_Suspended           => return "error.job_is_suspended";
         when Msg_Execution_Cancelled        => return "error.execution_cancelled";
         when Msg_Capability_Unavailable     => return "error.capability_unavailable";
         when Msg_Directory_Not_Found        => return "error.directory_not_found";
         when Msg_Directory_Denied           => return "error.directory_denied";
         when Msg_Source_Unreadable          => return "error.source_unreadable";
         when Msg_Source_Too_Large           => return "error.source_too_large";
         when Msg_Module_Not_Found          => return "error.module_not_found";
         when Msg_Module_Looked_As_Written  =>
            return "module.looked.as_written";
         when Msg_Module_Looked_Beside      => return "module.looked.beside";
         when Msg_Module_Looked_In_Modules  =>
            return "module.looked.in_modules";
         when Msg_Source_Invalid_Encoding    => return "error.source_invalid_encoding";
         when Msg_Type_Mismatch              => return "error.type_mismatch";
         when Msg_Name_Undeclared            => return "error.name_undeclared";
         when Msg_Name_Already_Declared      => return "error.name_already_declared";
         when Msg_Lexical_Stray_Character    => return "error.lexical.stray_character";
         when Msg_Lexical_Unterminated_String =>
            return "error.lexical.unterminated_string";
         when Msg_Lexical_Unterminated_Character =>
            return "error.lexical.unterminated_character";
         when Msg_Lexical_Malformed_Number   => return "error.lexical.malformed_number";
         when Msg_Lexical_Malformed_Identifier =>
            return "error.lexical.malformed_identifier";
         when Msg_Lexical_Bad_Escape         => return "error.lexical.bad_escape";
         when Msg_Lexical_Brace_Unescaped    =>
            return "error.lexical.brace_unescaped";
         when Msg_Lexical_Quote_In_Interpolation =>
            return "error.lexical.quote_in_interpolation";
         when Msg_Syntax_Unexpected          => return "error.syntax.unexpected";
         when Msg_Syntax_Missing             => return "error.syntax.missing";
         when Msg_Syntax_Mixed_Logical       => return "error.syntax.mixed_logical";
         when Msg_Not_Assignable             => return "error.not_assignable";
         when Msg_Not_A_Type                 => return "error.not_a_type";
         when Msg_Not_Callable               => return "error.not_callable";
         when Msg_Not_An_Exception          => return "error.not_an_exception";
         when Msg_Function_As_Statement      =>
            return "error.function_as_statement";
         when Msg_Exit_Outside_Loop          => return "error.exit_outside_loop";
         when Msg_Nested_Subprogram          => return "error.nested_subprogram";
         when Msg_Actual_Not_Variable        => return "error.actual_not_variable";
         when Msg_Attribute_Not_Defined      =>
            return "error.attribute_not_defined";
         when Msg_Name_Is_Predefined         => return "error.name_is_predefined";
         when Msg_Body_Missing               => return "error.body_missing";
         when Msg_No_Matching_Subprogram     =>
            return "error.no_matching_subprogram";
         when Msg_Ambiguous_Call             => return "error.ambiguous_call";
         when Msg_Return_Without_Value       => return "error.return_without_value";
         when Msg_Return_With_Value          => return "error.return_with_value";
         when Msg_Condition_Not_Boolean      => return "error.condition_not_boolean";
         when Msg_Operator_Not_Defined       => return "error.operator_not_defined";
         when Msg_Statement_Among_Declarations =>
            return "error.statement_among_declarations";
         when Msg_String_Index_Malformed   =>
            return "error.string_index_malformed";
         when Msg_Not_Taken_Apart          =>
            return "error.not_taken_apart";
         when Msg_No_Such_Slice            =>
            return "error.no_such_slice";
         when Msg_Needs_Bounds             =>
            return "error.needs_bounds";
         when Msg_Open_By_Element          =>
            return "error.open_by_element";
         when Msg_Too_Many_At_Once         =>
            return "error.too_many_at_once";
         when Msg_Too_Many_Parameters      =>
            return "error.too_many_parameters";
         when Msg_List_Alternatives            =>
            return "list.alternatives";
         when Msg_List_Parameters              =>
            return "list.parameters";
         when Msg_List_Components              =>
            return "list.components";
         when Msg_List_Values                  =>
            return "list.values";
         when Msg_List_Names                   =>
            return "list.names";
         when Msg_List_Statements              =>
            return "list.statements";
         when Msg_List_Arguments               =>
            return "list.arguments";
         when Msg_List_Choices                 =>
            return "list.choices";
         when Msg_List_Handlers                =>
            return "list.handlers";
         when Msg_Case_Not_Discrete        =>
            return "error.case.not_discrete";
         when Msg_Case_Choice_Not_Static   =>
            return "error.case.choice_not_static";
         when Msg_Case_Choice_Covered_Twice =>
            return "error.case.choice_covered_twice";
         when Msg_Case_Range_Is_Empty      =>
            return "error.case.range_is_empty";
         when Msg_Number_Not_A_Literal     =>
            return "error.number_not_a_literal";
         when Msg_Number_Not_Numeric       =>
            return "error.number_not_numeric";
         when Msg_Case_Others_Not_Last     =>
            return "error.case.others_not_last";
         when Msg_Case_Incomplete          =>
            return "error.case.incomplete";
         when Msg_Not_Lowerable              => return "error.not_lowerable";
         when Msg_Program_Raised             => return "error.program_raised";
         when Msg_Program_Raised_Detail      =>
            return "error.program_raised_detail";
         when Msg_Predefined_Type_Doc        => return "predefined.type.doc";
         when Msg_Predefined_Clock_Doc       => return "predefined.clock.doc";
         when Msg_Predefined_Clock_Hint      => return "predefined.clock.hint";
         when Msg_Predefined_True_Doc        => return "predefined.true.doc";
         when Msg_Predefined_False_Doc       => return "predefined.false.doc";
         when Msg_Predefined_Put_Line_Doc    => return "predefined.put_line.doc";
         when Msg_Predefined_Put_Doc         => return "predefined.put.doc";
         when Msg_Predefined_New_Line_Doc    => return "predefined.new_line.doc";
         when Msg_Predefined_Env_Value_Doc   => return "predefined.env_value.doc";
         when Msg_Predefined_Status_Doc      => return "predefined.status.doc";
         when Msg_Predefined_Output_Of_Doc   =>
            return "predefined.output_of.doc";
         when Msg_Predefined_Error_Of_Doc    =>
            return "predefined.error_of.doc";
         when Msg_Predefined_All_Of_Doc      =>
            return "predefined.all_of.doc";
         when Msg_Predefined_Last_Job_Doc =>
            return "predefined.last_job.doc";
         when Msg_Predefined_Last_Job_Hint =>
            return "predefined.last_job.hint";
         when Msg_Predefined_Output_Of_Pipe_Doc =>
            return "predefined.output_of_pipe.doc";
         when Msg_Predefined_Error_Of_Pipe_Doc =>
            return "predefined.error_of_pipe.doc";
         when Msg_Predefined_All_Of_Pipe_Doc =>
            return "predefined.all_of_pipe.doc";
         when Msg_Predefined_Read_Line_Doc  =>
            return "predefined.read_line.doc";
         when Msg_Predefined_Input_Ended_Doc =>
            return "predefined.input_ended.doc";
         when Msg_Predefined_Exists_Doc =>
            return "predefined.exists.doc";
         when Msg_Predefined_Is_Directory_Doc =>
            return "predefined.is_directory.doc";
         when Msg_Predefined_Read_File_Doc =>
            return "predefined.read_file.doc";
         when Msg_Predefined_Read_File_Hint =>
            return "predefined.read_file.hint";
         when Msg_Predefined_Current_Directory_Doc =>
            return "predefined.current_directory.doc";
         when Msg_Predefined_File_Count_Doc =>
            return "predefined.file_count.doc";
         when Msg_Predefined_File_At_Doc =>
            return "predefined.file_at.doc";
         when Msg_Predefined_Program_Path_Doc =>
            return "predefined.program_path.doc";
         when Msg_Predefined_Stage_Count_Doc =>
            return "predefined.stage_count.doc";
         when Msg_Predefined_Stage_Status_Doc =>
            return "predefined.stage_status.doc";
         when Msg_Predefined_Current_Directory_Hint =>
            return "predefined.current_directory.hint";
         when Msg_Predefined_File_Count_Hint =>
            return "predefined.file_count.hint";
         when Msg_Predefined_File_At_Hint =>
            return "predefined.file_at.hint";
         when Msg_Predefined_Program_Path_Hint =>
            return "predefined.program_path.hint";
         when Msg_Predefined_Stage_Count_Hint =>
            return "predefined.stage_count.hint";
         when Msg_Predefined_Stage_Status_Hint =>
            return "predefined.stage_status.hint";
         when Msg_Predefined_Is_Executable_Doc =>
            return "predefined.is_executable.doc";
         when Msg_Predefined_Index_Doc =>
            return "predefined.index.doc";
         when Msg_Predefined_Trim_Doc =>
            return "predefined.trim.doc";
         when Msg_Predefined_To_Upper_Doc =>
            return "predefined.to_upper.doc";
         when Msg_Predefined_To_Lower_Doc =>
            return "predefined.to_lower.doc";
         when Msg_Predefined_Starts_With_Doc =>
            return "predefined.starts_with.doc";
         when Msg_Predefined_Ends_With_Doc =>
            return "predefined.ends_with.doc";
         when Msg_Predefined_Argument_Count_Doc =>
            return "predefined.argument_count.doc";
         when Msg_Predefined_Argument_Doc    => return "predefined.argument.doc";
         when Msg_Predefined_Type_Hint       => return "predefined.type.hint";
         when Msg_Predefined_Constant_Hint   => return "predefined.constant.hint";
         when Msg_Predefined_Put_Line_Hint   => return "predefined.put_line.hint";
         when Msg_Predefined_Put_Hint        => return "predefined.put.hint";
         when Msg_Predefined_New_Line_Hint   => return "predefined.new_line.hint";
         when Msg_Predefined_Env_Value_Hint  => return "predefined.env_value.hint";
         when Msg_Predefined_Status_Hint     => return "predefined.status.hint";
         when Msg_Predefined_Output_Of_Hint  =>
            return "predefined.output_of.hint";
         when Msg_Predefined_Error_Of_Hint   =>
            return "predefined.error_of.hint";
         when Msg_Predefined_All_Of_Hint     =>
            return "predefined.all_of.hint";
         when Msg_Predefined_Output_Of_Pipe_Hint =>
            return "predefined.output_of_pipe.hint";
         when Msg_Predefined_Error_Of_Pipe_Hint =>
            return "predefined.error_of_pipe.hint";
         when Msg_Predefined_All_Of_Pipe_Hint =>
            return "predefined.all_of_pipe.hint";
         when Msg_Predefined_Read_Line_Hint =>
            return "predefined.read_line.hint";
         when Msg_Predefined_Input_Ended_Hint =>
            return "predefined.input_ended.hint";
         when Msg_Predefined_Exists_Hint =>
            return "predefined.exists.hint";
         when Msg_Predefined_Is_Directory_Hint =>
            return "predefined.is_directory.hint";
         when Msg_Predefined_Is_Executable_Hint =>
            return "predefined.is_executable.hint";
         when Msg_Predefined_Index_Hint =>
            return "predefined.index.hint";
         when Msg_Predefined_Trim_Hint =>
            return "predefined.trim.hint";
         when Msg_Predefined_To_Upper_Hint =>
            return "predefined.to_upper.hint";
         when Msg_Predefined_To_Lower_Hint =>
            return "predefined.to_lower.hint";
         when Msg_Predefined_Starts_With_Hint =>
            return "predefined.starts_with.hint";
         when Msg_Predefined_Ends_With_Hint =>
            return "predefined.ends_with.hint";
         when Msg_Predefined_Argument_Count_Hint =>
            return "predefined.argument_count.hint";
         when Msg_Predefined_Argument_Hint   => return "predefined.argument.hint";
         when Msg_Wrong_Argument_Count       => return "error.wrong_argument_count";
         when Msg_No_Such_Parameter          => return "error.no_such_parameter";
         when Msg_Parameter_Given_Twice      =>
            return "error.parameter_given_twice";
         when Msg_Positional_After_Named     =>
            return "error.positional_after_named";
         when Msg_Parameter_Not_Given        =>
            return "error.parameter_not_given";
         when Msg_Default_Not_Literal        => return "error.default_not_literal";
         when Msg_Default_Not_In_Mode        => return "error.default_not_in_mode";
         when Msg_Not_Runnable_Yet           => return "error.not_runnable_yet";
         when Msg_Command_Cd_Doc             => return "command.cd.doc";
         when Msg_Command_Pwd_Doc            => return "command.pwd.doc";
         when Msg_Command_Exit_Doc           => return "command.exit.doc";
         when Msg_Command_Set_Doc            => return "command.set.doc";
         when Msg_Command_Unset_Doc          => return "command.unset.doc";
         when Msg_Command_Env_Doc            => return "command.env.doc";
         when Msg_Command_Jobs_Doc           => return "command.jobs.doc";
         when Msg_Command_Help_Doc           => return "command.help.doc";
         when Msg_Command_Version_Doc        => return "command.version.doc";
         when Msg_Command_History_Doc        => return "command.history.doc";
         when Msg_Command_Forget_Doc         => return "command.forget.doc";
         when Msg_Command_Run_Doc            => return "command.run.doc";
         when Msg_Command_Run_Into_Doc       => return "command.run_into.doc";
         when Msg_Command_Run_From_Doc       => return "command.run_from.doc";
         when Msg_Command_Run_Append_Doc     => return "command.run_append.doc";
         when Msg_Command_Run_New_Doc        => return "command.run_new.doc";
         when Msg_Command_Run_Errors_Into_Doc =>
            return "command.run_errors_into.doc";
         when Msg_Command_Run_Errors_Append_Doc =>
            return "command.run_errors_append.doc";
         when Msg_Command_Run_Errors_New_Doc =>
            return "command.run_errors_new.doc";
         when Msg_Command_Run_All_Into_Doc =>
            return "command.run_all_into.doc";
         when Msg_Command_Run_All_Append_Doc =>
            return "command.run_all_append.doc";
         when Msg_Command_Run_All_New_Doc =>
            return "command.run_all_new.doc";
         when Msg_Command_Pipe_Doc           => return "command.pipe.doc";
         when Msg_Command_Pipe_Start_Doc =>
            return "command.pipe_start.doc";
         when Msg_Command_Pipe_From_Doc =>
            return "command.pipe_from.doc";
         when Msg_Command_Pipe_Into_Doc =>
            return "command.pipe_into.doc";
         when Msg_Command_Pipe_Append_Doc =>
            return "command.pipe_append.doc";
         when Msg_Command_Pipe_New_Doc =>
            return "command.pipe_new.doc";
         when Msg_Command_Pipe_Errors_Into_Doc =>
            return "command.pipe_errors_into.doc";
         when Msg_Command_Pipe_Errors_Append_Doc =>
            return "command.pipe_errors_append.doc";
         when Msg_Command_Pipe_Errors_New_Doc =>
            return "command.pipe_errors_new.doc";
         when Msg_Command_Pipe_All_Into_Doc =>
            return "command.pipe_all_into.doc";
         when Msg_Command_Pipe_All_Append_Doc =>
            return "command.pipe_all_append.doc";
         when Msg_Command_Pipe_All_New_Doc =>
            return "command.pipe_all_new.doc";
         when Msg_Command_Pipe_Run_Doc       => return "command.pipe_run.doc";
         when Msg_Command_Start_Doc          => return "command.start.doc";
         when Msg_Command_Wait_Doc           => return "command.wait.doc";
         when Msg_Command_Stop_Doc           => return "command.stop.doc";
         when Msg_Command_Suspend_Doc      => return "command.suspend.doc";
         when Msg_Command_Foreground_Doc     => return "command.foreground.doc";
         when Msg_Command_Resume_Doc       => return "command.resume.doc";
         when Msg_Command_Settings_Doc      => return "command.settings.doc";
         when Msg_Command_Save_Settings_Doc =>
            return "command.save_settings.doc";
         when Msg_Command_Write_File_Doc    => return "command.write_file.doc";
         when Msg_Command_Make_Directory_Doc =>
            return "command.make_directory.doc";
         when Msg_Command_Remove_File_Doc =>
            return "command.remove_file.doc";
         when Msg_Command_Remove_Directory_Doc =>
            return "command.remove_directory.doc";
         when Msg_Command_Rename_Doc =>
            return "command.rename.doc";
         when Msg_Command_Copy_File_Doc =>
            return "command.copy_file.doc";
         when Msg_Command_On_Exit_Doc =>
            return "command.on_exit.doc";
         when Msg_Command_Append_File_Doc   =>
            return "command.append_file.doc";
         when Msg_Line_History_Entry         => return "line.history_entry";
         when Msg_Line_Forgotten             => return "line.forgotten";
         when Msg_Line_Diagnostic_At       => return "line.diagnostic_at";
         when Msg_Note_Declared_Here       => return "note.declared_here";
         when Msg_Note_First_Here          => return "note.first_here";
         when Msg_Line_Job_Started           => return "line.job_started";
         when Msg_Line_Job_Finished          => return "line.job_finished";
         when Msg_Line_Job_Signalled         => return "line.job_signalled";
         when Msg_Command_Source_Doc         => return "command.source.doc";
         when Msg_Command_Hint               => return "command.hint";
         when Msg_Line_Directory             => return "line.directory";
         when Msg_Line_Variable              => return "line.variable";
         when Msg_Line_Setting              => return "line.setting";
         when Msg_Line_Settings_Saved       => return "line.settings_saved";
         when Msg_Line_Job                   => return "line.job";
         when Msg_Line_Command_Entry         => return "line.command_entry";
         when Msg_Line_Version               => return "line.version";
         when Msg_Command_Wrong_Arguments    => return "error.command.wrong_arguments";
         when Msg_Command_Unavailable        => return "error.command.unavailable";
         when Msg_No_History_Here            => return "error.no_history_here";
         when Msg_History_Not_Forgotten      =>
            return "error.history_not_forgotten";
         when Msg_Empty_Pipeline             => return "error.empty_pipeline";
         when Msg_Too_Many_Kept              => return "error.too_many_kept";
         when Msg_Command_Bad_Assignment     => return "error.command.bad_assignment";
         when Msg_Script_Cycle               => return "error.script_cycle";
         when Msg_Signal_Interrupt         => return "signal.interrupt";
         when Msg_Signal_Quit              => return "signal.quit";
         when Msg_Signal_Terminate         => return "signal.terminate";
         when Msg_Signal_Kill              => return "signal.kill";
         when Msg_Signal_Hangup            => return "signal.hangup";
         when Msg_Signal_Stop              => return "signal.stop";
         when Msg_Signal_Terminal_Stop     => return "signal.terminal_stop";
         when Msg_Signal_Continue          => return "signal.continue";
         when Msg_Signal_Pipe              => return "signal.pipe";
         when Msg_Signal_Background_Read   => return "signal.background_read";
         when Msg_Signal_Background_Write  => return "signal.background_write";
         when Msg_Signal_Window_Change     => return "signal.window_change";
         when Msg_Signal_Child             => return "signal.child";
         when Msg_Job_State_Running        => return "job.state.running";
         when Msg_Job_State_Stopped        => return "job.state.stopped";
         when Msg_Job_State_Completed      => return "job.state.completed";
         when Msg_Capability_Signals       => return "capability.signals";
         when Msg_Capability_Job_Control   => return "capability.job_control";
         when Msg_Capability_Pseudo_Terminal => return "capability.pseudo_terminal";
         when Msg_Capability_Advisory_Locks => return "capability.advisory_locks";
         when Msg_Start_Reason_Host_Refused => return "start.reason.host_refused";
         when Msg_Start_Reason_Stream_Setup => return "start.reason.stream_setup";
         when Msg_Completion_Keyword         => return "completion.keyword";
         when Msg_Completion_Path            => return "completion.path";
         when Msg_Completion_Program         => return "completion.program";
         when Msg_Prompt_Primary             => return "prompt.primary";
         when Msg_Prompt_Continuation        => return "prompt.continuation";
         when Msg_Prompt_Failed              => return "prompt.failed";
         when Msg_Interactive_Line_Editing_Unavailable =>
            return "interactive.line-editing-unavailable";
         when Msg_Interactive_Read_Failed    => return "interactive.read-failed";
         when Msg_Setting_Color              => return "setting.color";
         when Msg_Setting_History_Enabled    => return "setting.history-enabled";
         when Msg_Setting_History_Limit      => return "setting.history-limit";
         when Msg_Setting_Read_Limit         => return "setting.read-limit";
         when Msg_Setting_Trace              => return "setting.trace";
         when Msg_Line_Traced                => return "line.traced";
         when Msg_Setting_Prompt_Directory   => return "setting.prompt-directory";
         when Msg_Setting_Prompt_Failure     => return "setting.prompt-failure";
         when Msg_Setting_Editing            => return "setting.editing";
         when Msg_Setting_Session_File       => return "setting.session-file";
         when Msg_Setting_History_Per_Session =>
            return "setting.history-per-session";
         when Msg_Setting_History_Ignore_Space =>
            return "setting.history-ignore-space";
         when Msg_Config_Unknown_Key         => return "config.unknown-key";
         when Msg_Setting_Unknown           => return "error.setting_unknown";
         when Msg_Config_Wrong_Type          => return "config.wrong-type";
         when Msg_Config_Out_Of_Range        => return "config.out-of-range";
         when Msg_Config_Bad_Choice          => return "config.bad-choice";
         when Msg_Config_Syntax              => return "config.syntax";
         when Msg_Config_Unreadable          => return "config.unreadable";
         when Msg_Config_Not_Text            => return "config.not-text";
         when Msg_Config_Too_Large           => return "config.too-large";
         when Msg_Config_Newer_Schema        => return "config.newer-schema";
         when Msg_Config_Migrated            => return "config.migrated";
         when Msg_History_Unreadable         => return "history.unreadable";
         when Msg_History_Damaged_Lines      => return "history.damaged-lines";
         when Msg_History_Not_Written        => return "history.not-written";
      end case;
   end Key;

   ------------------
   -- Placeholders --
   ------------------

   function Placeholders (Id : Message_Id) return Placeholder_Names is

      function N (Item : String) return US.Unbounded_String
        renames US.To_Unbounded_String;

   begin
      --  No `others`, for the same reason as Key: a message whose
      --  placeholders were never declared is a message nothing can check.
      case Id is
         when Msg_List_Alternatives
            | Msg_List_Parameters
            | Msg_List_Components
            | Msg_List_Values
            | Msg_List_Names
            | Msg_List_Statements
            | Msg_List_Arguments
            | Msg_List_Choices
            | Msg_List_Handlers
            | Msg_Application_Name
            | Msg_Application_Summary
            | Msg_Version_Prerelease_Notice
            | Msg_Usage
            | Msg_Usage_Options_Header
            | Msg_Usage_Option_Help
            | Msg_Usage_Option_Version
            | Msg_Usage_More
            | Msg_Usage_Script
            | Msg_Error_None
            | Msg_Execution_Cancelled
            | Msg_Module_Looked_As_Written
            | Msg_Module_Looked_Beside
            | Msg_Module_Looked_In_Modules
            | Msg_Signal_Interrupt
            | Msg_Signal_Quit
            | Msg_Signal_Terminate
            | Msg_Signal_Kill
            | Msg_Signal_Hangup
            | Msg_Signal_Stop
            | Msg_Signal_Terminal_Stop
            | Msg_Signal_Continue
            | Msg_Signal_Pipe
            | Msg_Signal_Background_Read
            | Msg_Signal_Background_Write
            | Msg_Signal_Window_Change
            | Msg_Signal_Child
            | Msg_Job_State_Running
            | Msg_Job_State_Stopped
            | Msg_Job_State_Completed
            | Msg_Capability_Signals
            | Msg_Capability_Job_Control
            | Msg_Capability_Pseudo_Terminal
            | Msg_Capability_Advisory_Locks
            | Msg_Start_Reason_Host_Refused
            | Msg_Start_Reason_Stream_Setup

            --  A case diagnostic points at the choice, the range or the
            --  alternative that is wrong, so the text has nothing to name that
            --  the extent does not already say.
            | Msg_Statement_Among_Declarations
            | Msg_String_Index_Malformed
            | Msg_Case_Choice_Not_Static
            | Msg_Case_Choice_Covered_Twice
            | Msg_Case_Range_Is_Empty
            | Msg_Case_Others_Not_Last
            | Msg_Note_Declared_Here
            | Msg_Note_First_Here =>
            return No_Placeholders;

         when Msg_Number_Not_A_Literal =>
            return [1 => N ("name")];

         when Msg_Number_Not_Numeric =>
            return [N ("name"), N ("found")];

         when Msg_Command_Not_Found
            | Msg_Command_Not_Executable
            | Msg_Command_Denied =>
            return [1 => N ("command")];

         when Msg_Command_Start_Failed =>
            return [N ("command"), N ("reason")];

         when Msg_Redirection_Open_Failed
            | Msg_Directory_Not_Found
            | Msg_Directory_Denied =>
            return [1 => N ("path")];

         when Msg_Module_Not_Found =>
            return [N ("name"), N ("where")];

         when Msg_Source_Unreadable | Msg_Source_Too_Large =>
            return [1 => N ("source")];

         when Msg_Source_Invalid_Encoding =>
            return [N ("source"), N ("offset")];

         when Msg_Type_Mismatch =>
            return [N ("found"), N ("expected")];

         when Msg_Name_Undeclared =>
            return [1 => N ("name")];

         when Msg_Name_Already_Declared =>
            return [1 => N ("name")];

         when Msg_Lexical_Stray_Character =>
            return [1 => N ("character")];

         when Msg_Lexical_Unterminated_String
            | Msg_Lexical_Unterminated_Character =>
            return No_Placeholders;

         when Msg_Lexical_Malformed_Number
            | Msg_Lexical_Malformed_Identifier
            | Msg_Lexical_Bad_Escape =>
            return [1 => N ("text")];

         when Msg_Lexical_Brace_Unescaped
            | Msg_Lexical_Quote_In_Interpolation =>
            return No_Placeholders;

         when Msg_Syntax_Unexpected =>
            return [N ("found"), N ("expected")];

         when Msg_Syntax_Missing =>
            return [1 => N ("expected")];

         when Msg_Syntax_Mixed_Logical =>
            return [N ("first"), N ("second")];

         when Msg_Not_Assignable
            | Msg_Not_A_Type
            | Msg_Not_Callable
            | Msg_Not_An_Exception
            | Msg_Function_As_Statement =>
            return [1 => N ("name")];

         when Msg_Exit_Outside_Loop
            | Msg_Return_Without_Value
            | Msg_Return_With_Value =>
            --  Nothing to name: neither statement has an identifier, and the
            --  statement itself is where the diagnostic points.
            return No_Placeholders;

         when Msg_Nested_Subprogram =>
            return [1 => N ("name")];

         when Msg_Actual_Not_Variable =>
            return [N ("position"), N ("mode")];

         when Msg_Attribute_Not_Defined =>
            return [N ("attribute"), N ("found")];

         when Msg_Name_Is_Predefined | Msg_Body_Missing =>
            return [1 => N ("name")];

         when Msg_No_Matching_Subprogram | Msg_Ambiguous_Call
            | Msg_Ambiguous_Literal =>
            return [N ("name"), N ("count")];

         when Msg_Condition_Not_Boolean
            | Msg_Case_Not_Discrete
            | Msg_Not_Taken_Apart
            | Msg_Case_Incomplete =>
            return [1 => N ("found")];

         when Msg_Operator_Not_Defined =>
            return [N ("operator"), N ("left"), N ("right")];

         when Msg_Program_Raised =>
            return [1 => N ("exception")];

         when Msg_Program_Raised_Detail =>
            return [N ("exception"), N ("detail")];

         when Msg_Not_Lowerable =>
            return [1 => N ("construct")];

         when Msg_Predefined_Type_Doc
            | Msg_Predefined_Clock_Doc | Msg_Predefined_Clock_Hint
            | Msg_Predefined_True_Doc
            | Msg_Predefined_False_Doc
            | Msg_Predefined_Put_Line_Doc
            | Msg_Predefined_Put_Doc
            | Msg_Predefined_New_Line_Doc | Msg_Predefined_Env_Value_Doc
            | Msg_Predefined_Env_Value_Hint
            | Msg_Predefined_Status_Doc | Msg_Predefined_Status_Hint
            | Msg_Predefined_Output_Of_Doc | Msg_Predefined_Output_Of_Hint
            | Msg_Predefined_Error_Of_Doc | Msg_Predefined_Error_Of_Hint
            | Msg_Predefined_All_Of_Doc | Msg_Predefined_All_Of_Hint
            | Msg_Predefined_Last_Job_Doc | Msg_Predefined_Last_Job_Hint
            | Msg_Predefined_Output_Of_Pipe_Doc | Msg_Predefined_Output_Of_Pipe_Hint
            | Msg_Predefined_Error_Of_Pipe_Doc | Msg_Predefined_Error_Of_Pipe_Hint
            | Msg_Predefined_All_Of_Pipe_Doc | Msg_Predefined_All_Of_Pipe_Hint
            | Msg_Predefined_Read_Line_Doc | Msg_Predefined_Read_Line_Hint
            | Msg_Predefined_Input_Ended_Doc
            | Msg_Predefined_Input_Ended_Hint
            | Msg_Predefined_Exists_Doc | Msg_Predefined_Exists_Hint
            | Msg_Predefined_Is_Directory_Doc | Msg_Predefined_Is_Directory_Hint
            | Msg_Predefined_Is_Executable_Doc
            | Msg_Predefined_Read_File_Doc | Msg_Predefined_Read_File_Hint
            | Msg_Predefined_Current_Directory_Doc
            | Msg_Predefined_Current_Directory_Hint
            | Msg_Predefined_File_Count_Doc | Msg_Predefined_File_Count_Hint
            | Msg_Predefined_File_At_Doc | Msg_Predefined_File_At_Hint
            | Msg_Predefined_Program_Path_Doc
            | Msg_Predefined_Program_Path_Hint
            | Msg_Predefined_Stage_Count_Doc | Msg_Predefined_Stage_Count_Hint
            | Msg_Predefined_Stage_Status_Doc
            | Msg_Predefined_Stage_Status_Hint
            | Msg_Predefined_Is_Executable_Hint
            | Msg_Predefined_Index_Doc | Msg_Predefined_Index_Hint
            | Msg_Predefined_Trim_Doc | Msg_Predefined_Trim_Hint
            | Msg_Predefined_To_Upper_Doc | Msg_Predefined_To_Upper_Hint
            | Msg_Predefined_To_Lower_Doc | Msg_Predefined_To_Lower_Hint
            | Msg_Predefined_Starts_With_Doc | Msg_Predefined_Starts_With_Hint
            | Msg_Predefined_Ends_With_Doc | Msg_Predefined_Ends_With_Hint
            | Msg_Predefined_Argument_Count_Doc
            | Msg_Predefined_Argument_Count_Hint
            | Msg_Predefined_Argument_Doc | Msg_Predefined_Argument_Hint
            | Msg_Predefined_Type_Hint
            | Msg_Predefined_Constant_Hint
            | Msg_Predefined_Put_Line_Hint
            | Msg_Predefined_Put_Hint
            | Msg_Predefined_New_Line_Hint =>
            return No_Placeholders;

         when Msg_No_Such_Parameter =>
            return [N ("name"), N ("parameter")];

         when Msg_Parameter_Given_Twice | Msg_Parameter_Not_Given =>
            return [N ("name"), N ("parameter")];

         when Msg_Positional_After_Named =>
            return [1 => N ("name")];

         when Msg_Default_Not_Literal | Msg_Default_Not_In_Mode =>
            return [1 => N ("name")];

         when Msg_Wrong_Argument_Count =>
            return [N ("name"), N ("expected"), N ("found")];

         when Msg_Not_Runnable_Yet =>
            return [1 => N ("name")];

         when Msg_Command_Cd_Doc | Msg_Command_Pwd_Doc | Msg_Command_Exit_Doc
            | Msg_Command_Set_Doc | Msg_Command_Unset_Doc | Msg_Command_Env_Doc
            | Msg_Command_Jobs_Doc | Msg_Command_Help_Doc
            | Msg_Command_Version_Doc | Msg_Command_History_Doc
            | Msg_Command_Forget_Doc
            | Msg_Command_Source_Doc
            | Msg_Command_Run_Doc | Msg_Command_Run_Into_Doc
            | Msg_Command_Run_From_Doc | Msg_Command_Run_Append_Doc
            | Msg_Command_Run_New_Doc | Msg_Command_Run_Errors_Into_Doc
            | Msg_Command_Run_Errors_Append_Doc
            | Msg_Command_Run_Errors_New_Doc
            | Msg_Command_Run_All_Into_Doc | Msg_Command_Run_All_Append_Doc
            | Msg_Command_Run_All_New_Doc
            | Msg_Command_Pipe_Doc
            | Msg_Command_Pipe_Start_Doc
            | Msg_Command_Pipe_From_Doc
            | Msg_Command_Pipe_Into_Doc
            | Msg_Command_Pipe_Append_Doc
            | Msg_Command_Pipe_New_Doc
            | Msg_Command_Pipe_Errors_Into_Doc
            | Msg_Command_Pipe_Errors_Append_Doc
            | Msg_Command_Pipe_Errors_New_Doc
            | Msg_Command_Pipe_All_Into_Doc
            | Msg_Command_Pipe_All_Append_Doc
            | Msg_Command_Pipe_All_New_Doc
            | Msg_Command_Pipe_Run_Doc
            | Msg_Command_Start_Doc | Msg_Command_Wait_Doc
            | Msg_Command_Stop_Doc
            | Msg_Command_Suspend_Doc | Msg_Command_Resume_Doc
            | Msg_Command_Foreground_Doc
            | Msg_Command_Settings_Doc | Msg_Command_Save_Settings_Doc
            | Msg_Command_Write_File_Doc | Msg_Command_Append_File_Doc
            | Msg_Command_Make_Directory_Doc
            | Msg_Command_Remove_File_Doc
            | Msg_Command_Remove_Directory_Doc
            | Msg_Command_Rename_Doc
            | Msg_Command_Copy_File_Doc | Msg_Command_On_Exit_Doc
            | Msg_Command_Hint =>
            return No_Placeholders;

         when Msg_Line_History_Entry =>
            return [N ("number"), N ("line")];

         when Msg_Line_Forgotten =>
            return [1 => N ("count")];

         when Msg_Line_Diagnostic_At =>
            return [N ("path"), N ("line"), N ("column"), N ("text")];

         when Msg_Line_Job_Started =>
            return [N ("id"), N ("what")];

         when Msg_Line_Job_Finished =>
            return [N ("id"), N ("status")];

         when Msg_Line_Job_Signalled =>
            return [N ("id"), N ("signal")];

         when Msg_Line_Directory =>
            return [1 => N ("path")];

         when Msg_Line_Settings_Saved =>
            return [1 => N ("path")];

         when Msg_Line_Setting =>
            return [N ("key"), N ("value"), N ("summary")];

         when Msg_Line_Variable =>
            return [N ("name"), N ("value")];

         when Msg_Line_Job =>
            return [N ("job"), N ("state"), N ("description")];

         when Msg_Line_Command_Entry =>
            return [N ("name"), N ("summary")];

         when Msg_Line_Version =>
            return [N ("name"), N ("version")];

         when Msg_Command_Wrong_Arguments =>
            return [N ("name"), N ("found")];

         when Msg_Command_Unavailable =>
            return [1 => N ("name")];

         when Msg_Too_Many_Kept =>
            return [N ("name"), N ("limit")];

         when Msg_Empty_Pipeline =>
            return No_Placeholders;

         when Msg_No_History_Here =>
            --  Nothing to name: the session is the subject, and it has no
            --  name a user would recognise.
            return No_Placeholders;

         when Msg_History_Not_Forgotten =>
            --  Which file it was is a question with two answers when a session
            --  keeps one of its own, and the user's problem is the same either
            --  way: the line is still on disk.
            return No_Placeholders;

         when Msg_Command_Bad_Assignment =>
            return [1 => N ("text")];

         when Msg_Script_Cycle =>
            return [1 => N ("source")];

         when Msg_Completion_Keyword | Msg_Completion_Path
            | Msg_Completion_Program
            | Msg_Prompt_Primary | Msg_Prompt_Continuation
            | Msg_Prompt_Failed
            | Msg_Interactive_Line_Editing_Unavailable
            | Msg_Interactive_Read_Failed
            | Msg_Setting_Color | Msg_Setting_History_Enabled
            | Msg_Setting_History_Limit | Msg_Setting_Read_Limit
            | Msg_Setting_Trace
            | Msg_Setting_Prompt_Directory
            | Msg_Setting_Prompt_Failure | Msg_Setting_Editing
            | Msg_Setting_Session_File
            | Msg_Setting_History_Per_Session
            | Msg_Setting_History_Ignore_Space =>
            return No_Placeholders;

         when Msg_Setting_Unknown =>
            return [1 => N ("key")];

         when Msg_Config_Unknown_Key =>
            return [N ("path"), N ("key")];

         when Msg_Config_Wrong_Type | Msg_Config_Bad_Choice =>
            return [N ("key"), N ("detail")];

         when Msg_Config_Out_Of_Range =>
            return [N ("key"), N ("detail")];

         when Msg_Config_Syntax =>
            return [N ("path"), N ("line"), N ("column"), N ("detail")];

         when Msg_Line_Traced =>
            return [1 => N ("command")];

         when Msg_Config_Unreadable | Msg_Config_Not_Text
            | Msg_Config_Too_Large =>
            return [1 => N ("path")];

         when Msg_Config_Newer_Schema | Msg_Config_Migrated =>
            return [N ("path"), N ("detail")];

         when Msg_History_Unreadable | Msg_History_Not_Written =>
            return [1 => N ("path")];

         when Msg_History_Damaged_Lines =>
            return [N ("path"), N ("detail")];

         when Msg_Redirection_Conflict =>
            return [1 => N ("stream")];

         when Msg_Pipe_Creation_Failed =>
            return No_Placeholders;

         when Msg_Stream_Write_Failed
            | Msg_Stream_Read_Failed =>
            return [1 => N ("stream")];

         when Msg_File_Not_Writable
            | Msg_File_Write_Failed | Msg_File_Too_Large =>
            return [1 => N ("path")];

         --  Named after what wrote it rather than where it was going: what a
         --  user does about this is run that program differently.
         when Msg_Output_Too_Large =>
            return [1 => N ("program")];

         when Msg_Machine_Stack_Full | Msg_Machine_Stack_Empty
            | Msg_Machine_No_Place | Msg_Machine_No_Value
            | Msg_Machine_No_Caller
            | Msg_Machine_Above_Ceiling | Msg_Machine_Blocking_In_Protected
            | Msg_Machine_Too_Many_Allowed | Msg_Machine_Queue_Too_Long
            | Msg_Machine_Too_Many_Alternatives
            | Msg_Machine_Task_Ran_Out
            | Msg_Machine_No_Store_Place
            | Msg_Machine_Swap_Empty | Msg_Machine_Not_A_Number
            | Msg_Machine_Arithmetic | Msg_Machine_Too_Many_Calls
            | Msg_Machine_No_Frame_Room | Msg_Machine_No_Return_To
            | Msg_Machine_No_Shell | Msg_Machine_Too_Many_Handlers
            | Msg_Machine_No_Return_Value | Msg_Machine_Not_A_Raise
            | Msg_Machine_Too_Many_Tasks | Msg_Machine_Tasks_Stuck
            | Msg_Machine_Task_Finished
            | Msg_Expected_Expression | Msg_Expected_Statement
            | Msg_Expected_Type_Name | Msg_Expected_Literal_Name
            | Msg_Expected_Component_Name | Msg_Expected_Package_Name
            | Msg_Expected_Task_Name
            | Msg_Expected_Parameter_Name
            | Msg_Expected_Loop_Variable | Msg_Expected_Subprogram_Name
            | Msg_Expected_Exception_Name | Msg_Expected_Attribute_Name
            | Msg_Expected_Interpolation_Rest | Msg_Expected_End_Of_Input
            | Msg_Lower_Call_Wrong_Count
            | Msg_Lower_Write_Back_Not_Variable | Msg_Lower_Float_Literal
            | Msg_Lower_Unresolved_Name | Msg_Lower_This_Operator
            | Msg_Lower_Float_Operation | Msg_Lower_Joining_Letters
            | Msg_Lower_String_Operation | Msg_Lower_String_Concatenation
            | Msg_Lower_Procedure_As_Value | Msg_Lower_This_Expression
            | Msg_Lower_Declaration_Unresolved | Msg_Lower_String_No_Value
            | Msg_Lower_Assignment_Unresolved | Msg_Lower_Case_Choice
            | Msg_Lower_Exit_Outside_Loop | Msg_Lower_Return_With_Value
            | Msg_Lower_This_Statement | Msg_Config_Wants_Truth
            | Msg_Config_Wants_Whole =>
            return No_Placeholders;

         when Msg_Lower_Variable_Of_Type | Msg_Lower_Arithmetic_On
            | Msg_Lower_Value_Of | Msg_Lower_Image_Of
            | Msg_Lower_Argument_Of_Type | Msg_Lower_Writing_Type =>
            return [1 => N ("type")];

         when Msg_Lower_Call_To | Msg_Lower_Call_In_Context =>
            return [1 => N ("name")];

         when Msg_Lower_Command_Arguments =>
            return [1 => N ("count")];

         when Msg_Config_Wants_Range =>
            return [N ("low"), N ("high")];

         when Msg_Config_Wants_Choice =>
            return [1 => N ("choices")];

         when Msg_Machine_Index_Outside =>
            return [N ("position"), N ("length")];

         when Msg_Machine_Slice_Outside =>
            return [N ("first"), N ("last"), N ("length")];

         when Msg_Machine_Slice_Lengths =>
            return [N ("wanted"), N ("given")];

         when Msg_No_Such_Slice =>
            return [N ("name"), N ("first"), N ("last")];

         when Msg_Needs_Bounds | Msg_Open_By_Element =>
            return [1 => N ("name")];

         when Msg_Too_Many_At_Once =>
            return [N ("what"), N ("limit")];

         when Msg_Too_Many_Parameters =>
            return [N ("name"), N ("limit")];

         when Msg_Machine_Bad_Value_Text =>
            return [1 => N ("text")];

         when Msg_Machine_Position_Outside | Msg_Machine_Outside_Bounds
            | Msg_Machine_Outside_Array =>
            return [N ("position"), N ("type")];

         when Msg_Subtype_Not_Discrete =>
            return [1 => N ("found")];

         when Msg_Subtype_Bound_Not_Static | Msg_Subtype_Range_Is_Empty =>
            return No_Placeholders;

         when Msg_Part_Not_Simple =>
            return [N ("name"), N ("found")];

         when Msg_Part_Given_Twice =>
            return [N ("name")];

         when Msg_Record_Is_Empty =>
            return [N ("name")];

         when Msg_Array_Bound_Not_Static =>
            return No_Placeholders;

         when Msg_Array_Is_Empty =>
            return [N ("name")];

         when Msg_Array_Too_Long =>
            return [N ("name"), N ("limit")];

         when Msg_Not_A_Record =>
            return [N ("name"), N ("found")];

         when Msg_No_Such_Component =>
            return [N ("name"), N ("found")];

         when Msg_Not_An_Array =>
            return [N ("found")];

         when Msg_Aggregate_Wrong_Count =>
            return [N ("name"), N ("expected"), N ("found")];

         when Msg_Aggregate_Not_Expected =>
            return [N ("found")];

         when Msg_Select_Alternative | Msg_Select_Waits_Twice
            | Msg_Select_Trigger | Msg_Terminate_Outside_Select
            | Msg_Raise_Outside_A_Handler
            | Msg_Aggregate_Others_Covers_Nothing =>
            return Placeholder_Names'(1 .. 0 => <>);

         when Msg_Discriminants_Need_A_Type | Msg_Nothing_To_Constrain
            | Msg_Count_Outside_Its_Unit | Msg_Is_A_Type
            | Msg_Requeue_Not_An_Entry | Msg_Requeue_Takes_Nothing
            | Msg_Family_Takes_Nothing
            | Msg_Not_A_Family | Msg_Family_Needs_A_Member
            | Msg_Cannot_Be_Copied | Msg_Identity_Needs_A_Task
            | Msg_Unknown_Pragma | Msg_Unknown_Restriction
            | Msg_Unknown_Policy | Msg_Unknown_Profile
            | Msg_Dispatching_Twice | Msg_Queuing_Twice
            | Msg_Restriction_Broken =>
            return [N ("name")];

         when Msg_Empty_Priority_Range =>
            return [N ("first"), N ("last")];

         when Msg_Priority_Not_Static =>
            return Placeholder_Names'(1 .. 0 => <>);

         when Msg_Family_Index_Not_Discrete =>
            return [N ("found")];

         when Msg_Discriminants_Wrong_Count =>
            return [N ("name"), N ("expected"), N ("found")];

         when Msg_Result_Not_Simple | Msg_Cannot_Write
            | Msg_Entry_Parameter_Not_Simple =>
            return [N ("name"), N ("found")];

         when Msg_Not_A_Package =>
            return [N ("name")];

         when Msg_Package_Not_Declared =>
            return [N ("name")];

         when Msg_Not_A_Generic =>
            return [N ("name")];

         when Msg_Generic_Wrong_Actuals =>
            return [N ("name"), N ("expected"), N ("found")];

         when Msg_Generic_Not_Callable | Msg_Not_A_Task | Msg_Not_An_Entry
            | Msg_Accept_Differs | Msg_Protected_Entry_Parameters =>
            return [N ("name")];

         when Msg_Job_Is_Suspended =>
            return [1 => N ("job")];

         when Msg_Job_Unknown =>
            return [1 => N ("job")];

         when Msg_Capability_Unavailable =>
            return [1 => N ("capability")];

         when Msg_Version_Line =>
            return [1 => N ("version")];

         when Msg_Version_Build =>
            return [N ("profile"), N ("os"), N ("arch")];

         when Msg_Unknown_Option =>
            return [1 => N ("option")];

         when Msg_Catalog_Unavailable =>
            return [1 => N ("path")];
      end case;
   end Placeholders;

   ---------------------
   -- To_Placeholder --
   ---------------------

   function To_Placeholder (Name : String) return Placeholder_Name is
      Result : Placeholder_Name := (others => ' ');
   begin
      if Name'Length >= Placeholder_Name'Length then
         Result := Name (Name'Last - Placeholder_Name'Length + 1 .. Name'Last);
      else
         Result (1 .. Name'Length) := Name;
      end if;

      return Result;
   end To_Placeholder;

   -----------------------
   -- From_Placeholder --
   -----------------------

   function From_Placeholder (Name : Placeholder_Name) return String is
   begin
      for Index in reverse Name'Range loop
         if Name (Index) /= ' ' then
            return Name (Name'First .. Index);
         end if;
      end loop;

      return "";
   end From_Placeholder;

   -----------
   -- Named --
   -----------

   function Named (Name : String; Value : String) return Argument is
   begin
      return (Name  => US.To_Unbounded_String (Name),
              Value => US.To_Unbounded_String (Value));
   end Named;

   ----------
   -- Name --
   ----------

   function Name (Item : Argument) return String is
   begin
      return US.To_String (Item.Name);
   end Name;

   -----------
   -- Value --
   -----------

   function Value (Item : Argument) return String is
   begin
      return US.To_String (Item.Value);
   end Value;

end Adash.Messages;

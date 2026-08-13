with AUnit.Test_Cases;

--  Tests for lowering to p-code and running it.
--
--  Observing a running program is the difficulty here: Adash has no output
--  statement yet, so nothing it runs can say what it computed. These tests use
--  division by zero as the observable instead — a program that reaches it
--  raises and one that does not runs clean. That turns "did the jump land in
--  the right place" into a yes-or-no answer, which is exactly the question a
--  code generator has to get right and the one that fails silently when it does
--  not.
package Adash_Tests.Evaluation_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  Name shown by the reporter.
   --
   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  Register the routines of this case.
   --
   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

   procedure Subprograms_Are_Called_And_Return
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Subprograms_Cannot_Do_Yet
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Parameters_Can_Be_Written_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Parameter_Modes_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Images_Turn_Values_Into_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Attributes_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Interpolation_Builds_Strings
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Interpolation_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure For_Loops_Follow_Adas_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Nested_Subprograms_See_Out
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Overloads_Are_Chosen_By_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Overloading_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Specifications_Precede_Bodies
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Specifications_Refuse
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Commands_Take_Several_Arguments
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Result_Type_Settles_An_Overload
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_Result_Overloading_Refuses
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Evaluation_Cases;

with AUnit.Test_Cases;

--  Tests for the lexer.
--
--  Ada's lexical rules have several corners where a plausible implementation is
--  quietly wrong, and each of these tests pins one of them: the apostrophe that
--  is sometimes a quote and sometimes an attribute marker, the dot that is
--  sometimes a decimal point and sometimes half of a range, the underscore that
--  is legal between digits and not beside them, and longest-match on compound
--  delimiters. None of these fails loudly when it is wrong; they produce a
--  different program.
package Adash_Tests.Lexer_Cases is

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

   procedure Interpolation_Escapes_Are_Adas
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Lexer_Cases;

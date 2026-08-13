with AUnit.Test_Cases;

--  Tests for the syntax tree and the parser.
--
--  Precedence and associativity are the substance here. A parser that gets them
--  wrong does not fail: it builds a tree that means something else, and the
--  program runs and gives an answer nobody can explain. So these tests assert
--  the *shape* of the tree rather than that parsing succeeded.
package Adash_Tests.Parser_Cases is

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

   procedure A_Statement_Spans_Only_Itself
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Parser_Cases;

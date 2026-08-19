with AUnit.Test_Cases;

--  Tests for Adash.Interactive.Prompt: what the shell puts in front of a line.
--
--  A prompt is a model here rather than a string -- parts with roles, which a
--  frontend renders -- so it can be asserted without a terminal. What matters
--  and is easy to get wrong: a user's own format is used exactly as written,
--  spacing included, while the built-in one puts a blank between its parts; a
--  failure marker appears only after a failure; and a `{word}` this shell does
--  not know stays the text it is rather than disappearing.
package Adash_Tests.Prompt_Cases is

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

end Adash_Tests.Prompt_Cases;

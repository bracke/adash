with AUnit.Test_Cases;

--  Tests for Adash.Interactive.
--
--  The interactive frontend is the part of a shell that runs thousands of
--  times a session and is never watched by a test, because the usual way to
--  exercise it is to sit in front of it. So the models are separated from the
--  terminal on purpose -- a buffer, a decoder, a history, a queue, a prompt --
--  and this is where they are held to their contracts.
--
--  Two properties are worth stating plainly, because both are the kind that
--  fails silently:
--
--    * the buffer's cursor never lands inside a UTF-8 character. If it does,
--      the next keystroke corrupts a letter and every position after it is
--      wrong;
--
--    * the key decoder asks for more bytes rather than guessing. An escape
--      sequence split across two reads is normal, and a decoder that treated
--      the first half as a keystroke would insert rubbish into the user's
--      line.
--
--  What is not tested here is the reader itself: it needs a real terminal in
--  raw mode, and a test that faked one would be testing the fake.
package Adash_Tests.Interactive_Cases is

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

   procedure Width_Counts_Cells_Not_Characters
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Wrapped_Line_Places_Its_Cursor
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Interactive_Cases;

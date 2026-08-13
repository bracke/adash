with AUnit.Test_Cases;

--  Tests for Adash.Persistence.
--
--  These touch the filesystem, because that is the whole subject: a store that
--  was tested against a fake would be tested against the fake's idea of what
--  replacing a file means, which is the one thing worth checking. Everything
--  is done under a temporary directory that is removed afterwards, and nothing
--  is written to the user's real configuration or history.
--
--  The properties that matter:
--
--    * **absence is not failure.** A shell starting for the first time finds no
--      files, and a store that could not tell that apart from "I am not allowed
--      to read it" would make the frontend report a problem where there is
--      none;
--
--    * **a write leaves either the old file or the new one.** Never half of
--      either. A shell writes its history at the end of every session, which is
--      exactly when a machine is most likely to be going down;
--
--    * **the history format holds anything that was typed**, including the
--      newlines that a line-per-entry file cannot.
package Adash_Tests.Persistence_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

   procedure A_Session_Can_Keep_Its_Own_History
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure An_Abandoned_Session_File_Is_Found
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

end Adash_Tests.Persistence_Cases;

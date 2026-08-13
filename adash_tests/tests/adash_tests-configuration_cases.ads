with AUnit.Test_Cases;

--  Tests for Adash.Configuration.
--
--  Two properties matter more than the rest, and both fail quietly:
--
--    * **a bad file never stops the shell.** Every path through the reader
--      leaves a usable set of settings. A shell that refused to start because
--      one line of its configuration was wrong would leave the user with no
--      shell to fix it with, at exactly the moment they need one;
--
--    * **a value that is refused keeps its default, and says so.** Clamping is
--      the tempting alternative and is worse: a history limit silently reduced
--      from a million to a thousand is a surprise the user gets much later,
--      when the entries they expected are missing and nothing ever said why.
--
--  The reader is tested through Read_From rather than through a file, so the
--  interesting cases -- malformed TOML, wrong types, unknown keys -- need no
--  filesystem and leave nothing behind when they fail.
package Adash_Tests.Configuration_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

end Adash_Tests.Configuration_Cases;

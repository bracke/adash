with Adash.Diagnostics;
with Adash.Persistence;

--  Reading and writing the configuration file.
--
--  TOML, through tomllib. Adash parses no TOML of its own, and a hand-rolled
--  reader for "just the simple cases" here would be a second implementation to
--  keep correct — and the simple cases are exactly the ones that stop being
--  simple the first time somebody quotes a key.
--
--  **A bad file never stops the shell.** Every problem is a diagnostic and the
--  setting keeps its default. A shell that refused to start because one line of
--  its configuration was wrong would leave the user with no shell to fix it
--  with, which is the worst possible moment to be short of one.
--
--  **Every problem names the key.** "Line 7 is wrong" makes the reader count
--  lines; `history.limit must be between 1 and 1000000` tells them what to
--  change. The key is in the diagnostic's arguments, so the message can be
--  translated and a test can assert the identity rather than the sentence.
--
--  **An unknown key is a warning, not an error.** A user with two versions of
--  Adash on two machines will share one file, and refusing the newer one's
--  settings would make that impossible. They are reported so a typo is still
--  visible.
package Adash.Configuration.Files is

   --  What the file is called inside the configuration store.
   File_Name : constant String := "config.toml";

   --  Where it lives.
   --
   --  @return The full path, or "" when this host has no configuration
   --          directory.
   function Path return String;

   --  Read settings from text.
   --
   --  Separate from Load so that the whole of this can be tested without a
   --  filesystem: the interesting behaviour is what happens to a malformed
   --  file, and a test that had to write one to disk first would be slower and
   --  would leave things behind when it failed.
   --
   --  @param Text The file's contents.
   --  @param Origin_Name What to call it in diagnostics -- a path, or a label.
   --  @param Into The settings. Starts from the defaults, so a key that is
   --         absent or wrong keeps the default rather than being unset.
   --  @param Report Where diagnostics go. Not cleared.
   procedure Read_From
     (Text        : String;
      Origin_Name : String;
      Into        : out Settings;
      Report      : in out Adash.Diagnostics.List);

   --  Read the configuration file.
   --
   --  @param Into The settings, defaults where the file is silent, and the
   --         defaults entirely when there is no file.
   --  @param Result Store_Absent when there is no file yet, which is the
   --         ordinary case for a first run and not a problem to report.
   --  @param Report Where diagnostics go.
   procedure Load
     (Into   : out Settings;
      Result : out Adash.Persistence.Outcome;
      Report : in out Adash.Diagnostics.List);

   --  Turn settings into the text of a file.
   --
   --  Only what differs from the defaults is written, plus the schema. A file
   --  listing every default would be four times the size, would have to be
   --  rewritten whenever a default changed, and would hide the two lines the
   --  user actually chose.
   --
   --  @param Item The settings.
   --  @return The file's contents, as UTF-8.
   function To_Text (Item : Settings) return String;

   --  Write the configuration file.
   --
   --  @param Item The settings.
   --  @param Result What became of it.
   procedure Save
     (Item   : Settings;
      Result : out Adash.Persistence.Outcome);

end Adash.Configuration.Files;

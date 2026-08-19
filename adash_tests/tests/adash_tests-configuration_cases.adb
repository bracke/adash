with AUnit.Assertions;

with Tomllib.Documents;
with Tomllib.Errors;
with Tomllib.Parsers;

with Adash.Configuration.Files;
with Adash.Configuration.Migration;
with Adash.Diagnostics;
with Adash.Messages;

package body Adash_Tests.Configuration_Cases is

   use AUnit.Assertions;

   package C renames Adash.Configuration;
   package F renames Adash.Configuration.Files;
   package M renames Adash.Configuration.Migration;
   package D renames Adash.Diagnostics;

   use type Adash.Messages.Message_Id;
   use type D.Severity;
   use type C.Setting_Kind;
   use type C.Setting_Id;

   Newline : constant Character := Character'Val (16#0A#);

   --  Whether a report contains a diagnostic with a given identifier.
   function Reported
     (Report : D.List; Which : Adash.Messages.Message_Id) return Boolean;

   function Reported
     (Report : D.List; Which : Adash.Messages.Message_Id) return Boolean
   is
   begin
      for Index in 1 .. Report.Count loop
         if D.Message (Report.Element (Index)) = Which then
            return True;
         end if;
      end loop;

      return False;
   end Reported;

   procedure Every_Setting_Is_Well_Formed
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Defaults_Are_What_The_Shell_Does
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Values_Are_Validated
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Good_File_Is_Read
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Bad_File_Never_Stops_The_Shell
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Unknown_Keys_Warn_Rather_Than_Fail
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Writing_Then_Reading_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Only_Changes_Are_Written
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Schema_Is_Read_And_Honoured
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ------------------------------------------
   -- Every_Setting_Is_Well_Formed --
   ------------------------------------------

   procedure Every_Setting_Is_Well_Formed
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      for Which in C.Setting_Id loop
         declare
            Name  : constant String := C.Key (Which);
            Found : C.Setting_Id;
         begin
            Assert (Name'Length > 0,
                    C.Setting_Id'Image (Which) & " has no key");

            --  Every key finds its way back to its setting. A key that did not
            --  would be one the reader could never match, so the setting would
            --  exist and be unconfigurable.
            Assert (C.Find (Name, Found) and then Found = Which,
                    "the key " & Name & " did not resolve to "
                    & C.Setting_Id'Image (Which));

            --  A description for each, because they are listed to the user and
            --  a missing one would show as a raw identifier.
            Assert (C.Description (Which) /= Adash.Messages.Msg_Error_None,
                    C.Setting_Id'Image (Which) & " has no description");

            case C.Kind (Which) is
               when C.Choice_Setting =>
                  Assert (C.Choice_Count (Which) > 1,
                          C.Setting_Id'Image (Which)
                          & " is a choice with fewer than two words");

               when C.Text_Setting =>
                  --  Free text has no list to check. What it must not do is
                  --  accept what a terminal would read as an instruction, and
                  --  the case below asks that of it.
                  null;

               when C.Integer_Setting =>
                  Assert (C.Minimum (Which) <= C.Maximum (Which),
                          C.Setting_Id'Image (Which)
                          & " has a minimum above its maximum");

               when C.Boolean_Setting =>
                  null;
            end case;
         end;
      end loop;

      --  And no two settings share a key, which Find would resolve silently in
      --  favour of whichever came first.
      for Left in C.Setting_Id loop
         for Right in C.Setting_Id loop
            if Left /= Right then
               Assert (C.Key (Left) /= C.Key (Right),
                       "two settings share the key " & C.Key (Left));
            end if;
         end loop;
      end loop;
   end Every_Setting_Is_Well_Formed;

   ----------------------------------------------
   -- Defaults_Are_What_The_Shell_Does --
   ----------------------------------------------

   procedure Defaults_Are_What_The_Shell_Does
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen : constant C.Settings := C.Defaults;
   begin
      --  Every default is a value the setting itself would accept. A default
      --  outside its own bounds is a setting nobody can restore.
      for Which in C.Setting_Id loop
         Assert (C.Is_Default (Chosen, Which),
                 "the defaults do not report themselves as default for "
                 & C.Setting_Id'Image (Which));

         case C.Kind (Which) is
            when C.Text_Setting =>
               Assert (C.Text_Value (Chosen, Which)'Length <= C.Maximum_Text,
                       "the default for " & C.Key (Which)
                       & " is longer than a text setting may be");

            when C.Integer_Setting =>
               Assert (C.Integer_Value (Chosen, Which) >= C.Minimum (Which)
                       and then C.Integer_Value (Chosen, Which)
                                <= C.Maximum (Which),
                       "the default for " & C.Key (Which)
                       & " is outside its own bounds");

            when C.Choice_Setting =>
               declare
                  Word  : constant String := C.Choice_Value (Chosen, Which);
                  Known : Boolean := False;
               begin
                  for Index in 1 .. C.Choice_Count (Which) loop
                     Known := Known or else C.Choice_At (Which, Index) = Word;
                  end loop;

                  Assert (Known,
                          "the default for " & C.Key (Which)
                          & " is not one of its own words: " & Word);
               end;

            when C.Boolean_Setting =>
               null;
         end case;
      end loop;

      --  The shape of the defaults, stated so that changing one is a decision
      --  rather than an accident. These are what a first-time user gets.
      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "auto",
              "colour did not default to auto");
      Assert (C.Boolean_Value (Chosen, C.History_Enabled_Setting),
              "history did not default to on");
      Assert (C.Boolean_Value (Chosen, C.Editing_Setting),
              "line editing did not default to on");

      --  On, because a protection that has to be switched on first is off in
      --  the session where it was needed.
      Assert (C.Boolean_Value (Chosen, C.History_Ignore_Space_Setting),
              "the leading-space mark did not default to honoured");
   end Defaults_Are_What_The_Shell_Does;

   -------------------------------
   -- Values_Are_Validated --
   -------------------------------

   procedure Values_Are_Validated
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen : C.Settings := C.Defaults;
   begin
      Assert (C.Set_Integer (Chosen, C.History_Limit_Setting, 50),
              "a value inside the bounds was refused");
      Assert (C.Integer_Value (Chosen, C.History_Limit_Setting) = 50,
              "the accepted value did not take");
      Assert (not C.Is_Default (Chosen, C.History_Limit_Setting),
              "a changed setting still reported itself as default");

      --  Refused, not clamped: a limit silently reduced is a surprise the user
      --  gets much later, when entries they expected are missing.
      Assert (not C.Set_Integer (Chosen, C.History_Limit_Setting, 0),
              "a value below the minimum was accepted");
      Assert (C.Integer_Value (Chosen, C.History_Limit_Setting) = 50,
              "a refused value changed the setting anyway");

      Assert (not C.Set_Integer (Chosen, C.History_Limit_Setting,
                                 C.Maximum (C.History_Limit_Setting) + 1),
              "a value above the maximum was accepted");

      Assert (C.Set_Choice (Chosen, C.Color_Setting, "never"),
              "a word the setting offers was refused");
      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "never",
              "the accepted word did not take");

      --  Case does not matter for a word the user types into a file; the
      --  stored form is the canonical one, so everything downstream compares
      --  against one spelling.
      Assert (C.Set_Choice (Chosen, C.Color_Setting, "ALWAYS"),
              "a word in the wrong case was refused");
      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "always",
              "the word was not folded to its canonical form");

      Assert (not C.Set_Choice (Chosen, C.Color_Setting, "sometimes"),
              "a word the setting does not offer was accepted");
      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "always",
              "a refused word changed the setting anyway");
   end Values_Are_Validated;

   ------------------------------
   -- A_Good_File_Is_Read --
   ------------------------------

   procedure A_Good_File_Is_Read
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen : C.Settings;
      Report : D.List;
   begin
      F.Read_From
        ("color = ""never""" & Newline
         & "[history]" & Newline
         & "enabled = false" & Newline
         & "limit = 25" & Newline
         & "[prompt]" & Newline
         & "directory = false" & Newline,
         "<test>", Chosen, Report);

      Assert (Report.Count = 0,
              "a good file produced" & Natural'Image (Report.Count)
              & " diagnostics");

      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "never",
              "a top-level key was not read");
      Assert (not C.Boolean_Value (Chosen, C.History_Enabled_Setting),
              "a key under a table header was not read");
      Assert (C.Integer_Value (Chosen, C.History_Limit_Setting) = 25,
              "an integer under a table header was not read");
      Assert (not C.Boolean_Value (Chosen, C.Prompt_Directory_Setting),
              "a key under a second table header was not read");

      --  What the file did not mention keeps its default rather than being
      --  unset. A configuration file is a set of changes, not a complete state.
      Assert (C.Boolean_Value (Chosen, C.Editing_Setting),
              "a setting the file did not mention lost its default");

      --  And an empty file is a valid one.
      declare
         Empty  : C.Settings;
         Silent : D.List;
      begin
         F.Read_From ("", "<test>", Empty, Silent);
         Assert (Silent.Count = 0, "an empty file produced diagnostics");

         for Which in C.Setting_Id loop
            Assert (C.Is_Default (Empty, Which),
                    "an empty file changed " & C.Key (Which));
         end loop;
      end;
   end A_Good_File_Is_Read;

   --------------------------------------------------
   -- A_Bad_File_Never_Stops_The_Shell --
   --------------------------------------------------

   procedure A_Bad_File_Never_Stops_The_Shell
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      procedure Survives (Text : String; Expect : Adash.Messages.Message_Id);

      procedure Survives (Text : String; Expect : Adash.Messages.Message_Id) is
         Chosen : C.Settings;
         Report : D.List;
      begin
         F.Read_From (Text, "<test>", Chosen, Report);

         Assert (Reported (Report, Expect),
                 "reading [" & Text & "] did not report "
                 & Adash.Messages.Key (Expect));

         --  The point of the whole test: whatever was wrong, there are usable
         --  settings afterwards. A shell that would not start because of one
         --  line would leave the user with no shell to fix it with.
         Assert (C.Choice_Value (Chosen, C.Color_Setting)'Length > 0,
                 "a bad file left the settings unusable");
      end Survives;

   begin
      --  Not TOML at all.
      Survives ("this is not toml", Adash.Messages.Msg_Config_Syntax);
      Survives ("color = ", Adash.Messages.Msg_Config_Syntax);

      --  A setting given the wrong sort of value.
      Survives ("color = 1", Adash.Messages.Msg_Config_Wrong_Type);
      Survives ("[history]" & Newline & "limit = ""many""",
                Adash.Messages.Msg_Config_Wrong_Type);
      Survives ("[history]" & Newline & "enabled = 1",
                Adash.Messages.Msg_Config_Wrong_Type);

      --  A number outside the setting's range, and a word it does not offer.
      Survives ("[history]" & Newline & "limit = 0",
                Adash.Messages.Msg_Config_Out_Of_Range);
      Survives ("color = ""puce""", Adash.Messages.Msg_Config_Bad_Choice);

      --  And a setting that was refused keeps its default rather than being
      --  half-applied.
      declare
         Chosen : C.Settings;
         Report : D.List;
      begin
         F.Read_From ("[history]" & Newline & "limit = 0",
                      "<test>", Chosen, Report);
         Assert (C.Is_Default (Chosen, C.History_Limit_Setting),
                 "a refused value did not leave the default in place");
      end;
   end A_Bad_File_Never_Stops_The_Shell;

   ----------------------------------------------------
   -- Unknown_Keys_Warn_Rather_Than_Fail --
   ----------------------------------------------------

   procedure Unknown_Keys_Warn_Rather_Than_Fail
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen : C.Settings;
      Report : D.List;
   begin
      F.Read_From
        ("color = ""never""" & Newline
         & "invented = 1" & Newline
         & "[history]" & Newline
         & "enabled = false" & Newline
         & "invented_too = true" & Newline,
         "<test>", Chosen, Report);

      Assert (Reported (Report, Adash.Messages.Msg_Config_Unknown_Key),
              "an unknown key was not reported");

      --  A warning rather than an error: a user with two versions of Adash on
      --  two machines will share one file, and refusing the newer one's
      --  settings would make that impossible.
      for Index in 1 .. Report.Count loop
         if D.Message (Report.Element (Index))
            = Adash.Messages.Msg_Config_Unknown_Key
         then
            Assert (D.Level (Report.Element (Index)) = D.Severity_Warning,
                    "an unknown key was reported as "
                    & D.Severity'Image (D.Level (Report.Element (Index))));
         end if;
      end loop;

      --  And the keys that were recognised still took effect, including the
      --  one after the unknown key inside the same table.
      Assert (C.Choice_Value (Chosen, C.Color_Setting) = "never",
              "an unknown key stopped a good one being read");
      Assert (not C.Boolean_Value (Chosen, C.History_Enabled_Setting),
              "an unknown key inside a table stopped a good one being read");
   end Unknown_Keys_Warn_Rather_Than_Fail;

   ------------------------------------------------
   -- Writing_Then_Reading_Round_Trips --
   ------------------------------------------------

   procedure Writing_Then_Reading_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen : C.Settings := C.Defaults;
      Again  : C.Settings;
      Report : D.List;

      Ignored : Boolean;
   begin
      Ignored := C.Set_Choice (Chosen, C.Color_Setting, "never");
      Ignored := C.Set_Integer (Chosen, C.History_Limit_Setting, 7);
      C.Set_Boolean (Chosen, C.Prompt_Directory_Setting, False);
      C.Set_Boolean (Chosen, C.Editing_Setting, False);

      declare
         Written : constant String := F.To_Text (Chosen);
      begin
         F.Read_From (Written, "<test>", Again, Report);

         Assert (Report.Count = 0,
                 "our own output did not read back cleanly:"
                 & Newline & Written);

         for Which in C.Setting_Id loop
            case C.Kind (Which) is
               when C.Text_Setting =>
                  Assert (C.Text_Value (Again, Which)
                          = C.Text_Value (Chosen, Which),
                          C.Key (Which) & " did not survive the round trip");

               when C.Boolean_Setting =>
                  Assert (C.Boolean_Value (Again, Which)
                          = C.Boolean_Value (Chosen, Which),
                          C.Key (Which) & " did not survive the round trip");

               when C.Integer_Setting =>
                  Assert (C.Integer_Value (Again, Which)
                          = C.Integer_Value (Chosen, Which),
                          C.Key (Which) & " did not survive the round trip");

               when C.Choice_Setting =>
                  Assert (C.Choice_Value (Again, Which)
                          = C.Choice_Value (Chosen, Which),
                          C.Key (Which) & " did not survive the round trip");
            end case;
         end loop;
      end;
   end Writing_Then_Reading_Round_Trips;

   ------------------------------------
   -- Only_Changes_Are_Written --
   ------------------------------------

   procedure Only_Changes_Are_Written
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chosen  : C.Settings := C.Defaults;
      Ignored : Boolean;

      function Mentions (Text : String; Fragment : String) return Boolean;

      function Mentions (Text : String; Fragment : String) return Boolean is
      begin
         if Fragment'Length > Text'Length then
            return False;
         end if;

         for Start in Text'First .. Text'Last - Fragment'Length + 1 loop
            if Text (Start .. Start + Fragment'Length - 1) = Fragment then
               return True;
            end if;
         end loop;

         return False;
      end Mentions;

   begin
      declare
         Written : constant String := F.To_Text (Chosen);
      begin
         --  Nothing but the schema. A file listing every default would be four
         --  times the size, would need rewriting whenever a default changed,
         --  and would bury the lines the user actually chose.
         Assert (Mentions (Written, "schema"),
                 "the written file did not record its schema");
         Assert (not Mentions (Written, "color"),
                 "an unchanged setting was written:" & Newline & Written);
         Assert (not Mentions (Written, "history"),
                 "an unchanged group was written:" & Newline & Written);
      end;

      Ignored := C.Set_Integer (Chosen, C.History_Limit_Setting, 7);

      declare
         Written : constant String := F.To_Text (Chosen);
      begin
         Assert (Mentions (Written, "limit"),
                 "a changed setting was not written:" & Newline & Written);

         --  Under a header rather than as a dotted line, which is what a person
         --  editing the file expects to see.
         Assert (Mentions (Written, "[history]"),
                 "a dotted key was not written under its header:"
                 & Newline & Written);
         Assert (not Mentions (Written, "color"),
                 "an unchanged setting was written alongside a changed one");
      end;
   end Only_Changes_Are_Written;

   -----------------------------------------
   -- Schema_Is_Read_And_Honoured --
   -----------------------------------------

   procedure Schema_Is_Read_And_Honoured
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      function Schema_In (Text : String) return Natural;

      function Schema_In (Text : String) return Natural is
         Document : Tomllib.Documents.Document;
         Error    : Tomllib.Errors.Error_Info;
      begin
         Tomllib.Parsers.Parse (Text, Document, Error);
         Assert (not Tomllib.Errors.Failed (Error),
                 "the sample did not parse: " & Text);
         return M.Schema_Of (Document);
      end Schema_In;

   begin
      --  A file with no schema key is current. Hand-written files are the
      --  common case and nobody should have to write a version number to
      --  configure a shell.
      Assert (Schema_In ("color = ""never""") = M.Current_Schema,
              "a file with no schema was not treated as current");

      --  A schema key that is not a whole number is a mistake in a file
      --  somebody wrote by hand; guessing low would migrate settings that
      --  never needed it.
      Assert (Schema_In ("schema = ""one""") = M.Current_Schema,
              "a non-numeric schema was not treated as current");
      Assert (Schema_In ("schema = -1") = M.Current_Schema,
              "a negative schema was not treated as current");

      Assert (Schema_In ("schema = 1") = 1, "schema 1 was not read as 1");
      Assert (M.Is_Newer (Schema_In ("schema = 99")),
              "a newer schema was not recognised");
      Assert (not M.Is_Newer (Schema_In ("schema = 1")),
              "the current schema was called newer");

      --  The rename table and the schema number have to move together: a
      --  rename added without a bump means older files silently lose the
      --  setting, and a bump without a rename means nothing at all.
      Assert (M.Rename_Count = M.Current_Schema - 1,
              "the rename table has" & Natural'Image (M.Rename_Count)
              & " entries for schema" & Natural'Image (M.Current_Schema));

      --  A newer file is read as far as it can be, and warned about, rather
      --  than refused: a user with two machines will share one file.
      declare
         Chosen : C.Settings;
         Report : D.List;
      begin
         F.Read_From ("schema = 99" & Newline & "color = ""never""",
                      "<test>", Chosen, Report);

         Assert (Reported (Report, Adash.Messages.Msg_Config_Newer_Schema),
                 "a newer schema was not reported");
         Assert (C.Choice_Value (Chosen, C.Color_Setting) = "never",
                 "a newer file's recognised settings were not honoured");
      end;

      --  And the schema key itself is never reported as an unknown setting,
      --  which would make every written file complain about itself.
      declare
         Chosen : C.Settings;
         Report : D.List;
      begin
         F.Read_From ("schema = 1", "<test>", Chosen, Report);
         Assert (not Reported (Report, Adash.Messages.Msg_Config_Unknown_Key),
                 "the schema key was reported as an unknown setting");
      end;
   end Schema_Is_Read_And_Honoured;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Configuration");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Every_Setting_Is_Well_Formed'Access,
                        "every setting has a unique key and a description");
      Register_Routine (T, Defaults_Are_What_The_Shell_Does'Access,
                        "every default is a value its own setting accepts");
      Register_Routine (T, Values_Are_Validated'Access,
                        "a value out of range is refused, not clamped");
      Register_Routine (T, A_Good_File_Is_Read'Access,
                        "a well-formed file is read, silently");
      Register_Routine (T, A_Bad_File_Never_Stops_The_Shell'Access,
                        "every kind of bad file still leaves usable settings");
      Register_Routine (T, Unknown_Keys_Warn_Rather_Than_Fail'Access,
                        "an unknown key warns and the rest is still read");
      Register_Routine (T, Writing_Then_Reading_Round_Trips'Access,
                        "settings written and read back are the same settings");
      Register_Routine (T, Only_Changes_Are_Written'Access,
                        "only what the user changed is written to the file");
      Register_Routine (T, Schema_Is_Read_And_Honoured'Access,
                        "the schema is read, and migration moves with it");
   end Register_Tests;

end Adash_Tests.Configuration_Cases;

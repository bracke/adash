with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Hostkit.Signals;

with Adash.Execution;
with Adash.Execution.Jobs;
with Adash.Messages;
with Adash.Platform;
with Adash.Messages.Rendering;

package body Adash_Tests.Message_Cases is

   use AUnit.Assertions;

   package Msg renames Adash.Messages;
   package Render renames Adash.Messages.Rendering;
   package Fixed renames Ada.Strings.Fixed;
   package US renames Ada.Strings.Unbounded;

   use type Msg.Message_Id;

   function Sample_Value (Index : Positive) return String;
   --  A distinct filler value for the Index'th placeholder of a message.

   ------------------
   -- Sample_Value --
   ------------------

   function Sample_Value (Index : Positive) return String is
      Image : constant String := Positive'Image (Index);
   begin
      return "value" & Image (Image'First + 1 .. Image'Last);
   end Sample_Value;

   --  Relative to the adash_tests directory, which is where `alr test` and
   --  the documented invocation both run from. Repository-relative rather
   --  than absolute: a developer-specific path in a test is a test that
   --  passes only on the machine it was written on.
   Catalog_Path : constant String := "../resources/messages/catalog.txt";

   procedure Keys_Are_Unique (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Keys_Are_Well_Formed (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Arguments_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Fallback_Names_The_Key (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Absent_Catalog_Degrades (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Message_Can_Quote_One (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Every_Name_Below_Has_Words (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Real_Catalog_Renders (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Every_Identifier_Renders (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------
   -- Keys_Are_Unique --
   ---------------------

   procedure Keys_Are_Unique (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Quadratic, over an enumeration with a few dozen literals. The
      --  alternative -- a set -- would need a hash and would not be clearer
      --  at this size.
      for Left in Msg.Message_Id loop
         for Right in Msg.Message_Id loop
            if Left /= Right then
               Assert (Msg.Key (Left) /= Msg.Key (Right),
                       "two identifiers share the key " & Msg.Key (Left) & ": "
                       & Msg.Message_Id'Image (Left) & " and "
                       & Msg.Message_Id'Image (Right));
            end if;
         end loop;
      end loop;
   end Keys_Are_Unique;

   -----------------------------
   -- Keys_Are_Well_Formed --
   -----------------------------

   procedure Keys_Are_Well_Formed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for Id in Msg.Message_Id loop
         declare
            Value : constant String := Msg.Key (Id);
         begin
            Assert (Value'Length > 0,
                    "empty key for " & Msg.Message_Id'Image (Id));

            --  The catalog format is `locale.key = text`, so a key carrying a
            --  blank or an equals sign produces a line that parses as
            --  something else entirely -- and does so silently.
            for Index in Value'Range loop
               Assert (Value (Index) /= ' ' and then Value (Index) /= '=',
                       "key contains a blank or an equals sign: " & Value);
            end loop;
         end;
      end loop;
   end Keys_Are_Well_Formed;

   -----------------------------
   -- Arguments_Round_Trip --
   -----------------------------

   procedure Arguments_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Item : constant Msg.Argument := Msg.Named ("version", "0.1.0-dev");
   begin
      Assert (Msg.Name (Item) = "version", "argument name did not round-trip");
      Assert (Msg.Value (Item) = "0.1.0-dev", "argument value did not round-trip");
      Assert (Msg.No_Arguments'Length = 0, "No_Arguments is not empty");
   end Arguments_Round_Trip;

   -------------------------------
   -- Fallback_Names_The_Key --
   -------------------------------

   procedure Fallback_Names_The_Key (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  The exact form is part of the contract, not a debugging
      --  convenience: it is what a user sees when the catalog is gone, and
      --  what a support request will quote back.
      Assert (Render.Fallback_Text ("version.line") = "!version.line!",
              "fallback form for an argumentless message changed: "
              & Render.Fallback_Text ("version.line"));

      Assert (Render.Fallback_Text
                ("version.line", [1 => Msg.Named ("version", "9.9.9")])
              = "!version.line{version=9.9.9}!",
              "fallback form with one argument changed: "
              & Render.Fallback_Text
                  ("version.line", [1 => Msg.Named ("version", "9.9.9")]));

      Assert (Render.Fallback_Text
                ("k", [Msg.Named ("a", "1"), Msg.Named ("b", "2")])
              = "!k{a=1,b=2}!",
              "fallback form with two arguments changed");
   end Fallback_Names_The_Key;

   ---------------------------------
   -- Absent_Catalog_Degrades --
   ---------------------------------

   procedure Absent_Catalog_Degrades (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Catalog : Render.Catalog;
   begin
      Catalog.Open (Catalog_Path => "./does-not-exist/catalog.txt");

      Assert (not Catalog.Is_Ready, "a missing catalog reported itself ready");

      --  The point of the design: a lookup still answers. A shell that cannot
      --  load its catalog must still be able to say so.
      Assert (Catalog.Text (Msg.Msg_Application_Name) = "!application.name!",
              "a missing catalog did not fall back: "
              & Catalog.Text (Msg.Msg_Application_Name));

      Assert (Catalog.Path = "./does-not-exist/catalog.txt",
              "the catalog did not remember the path it tried");

      Catalog.Close;
   end Absent_Catalog_Degrades;

   ------------------------------
   -- Real_Catalog_Renders --
   ------------------------------

   procedure Real_Catalog_Renders (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Catalog : Render.Catalog;
   begin
      --  Pinned to a locale so the result does not depend on the developer's
      --  environment. Without this the test reads LANG and fails for whoever
      --  has it set to something the catalog does not carry.
      Catalog.Open (Catalog_Path => Catalog_Path, Requested_Locale => "en");

      Assert (Catalog.Is_Ready,
              "the repository catalog did not load from " & Catalog_Path);
      Assert (Catalog.Text (Msg.Msg_Application_Name) = "adash",
              "application.name did not render as adash: "
              & Catalog.Text (Msg.Msg_Application_Name));

      --  Argument substitution, which is the part that silently produces a
      --  half-sentence when a placeholder name drifts.
      declare
         Rendered : constant String :=
           Catalog.Text (Msg.Msg_Version_Line, [1 => Msg.Named ("version", "1.2.3")]);
      begin
         Assert (Rendered = "adash 1.2.3",
                 "version.line did not substitute its argument: " & Rendered);
      end;

      Catalog.Close;
   end Real_Catalog_Renders;

   ------------------------------
   -- A_Message_Can_Quote_One --
   ------------------------------

   procedure A_Message_Can_Quote_One (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Catalog : Render.Catalog;
   begin
      Catalog.Open (Catalog_Path => Catalog_Path, Requested_Locale => "en");
      Assert (Catalog.Is_Ready, "the repository catalog did not load");

      --  What `help` needs: a subsystem below the presentation boundary may
      --  name a message and may not render one, so a line that has to say what
      --  another message says carries the identifier and the two become text
      --  here.
      declare
         Rendered : constant String :=
           Catalog.Text (Msg.Msg_Line_Command_Entry,
                         [1 => Msg.Named ("name", "pwd")],
                         Msg.Msg_Command_Pwd_Doc, "summary");
      begin
         Assert (Rendered = "pwd  " & Catalog.Text (Msg.Msg_Command_Pwd_Doc),
                 "a quoted message did not reach the outer one: " & Rendered);
      end;

      --  Nothing quoted, so a caller rendering lines that may or may not carry
      --  one does not need two call sites.
      Assert (Catalog.Text (Msg.Msg_Application_Name, Msg.No_Arguments,
                            Msg.Msg_Error_None, "summary")
              = Catalog.Text (Msg.Msg_Application_Name),
              "quoting nothing changed the result");

      Catalog.Close;

      --  Both halves degrade rather than one silently disappearing: a catalog
      --  that cannot answer for either still says which one it was.
      Catalog.Open (Catalog_Path => "./does-not-exist/catalog.txt");

      declare
         Rendered : constant String :=
           Catalog.Text (Msg.Msg_Line_Command_Entry,
                         [1 => Msg.Named ("name", "pwd")],
                         Msg.Msg_Command_Pwd_Doc, "summary");
      begin
         Assert (Fixed.Index (Rendered, "line.command_entry") > 0
                   and then Fixed.Index (Rendered, "command.pwd.doc") > 0,
                 "a quoted message lost one of its keys in the fallback: "
                 & Rendered);
      end;

      Catalog.Close;
   end A_Message_Can_Quote_One;

   -------------------------------------
   -- Every_Name_Below_Has_Words --
   -------------------------------------

   procedure Every_Name_Below_Has_Words (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Catalog : Render.Catalog;
   begin
      Catalog.Open (Catalog_Path => Catalog_Path, Requested_Locale => "en");
      Assert (Catalog.Is_Ready, "the repository catalog did not load");

      --  Every signal, job state and capability the shell can name has words
      --  to say it in. The mappings have no `others`, so a value added below
      --  fails to compile rather than reaching a user as its identifier -- and
      --  this checks the other direction, that the message it names renders.
      for Item in Hostkit.Signals.Signal loop
         declare
            Said : constant String :=
              Catalog.Text (Adash.Execution.Message (Item));
         begin
            Assert (Said'Length > 0 and then Said (Said'First) /= '!',
                    "a signal has no words: " & Said);
         end;
      end loop;

      for Item in Adash.Execution.Jobs.Job_State loop
         declare
            Said : constant String :=
              Catalog.Text (Adash.Execution.Jobs.Message (Item));
         begin
            Assert (Said'Length > 0 and then Said (Said'First) /= '!',
                    "a job state has no words: " & Said);
         end;
      end loop;

      for Item in Adash.Platform.Capability loop
         declare
            Said : constant String :=
              Catalog.Text (Adash.Platform.Message (Item));
         begin
            Assert (Said'Length > 0 and then Said (Said'First) /= '!',
                    "a capability has no words: " & Said);
         end;
      end loop;

      Catalog.Close;
   end Every_Name_Below_Has_Words;

   ----------------------------------
   -- Every_Identifier_Renders --
   ----------------------------------

   procedure Every_Identifier_Renders (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Catalog : Render.Catalog;
   begin
      Catalog.Open (Catalog_Path => Catalog_Path, Requested_Locale => "en");
      Assert (Catalog.Is_Ready, "the repository catalog did not load");

      --  adash_check asserts that every key is present in the catalog file.
      --  This asserts the stronger property that it also renders, given the
      --  placeholders the message itself declares -- which catches a key that
      --  exists but whose message is malformed, and a declared placeholder
      --  the catalog entry does not actually use, neither of which a textual
      --  check can see.
      for Id in Msg.Message_Id loop
         declare
            Names : constant Msg.Placeholder_Names := Msg.Placeholders (Id);

            --  A distinct value per placeholder, so a catalog entry that
            --  substitutes the wrong one is visible rather than
            --  self-consistent.
            Values : Msg.Argument_List (Names'Range);
         begin
            for Index in Names'Range loop
               Values (Index) :=
                 Msg.Named (US.To_String (Names (Index)), Sample_Value (Index));
            end loop;

            declare
               Text : constant String := Catalog.Text (Id, Values);
            begin
               Assert (Text /= Render.Fallback_Text (Msg.Key (Id), Values),
                       "identifier " & Msg.Message_Id'Image (Id)
                       & " fell back to its key; the catalog entry for "
                       & Msg.Key (Id)
                       & " is missing, malformed, or does not accept the"
                       & " placeholders the identifier declares");

               --  Every declared placeholder must actually be consumed. One
               --  that is declared but unused leaves its value nowhere, and
               --  callers go on supplying it for ever.
               for Index in Names'Range loop
                  Assert
                    (Fixed.Index (Text, Sample_Value (Index)) > 0,
                     "identifier " & Msg.Message_Id'Image (Id)
                     & " declares placeholder " & US.To_String (Names (Index))
                     & " but the catalog entry does not substitute it");
               end loop;
            end;
         end;
      end loop;

      Catalog.Close;
   end Every_Identifier_Renders;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Messages");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Keys_Are_Unique'Access, "identifier keys are unique");
      Register_Routine (T, Keys_Are_Well_Formed'Access, "identifier keys are well formed");
      Register_Routine (T, Arguments_Round_Trip'Access, "arguments round-trip");
      Register_Routine (T, Fallback_Names_The_Key'Access, "the fallback form names the key");
      Register_Routine (T, Absent_Catalog_Degrades'Access, "an absent catalog degrades");
      Register_Routine (T, Real_Catalog_Renders'Access, "the repository catalog renders");
      Register_Routine (T, A_Message_Can_Quote_One'Access, "a message can quote another");
      Register_Routine (T, Every_Name_Below_Has_Words'Access,
                        "every name below the boundary has words");
      Register_Routine (T, Every_Identifier_Renders'Access, "every identifier renders");
   end Register_Tests;

end Adash_Tests.Message_Cases;

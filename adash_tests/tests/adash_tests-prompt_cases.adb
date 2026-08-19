with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Engine;
with Adash.Interactive.Prompt;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Prompt_Cases is

   use AUnit.Assertions;

   package E renames Adash.Engine;
   package P renames Adash.Interactive.Prompt;

   use type P.Element_Kind;

   --  Everything a model would put on the line, run together, so a case can
   --  say what it expects in one string. A message part has no text of its
   --  own -- the caller's catalog renders it -- so it shows as its identifier,
   --  which is what a case wants to assert about anyway.
   function Rendered (Item : P.Model) return String;

   function Rendered (Item : P.Model) return String is
      Result : String (1 .. 512) := [others => ' '];
      Used   : Natural := 0;

      procedure Take (Text : String);

      procedure Take (Text : String) is
      begin
         for Letter of Text loop
            if Used < Result'Last then
               Used := Used + 1;
               Result (Used) := Letter;
            end if;
         end loop;
      end Take;

   begin
      for Index in 1 .. Item.Count loop
         declare
            Part : constant P.Element := Item.Elements (Index);
         begin
            case Part.Kind is
               when P.Element_Message | P.Element_Status =>
                  Take ("<" & Adash.Messages.Message_Id'Image (Part.Message)
                        & ">");

               when others =>
                  Take (P.Text_Of (Part));
            end case;

            if not Item.Joined then
               Take (" ");
            end if;
         end;
      end loop;

      return Result (1 .. Used);
   end Rendered;

   --  A session with a prompt format set, or with none.
   procedure Start (Shell : in out E.Session; Format : String);

   procedure Start (Shell : in out E.Session; Format : String) is
      Outcome : E.Result;
      Report  : Adash.Diagnostics.List;
   begin
      E.Open (Shell);

      if Format /= "" then
         E.Submit (Shell,
                   "settings (""prompt.format"", """ & Format & """);",
                   "<line>", Adash.Source.Origin_Interactive, Outcome, Report);
      end if;
   end Start;

   ------------------------------------------------------------------

   procedure The_Built_In_Prompt_Is_Parts_With_Blanks
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure The_Built_In_Prompt_Is_Parts_With_Blanks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell : E.Session;
   begin
      Start (Shell, "");

      declare
         Model : constant P.Model := P.Build (Shell);
      begin
         Assert (not Model.Joined,
                 "the built-in prompt puts a blank between its parts, so a"
                 & " typed line does not begin against it");
         Assert (Model.Count >= 2,
                 "the built-in prompt has a directory and a marker:"
                 & Natural'Image (Model.Count));
      end;

      --  The failure marker is a part rather than a colour: a prompt that said
      --  "the last thing failed" only by turning red would say nothing to a
      --  reader who cannot see red.
      declare
         Quiet   : constant P.Model := P.Build (Shell, Last_Failed => False);
         Shouted : constant P.Model := P.Build (Shell, Last_Failed => True);
      begin
         Assert (Shouted.Count = Quiet.Count + 1,
                 "a failure adds a part rather than changing one:"
                 & Natural'Image (Quiet.Count)
                 & Natural'Image (Shouted.Count));
      end;
   end The_Built_In_Prompt_Is_Parts_With_Blanks;

   procedure A_Format_Is_Used_Exactly_As_Written
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Format_Is_Used_Exactly_As_Written
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell : E.Session;
   begin
      --  No blanks are added anywhere: the spacing is the user's, which is
      --  what makes `{directory}$` come out as `src$` rather than `src $`.
      Start (Shell, "[{directory}]$ ");

      declare
         Model : constant P.Model := P.Build (Shell);
         Text  : constant String := Rendered (Model);
      begin
         Assert (Model.Joined,
                 "a format's parts run together");
         Assert (Text (Text'First) = '[' and then Text (Text'Last) = ' ',
                 "what was written is what is shown: [" & Text & "]");
         Assert (Text (Text'Last - 1) = '$',
                 "including the punctuation: [" & Text & "]");
      end;
   end A_Format_Is_Used_Exactly_As_Written;

   procedure A_Placeholder_Nobody_Knows_Stays_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Placeholder_Nobody_Knows_Stays_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell : E.Session;
   begin
      --  A `{word}` this shell does not fill in is text, not nothing: what a
      --  prompt does wrong is on the screen the moment it is set, and a
      --  placeholder that vanished would leave somebody wondering where their
      --  text went.
      Start (Shell, "{nonesuch}> ");

      declare
         Text : constant String := Rendered (P.Build (Shell));
      begin
         Assert (Text = "{nonesuch}> ",
                 "an unknown placeholder is the text it is: [" & Text & "]");
      end;
   end A_Placeholder_Nobody_Knows_Stays_Text;

   procedure A_Failure_Marker_Waits_For_A_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Failure_Marker_Waits_For_A_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell : E.Session;
   begin
      Start (Shell, "{failed}> ");

      declare
         Quiet : constant String := Rendered (P.Build (Shell, Last_Failed => False));
         Loud  : constant String :=
           Rendered (P.Build (Shell, Last_Failed => True));
      begin
         Assert (Quiet = "> ",
                 "a format can carry a marker and stay quiet on a good day: ["
                 & Quiet & "]");
         Assert (Loud /= Quiet,
                 "and show it after a failure: [" & Loud & "]");
      end;
   end A_Failure_Marker_Waits_For_A_Failure;

   procedure The_Status_Is_The_Last_Submissions
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure The_Status_Is_The_Last_Submissions
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Shell   : E.Session;
      Outcome : E.Result;
      Report  : Adash.Diagnostics.List;
   begin
      Start (Shell, "{status}> ");

      declare
         Text : constant String := Rendered (P.Build (Shell));
      begin
         Assert (Text = "0> ",
                 "a session that has run nothing shows a nought: ["
                 & Text & "]");
      end;

      --  `quit` is the one command that sets a status without running a
      --  program, which is what lets this case say a number it chose.
      E.Submit (Shell, "quit (3);", "<line>",
                Adash.Source.Origin_Interactive, Outcome, Report);

      declare
         Text : constant String := Rendered (P.Build (Shell));
      begin
         Assert (Text = "3> ",
                 "and the number the last submission ended with: ["
                 & Text & "]");
      end;
   end The_Status_Is_The_Last_Submissions;

   ------------------------------------------------------------------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Interactive.Prompt");
   end Name;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, The_Built_In_Prompt_Is_Parts_With_Blanks'Access,
         "prompt : the built-in prompt is parts with blanks between them");
      Register_Routine
        (T, A_Format_Is_Used_Exactly_As_Written'Access,
         "prompt : a format is used exactly as written, spacing included");
      Register_Routine
        (T, A_Placeholder_Nobody_Knows_Stays_Text'Access,
         "prompt : a placeholder nobody knows stays the text it is");
      Register_Routine
        (T, A_Failure_Marker_Waits_For_A_Failure'Access,
         "prompt : a failure marker waits for a failure");
      Register_Routine
        (T, The_Status_Is_The_Last_Submissions'Access,
         "prompt : the status shown is the last submission's");
   end Register_Tests;

end Adash_Tests.Prompt_Cases;

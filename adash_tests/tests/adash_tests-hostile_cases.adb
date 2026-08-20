with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Engine;
with Adash.Execution;
with Adash.Source;

package body Adash_Tests.Hostile_Cases is

   use AUnit.Assertions;

   package E renames Adash.Engine;
   package D renames Adash.Diagnostics;
   package US renames Ada.Strings.Unbounded;

   --  Text nobody would write on purpose.
   --
   --  Each of these has a reason to be here: something that is not finished,
   --  something that is too deep, something too long, a byte that is not text,
   --  and the shapes a mistyped line takes. What none of them may do is end
   --  the session.
   function Awkward (Which : Positive) return String;

   function Awkward (Which : Positive) return String is
      Deep : US.Unbounded_String;
      Long : US.Unbounded_String;
   begin
      case Which is
         when 1 => return "put_line (""unfinished";
         when 2 => return "X : Character := 'ab';";
         when 3 => return "put_line (""a"" # ""b"");";
         when 4 => return "X : Integer := 12ab;";
         when 5 => return "if true and false or true then null; end if;";
         when 6 => return "end;";
         when 7 => return "begin";
         when 8 => return ");";
         when 9 => return "put_line (f""closes } nothing"");";
         when 10 => return "put_line (f""a """" b"");";
         when 11 => return "X_ : Integer := 1;";
         when 12 => return "type A is array (5 .. 1) of Integer;";
         when 13 => return "put_line (" & Ada.Characters.Latin_1.NUL & ");";
         when 14 => return "put_line (""" & Ada.Characters.Latin_1.ESC & """);";
         when 15 => return "X : String := """
                           & Ada.Characters.Latin_1.LF & """;";

         when 16 =>
            --  A hundred open brackets: deeper than anything a person writes
            --  and shallower than what would take a minute to refuse.
            for Index in 1 .. 100 loop
               US.Append (Deep, "(");
            end loop;

            return "X : Integer := " & US.To_String (Deep) & "1;";

         when 17 =>
            --  One identifier of four thousand characters.
            for Index in 1 .. 4_000 loop
               US.Append (Long, "a");
            end loop;

            return US.To_String (Long) & " : Integer := 1;";

         when 18 =>
            --  A literal of four thousand characters, unterminated.
            for Index in 1 .. 4_000 loop
               US.Append (Long, "b");
            end loop;

            return "put_line (""" & US.To_String (Long) & ";";

         when 19 => return "procedure P is begin P; end P; P;";
         when 20 => return "raise Constraint_Error;";
         when others => return "quit";
      end case;
   end Awkward;

   Awkward_Count : constant := 20;

   --  What each of them must do, said in advance.
   --
   --  "Ran or complained" was too weak to be worth asserting: a submission
   --  that parsed half its text, ran that half and dropped the rest passes it
   --  -- which is precisely what `end;` did, and this table is what caught it.
   --  Saying which of the three answers is the right one turns each entry into
   --  a claim that can be wrong.
   type Verdict is
     (
      --  The grammar says more input could still finish it, so a frontend
      --  reads another line rather than reporting anything.
      Unfinished,

      --  It was submitted and something was said about it.
      Complained_About,

      --  It was submitted, nothing was said, and it succeeded.
      Ran);

   Expected : constant array (1 .. Awkward_Count) of Verdict :=
     [1  => Complained_About,  --  a literal nobody closed, and nobody can
      2  => Complained_About,  --  two characters in a character literal
      3  => Complained_About,  --  `#` is not an operator here
      4  => Complained_About,  --  `12ab` is not a number
      5  => Complained_About,  --  `and` and `or` without brackets
      6  => Complained_About,  --  a stray `end` at the top level
      7  => Unfinished,        --  a block that has only begun
      8  => Complained_About,  --  a bracket that closes nothing
      9  => Complained_About,  --  `}` with no `{` in a formatted literal
      10 => Complained_About,  --  Ada 2022 forbids `""` in one of these
      11 => Complained_About,  --  an identifier ending in an underscore
      12 => Complained_About,  --  an array with no elements is refused
      13 => Complained_About,  --  a byte that is not text
      14 => Ran,               --  an escape byte in a literal is a byte
      15 => Complained_About,  --  a raw newline inside a literal
      16 => Complained_About,  --  a hundred brackets and a `;` inside them
      17 => Ran,               --  a four-thousand-character name is a name:
                               --  Ada sets no length, and two of them that
                               --  differ in the last character keep their own
                               --  values rather than becoming one
      18 => Complained_About,  --  four thousand characters, still open
      19 => Complained_About,  --  a procedure that calls itself forever
      20 => Complained_About]; --  an exception nobody handles

   ------------------------------------------------------------------

   procedure A_Bad_Line_Never_Takes_The_Session_Down
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Bad_Line_Never_Takes_The_Session_Down
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Gathered and asserted once at the end, because a failed Assert ends
      --  the routine: asserting inside the loop reports the first entry that
      --  is wrong and says nothing about the nineteen after it, so a change
      --  that moved four of them took four runs to find out.
      Wrong : US.Unbounded_String;
   begin
      for Index in 1 .. Awkward_Count loop
         declare
            Shell   : E.Session;
            Outcome : E.Result;
            Report  : D.List;

            Text : constant String := Awkward (Index);

            procedure Note (What : String);

            procedure Note (What : String) is
            begin
               US.Append
                 (Wrong,
                  (if US.Length (Wrong) = 0 then "" else "; ")
                  & "input" & Positive'Image (Index) & " " & What);
            end Note;
         begin
            E.Open (Shell);

            --  Asked first, because a frontend asks first: text that stops in
            --  the middle of something is not submitted at all, so a
            --  diagnostic about it would be a diagnostic about a line the user
            --  is still typing.
            if E.Wants_More (Text, "<hostile>") then
               if Expected (Index) /= Unfinished then
                  Note ("UNFINISHED, expected "
                        & Verdict'Image (Expected (Index)));
               end if;

               goto Next;
            end if;

            if Expected (Index) = Unfinished then
               Note ("was submitted, expected UNFINISHED");
            end if;

            --  A submission of its own each time, in a session of its own, so
            --  that what this asserts about one is not an accident of what the
            --  one before it left behind.
            E.Submit (Shell, Text, "<hostile>",
                      Adash.Source.Origin_Interactive, Outcome, Report);

            --  What actually became of it, in the same three words.
            declare
               Saw : constant Verdict :=
                 (if D.Count (Report) > 0 then Complained_About
                  elsif Adash.Execution.Succeeded (Outcome.Status) then Ran
                  else Complained_About);

               --  A submission that failed and said nothing is the one answer
               --  with no name above, because it is never right. It arrives
               --  here as Complained_About with an empty report, so it is
               --  noticed on its own rather than folded into the comparison.
               Silent_Failure : constant Boolean :=
                 D.Count (Report) = 0
                   and then not Adash.Execution.Succeeded (Outcome.Status);
            begin
               if Silent_Failure then
                  Note ("failed without saying anything");
               elsif Saw /= Expected (Index) then
                  Note (Verdict'Image (Saw) & ", expected "
                        & Verdict'Image (Expected (Index)));
               end if;
            end;
         end;

         <<Next>>
      end loop;

      Assert (US.Length (Wrong) = 0, US.To_String (Wrong));
   end A_Bad_Line_Never_Takes_The_Session_Down;

   procedure A_Session_Works_After_Every_One_Of_Them
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Session_Works_After_Every_One_Of_Them
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Index in 1 .. Awkward_Count loop
         declare
            Shell   : E.Session;
            Outcome : E.Result;
            Report  : D.List;
            After   : D.List;
         begin
            E.Open (Shell);

            E.Submit (Shell, Awkward (Index), "<hostile>",
                      Adash.Source.Origin_Interactive, Outcome, Report);

            --  And now something ordinary. This is the property the
            --  carried-value defect broke: a session that survived a bad line
            --  and could not run a good one afterwards, for the rest of its
            --  life.
            E.Submit (Shell, "Fine : Integer := 6 * 7;", "<line>",
                      Adash.Source.Origin_Interactive, Outcome, After);

            Assert (Adash.Execution.Succeeded (Outcome.Status),
                    "after input" & Positive'Image (Index)
                    & " an ordinary declaration would not run");
            Assert (D.Count (After) = 0,
                    "after input" & Positive'Image (Index)
                    & " an ordinary declaration was complained about");
         end;
      end loop;
   end A_Session_Works_After_Every_One_Of_Them;

   procedure Nothing_Awkward_Is_Silent
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Nothing_Awkward_Is_Silent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  The same inputs one after another in *one* session, which is what a
      --  user does: a bad line, another bad line, and then work. Nothing may
      --  accumulate -- not a half-open construct, not a carried value, not a
      --  parser that is still waiting for something.
      declare
         Shell   : E.Session;
         Outcome : E.Result;
         Report  : D.List;
      begin
         E.Open (Shell);

         for Index in 1 .. Awkward_Count loop
            E.Submit (Shell, Awkward (Index), "<hostile>",
                      Adash.Source.Origin_Interactive, Outcome, Report);
         end loop;

         declare
            After : D.List;
         begin
            E.Submit (Shell, "Sane : Integer := 1; Put_Line (Sane);", "<line>",
                      Adash.Source.Origin_Interactive, Outcome, After);

            Assert (Adash.Execution.Succeeded (Outcome.Status)
                      and then D.Count (After) = 0,
                    "a session that had seen every awkward line could not run"
                    & " an ordinary one afterwards");
         end;
      end;
   end Nothing_Awkward_Is_Silent;

   ------------------------------------------------------------------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Hostile_Input");
   end Name;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Bad_Line_Never_Takes_The_Session_Down'Access,
         "hostile : every awkward line does what it is supposed to");
      Register_Routine
        (T, A_Session_Works_After_Every_One_Of_Them'Access,
         "hostile : a session works after each of them");
      Register_Routine
        (T, Nothing_Awkward_Is_Silent'Access,
         "hostile : a session works after all of them, one after another");
   end Register_Tests;

end Adash_Tests.Hostile_Cases;

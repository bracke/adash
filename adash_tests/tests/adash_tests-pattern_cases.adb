with AUnit.Assertions;

with Adash.Patterns;

package body Adash_Tests.Pattern_Cases is

   use AUnit.Assertions;

   ---------------------------------------------------------------------
   --  Matching
   ---------------------------------------------------------------------

   procedure A_Pattern_Describes_The_Whole_String
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Pattern_Describes_The_Whole_String
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Anchored at both ends. A matcher that searched instead would make
      --  `*.log` match `notes.log.bak`, and a script removing what it matched
      --  would take the backup with it.
      Assert (Adash.Patterns.Matches ("notes.log", "*.log"),
              "a star matches a run of characters");
      Assert (not Adash.Patterns.Matches ("notes.log.bak", "*.log"),
              "a pattern describes the whole string, not a part of it");

      --  A star matches nothing at all as readily as something.
      Assert (Adash.Patterns.Matches (".log", "*.log"),
              "a star matches an empty run");
      Assert (Adash.Patterns.Matches ("", "*"),
              "a star matches an empty string");
      Assert (not Adash.Patterns.Matches ("", "?"),
              "a question mark wants exactly one character");

      Assert (Adash.Patterns.Matches ("a", "?"), "one character, one mark");
      Assert (Adash.Patterns.Matches ("abc", "a?c"), "a mark in the middle");

      --  Several stars, and one that has to give ground: the matcher tries a
      --  star, fails later, and comes back to try it a character longer.
      Assert (Adash.Patterns.Matches ("aXbXc", "a*b*c"),
              "two stars, each taking what it must");
      Assert (Adash.Patterns.Matches ("abcbd", "a*bd"),
              "a star gives ground when what follows it does not fit");
   end A_Pattern_Describes_The_Whole_String;

   procedure A_Class_Holds_What_It_Lists
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Class_Holds_What_It_Lists
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Adash.Patterns.Matches ("b", "[abc]"), "a listed character");
      Assert (not Adash.Patterns.Matches ("d", "[abc]"), "an unlisted one");
      Assert (Adash.Patterns.Matches ("c", "[a-z]"), "a range");
      Assert (not Adash.Patterns.Matches ("C", "[a-z]"),
              "a range is case sensitive, as the host's names are");

      Assert (Adash.Patterns.Matches ("d", "[!abc]"),
              "a negated class holds what it does not list");
      Assert (not Adash.Patterns.Matches ("a", "[!abc]"),
              "and not what it does");
      Assert (Adash.Patterns.Matches ("d", "[^abc]"),
              "the other spelling of a negation");

      --  An unclosed class is not a class. Somebody who typed `[` and meant
      --  one gets it; a pattern that silently matched nothing would be a file
      --  quietly not found.
      Assert (Adash.Patterns.Matches ("[x", "[x"),
              "an unclosed bracket stands for itself");
      Assert (not Adash.Patterns.Matches ("x", "[x"),
              "and does not open a class");
   end A_Class_Holds_What_It_Lists;

   procedure A_Name_With_Nothing_To_Match_Is_Not_A_Pattern
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Name_With_Nothing_To_Match_Is_Not_A_Pattern
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  What separates an argument `run_matching` expands from one it passes
      --  along untouched.
      Assert (Adash.Patterns.Holds_A_Pattern ("*.log"), "a star");
      Assert (Adash.Patterns.Holds_A_Pattern ("note?.txt"), "a mark");
      Assert (Adash.Patterns.Holds_A_Pattern ("[abc].txt"), "a bracket");
      Assert (not Adash.Patterns.Holds_A_Pattern ("--force"),
              "a flag is not a pattern");
      Assert (not Adash.Patterns.Holds_A_Pattern (""),
              "nothing is not a pattern");
   end A_Name_With_Nothing_To_Match_Is_Not_A_Pattern;

   ---------------------------------------------------------------------
   --  Braces
   ---------------------------------------------------------------------

   function Joined (Text : String) return String;

   --  What a text stands for, as one string, so a case can say what it
   --  expects in one line.
   function Joined (Text : String) return String is
      Pieces  : Adash.Patterns.Text_Lists.Vector;
      Refused : Boolean;

      Result : String (1 .. 4_096) := [others => ' '];
      Used   : Natural := 0;
   begin
      Adash.Patterns.Expand (Text, Pieces, Refused);

      if Refused then
         return "<refused>";
      end if;

      for Item of Pieces loop
         if Used > 0 and then Used < Result'Last then
            Used := Used + 1;
            Result (Used) := ' ';
         end if;

         for Letter of Item loop
            if Used < Result'Last then
               Used := Used + 1;
               Result (Used) := Letter;
            end if;
         end loop;
      end loop;

      return Result (1 .. Used);
   end Joined;

   procedure Braces_Say_What_Strings_To_Make
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Braces_Say_What_Strings_To_Make
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Joined ("{a,b}") = "a b", "two alternatives: " & Joined ("{a,b}"));
      Assert (Joined ("x{a,b}y") = "xay xby",
              "what is around a group is kept: " & Joined ("x{a,b}y"));

      --  Leftmost varies slowest, which is the order every other shell
      --  produces and the order a reader expects.
      Assert (Joined ("{a,b}{1,2}") = "a1 a2 b1 b2",
              "two groups multiply: " & Joined ("{a,b}{1,2}"));

      Assert (Joined ("{a,{b,c}}") = "a b c",
              "groups nest: " & Joined ("{a,{b,c}}"));

      Assert (Joined ("{1..4}") = "1 2 3 4",
              "a range counts: " & Joined ("{1..4}"));
      Assert (Joined ("{4..1}") = "4 3 2 1",
              "and counts back when it is written backwards: "
              & Joined ("{4..1}"));
      Assert (Joined ("{a..d}") = "a b c d",
              "a range of letters: " & Joined ("{a..d}"));

      --  An empty alternative is a string, which is how `file{,.bak}` names
      --  both a file and its backup.
      Assert (Joined ("f{,x}") = "f fx",
              "an empty alternative is one of them: " & Joined ("f{,x}"));
   end Braces_Say_What_Strings_To_Make;

   procedure A_Group_That_Says_Nothing_Is_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Group_That_Says_Nothing_Is_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Neither a comma nor a range: `{a}` is what somebody typed and what
      --  they get.
      Assert (Joined ("{a}") = "{a}", "a group of one: " & Joined ("{a}"));
      Assert (Joined ("plain") = "plain",
              "text with no group stands for itself: " & Joined ("plain"));
      Assert (Joined ("") = "", "nothing stands for nothing");

      --  An unclosed group is text too, for the same reason an unclosed
      --  bracket is: it is what was written.
      Assert (Joined ("{a,b") = "{a,b",
              "an unclosed group: " & Joined ("{a,b"));

      --  A range whose ends do not match in shape is not a range.
      Assert (Joined ("{1..d}") = "{1..d}",
              "a number and a letter are not a range: " & Joined ("{1..d}"));
   end A_Group_That_Says_Nothing_Is_Text;

   procedure An_Expansion_Has_A_Bound
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure An_Expansion_Has_A_Bound
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Four groups of ten multiply to ten thousand, which is over the
      --  bound; three groups of ten are a thousand, which is under it. The
      --  bound is what stops a short line naming more strings than a machine
      --  has memory for, and the multiplying is the point of the feature
      --  rather than a misuse of it.
      Under : constant String := "{0..9}{0..9}{0..9}";
      Over  : constant String := "{0..9}{0..9}{0..9}{0..9}";

      Pieces  : Adash.Patterns.Text_Lists.Vector;
      Refused : Boolean;
   begin
      Adash.Patterns.Expand (Under, Pieces, Refused);
      Assert (not Refused, "a thousand strings is under the bound");
      Assert (Natural (Pieces.Length) = 1_000,
              "three groups of ten make a thousand:"
              & Natural'Image (Natural (Pieces.Length)));

      Adash.Patterns.Expand (Over, Pieces, Refused);
      Assert (Refused, "ten thousand strings is over the bound");
      Assert (Pieces.Is_Empty,
              "and nothing comes back, rather than the first four thousand");
   end An_Expansion_Has_A_Bound;

   ---------------------------------------------------------------------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Patterns");
   end Name;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Pattern_Describes_The_Whole_String'Access,
         "patterns : a pattern describes the whole string");
      Register_Routine
        (T, A_Class_Holds_What_It_Lists'Access,
         "patterns : a class holds what it lists, and an unclosed one is text");
      Register_Routine
        (T, A_Name_With_Nothing_To_Match_Is_Not_A_Pattern'Access,
         "patterns : a name with nothing to match is not a pattern");
      Register_Routine
        (T, Braces_Say_What_Strings_To_Make'Access,
         "braces : what a text with groups stands for");
      Register_Routine
        (T, A_Group_That_Says_Nothing_Is_Text'Access,
         "braces : a group that says nothing is text");
      Register_Routine
        (T, An_Expansion_Has_A_Bound'Access,
         "braces : an expansion has a bound and refuses whole");
   end Register_Tests;

end Adash_Tests.Pattern_Cases;

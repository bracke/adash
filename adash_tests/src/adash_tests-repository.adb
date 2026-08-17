with Ada.Characters.Latin_1;
with Ada.Directories;

with Project_Tools.Files;
with Project_Tools.Text;
with Project_Tools.TOML;

package body Adash_Tests.Repository is

   package US renames Ada.Strings.Unbounded;
   package Msg renames Adash.Messages;

   --  Catalog keys this package reports under. They are constants rather than
   --  literals at the point of use so that a key renamed in the catalog is
   --  renamed in one place here, and so that Repository_Cases can assert on
   --  the same constants instead of on copies of the strings.
   Key_Missing_File         : constant String := "tooling.check.missing_file";
   Key_Missing_Directory    : constant String := "tooling.check.missing_directory";
   Key_Version_Mismatch     : constant String := "tooling.check.version_mismatch";
   Key_Version_Unreadable   : constant String := "tooling.check.version_unreadable";
   Key_Inventory_Unreadable : constant String :=
     "tooling.check.inventory_unreadable";
   Key_Catalog_Missing_Key  : constant String := "tooling.check.catalog_missing_key";
   Key_Catalog_Unreadable   : constant String := "tooling.check.catalog_unreadable";
   Key_Escape_Sequence      : constant String := "tooling.check.escape_sequence";
   Key_Silent_Truncation    : constant String :=
     "tooling.check.silent_truncation";
   Key_Pin_Not_Cloned       : constant String :=
     "tooling.check.pin_not_cloned";
   Key_Identifier_As_Text   : constant String :=
     "tooling.check.identifier_as_text";
   Key_Prose_As_Text        : constant String :=
     "tooling.check.prose_as_text";
   Key_Forbidden_Dependency : constant String := "tooling.check.forbidden_dependency";
   Key_Inventory_Missing    : constant String := "tooling.check.inventory_missing";
   Key_Inventory_Unlisted   : constant String := "tooling.check.inventory_unlisted";
   Key_Grammar_Missing      : constant String :=
     "tooling.check.grammar_missing";
   Key_Grammar_Unknown      : constant String :=
     "tooling.check.grammar_unknown";

   --  Units no Adash source may name. Each has one legitimate provider, and
   --  naming it directly is how a second one starts.
   --
   --  These are prefixes, matched against the text following "with ", so
   --  "GNAT.OS_Lib" catches "GNAT.OS_Lib;" and any child of it.
   type Forbidden_Unit is (Unit_GNAT_OS_Lib, Unit_GNAT_Expect, Unit_Interfaces_C, Unit_System_OS);

   function Forbidden_Name (Unit : Forbidden_Unit) return String
   is (case Unit is
          when Unit_GNAT_OS_Lib  => "GNAT.OS_Lib",
          when Unit_GNAT_Expect  => "GNAT.Expect",
          when Unit_Interfaces_C => "Interfaces.C",
          when Unit_System_OS    => "System.OS_Interface");

   procedure Add
     (Into      : in out Report;
      Key       : String;
      Arguments : Msg.Argument_List := Msg.No_Arguments);
   --  Record a finding.

   function Join (Root : String; Relative : String) return String;
   --  Repository-relative path. Always '/' -- these are paths inside a
   --  repository, which is a POSIX-shaped namespace even on Windows, and the
   --  separator ends up in a finding a person reads.

   function Read_If_Present (Path : String) return String;
   --  File contents, or "" when the file is absent or unreadable.

   function Source_Files (Root : String) return Project_Tools.Files.Path_List;
   --  Every Ada source under the shell crate's src tree.

   function Tooling_Files (Root : String) return Project_Tools.Files.Path_List;
   --  Every Ada source under the test crate's src tree.
   --
   --  The repository tooling: the checker, the conformance runner, the test
   --  runner, the benchmark harness. The rules about hard-coded text apply to
   --  these as much as to the shell -- the constraint names release tools and
   --  test runners in as many words -- and `adash_bench` printed its whole
   --  report in English for as long as it existed because nothing looked
   --  here.

   ---------
   -- Add --
   ---------

   procedure Add
     (Into      : in out Report;
      Key       : String;
      Arguments : Msg.Argument_List := Msg.No_Arguments)
   is
      Item : Finding;
   begin
      Item.Key            := US.To_Unbounded_String (Key);
      Item.Argument_Count := Arguments'Length;

      for Index in Arguments'Range loop
         Item.Arguments (Item.Arguments'First + (Index - Arguments'First)) :=
           Arguments (Index);
      end loop;

      Into.Findings.Append (Item);
   end Add;

   ----------
   -- Join --
   ----------

   function Join (Root : String; Relative : String) return String is
   begin
      if Root = "" then
         return Relative;
      elsif Root (Root'Last) = '/' then
         return Root & Relative;
      else
         return Root & "/" & Relative;
      end if;
   end Join;

   ---------------------
   -- Read_If_Present --
   ---------------------

   function Read_If_Present (Path : String) return String is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         return "";
      end if;
      return Project_Tools.Files.Read_Raw_File (Path);
   end Read_If_Present;

   ------------------
   -- Source_Files --
   ------------------

   function Source_Files (Root : String) return Project_Tools.Files.Path_List is
      Tree : constant String := Join (Root, "src");
   begin
      if not Project_Tools.Files.Directory_Exists (Tree) then
         return [1 .. 0 => <>];
      end if;
      return Project_Tools.Files.List_Tree (Tree, "*.ad?");
   end Source_Files;

   ---------------------
   -- Tooling_Files --
   ---------------------

   function Tooling_Files (Root : String) return Project_Tools.Files.Path_List
   is
      Tree : constant String := Join (Join (Root, "adash_tests"), "src");
   begin
      if not Project_Tools.Files.Directory_Exists (Tree) then
         return [1 .. 0 => <>];
      end if;
      return Project_Tools.Files.List_Tree (Tree, "*.ad?");
   end Tooling_Files;

   ---------
   -- Key --
   ---------

   function Key (Item : Finding) return String is
   begin
      return US.To_String (Item.Key);
   end Key;

   ---------------
   -- Arguments --
   ---------------

   function Arguments (Item : Finding) return Msg.Argument_List is
   begin
      return Item.Arguments (Item.Arguments'First
                             .. Item.Arguments'First + Item.Argument_Count - 1);
   end Arguments;

   ------------
   -- Passed --
   ------------

   function Passed (Item : Report) return Boolean is
   begin
      return Item.Findings.Is_Empty;
   end Passed;

   -------------------
   -- Failure_Count --
   -------------------

   function Failure_Count (Item : Report) return Natural is
   begin
      return Natural (Item.Findings.Length);
   end Failure_Count;

   --------------------------
   -- Check_Required_Files --
   --------------------------

   procedure Check_Required_Files (Root : String; Into : in out Report) is

      procedure Require (Relative : String);
      --  One required file.

      procedure Require (Relative : String) is
      begin
         Into.Checks_Run := Into.Checks_Run + 1;
         if not Project_Tools.Files.File_Exists (Join (Root, Relative)) then
            Add (Into, Key_Missing_File, [1 => Msg.Named ("path", Relative)]);
         end if;
      end Require;

   begin
      Require ("alire.toml");
      Require ("adash.gpr");
      Require ("repository.toml");

      --  The documentation set is not decoration. Each of these is named by
      --  the architecture as the authoritative place for something, and a
      --  missing one means that something is now only in somebody's head.
      Require ("README.md");
      Require ("ARCHITECTURE.md");
      Require ("CONTRIBUTING.md");
      Require ("STYLE_GUIDE.md");
      Require ("SECURITY.md");
      Require ("CHANGELOG.md");
      Require ("ROADMAP.md");
      Require ("AI.md");
      Require ("LICENSE");

      Require ("resources/messages/catalog.txt");

      --  The bounds every benchmark figure is checked against. Required
      --  because `adash_bench` refuses to measure without them, and CI runs it
      --  on every push: a file that went missing would turn a check into a
      --  failing step whose message is about a file rather than about
      --  performance.
      Require ("benchmarks/ceilings.toml");
   end Check_Required_Files;

   --------------------------------
   -- Check_Required_Directories --
   --------------------------------

   procedure Check_Required_Directories (Root : String; Into : in out Report) is

      procedure Require (Relative : String);
      --  One required directory.

      procedure Require (Relative : String) is
      begin
         Into.Checks_Run := Into.Checks_Run + 1;
         if not Project_Tools.Files.Directory_Exists (Join (Root, Relative)) then
            Add (Into, Key_Missing_Directory, [1 => Msg.Named ("path", Relative)]);
         end if;
      end Require;

   begin
      Require ("src");
      Require ("resources");
      Require ("docs");
      Require ("examples");
      Require ("benchmarks");
      Require ("conformance");
      Require ("generated");

      Require ("adash_tests");
      Require ("adash_tests/src");
      Require ("adash_tests/tests");
      Require ("adash_tests/fixtures");
      Require ("adash_tests/generated");
      Require ("adash_tests/docs");
   end Check_Required_Directories;

   ----------------------------
   -- Check_CI_Clones_Pins --
   ----------------------------

   --  Every crate the manifests pin is one CI has to check out.
   --
   --  Alire honours pins only in the root crate, so the workflow clones each
   --  by hand -- and a list written by hand beside a list of pins is two
   --  places for one fact. The first run of this repository's CI failed on
   --  exactly that: the manifests had gained jsonlib and tomllib and the
   --  workflow had not, so `alr build` stopped at a pin path that was not
   --  there. The workflow stays an entry point and this holds it to the
   --  manifests, which is where the decision lives.
   procedure Check_CI_Clones_Pins (Root : String; Into : in out Report);

   procedure Check_CI_Clones_Pins (Root : String; Into : in out Report) is
      Workflow : constant String :=
        Read_If_Present (Join (Root, ".github/workflows/ci.yml"));

      --  Both manifests: the test crate pins what it needs to build the
      --  tools, and CI runs those.
      Manifests : constant array (1 .. 2) of US.Unbounded_String :=
        [US.To_Unbounded_String (Read_If_Present (Join (Root, "alire.toml"))),
         US.To_Unbounded_String
           (Read_If_Present (Join (Root, "adash_tests/alire.toml")))];
   begin
      if Workflow = "" then
         return;
      end if;

      for Manifest of Manifests loop
         declare
            Text : constant String := US.To_String (Manifest);
            From : Positive := Text'First;
         begin
            while From <= Text'Last loop
               declare
                  Ends : Natural := From;
               begin
                  while Ends <= Text'Last
                    and then Text (Ends) /= Ada.Characters.Latin_1.LF
                  loop
                     Ends := Ends + 1;
                  end loop;

                  declare
                     One : constant String := Text (From .. Ends - 1);
                     At_Path : constant Natural :=
                       Project_Tools.Text.Index (One, " = { path = ");
                  begin
                     --  A pin is `name = { path = "../name" }` at the start of
                     --  a line. The crate this *is* pins itself in the test
                     --  crate's manifest, and nothing clones what it is
                     --  standing in.
                     if At_Path > One'First
                       and then One (One'First) not in ' ' | '#'
                       and then One (One'First .. At_Path - 1) /= "adash"
                     then
                        Into.Checks_Run := Into.Checks_Run + 1;

                        if not Project_Tools.Text.Contains
                                 (Workflow,
                                  " " & One (One'First .. At_Path - 1) & " ")
                          and then not Project_Tools.Text.Contains
                                         (Workflow,
                                          " " & One (One'First .. At_Path - 1)
                                          & ";")
                        then
                           Add (Into, Key_Pin_Not_Cloned,
                                [1 => Msg.Named
                                        ("name",
                                         One (One'First .. At_Path - 1))]);
                        end if;
                     end if;
                  end;

                  From := Ends + 1;
               end;
            end loop;
         end;
      end loop;
   end Check_CI_Clones_Pins;

   -------------------------------
   -- Check_Version_Consistency --
   -------------------------------

   procedure Check_Version_Consistency (Root : String; Into : in out Report) is
      Manifest   : constant String := Read_If_Present (Join (Root, "alire.toml"));
      Inventory  : constant String := Read_If_Present (Join (Root, "repository.toml"));
   begin
      Into.Checks_Run := Into.Checks_Run + 1;

      if Manifest = "" or else Inventory = "" then
         --  Check_Required_Files has already reported whichever is missing;
         --  reporting it twice would only make the second report look like a
         --  second defect.
         return;
      end if;

      --  The key carries its `= `, which is what this reader expects: it takes
      --  the text after what it was given and requires a quote there, and does
      --  not skip an assignment nobody told it about.
      --
      --  Asked for as `"version"` this check read nothing out of either file,
      --  compared the two nothings, and passed -- for every version this
      --  repository has ever had, including the ones where the two files were
      --  made to disagree on purpose to see whether it worked. The release
      --  guide names it as one of the things that cannot go wrong.
      declare
         From_Manifest : constant String :=
           Project_Tools.TOML.String_Value_After
             (Manifest, "version = ", Manifest'First);
         From_Inventory : constant String :=
           Project_Tools.TOML.String_Value_After
             (Inventory, "version = ", Inventory'First);
      begin
         --  Reported rather than skipped. A comparison of two values that
         --  could not be read is the shape this check failed in, so an
         --  unreadable one is a finding of its own now: `version="0.1.0"`
         --  written without the spaces this reader wants would otherwise take
         --  the check back to agreeing about nothing.
         if From_Manifest = "" then
            Add (Into, Key_Version_Unreadable,
                 [1 => Msg.Named ("path", "alire.toml")]);

         elsif From_Inventory = "" then
            Add (Into, Key_Version_Unreadable,
                 [1 => Msg.Named ("path", "repository.toml")]);

         elsif From_Manifest /= From_Inventory then
            Add (Into, Key_Version_Mismatch,
                 [Msg.Named ("first", "alire.toml"),
                  Msg.Named ("first_value", From_Manifest),
                  Msg.Named ("second", "repository.toml"),
                  Msg.Named ("second_value", From_Inventory)]);
         end if;
      end;
   end Check_Version_Consistency;

   ------------------------------
   -- Check_Package_Inventory --
   ------------------------------

   procedure Check_Package_Inventory (Root : String; Into : in out Report) is
      Inventory : constant String := Read_If_Present (Join (Root, "repository.toml"));
      Specs     : constant Project_Tools.Files.Path_List := Source_Files (Root);
   begin
      if Inventory = "" then
         return;
      end if;

      --  Direction one: everything the inventory names must exist.
      declare
         Cursor : Positive := Inventory'First;
      begin
         while Cursor <= Inventory'Last loop
            declare
               Position : constant Natural :=
                 Project_Tools.Text.Index_From (Inventory, "spec = """, Cursor);
            begin
               exit when Position = 0;

               declare
                  --  With its `= `, for the reason Check_Version_Consistency
                  --  gives. Read as `"spec"` this said "" for every entry in
                  --  the file and the guard below turned each one into a check
                  --  that passed, so this direction -- everything the
                  --  inventory names exists -- had never run.
                  Value : constant String :=
                    Project_Tools.TOML.String_Value_After
                      (Inventory, "spec = ", Position);
               begin
                  Into.Checks_Run := Into.Checks_Run + 1;

                  if Value = "" then
                     Add (Into, Key_Inventory_Unreadable,
                          [1 => Msg.Named
                                  ("position", Natural'Image (Position))]);

                  elsif not Project_Tools.Files.File_Exists (Join (Root, Value))
                  then
                     Add (Into, Key_Inventory_Missing,
                          [1 => Msg.Named ("path", Value)]);
                  end if;
               end;

               Cursor := Position + 1;
            end;
         end loop;
      end;

      --  Direction two, and the one that actually catches drift: every spec
      --  that exists must be named by the inventory. A package added without
      --  an entry has no recorded owner.
      for Path of Specs loop
         declare
            Full : constant String := US.To_String (Path);
         begin
            if Project_Tools.Text.Ends_With (Full, ".ads") then
               Into.Checks_Run := Into.Checks_Run + 1;

               declare
                  Base : constant String := Ada.Directories.Simple_Name (Full);
               begin
                  if not Project_Tools.Text.Contains (Inventory, Base) then
                     Add (Into, Key_Inventory_Unlisted,
                          [1 => Msg.Named ("path", Base)]);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Check_Package_Inventory;

   ---------------------------
   -- Check_Message_Catalog --
   ---------------------------

   procedure Check_Message_Catalog (Root : String; Into : in out Report) is
      Catalog_Path : constant String := Join (Root, "resources/messages/catalog.txt");
      Catalog      : constant String := Read_If_Present (Catalog_Path);
   begin
      Into.Checks_Run := Into.Checks_Run + 1;

      if Catalog = "" then
         Add (Into, Key_Catalog_Unreadable, [1 => Msg.Named ("path", Catalog_Path)]);
         return;
      end if;

      --  The default locale is the one every key must be complete in. A
      --  translation may lag; the language the fallback chain ends at may not.
      declare
         Default_Locale : constant String :=
           Project_Tools.Text.Line_Value (Catalog, "default_locale");
         Locale : constant String :=
           (if Default_Locale = "" then "en" else Default_Locale);
      begin
         for Id in Msg.Message_Id loop
            Into.Checks_Run := Into.Checks_Run + 1;

            declare
               Entry_Prefix : constant String := Locale & "." & Msg.Key (Id) & " =";
            begin
               if not Project_Tools.Text.Contains (Catalog, Entry_Prefix) then
                  Add (Into, Key_Catalog_Missing_Key,
                       [Msg.Named ("id", Msg.Message_Id'Image (Id)),
                        Msg.Named ("key", Msg.Key (Id))]);
               end if;
            end;
         end loop;
      end;
   end Check_Message_Catalog;

   ---------------------------------
   -- Check_No_Silent_Truncation --
   ---------------------------------

   --  The parser collects into fixed-size lists, and a loop that stops at the
   --  end of one without saying so drops what a program wrote. That is how a
   --  select of thirty-three alternatives came to serve thirty-two and leave a
   --  caller of the last one waiting for ever -- the bound was documented as a
   --  refusal and was a truncation. Every such loop reports now; this is what
   --  stops the next one being written silently.
   procedure Check_No_Silent_Truncation (Root : String; Into : in out Report);

   procedure Check_No_Silent_Truncation (Root : String; Into : in out Report) is
      --  The parser only. Elsewhere a loop that stops at a bound is a cap on
      --  what this build looks at -- how many session files to read, say --
      --  and dropping the rest is the decision rather than a loss of it. In
      --  the parser what is dropped is what somebody wrote.
      Where : constant String :=
        Join (Root, "src/library/adash-language-parser.adb");

      Content : constant String := Read_If_Present (Where);

      --  Both shapes the parser had. `exit when X = List'Last` stopped a
      --  collecting loop, and `and then Count < List'Last` stopped it from
      --  the loop's own condition -- the second reads as a guard rather than
      --  as a truncation, which is why it outlived the first by a turn.
      --  Neither says which counter it uses, so both are matched by what
      --  stands beside them: a line at a time, because what makes one of
      --  these a truncation is that the test and the bound are together.
      From : Positive := Content'First;
   begin
      Into.Checks_Run := Into.Checks_Run + 1;

      while From <= Content'Last loop
         declare
            Ends : Natural := From;
         begin
            while Ends <= Content'Last
              and then Content (Ends) /= Ada.Characters.Latin_1.LF
            loop
               Ends := Ends + 1;
            end loop;

            declare
               One : constant String := Content (From .. Ends - 1);
            begin
               if Project_Tools.Text.Contains (One, "'Last")
                 and then (Project_Tools.Text.Contains (One, "exit when ")
                           or else Project_Tools.Text.Contains
                                     (One, "and then "))
               then
                  Add (Into, Key_Silent_Truncation,
                       [1 => Msg.Named
                               ("path",
                                Ada.Directories.Simple_Name (Where))]);
               end if;
            end;

            From := Ends + 1;
         end;
      end loop;
   end Check_No_Silent_Truncation;

   -------------------------------
   -- Check_No_Terminal_Escapes --
   -------------------------------

   procedure Check_No_Terminal_Escapes (Root : String; Into : in out Report) is
      Escape : constant Character := Ada.Characters.Latin_1.ESC;
   begin
      for Path of Source_Files (Root) loop
         declare
            Full    : constant String := US.To_String (Path);
            Content : constant String := Read_If_Present (Full);
            Found   : Boolean := False;
         begin
            Into.Checks_Run := Into.Checks_Run + 1;

            --  A literal escape byte in the source, and the two ways to write
            --  one without typing it: both are the same defect.
            for Character_Index in Content'Range loop
               if Content (Character_Index) = Escape then
                  Found := True;
                  exit;
               end if;
            end loop;

            if not Found then
               Found := Project_Tools.Text.Contains (Content, "ASCII.ESC")
                 or else Project_Tools.Text.Contains (Content, "Latin_1.ESC")
                 or else Project_Tools.Text.Contains (Content, "Character'Val (27)");
            end if;

            if Found then
               Add (Into, Key_Escape_Sequence,
                    [1 => Msg.Named ("path", Ada.Directories.Simple_Name (Full))]);
            end if;
         end;
      end loop;
   end Check_No_Terminal_Escapes;

   ----------------------------------
   -- Check_No_Identifiers_As_Text --
   ----------------------------------

   --  A message argument must be text, not a name for something.
   --
   --  Passing an identifier where the catalog promised words reached users as
   --  `this system does not support JOB_CONTROL` and `[1] JOB_RUNNING  sleep
   --  30`. Neither is translatable and neither reads like a sentence. A
   --  message that has to quote a name says so with the Quoted parameter
   --  instead, and the boundary renders that name`s own message.
   --
   --  Two shapes, both of which have been identifiers every time they
   --  appeared: an enumeration`s image, and a literal written entirely in
   --  capitals. A number`s image is text a reader wants -- a line number is a
   --  number -- so the numeric types are named here rather than guessed at.
   procedure Check_No_Identifiers_As_Text (Root : String; Into : in out Report)
   is
      function Shouted_Literal (Line : String) return Boolean;
      function Enumeration_Image (Line : String) return Boolean;

      --  A literal of three or more characters, every one of them a capital or
      --  an underscore. A name a user types is not written that way; an
      --  identifier standing in for words always is.
      function Shouted_Literal (Line : String) return Boolean is
         Inside : Boolean := False;
         Run    : Natural := 0;
         Shouts : Boolean := True;
      begin
         for Position in Line'Range loop
            if Line (Position) = '"' then
               if Inside and then Run >= 3 and then Shouts then
                  return True;
               end if;

               Inside := not Inside;
               Run := 0;
               Shouts := True;
            elsif Inside then
               Run := Run + 1;

               if Line (Position) not in 'A' .. 'Z' | '_' then
                  Shouts := False;
               end if;
            end if;
         end loop;

         return False;
      end Shouted_Literal;

      function Enumeration_Image (Line : String) return Boolean is
      begin
         if not Project_Tools.Text.Contains (Line, "'Image") then
            return False;
         end if;

         --  The numeric ones are text. Anything else imaged into a message is
         --  an enumeration literal, and those are identifiers.
         return not (Project_Tools.Text.Contains (Line, "Natural'Image")
                     or else Project_Tools.Text.Contains (Line, "Positive'Image")
                     or else Project_Tools.Text.Contains (Line, "Integer'Image"));
      end Enumeration_Image;
   begin
      for Path of Source_Files (Root) loop
         declare
            Full    : constant String := US.To_String (Path);
            Content : constant String := Read_If_Present (Full);
            From    : Natural := Content'First;
         begin
            Into.Checks_Run := Into.Checks_Run + 1;

            while From <= Content'Last loop
               declare
                  Stop : Natural := From;
               begin
                  while Stop <= Content'Last
                    and then Content (Stop) /= Ada.Characters.Latin_1.LF
                  loop
                     Stop := Stop + 1;
                  end loop;

                  declare
                     Line : constant String := Content (From .. Stop - 1);
                  begin
                     if Project_Tools.Text.Contains (Line, "Named (""")
                       and then (Enumeration_Image (Line)
                                 or else Shouted_Literal (Line))
                     then
                        Add (Into, Key_Identifier_As_Text,
                             [Msg.Named
                                ("path", Ada.Directories.Simple_Name (Full)),
                              Msg.Named ("text", Line)]);
                     end if;
                  end;

                  From := Stop + 1;
               end;
            end loop;
         end;
      end loop;
   end Check_No_Identifiers_As_Text;

   ---------------------------
   -- Check_No_Prose_As_Text --
   ---------------------------

   --  No sentence may be written in Ada source.
   --
   --  Every user-visible string belongs to the catalog. That was true of the
   --  obvious ones from the start, and quietly untrue of a whole class beside
   --  them: the machine said `the arithmetic does not hold`, the parser said
   --  `an expression`, the lowering said `a call with the wrong number of
   --  arguments`, and the settings said `true or false` -- four subsystems,
   --  none of them a presentation boundary, each writing English.
   --
   --  Two or more words of ordinary text inside a literal is the shape. Ada
   --  spells a few of its own constructs with a space in them and those are
   --  syntax rather than prose, so they are named here; anything else with a
   --  space in it is a sentence and belongs in the catalog.
   procedure Check_No_Prose_As_Text (Root : String; Into : in out Report) is

      --  Ada`s own spellings. Not prose: a diagnostic naming the `in out` mode
      --  is quoting the language, and translating it would be wrong.
      Allowed : constant array (Positive range <>) of US.Unbounded_String :=
        [US.To_Unbounded_String ("in out"),
         US.To_Unbounded_String ("and then"),
         US.To_Unbounded_String ("or else"),
         US.To_Unbounded_String ("constant String"),
         US.To_Unbounded_String ("not in")];

      function Is_Allowed (Text : String) return Boolean;
      function Is_Prose (Text : String) return Boolean;

      function Is_Allowed (Text : String) return Boolean is
      begin
         for Item of Allowed loop
            if US.To_String (Item) = Text then
               return True;
            end if;
         end loop;

         return False;
      end Is_Allowed;

      --  Words, at least two of them, with a lower-case letter somewhere.
      --
      --  The lower-case letter is what keeps this from firing on an
      --  identifier -- those are caught by the check above and reported as the
      --  different thing they are. Ordinary punctuation is allowed *inside*
      --  the run of words rather than rejected: a sentence with a full stop in
      --  it is still a sentence, and requiring letters and spaces only is how
      --  `which is a defect rather than noise. See ...` went unnoticed.
      --
      --  What is still rejected outright is a literal carrying anything that
      --  belongs to a format rather than to a language: a brace, a percent, a
      --  backslash, a control character.
      function Is_Prose (Text : String) return Boolean is
         Words   : Natural := 0;
         Lettered : Boolean := False;
         Small   : Boolean := False;
      begin
         if Text'Length < 8 then
            return False;
         end if;

         for Position in Text'Range loop
            case Text (Position) is
               when 'a' .. 'z' =>
                  Small    := True;
                  Lettered := True;

               when 'A' .. 'Z' =>
                  Lettered := True;

               when '0' .. '9'
                  | '.' | ',' | ';' | ':' | '-' | '/' | '(' | ')'
                  | ''' =>
                  null;

               when ' ' =>
                  if Position = Text'First or else Position = Text'Last
                    or else Text (Position - 1) = ' '
                  then
                     return False;
                  end if;

                  --  Counted only when it held a letter. `Character'Val (27)`
                  --  is two runs and one word, and it is the escape rule's own
                  --  needle rather than anything a user reads.
                  if Lettered then
                     Words := Words + 1;
                  end if;

                  Lettered := False;

               when others =>
                  return False;
            end case;
         end loop;

         if Lettered then
            Words := Words + 1;
         end if;

         return Words >= 2 and then Small;
      end Is_Prose;
      --  Both trees: the shell's own sources and the repository tooling's.
      procedure Scan (Files : Project_Tools.Files.Path_List);

      procedure Scan (Files : Project_Tools.Files.Path_List) is
      begin
         for Path of Files loop
            declare
               Full    : constant String := US.To_String (Path);
               Content : constant String := Read_If_Present (Full);
               From    : Natural := Content'First;
            begin
               Into.Checks_Run := Into.Checks_Run + 1;

               while From <= Content'Last loop
                  declare
                     Stop : Natural := From;
                  begin
                     while Stop <= Content'Last
                       and then Content (Stop) /= Ada.Characters.Latin_1.LF
                     loop
                        Stop := Stop + 1;
                     end loop;

                     declare
                        Line   : constant String := Content (From .. Stop - 1);
                        Opened : Natural := 0;
                     begin
                        --  A comment is not source. Quoting a sentence while
                        --  explaining why it is not written here has to stay
                        --  possible, or the reasoning goes out with the defect.
                        if Project_Tools.Text.Contains (Line, "--") then
                           null;
                        else
                           for Position in Line'Range loop
                              if Line (Position) = '"' then
                                 if Opened = 0 then
                                    Opened := Position;
                                 else
                                    declare
                                       Inside : constant String :=
                                         Line (Opened + 1 .. Position - 1);
                                    begin
                                       if Is_Prose (Inside)
                                         and then not Is_Allowed (Inside)
                                       then
                                          Add (Into, Key_Prose_As_Text,
                                               [Msg.Named
                                                  ("path",
                                                   Ada.Directories.Simple_Name
                                                     (Full)),
                                                Msg.Named ("text", Inside)]);
                                       end if;
                                    end;

                                    Opened := 0;
                                 end if;
                              end if;
                           end loop;
                        end if;
                     end;

                     From := Stop + 1;
                  end;
               end loop;
            end;
         end loop;
      end Scan;
   begin
      Scan (Source_Files (Root));
      Scan (Tooling_Files (Root));
   end Check_No_Prose_As_Text;

   ------------------------------
   -- Check_No_Forbidden_Units --
   ------------------------------

   --  The names one text mentions, in the order they first appear.
   package Name_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => US.Unbounded_String,
      "=" => US."=");

   --  Whether a list already holds a name.
   function Holds (Within : Name_Vectors.Vector; Name : String)
      return Boolean
   is (for some Item of Within => US.To_String (Item) = Name);

   procedure Check_Grammar_Covers_The_Syntax
     (Root : String; Into : in out Report)
   is
      Syntax : constant String :=
        Read_If_Present
          (Project_Tools.Files.Join
             (Root, "src/library/adash-language-syntax.ads"));
      Grammar : constant String :=
        Read_If_Present
          (Project_Tools.Files.Join (Root, "docs/grammar-reference.md"));

      --  Every `Node_X` written in one of the two, as a set of names. Read out
      --  of the text rather than out of the compiler, because what this
      --  compares is two documents: the enumeration is the parser's own list
      --  of what it can build, and the grammar is the account of it.
      procedure Each_Node_Kind
        (Within  : String;
         Listed  : Boolean;
         Found   : in out Name_Vectors.Vector);

      procedure Each_Node_Kind
        (Within  : String;
         Listed  : Boolean;
         Found   : in out Name_Vectors.Vector)
      is
         Position : Natural := Within'First;
      begin
         while Position < Within'Last loop
            declare
               At_Node : constant Natural :=
                 Project_Tools.Text.Index_From (Within, "Node_", Position);
            begin
               exit when At_Node = 0;

               declare
                  Stop : Natural := At_Node + 5;

                  --  An enumeration literal, told from a type named after the
                  --  enumeration by where it sits: the literals are the only
                  --  `Node_` names written six spaces in, which is how this
                  --  file lays a list of them out. A file laid out differently
                  --  fails this check loudly rather than passing it quietly.
                  Is_Literal : constant Boolean :=
                    At_Node > Within'First + 6
                    and then Within (At_Node - 7) = Ada.Characters.Latin_1.LF
                    and then (for all Blank in At_Node - 6 .. At_Node - 1 =>
                                Within (Blank) = ' ');
               begin
                  while Stop <= Within'Last
                    and then (Within (Stop) in 'A' .. 'Z' | 'a' .. 'z' | '_'
                              or else Within (Stop) in '0' .. '9')
                  loop
                     Stop := Stop + 1;
                  end loop;

                  declare
                     Name : constant String := Within (At_Node .. Stop - 1);
                  begin
                     if Name'Length > 5
                       and then (not Listed or else Is_Literal)
                       and then not Holds (Found, Name)
                     then
                        Found.Append (US.To_Unbounded_String (Name));
                     end if;
                  end;

                  Position := Stop;
               end;
            end;
         end loop;
      end Each_Node_Kind;

      In_Syntax  : Name_Vectors.Vector;
      In_Grammar : Name_Vectors.Vector;

   begin
      if Syntax = "" or else Grammar = "" then
         return;
      end if;

      --  The enumeration's own literals on one side -- `Node_Id` and
      --  `Node_List` are types named after it rather than kinds a parser can
      --  build -- and every mention on the other.
      Each_Node_Kind (Syntax, Listed => True, Found => In_Syntax);
      Each_Node_Kind (Grammar, Listed => False, Found => In_Grammar);

      --  Both directions. A construct the parser can build and the grammar
      --  does not mention is the drift this check exists for; a name the
      --  grammar mentions and the parser cannot build is a production for
      --  something that is gone.
      for Name of In_Syntax loop
         Into.Checks_Run := Into.Checks_Run + 1;

         if not Holds (In_Grammar, US.To_String (Name)) then
            Add (Into, Key_Grammar_Missing,
                 [1 => Msg.Named ("name", US.To_String (Name))]);
         end if;
      end loop;

      for Name of In_Grammar loop
         Into.Checks_Run := Into.Checks_Run + 1;

         if not Holds (In_Syntax, US.To_String (Name)) then
            Add (Into, Key_Grammar_Unknown,
                 [1 => Msg.Named ("name", US.To_String (Name))]);
         end if;
      end loop;
   end Check_Grammar_Covers_The_Syntax;

   procedure Check_No_Forbidden_Units (Root : String; Into : in out Report) is
   begin
      for Path of Source_Files (Root) loop
         declare
            Full    : constant String := US.To_String (Path);
            Content : constant String := Read_If_Present (Full);
         begin
            for Unit in Forbidden_Unit loop
               Into.Checks_Run := Into.Checks_Run + 1;

               if Project_Tools.Text.Contains (Content, "with " & Forbidden_Name (Unit))
               then
                  Add (Into, Key_Forbidden_Dependency,
                       [Msg.Named ("path", Ada.Directories.Simple_Name (Full)),
                        Msg.Named ("unit", Forbidden_Name (Unit))]);
               end if;
            end loop;
         end;
      end loop;
   end Check_No_Forbidden_Units;

   -----------
   -- Check --
   -----------

   procedure Check (Root : String; Into : in out Report) is
   begin
      Check_Grammar_Covers_The_Syntax (Root, Into);
      Check_Required_Files (Root, Into);
      Check_Required_Directories (Root, Into);
      Check_Version_Consistency (Root, Into);
      Check_Package_Inventory (Root, Into);
      Check_Message_Catalog (Root, Into);
      Check_No_Terminal_Escapes (Root, Into);
      Check_No_Silent_Truncation (Root, Into);
      Check_CI_Clones_Pins (Root, Into);
      Check_No_Identifiers_As_Text (Root, Into);
      Check_No_Prose_As_Text (Root, Into);
      Check_No_Forbidden_Units (Root, Into);
   end Check;

end Adash_Tests.Repository;

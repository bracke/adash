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
   Key_Catalog_Missing_Key  : constant String := "tooling.check.catalog_missing_key";
   Key_Catalog_Unreadable   : constant String := "tooling.check.catalog_unreadable";
   Key_Escape_Sequence      : constant String := "tooling.check.escape_sequence";
   Key_Identifier_As_Text   : constant String :=
     "tooling.check.identifier_as_text";
   Key_Prose_As_Text        : constant String :=
     "tooling.check.prose_as_text";
   Key_Forbidden_Dependency : constant String := "tooling.check.forbidden_dependency";
   Key_Inventory_Missing    : constant String := "tooling.check.inventory_missing";
   Key_Inventory_Unlisted   : constant String := "tooling.check.inventory_unlisted";

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

      declare
         From_Manifest : constant String :=
           Project_Tools.TOML.String_Value_After (Manifest, "version", Manifest'First);
         From_Inventory : constant String :=
           Project_Tools.TOML.String_Value_After (Inventory, "version", Inventory'First);
      begin
         if From_Manifest /= From_Inventory then
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
                  Value : constant String :=
                    Project_Tools.TOML.String_Value_After (Inventory, "spec", Position);
               begin
                  Into.Checks_Run := Into.Checks_Run + 1;

                  if Value /= ""
                    and then not Project_Tools.Files.File_Exists (Join (Root, Value))
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
      Check_Required_Files (Root, Into);
      Check_Required_Directories (Root, Into);
      Check_Version_Consistency (Root, Into);
      Check_Package_Inventory (Root, Into);
      Check_Message_Catalog (Root, Into);
      Check_No_Terminal_Escapes (Root, Into);
      Check_No_Identifiers_As_Text (Root, Into);
      Check_No_Prose_As_Text (Root, Into);
      Check_No_Forbidden_Units (Root, Into);
   end Check;

end Adash_Tests.Repository;

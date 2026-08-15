with Ada.Directories;

with Adash.Commands;
with Hostkit.Fs;

with Adash.Language.Lexer;
with Adash.Language.Symbols;
with Adash.Language.Tokens;
with Adash.Predefined;

package body Adash.Interactive.Completion is

   use type Ada.Directories.File_Kind;

   use Ada.Strings.Unbounded;

   package M renames Adash.Messages;

   --------------------
   -- Make_Request --
   --------------------

   function Make_Request
     (Line        : String;
      Cursor      : Positive;
      Search_Path : String := "") return Request is
   begin
      return (Line        => M.Named ("line", Line),
              Cursor      => Cursor,
              Search_Path => M.Named ("path", Search_Path));
   end Make_Request;

   ---------------
   -- Insertion --
   ---------------

   function Insertion (Item : Candidate) return String is
   begin
      return To_String (Item.Insertion);
   end Insertion;

   -------------
   -- Display --
   -------------

   function Display (Item : Candidate) return String is
   begin
      return To_String (Item.Display);
   end Display;

   ------------
   -- Source --
   ------------

   function Source (Item : Candidate) return Source_Kind is
   begin
      return Item.Source;
   end Source;

   --------------
   -- Replaces --
   --------------

   function Replaces (Item : Candidate) return Adash.Source.Span is
   begin
      return Item.Replaces;
   end Replaces;

   -----------------
   -- Description --
   -----------------

   function Description (Item : Candidate) return M.Message_Id is
   begin
      return Item.Description;
   end Description;

   ----------
   -- Role --
   ----------

   function Role (Item : Candidate) return Adash.Terminal.Style_Role is
   begin
      return Item.Role;
   end Role;

   -----------
   -- Count --
   -----------

   function Count (Item : Candidate_List) return Natural is
   begin
      return Natural (Item.Items.Length);
   end Count;

   -------------
   -- Element --
   -------------

   function Element (Item : Candidate_List; Index : Positive) return Candidate is
   begin
      return Item.Items.Element (Index);
   end Element;

   ---------------------
   -- Common_Prefix --
   ---------------------

   function Common_Prefix (Item : Candidate_List) return String is
   begin
      if Item.Items.Is_Empty then
         return "";
      end if;

      declare
         Result : Unbounded_String := Item.Items.Element (1).Insertion;
      begin
         for Index in 2 .. Natural (Item.Items.Length) loop
            declare
               Other : constant String :=
                 To_String (Item.Items.Element (Index).Insertion);
               Mine  : constant String := To_String (Result);
               Keep  : Natural := 0;
            begin
               while Keep < Mine'Length and then Keep < Other'Length
                 and then Mine (Mine'First + Keep) = Other (Other'First + Keep)
               loop
                  Keep := Keep + 1;
               end loop;

               Result := To_Unbounded_String (Mine (Mine'First .. Mine'First + Keep - 1));
            end;
         end loop;

         return To_String (Result);
      end;
   end Common_Prefix;

   --  The prefix as a pattern the host can match, in either case.
   --
   --  Everything else in this list folds case -- `QU` completes to `quit`,
   --  because the language does not care and neither should the list. A host
   --  glob does care, on the two hosts where a file name is case-sensitive, so
   --  each letter is written as the class of its two cases. What is inserted
   --  is the program's own spelling either way, so a name typed in the wrong
   --  case completes to one that runs.
   --
   --  A prefix holding a character the pattern language reads specially is
   --  handed over as "*" instead. Listing more and filtering here is slower
   --  and right; guessing at an escape is fast and wrong, and the escape
   --  differs between the hosts.
   --
   --  @param Prefix What the user has typed of the name.
   --  @return A pattern for Ada.Directories.Start_Search.
   function Host_Pattern (Prefix : String) return String;

   function Host_Pattern (Prefix : String) return String is
      Built : Unbounded_String;
   begin
      for Index in Prefix'Range loop
         declare
            Letter : constant Character := Prefix (Index);
         begin
            case Letter is
               when '*' | '?' | '[' | ']' | '\' | '{' | '}' | '(' | ')'
                  | '|' | '^' | '$' | '+' =>
                  return "*";

               when 'a' .. 'z' =>
                  Append (Built, "[" & Letter & Character'Val
                            (Character'Pos (Letter)
                             - Character'Pos ('a') + Character'Pos ('A')) & "]");

               when 'A' .. 'Z' =>
                  Append (Built, "[" & Letter & Character'Val
                            (Character'Pos (Letter)
                             - Character'Pos ('A') + Character'Pos ('a')) & "]");

               when others =>
                  Append (Built, Letter);
            end case;
         end;
      end loop;

      return To_String (Built) & "*";
   end Host_Pattern;

   --  Whether this callee takes a program name at this argument, folded as
   --  the language folds a name.
   --
   --  Written out rather than derived from the command registry, which says a
   --  parameter is a String without saying that the String is a program: `set
   --  ("PATH=...")` takes one too and completing a program there would be
   --  nonsense. The list is short because the shell has one way of running a
   --  program and a handful of spellings for it.
   --
   --  @param Callee The name in front of the parenthesis, folded.
   --  @param Argument Which argument the cursor is in, from one.
   --  @return True when a program name belongs there.
   function Runs_A_Program
     (Callee : String; Argument : Positive) return Boolean
   is (case Argument is
          when 1 =>
             Callee in "run" | "start" | "pipe" | "output_of" | "status_of",
          when 2 =>
             Callee in "run_into" | "run_append" | "run_new" | "run_from",
          when others => False);

   --  Whether the word starting here is inside the string that names a
   --  program to run.
   --
   --  Two questions, both answered by reading the line rather than parsing it:
   --  a half-typed line is exactly the input a parser reports as broken, and
   --  what is wanted is a prefix.
   --
   --  Is the cursor inside a string at all -- counted by quotes, where a
   --  doubled one inside a literal toggles twice and so leaves the count where
   --  it was. And is that string the argument that names a program: the call
   --  it belongs to is found by walking back to the parenthesis that is still
   --  open, the name in front of that is the callee, and the commas between
   --  say which argument this is.
   --
   --  @param Line The line as typed.
   --  @param Word Where the word being completed starts.
   --  @return True when a program name belongs there.
   function Naming_A_Program (Line : String; Word : Natural) return Boolean;

   function Naming_A_Program (Line : String; Word : Natural) return Boolean is
      Inside : Boolean := False;
      Depth  : Natural := 0;

      --  Where the innermost call that is still open begins, and how many
      --  commas have been passed inside it.
      Opened : Natural := 0;
      Commas : Natural := 0;

      --  A stack would be the general answer; two levels is what a program
      --  argument is ever written at -- `run ("x")` and `pipe (Output_Of
      --  ("y"))` -- and the innermost open call is the only one this asks
      --  about.
      Marks : array (1 .. 16) of Natural := [others => 0];
      Counts : array (1 .. 16) of Natural := [others => 0];
   begin
      if Word <= Line'First then
         return False;
      end if;

      for Index in Line'First .. Natural'Min (Word - 1, Line'Last) loop
         if Line (Index) = '"' then
            Inside := not Inside;

         elsif not Inside then
            case Line (Index) is
               when '(' =>
                  Depth := Depth + 1;

                  if Depth <= Marks'Last then
                     Marks (Depth) := Index;
                     Counts (Depth) := 0;
                  end if;

               when ')' =>
                  if Depth > 0 then
                     Depth := Depth - 1;
                  end if;

               when ',' =>
                  if Depth in 1 .. Counts'Last then
                     Counts (Depth) := Counts (Depth) + 1;
                  end if;

               when others =>
                  null;
            end case;
         end if;
      end loop;

      --  Not in a string, so whatever is being typed is a name in the
      --  language and not the text of an argument.
      if not Inside or else Depth not in 1 .. Marks'Last then
         return False;
      end if;

      Opened := Marks (Depth);
      Commas := Counts (Depth);

      --  The name in front of the parenthesis.
      declare
         Stop : Natural := Opened - 1;
      begin
         while Stop >= Line'First and then Line (Stop) = ' ' loop
            Stop := Stop - 1;
         end loop;

         declare
            Start : Natural := Stop;
         begin
            while Start > Line'First
              and then Adash.Language.Lexer.Is_Identifier_Part (Line (Start - 1))
            loop
               Start := Start - 1;
            end loop;

            if Start > Stop then
               return False;
            end if;

            return Runs_A_Program
                     (Adash.Language.Symbols.Fold (Line (Start .. Stop)),
                      Commas + 1);
         end;
      end;
   end Naming_A_Program;

   --  The word the cursor is in or at the end of, and where it starts.
   procedure Word_At
     (Line   : String;
      Cursor : Positive;
      First  : out Natural;
      Last   : out Natural)
   is
      Stop : constant Natural := Natural'Min (Cursor - 1, Line'Length);
   begin
      Last  := Line'First + Stop - 1;
      First := Last + 1;

      --  Backwards from the cursor over what an identifier or a path may be
      --  made of. Doing it on characters rather than on tokens is deliberate:
      --  a half-typed word is often not a token yet, and the lexer would
      --  report it as an error rather than hand back a prefix.
      while First > Line'First
        and then (Adash.Language.Lexer.Is_Identifier_Part (Line (First - 1))
                  or else Line (First - 1) = '.'
                  or else Line (First - 1) = '/')
      loop
         First := First - 1;
      end loop;
   end Word_At;

   --------------
   -- Complete --
   --------------

   function Complete (For_Request : Request) return Candidate_List is
      Line   : constant String := M.Value (For_Request.Line);
      Result : Candidate_List;

      First, Last : Natural;

      function Prefix return String
      is (if Last >= First and then First >= Line'First and then Last <= Line'Last
          then Line (First .. Last) else "");

      function Matches (Name : String) return Boolean is
         Wanted : constant String := Adash.Language.Symbols.Fold (Prefix);
         Folded : constant String := Adash.Language.Symbols.Fold (Name);
      begin
         if Wanted'Length = 0 then
            return True;
         end if;

         return Folded'Length >= Wanted'Length
           and then Folded (Folded'First .. Folded'First + Wanted'Length - 1) = Wanted;
      end Matches;

      procedure Offer
        (Text        : String;
         From        : Source_Kind;
         Describes   : M.Message_Id;
         Shown_As    : Adash.Terminal.Style_Role)
      is
      begin
         Result.Items.Append
           (Candidate'(Insertion   => To_Unbounded_String (Text),
                       Display     => To_Unbounded_String (Text),
                       Source      => From,
                       Replaces    => (First => Positive'Max (First, 1),
                                       Last  => Last),
                       Description => Describes,
                       Role        => Shown_As));
      end Offer;

   begin
      Word_At (Line, For_Request.Cursor, First, Last);

      --  Commands first: the shell's own vocabulary is what a user is most
      --  often reaching for. Within a source, by the order the registry holds,
      --  which is fixed -- so the list does not move under the user's finger
      --  between keystrokes.
      for Index in 1 .. Adash.Commands.Count loop
         declare
            About : constant Adash.Commands.Metadata :=
              Adash.Commands.Entry_At (Index);
            Name  : constant String := M.Value (About.Name);
         begin
            if Matches (Name) then
               Offer (Name, From_Command, About.Description,
                      Adash.Terminal.Role_Known_Name);
            end if;
         end;
      end loop;

      for Index in 1 .. Adash.Predefined.Count loop
         declare
            About : constant Adash.Predefined.Metadata :=
              Adash.Predefined.Entry_At (Index);
            Name  : constant String := M.Value (About.Name);
         begin
            if Matches (Name) then
               Offer (Name, From_Predefined, About.Description,
                      Adash.Terminal.Role_Known_Name);
            end if;
         end;
      end loop;

      for Word in Adash.Language.Tokens.Reserved_Word loop
         declare
            Spelling : constant String :=
              Adash.Language.Tokens.Spelling (Word);
         begin
            if Matches (Spelling) then
               Offer (Spelling, From_Keyword, M.Msg_Completion_Keyword,
                      Adash.Terminal.Role_Keyword);
            end if;
         end;
      end loop;

      --  Programs, where the cursor is in the string that says which one to
      --  run. Nowhere else: a program name means nothing outside that string,
      --  and a list of every executable on the machine offered at a bare
      --  prompt would bury the shell's own vocabulary.
      if Naming_A_Program (Line, First) and then Prefix'Length > 0 then
         declare
            Path : constant String := M.Value (For_Request.Search_Path);

            --  Collected and then sorted, because a directory listing comes
            --  back in whatever order the filesystem holds it, and because the
            --  same name in two directories on the path is one program to
            --  offer rather than two.
            Names : Candidate_Vectors.Vector;

            function Already (Text : String) return Boolean;

            function Already (Text : String) return Boolean is
            begin
               for Item of Names loop
                  if To_String (Item.Insertion) = Text then
                     return True;
                  end if;
               end loop;

               return False;
            end Already;

            From : Natural := Path'First;
         begin
            while From <= Path'Last loop
               declare
                  Stop : Natural := From;
               begin
                  while Stop <= Path'Last
                    and then Path (Stop) /= Hostkit.Fs.Search_Path_Delimiter
                  loop
                     Stop := Stop + 1;
                  end loop;

                  declare
                     Directory : constant String := Path (From .. Stop - 1);

                     Search : Ada.Directories.Search_Type;
                     Found  : Ada.Directories.Directory_Entry_Type;
                  begin
                     if Directory /= ""
                       and then Ada.Directories.Exists (Directory)
                       and then Ada.Directories.Kind (Directory)
                                = Ada.Directories.Directory
                     then
                        --  Asked of the host with the prefix in it, rather
                        --  than listing the directory and matching here. A
                        --  search path is ten directories of a few thousand
                        --  files, and walking all of them per keystroke costs
                        --  tens of milliseconds -- a pause a user feels on
                        --  every Tab. The host answers the same question from
                        --  its own index in a fraction of that.
                        --
                        --  In either case, because the rest of this list folds
                        --  case and a name typed in the wrong one is still the
                        --  name that was meant. Matches below folds too, so a
                        --  host whose own matching is already case-blind
                        --  agrees with one whose is not.
                        Ada.Directories.Start_Search
                          (Search, Directory, Host_Pattern (Prefix),
                           [Ada.Directories.Ordinary_File => True,
                            Ada.Directories.Directory     => False,
                            Ada.Directories.Special_File  => False]);

                        while Ada.Directories.More_Entries (Search) loop
                           Ada.Directories.Get_Next_Entry (Search, Found);

                           declare
                              Simple : constant String :=
                                Ada.Directories.Simple_Name (Found);

                              --  What a user would type. Windows supplies
                              --  ".exe" for a name written without one, so
                              --  offering `git.exe` would be offering the
                              --  spelling nobody uses for the program `git`.
                              --  Everything else keeps the name it has: a
                              --  `.bat` is run by the command interpreter
                              --  rather than by the loader, and its name has
                              --  to be written out.
                              Supplied : constant String :=
                                Hostkit.Fs.Executable_Suffix;

                              Offered : constant String :=
                                (if Supplied /= ""
                                   and then Simple'Length > Supplied'Length
                                   and then Adash.Language.Symbols.Fold
                                     (Simple
                                        (Simple'Last - Supplied'Length + 1
                                         .. Simple'Last))
                                     = Adash.Language.Symbols.Fold (Supplied)
                                 then Simple
                                        (Simple'First
                                         .. Simple'Last - Supplied'Length)
                                 else Simple);
                           begin
                              --  The name is matched before the host is asked
                              --  whether the file can be run. The question
                              --  costs a call per file, and a directory of two
                              --  thousand of them answered on every Tab is a
                              --  pause a user feels; the prefix rules out
                              --  nearly all of them for nothing.
                              --  What the shell could actually start, which
                              --  is narrower than what the host calls a
                              --  program: a `.bat`, a `.cmd`, a `.ps1` and an
                              --  `.msi` are all executables to Windows and
                              --  none of them is started by the loader.
                              --  Offering one would be offering a name that
                              --  fails when it is run, which is worse than
                              --  offering nothing -- the user would read the
                              --  failure as being about the program rather
                              --  than about the shell.
                              if Matches (Offered)
                                and then not Already (Offered)
                                and then Hostkit.Fs.Starts_Without_An_Interpreter
                                           (Ada.Directories.Compose
                                              (Directory, Simple))
                              then
                                 Names.Append
                                   (Candidate'
                                      (Insertion   => To_Unbounded_String (Offered),
                                       Display     => To_Unbounded_String (Offered),
                                       Source      => From_Program,
                                       Replaces    =>
                                         (First => Positive'Max (First, 1),
                                          Last  => Last),
                                       Description => M.Msg_Completion_Program,
                                       Role        => Adash.Terminal.Role_Known_Name));
                              end if;
                           end;
                        end loop;

                        Ada.Directories.End_Search (Search);
                     end if;
                  exception
                     when others =>
                        --  A directory on the path that cannot be listed --
                        --  removed, or not ours to read -- is one fewer place
                        --  to look, not a failure of the whole answer.
                        null;
                  end;

                  From := Stop + 1;
               end;
            end loop;

            --  Insertion sort by insertion text, as the paths below: short
            --  list, stable and total, so two runs agree.
            for Outer in 2 .. Natural (Names.Length) loop
               declare
                  Current : constant Candidate := Names.Element (Outer);
                  Inner   : Natural := Outer - 1;
               begin
                  while Inner >= 1
                    and then Names.Element (Inner).Insertion > Current.Insertion
                  loop
                     Names.Replace_Element (Inner + 1, Names.Element (Inner));
                     Inner := Inner - 1;
                  end loop;

                  Names.Replace_Element (Inner + 1, Current);
               end;
            end loop;

            for Item of Names loop
               Result.Items.Append (Item);
            end loop;
         end;
      end if;

      --  Paths only when the prefix looks like one. Listing the working
      --  directory for every empty prefix would bury the shell's own
      --  vocabulary under whatever happens to be in the directory.
      if Prefix'Length > 0
        and then (Prefix (Prefix'First) = '.' or else Prefix (Prefix'First) = '/')
      then
         declare
            Directory : constant String :=
              (if Ada.Directories.Exists (Prefix)
                 and then Ada.Directories.Kind (Prefix) = Ada.Directories.Directory
               then Prefix
               else Ada.Directories.Containing_Directory (Prefix));

            Search : Ada.Directories.Search_Type;
            Found  : Ada.Directories.Directory_Entry_Type;

            --  Collected and then sorted by name, because a directory listing
            --  comes back in whatever order the filesystem holds it and that
            --  order is not stable between machines.
            Names : Candidate_Vectors.Vector;
         begin
            if Ada.Directories.Exists (Directory) then
               Ada.Directories.Start_Search
                 (Search, Directory, "",
                  [Ada.Directories.Ordinary_File => True,
                   Ada.Directories.Directory     => True,
                   Ada.Directories.Special_File  => False]);

               while Ada.Directories.More_Entries (Search) loop
                  Ada.Directories.Get_Next_Entry (Search, Found);

                  declare
                     Simple : constant String :=
                       Ada.Directories.Simple_Name (Found);
                     Full   : constant String :=
                       Ada.Directories.Compose (Directory, Simple);
                  begin
                     if Simple /= "." and then Simple /= ".."
                       and then Matches (Full)
                     then
                        Names.Append
                          (Candidate'(Insertion   => To_Unbounded_String (Full),
                                      Display     => To_Unbounded_String (Simple),
                                      Source      => From_Path,
                                      Replaces    => (First => Positive'Max (First, 1),
                                                      Last  => Last),
                                      Description => M.Msg_Completion_Path,
                                      Role        => Adash.Terminal.Role_Plain));
                     end if;
                  end;
               end loop;

               Ada.Directories.End_Search (Search);

               --  Insertion sort by insertion text: the list is short and the
               --  sort has to be stable and total, which is what makes two
               --  runs on one directory agree.
               for Outer in 2 .. Natural (Names.Length) loop
                  declare
                     Current : constant Candidate := Names.Element (Outer);
                     Inner   : Natural := Outer - 1;
                  begin
                     while Inner >= 1
                       and then Names.Element (Inner).Insertion > Current.Insertion
                     loop
                        Names.Replace_Element (Inner + 1, Names.Element (Inner));
                        Inner := Inner - 1;
                     end loop;

                     Names.Replace_Element (Inner + 1, Current);
                  end;
               end loop;

               for Item of Names loop
                  Result.Items.Append (Item);
               end loop;
            end if;
         exception
            when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
               --  A prefix that names nothing openable. Not an error: the user
               --  is mid-word, and offering nothing is the right answer.
               null;
         end;
      end if;

      return Result;
   end Complete;

end Adash.Interactive.Completion;

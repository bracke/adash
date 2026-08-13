with Ada.Directories;

with Adash.Commands;
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

   function Make_Request (Line : String; Cursor : Positive) return Request is
   begin
      return (Line   => M.Named ("line", Line),
              Cursor => Cursor);
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

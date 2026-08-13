with Ada.Directories;

with Hostkit.Host;

with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;

package body Adash.Persistence.History is

   use Ada.Strings.Unbounded;

   Newline : constant Character := Character'Val (16#0A#);

   ----------
   -- Path --
   ----------

   function Path return String is
   begin
      return Adash.Persistence.Path_For
               (Adash.Persistence.Data_Store, File_Name);
   end Path;

   --  What a session file is called, and how one is recognised again.
   Session_Prefix : constant String := "history-";
   Session_Suffix : constant String := ".jsonl";

   --  What a session holds while it runs.
   Owner_Suffix : constant String := ".owner";

   --  A number without the leading space Integer'Image puts on it.
   function Trimmed (Value : Integer) return String is
      Text : constant String := Integer'Image (Value);
   begin
      return Text (Text'First + 1 .. Text'Last);
   end Trimmed;

   -------------------
   -- Session_Path --
   -------------------

   function Session_Path return String is
      Own : constant Integer := Hostkit.Host.Own_Process_Id;
   begin
      if Own < 0 then
         --  A host that will not say which process this is cannot give a
         --  session a file of its own. The shared one is the honest answer.
         return Path;
      end if;

      return Adash.Persistence.Path_For
               (Adash.Persistence.Data_Store,
                Session_Prefix & Trimmed (Own) & Session_Suffix);
   end Session_Path;

   -----------
   -- Count --
   -----------

   function Count (Item : Log) return Natural is
   begin
      return Natural (Item.Lines.Length);
   end Count;

   --------------
   -- Entry_At --
   --------------

   function Entry_At (Item : Log; Index : Positive) return String is
   begin
      if Index > Natural (Item.Lines.Length) then
         return "";
      end if;

      return To_String (Item.Lines.Element (Index));
   end Entry_At;

   -------------
   -- Skipped --
   -------------

   function Skipped (Item : Log) return Natural is
   begin
      return Item.Damaged;
   end Skipped;

   ---------
   -- Add --
   ---------

   procedure Add (Item : in out Log; Line : String) is
   begin
      Item.Lines.Append (To_Unbounded_String (Line));
   end Add;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Log) is
   begin
      Item.Lines.Clear;
      Item.Damaged := 0;
   end Clear;

   ------------
   -- Encode --
   ------------

   function Encode (Line : String) return String is
      Document : Jsonlib.Documents.Document;
      Value    : constant Jsonlib.Documents.Node :=
        Jsonlib.Documents.New_String (Document, Line);
   begin
      --  Through jsonlib rather than by quoting the text here. A hand-written
      --  escaper is the obvious shortcut and the obvious bug: it works until
      --  somebody types a tab, or a byte below a space, or a backslash before
      --  a quote.
      Jsonlib.Documents.Set_Root (Document, Value);
      return Jsonlib.Serializers.To_String (Document);
   end Encode;

   ------------
   -- Decode --
   ------------

   function Decode (Text : String; Line : out Adash.Persistence.Contents)
                    return Boolean
   is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;

      use type Jsonlib.Documents.Value_Kind;
   begin
      Line := Null_Unbounded_String;

      Jsonlib.Parsers.Parse (Text, Document, Error);

      if Jsonlib.Errors.Failed (Error) then
         return False;
      end if;

      --  A line that parses as JSON but is not a string is not one of ours.
      --  Refusing it rather than rendering it keeps the format one thing: a
      --  file where some lines were strings and some were objects would be a
      --  format nobody had decided on.
      if Jsonlib.Documents.Kind
           (Document, Jsonlib.Documents.Root (Document))
         /= Jsonlib.Documents.String_Value
      then
         return False;
      end if;

      Line := To_Unbounded_String
        (Jsonlib.Documents.As_String
           (Document, Jsonlib.Documents.Root (Document)));
      return True;
   end Decode;

   -----------------------
   -- Owner_Lock_Path --
   -----------------------

   function Owner_Lock_Path (For_File : String) return String is
   begin
      return For_File & Owner_Suffix;
   end Owner_Lock_Path;

   ---------------------------------
   -- Abandoned_Session_Files --
   ---------------------------------

   procedure Abandoned_Session_Files
     (Found : out Path_List; Count : out Natural)
   is
      Shared : constant String := Path;
      Mine   : constant String := Session_Path;
   begin
      Found := [others => Ada.Strings.Unbounded.Null_Unbounded_String];
      Count := 0;

      if Shared = "" then
         return;
      end if;

      declare
         Store : constant String :=
           Ada.Directories.Containing_Directory (Shared);
         Search : Ada.Directories.Search_Type;
         Item   : Ada.Directories.Directory_Entry_Type;
      begin
         if not Ada.Directories.Exists (Store) then
            return;
         end if;

         --  Ordinary files only. A directory named like a session file is not
         --  one, and following it would be a different kind of mistake.
         Ada.Directories.Start_Search
           (Search, Store, "",
            [Ada.Directories.Ordinary_File => True, others => False]);

         while Ada.Directories.More_Entries (Search) loop
            exit when Count = Max_Session_Files;

            Ada.Directories.Get_Next_Entry (Search, Item);

            declare
               Name : constant String := Ada.Directories.Simple_Name (Item);
               Full : constant String := Ada.Directories.Full_Name (Item);
            begin
               if Name'Length > Session_Prefix'Length + Session_Suffix'Length
                 and then Name (Name'First ..
                                Name'First + Session_Prefix'Length - 1)
                          = Session_Prefix
                 and then Name (Name'Last - Session_Suffix'Length + 1 ..
                                Name'Last) = Session_Suffix
                 and then Full /= Mine
               then
                  Count := Count + 1;
                  Found (Count) :=
                    Ada.Strings.Unbounded.To_Unbounded_String (Full);
               end if;
            end;
         end loop;

         Ada.Directories.End_Search (Search);
      end;

   exception
      when others =>
         --  A store that cannot be listed is not a failure worth reporting at
         --  the moment a shell is starting: the sweep is tidying, and a shell
         --  that refused to start because it could not tidy would be worse
         --  than one that left a file behind.
         Count := 0;
   end Abandoned_Session_Files;

   ----------
   -- Load --
   ----------

   procedure Load
     (Into   : out Log;
      Result : out Adash.Persistence.Outcome;
      Limit  : Positive := 1_000;
      From   : String := "")
   is
      Text   : Adash.Persistence.Contents;
      Chosen : constant String := (if From = "" then Path else From);
   begin
      Into.Lines.Clear;
      Into.Damaged := 0;

      Adash.Persistence.Read (Chosen, Text, Result);

      if not Adash.Persistence.Succeeded (Result) then
         return;
      end if;

      declare
         Raw   : constant String := To_String (Text);
         First : Natural := Raw'First;
      begin
         while First <= Raw'Last loop
            declare
               Stop : Natural := First;
            begin
               while Stop <= Raw'Last and then Raw (Stop) /= Newline loop
                  Stop := Stop + 1;
               end loop;

               declare
                  --  A trailing carriage return, from a file that has been
                  --  through a Windows editor. Dropped rather than made part
                  --  of the entry, where it would be invisible and would make
                  --  the line fail to parse.
                  Last : constant Natural :=
                    (if Stop - 1 >= First
                       and then Raw (Stop - 1) = Character'Val (16#0D#)
                     then Stop - 2 else Stop - 1);
                  Value : Adash.Persistence.Contents;
               begin
                  if Last >= First then
                     if Decode (Raw (First .. Last), Value) then
                        Into.Lines.Append (Value);
                     else
                        --  A truncated last line is the normal thing to find
                        --  in a file appended to at the end of a session. It
                        --  is counted rather than fatal: refusing the file
                        --  over it would throw away everything the user did.
                        Into.Damaged := Into.Damaged + 1;
                     end if;
                  end if;
               end;

               First := Stop + 1;
            end;
         end loop;

         --  Only the most recent are kept, so a long file does not become a
         --  long start-up. The rest were read and are dropped here rather than
         --  never read: finding the tail of a file needs the whole file, and
         --  seeking backwards through variable-length lines is a great deal of
         --  machinery for a file measured in kilobytes.
         while Natural (Into.Lines.Length) > Limit loop
            Into.Lines.Delete_First;
         end loop;
      end;
   end Load;

   ------------
   -- Append --
   ------------

   procedure Append
     (Line      : String;
      Result    : out Adash.Persistence.Outcome;
      Into_File : String := "")
   is
      Chosen : constant String := (if Into_File = "" then Path else Into_File);
   begin
      Adash.Persistence.Append_Line (Chosen, Encode (Line), Result);
   end Append;

   ----------
   -- Save --
   ----------

   procedure Save
     (Item      : Log;
      Result    : out Adash.Persistence.Outcome;
      Into_File : String := "")
   is
      Text   : Unbounded_String;
      Chosen : constant String := (if Into_File = "" then Path else Into_File);
   begin
      for Index in 1 .. Natural (Item.Lines.Length) loop
         Append (Text, Encode (To_String (Item.Lines.Element (Index))));
         Append (Text, Newline);
      end loop;

      Adash.Persistence.Write (Chosen, To_String (Text), Result);
   end Save;

end Adash.Persistence.History;

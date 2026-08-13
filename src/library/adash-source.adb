with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

with Adash.Messages;

package body Adash.Source is

   use Ada.Strings.Unbounded;

   function Decoded_Length (Lead : Character) return Natural;
   --  How many bytes the UTF-8 sequence starting with Lead occupies, or 0 when
   --  Lead cannot start one.

   function Validate_Utf8 (Text : String; Bad_At : out Natural) return Boolean;
   --  Whether Text is well-formed UTF-8, and where it first is not.

   procedure Build_Line_Map (Item : in out Buffer);
   --  Record where each line starts and where its text ends.

   ---------------------
   -- Decoded_Length --
   ---------------------

   function Decoded_Length (Lead : Character) return Natural is
      Value : constant Natural := Character'Pos (Lead);
   begin
      if Value < 16#80# then
         return 1;
      elsif Value < 16#C0# then
         --  A continuation byte cannot lead a sequence.
         return 0;
      elsif Value < 16#E0# then
         return 2;
      elsif Value < 16#F0# then
         return 3;
      elsif Value < 16#F5# then
         --  F5 and above would encode beyond U+10FFFF, which is not a
         --  character. Rejected here rather than decoded into a value nothing
         --  downstream can represent.
         return 4;
      else
         return 0;
      end if;
   end Decoded_Length;

   --------------------
   -- Validate_Utf8 --
   --------------------

   function Validate_Utf8 (Text : String; Bad_At : out Natural) return Boolean is
      Index : Natural := Text'First;
   begin
      Bad_At := 0;

      while Index <= Text'Last loop
         declare
            Needed : constant Natural := Decoded_Length (Text (Index));
         begin
            if Needed = 0 then
               Bad_At := Index;
               return False;
            end if;

            if Index + Needed - 1 > Text'Last then
               --  Truncated at the end of the input. Reported at the lead byte,
               --  which is the character the user would have to fix.
               Bad_At := Index;
               return False;
            end if;

            for Follower in Index + 1 .. Index + Needed - 1 loop
               if Character'Pos (Text (Follower)) not in 16#80# .. 16#BF# then
                  Bad_At := Follower;
                  return False;
               end if;
            end loop;

            --  Overlong encodings and surrogates are rejected too. Both are
            --  well-formed-looking sequences that decode to something they are
            --  not allowed to represent, and both are how a validator that
            --  only checks byte shapes gets used to smuggle a character past a
            --  later check.
            declare
               First_Byte  : constant Natural := Character'Pos (Text (Index));
               Second_Byte : constant Natural :=
                 (if Needed > 1 then Character'Pos (Text (Index + 1)) else 0);
            begin
               if Needed = 2 and then First_Byte < 16#C2# then
                  Bad_At := Index;
                  return False;
               end if;

               if Needed = 3
                 and then First_Byte = 16#E0#
                 and then Second_Byte < 16#A0#
               then
                  Bad_At := Index;
                  return False;
               end if;

               if Needed = 3
                 and then First_Byte = 16#ED#
                 and then Second_Byte >= 16#A0#
               then
                  --  A surrogate half. Not a character, and never valid UTF-8.
                  Bad_At := Index;
                  return False;
               end if;

               if Needed = 4
                 and then First_Byte = 16#F0#
                 and then Second_Byte < 16#90#
               then
                  Bad_At := Index;
                  return False;
               end if;

               if Needed = 4
                 and then First_Byte = 16#F4#
                 and then Second_Byte >= 16#90#
               then
                  Bad_At := Index;
                  return False;
               end if;
            end;

            Index := Index + Needed;
         end;
      end loop;

      return True;
   end Validate_Utf8;

   ---------------------
   -- Build_Line_Map --
   ---------------------

   procedure Build_Line_Map (Item : in out Buffer) is
      Text  : constant String := To_String (Item.Text);
      Index : Natural := Text'First;
      Start : Positive := 1;
   begin
      Item.Line_Starts.Clear;
      Item.Line_Ends.Clear;

      if Text'Length = 0 then
         --  An empty buffer still has one empty line, so a diagnostic at
         --  offset one has somewhere to point.
         Item.Line_Starts.Append (1);
         Item.Line_Ends.Append (0);
         return;
      end if;

      while Index <= Text'Last loop
         if Text (Index) = Character'Val (13)
           or else Text (Index) = Character'Val (10)
         then
            Item.Line_Starts.Append (Start);
            Item.Line_Ends.Append (Index - 1);

            --  CR LF is one terminator, not two empty lines. A file written on
            --  Windows would otherwise report twice the lines it has, and every
            --  line number in every diagnostic would be wrong.
            if Text (Index) = Character'Val (13)
              and then Index < Text'Last
              and then Text (Index + 1) = Character'Val (10)
            then
               Index := Index + 1;
            end if;

            Start := Index + 1;
         end if;

         Index := Index + 1;
      end loop;

      --  A file whose last line has no terminator is still a line. Dropping it
      --  would make the last error in such a file unreportable.
      Item.Line_Starts.Append (Start);
      Item.Line_Ends.Append (Text'Last);
   end Build_Line_Map;

   -------------------
   -- Make_Origin --
   -------------------

   function Make_Origin (Kind : Origin_Kind; Name : String) return Origin is
   begin
      return (Kind => Kind, Name => To_Unbounded_String (Name));
   end Make_Origin;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Origin) return Origin_Kind is
   begin
      return Item.Kind;
   end Kind;

   ----------
   -- Name --
   ----------

   function Name (Item : Origin) return String is
   begin
      return To_String (Item.Name);
   end Name;

   --------------
   -- Is_Empty --
   --------------

   function Is_Empty (Item : Span) return Boolean is
   begin
      return Item.Last < Item.First;
   end Is_Empty;

   ------------
   -- Length --
   ------------

   function Length (Item : Span) return Natural is
   begin
      if Is_Empty (Item) then
         return 0;
      end if;

      return Item.Last - Item.First + 1;
   end Length;

   ----------
   -- Join --
   ----------

   function Join (Left, Right : Span) return Span is
   begin
      --  An empty span still has a position, and a node built from one real
      --  child and one missing one should extend to where the missing one was
      --  expected. So an empty span contributes its First but not a Last.
      if Is_Empty (Left) and then Is_Empty (Right) then
         return (First => Positive'Min (Left.First, Right.First), Last => 0);
      elsif Is_Empty (Left) then
         return (First => Positive'Min (Left.First, Right.First), Last => Right.Last);
      elsif Is_Empty (Right) then
         return (First => Positive'Min (Left.First, Right.First), Last => Left.Last);
      end if;

      return (First => Positive'Min (Left.First, Right.First),
              Last  => Natural'Max (Left.Last, Right.Last));
   end Join;

   ----------
   -- Load --
   ----------

   function Load
     (Item  : in out Buffer;
      From  : Origin;
      Text  : String;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
      Bad_At : Natural;
   begin
      Error := Adash.Errors.Success;
      Item.Loaded := False;

      if not Validate_Utf8 (Text, Bad_At) then
         declare
            Offset : constant String := Natural'Image (Bad_At - Text'First + 1);
         begin
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Source_Invalid_Encoding,
               [Adash.Messages.Named ("source", Name (From)),
                Adash.Messages.Named
                  ("offset", Offset (Offset'First + 1 .. Offset'Last))]);
         end;
         return False;
      end if;

      Item.From := From;
      Item.Text := To_Unbounded_String (Text);
      Build_Line_Map (Item);
      Item.Loaded := True;

      return True;
   end Load;

   ----------------
   -- Load_File --
   ----------------

   function Load_File
     (Item  : in out Buffer;
      Path  : String;
      Kind  : Origin_Kind := Origin_File;
      Error : out Adash.Errors.Error_Info) return Boolean
   is
      use Ada.Streams;

      File   : Stream_IO.File_Type;
      Result : Unbounded_String;
   begin
      Error := Adash.Errors.Success;
      Item.Loaded := False;

      if not Ada.Directories.Exists (Path) then
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Source_Unreadable,
            [1 => Adash.Messages.Named ("source", Path)]);
         return False;
      end if;

      begin
         Stream_IO.Open (File, Stream_IO.In_File, Path);
      exception
         when Ada.IO_Exceptions.Name_Error
            | Ada.IO_Exceptions.Use_Error
            | Ada.IO_Exceptions.Status_Error =>
            --  A directory, or a file this user may not read. Reported rather
            --  than raised: a path a user typed being unreadable is an ordinary
            --  outcome, not a defect.
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Source_Unreadable,
               [1 => Adash.Messages.Named ("source", Path)]);
            return False;
      end;

      declare
         Chunk : Stream_Element_Array (1 .. 64 * 1024);
         Last  : Stream_Element_Offset;
      begin
         while not Stream_IO.End_Of_File (File) loop
            Stream_IO.Read (File, Chunk, Last);

            for Index in Chunk'First .. Last loop
               Append (Result, Character'Val (Natural (Chunk (Index))));
            end loop;
         end loop;

         Stream_IO.Close (File);
      exception
         when others =>
            if Stream_IO.Is_Open (File) then
               Stream_IO.Close (File);
            end if;

            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Source_Unreadable,
               [1 => Adash.Messages.Named ("source", Path)]);
            return False;
      end;

      return Load (Item, Make_Origin (Kind, Path), To_String (Result), Error);
   end Load_File;

   ----------------
   -- Is_Loaded --
   ----------------

   function Is_Loaded (Item : Buffer) return Boolean is
   begin
      return Item.Loaded;
   end Is_Loaded;

   ----------
   -- From --
   ----------

   function From (Item : Buffer) return Origin is
   begin
      return Item.From;
   end From;

   ------------
   -- Length --
   ------------

   function Length (Item : Buffer) return Natural is
   begin
      return Ada.Strings.Unbounded.Length (Item.Text);
   end Length;

   ----------
   -- Text --
   ----------

   function Text (Item : Buffer) return String is
   begin
      return To_String (Item.Text);
   end Text;

   -----------
   -- Slice --
   -----------

   function Slice (Item : Buffer; Extent : Span) return String is
      Size : constant Natural := Length (Item);
   begin
      if Is_Empty (Extent) or else Extent.First > Size then
         return "";
      end if;

      --  Clipped rather than raising. A diagnostic built from a span that is
      --  slightly wrong should still be reportable; failing here would replace
      --  a small reporting problem with a crash.
      return Ada.Strings.Unbounded.Slice
        (Item.Text, Extent.First, Natural'Min (Extent.Last, Size));
   end Slice;

   -----------
   -- Whole --
   -----------

   function Whole (Item : Buffer) return Span is
   begin
      return (First => 1, Last => Length (Item));
   end Whole;

   ---------------
   -- Where_Is --
   ---------------

   function Where_Is (Item : Buffer; Offset : Byte_Offset) return Location is
      Text    : constant String := To_String (Item.Text);
      Wanted  : constant Natural := Natural'Min (Offset, Natural'Max (Length (Item), 1));
      Result  : Location;
   begin
      if Item.Line_Starts.Is_Empty then
         return Result;
      end if;

      --  Binary search over the line starts. Linear would be fine for a typed
      --  line and painful for a large script full of errors, and this is on the
      --  path that reports every one of them.
      declare
         Low  : Positive := 1;
         High : Positive := Positive (Item.Line_Starts.Length);
         Line : Positive := 1;
      begin
         while Low <= High loop
            declare
               Middle : constant Positive := (Low + High) / 2;
            begin
               if Item.Line_Starts.Element (Middle) <= Wanted then
                  Line := Middle;
                  Low  := Middle + 1;
               else
                  exit when Middle = 1;
                  High := Middle - 1;
               end if;
            end;
         end loop;

         Result.Line := Line;

         --  Columns count characters, so continuation bytes do not advance it.
         --  A caret under the third character of a line with an accented letter
         --  before it has to be under the third character.
         declare
            Start  : constant Positive := Item.Line_Starts.Element (Line);
            Column : Positive := 1;
            Index  : Natural := Start;
         begin
            while Index < Wanted and then Index <= Text'Last loop
               if Character'Pos (Text (Index)) not in 16#80# .. 16#BF# then
                  Column := Column + 1;
               end if;

               Index := Index + 1;
            end loop;

            Result.Column := Column;
         end;
      end;

      return Result;
   end Where_Is;

   -----------------
   -- Line_Count --
   -----------------

   function Line_Count (Item : Buffer) return Positive is
   begin
      if Item.Line_Starts.Is_Empty then
         return 1;
      end if;

      return Positive (Item.Line_Starts.Length);
   end Line_Count;

   ------------------
   -- Line_Extent --
   ------------------

   function Line_Extent (Item : Buffer; Line : Positive) return Span is
   begin
      if Line > Natural (Item.Line_Starts.Length) then
         return Nowhere;
      end if;

      return (First => Item.Line_Starts.Element (Line),
              Last  => Item.Line_Ends.Element (Line));
   end Line_Extent;

   ----------------
   -- Line_Text --
   ----------------

   function Line_Text (Item : Buffer; Line : Positive) return String is
   begin
      return Slice (Item, Line_Extent (Item, Line));
   end Line_Text;

end Adash.Source;

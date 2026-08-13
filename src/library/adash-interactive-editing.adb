with Ada.Strings.Unbounded;

with Hostkit.Descriptors;
with Hostkit.Terminal_Control;

with Adash.Execution.Streams;

with Adash.Display_Width;

with Adash.Interactive.Completion;
with Adash.Source;

package body Adash.Interactive.Editing is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Hostkit.Descriptors.Transfer_Outcome;

   --  A byte that continues a UTF-8 character rather than starting one.
   function Is_Continuation (Item : Character) return Boolean is
     (Character'Pos (Item) in 16#80# .. 16#BF#);

   ---------------------------------------------------------------------
   --  The buffer.
   ---------------------------------------------------------------------

   ------------
   -- Length --
   ------------

   function Length (Item : Buffer) return Natural is
   begin
      return Item.Used;
   end Length;

   ----------
   -- Text --
   ----------

   function Text (Item : Buffer) return String is
   begin
      return Item.Content (1 .. Item.Used);
   end Text;

   ------------
   -- Cursor --
   ------------

   function Cursor (Item : Buffer) return Natural is
   begin
      return Item.Point;
   end Cursor;

   --------------------
   -- Cursor_Column --
   --------------------

   function Cursor_Column (Item : Buffer) return Natural is
      Count : Natural := 0;
   begin
      for Index in 1 .. Item.Point loop
         if not Is_Continuation (Item.Content (Index)) then
            Count := Count + 1;
         end if;
      end loop;

      return Count;
   end Cursor_Column;

   -----------
   -- Place --
   -----------

   function Place
     (Item         : Buffer;
      Prompt_Width : Natural;
      Usable       : Positive;
      Upto         : Natural) return Screen_Position
   is
      Text  : constant String := Item.Content (1 .. Item.Used);
      Index : Positive := Text'First;

      Result : Screen_Position := (Row => 0, Column => Prompt_Width);
   begin
      while Index <= Text'Last and then Index <= Upto loop
         declare
            Code   : Natural;
            Length : Positive;
            Wide   : Natural;
         begin
            Adash.Display_Width.Decode (Text, Index, Code, Length);
            Wide := Adash.Display_Width.Cells (Code);

            --  A character that would not fit goes whole to the next row. Half
            --  of a wide one is not something a terminal can draw.
            if Result.Column + Wide > Usable then
               Result.Row := Result.Row + 1;
               Result.Column := 0;
            end if;

            Result.Column := Result.Column + Wide;
            Index := Index + Length;
         end;
      end loop;

      return Result;
   end Place;

   -------------------
   -- Cursor_Cells --
   -------------------

   function Cursor_Cells (Item : Buffer) return Natural is
   begin
      return Adash.Display_Width.Cells_Before
        (Item.Content (1 .. Item.Used), Item.Point + 1);
   end Cursor_Cells;

   -----------------
   -- Cell_Count --
   -----------------

   function Cell_Count (Item : Buffer) return Natural is
   begin
      return Adash.Display_Width.Cells (Item.Content (1 .. Item.Used));
   end Cell_Count;

   ----------------------
   -- Character_Count --
   ----------------------

   function Character_Count (Item : Buffer) return Natural is
      Count : Natural := 0;
   begin
      for Index in 1 .. Item.Used loop
         if not Is_Continuation (Item.Content (Index)) then
            Count := Count + 1;
         end if;
      end loop;

      return Count;
   end Character_Count;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Buffer) is
   begin
      Item.Used := 0;
      Item.Point := 0;
   end Clear;

   ---------
   -- Set --
   ---------

   procedure Set (Item : in out Buffer; To : String) is
      Kept : constant Natural := Natural'Min (To'Length, Max_Line);
   begin
      Item.Content (1 .. Kept) := To (To'First .. To'First + Kept - 1);
      Item.Used := Kept;
      Item.Point := Kept;
   end Set;

   ------------
   -- Insert --
   ------------

   function Insert (Item : in out Buffer; What : String) return Boolean is
   begin
      if What'Length = 0 then
         return True;
      end if;

      --  All or nothing. A paste that stopped halfway would leave the user
      --  with a line that looks complete and is not.
      if Item.Used + What'Length > Max_Line then
         return False;
      end if;

      --  Shift the tail right, from the end, so the copy does not overwrite
      --  itself.
      for Index in reverse Item.Point + 1 .. Item.Used loop
         Item.Content (Index + What'Length) := Item.Content (Index);
      end loop;

      Item.Content (Item.Point + 1 .. Item.Point + What'Length) := What;
      Item.Used := Item.Used + What'Length;
      Item.Point := Item.Point + What'Length;
      return True;
   end Insert;

   --  Where the character before Position starts.
   function Start_Of_Previous (Item : Buffer; Position : Natural) return Natural;

   function Start_Of_Previous (Item : Buffer; Position : Natural) return Natural is
      Index : Natural := Position;
   begin
      if Index = 0 then
         return 0;
      end if;

      Index := Index - 1;

      while Index > 0 and then Is_Continuation (Item.Content (Index + 1)) loop
         Index := Index - 1;
      end loop;

      return Index;
   end Start_Of_Previous;

   --  Where the character at Position ends.
   function End_Of_Current (Item : Buffer; Position : Natural) return Natural;

   function End_Of_Current (Item : Buffer; Position : Natural) return Natural is
      Index : Natural := Position;
   begin
      if Index >= Item.Used then
         return Item.Used;
      end if;

      Index := Index + 1;

      while Index < Item.Used and then Is_Continuation (Item.Content (Index + 1)) loop
         Index := Index + 1;
      end loop;

      return Index;
   end End_Of_Current;

   --  Remove From + 1 .. To_Position, keeping the cursor at From.
   procedure Remove (Item : in out Buffer; From, To_Position : Natural);

   procedure Remove (Item : in out Buffer; From, To_Position : Natural) is
      Removed : constant Natural := To_Position - From;
   begin
      if Removed = 0 then
         return;
      end if;

      Item.Content (From + 1 .. Item.Used - Removed) :=
        Item.Content (To_Position + 1 .. Item.Used);
      Item.Used := Item.Used - Removed;
      Item.Point := From;
   end Remove;

   ----------------------
   -- Delete_Backward --
   ----------------------

   function Delete_Backward (Item : in out Buffer) return Boolean is
      Start : constant Natural := Start_Of_Previous (Item, Item.Point);
   begin
      if Item.Point = 0 then
         return False;
      end if;

      Remove (Item, Start, Item.Point);
      return True;
   end Delete_Backward;

   ---------------------
   -- Delete_Forward --
   ---------------------

   function Delete_Forward (Item : in out Buffer) return Boolean is
      Stop : constant Natural := End_Of_Current (Item, Item.Point);
   begin
      if Item.Point >= Item.Used then
         return False;
      end if;

      Remove (Item, Item.Point, Stop);
      return True;
   end Delete_Forward;

   ---------------------
   -- Delete_To_End --
   ---------------------

   function Delete_To_End (Item : in out Buffer) return Boolean is
   begin
      if Item.Point >= Item.Used then
         return False;
      end if;

      Item.Used := Item.Point;
      return True;
   end Delete_To_End;

   -----------------------
   -- Delete_To_Start --
   -----------------------

   function Delete_To_Start (Item : in out Buffer) return Boolean is
   begin
      if Item.Point = 0 then
         return False;
      end if;

      Remove (Item, 0, Item.Point);
      return True;
   end Delete_To_Start;

   -----------------------------
   -- Delete_Word_Backward --
   -----------------------------

   function Delete_Word_Backward (Item : in out Buffer) return Boolean is
      Start : Natural := Item.Point;
   begin
      if Item.Point = 0 then
         return False;
      end if;

      --  The blanks first, then the word. Stopping at the blanks would mean
      --  two presses per word for a line that has any spacing in it, which is
      --  every line.
      while Start > 0 and then Item.Content (Start) = ' ' loop
         Start := Start - 1;
      end loop;

      while Start > 0 and then Item.Content (Start) /= ' ' loop
         Start := Start - 1;
      end loop;

      Remove (Item, Start, Item.Point);
      return True;
   end Delete_Word_Backward;

   ----------
   -- Move --
   ----------

   function Move (Item : in out Buffer; Where : Movement) return Boolean is
   begin
      case Where is
         when To_Start =>
            if Item.Point = 0 then
               return False;
            end if;
            Item.Point := 0;
            return True;

         when To_End =>
            if Item.Point = Item.Used then
               return False;
            end if;
            Item.Point := Item.Used;
            return True;

         when Left =>
            if Item.Point = 0 then
               return False;
            end if;
            Item.Point := Start_Of_Previous (Item, Item.Point);
            return True;

         when Right =>
            if Item.Point >= Item.Used then
               return False;
            end if;
            Item.Point := End_Of_Current (Item, Item.Point);
            return True;

         when Word_Left =>
            if Item.Point = 0 then
               return False;
            end if;

            while Item.Point > 0 and then Item.Content (Item.Point) = ' ' loop
               Item.Point := Item.Point - 1;
            end loop;

            while Item.Point > 0 and then Item.Content (Item.Point) /= ' ' loop
               Item.Point := Item.Point - 1;
            end loop;

            return True;

         when Word_Right =>
            if Item.Point >= Item.Used then
               return False;
            end if;

            while Item.Point < Item.Used
              and then Item.Content (Item.Point + 1) = ' '
            loop
               Item.Point := Item.Point + 1;
            end loop;

            while Item.Point < Item.Used
              and then Item.Content (Item.Point + 1) /= ' '
            loop
               Item.Point := Item.Point + 1;
            end loop;

            return True;
      end case;
   end Move;

   ---------------------------------------------------------------------
   --  Keys.
   ---------------------------------------------------------------------

   Escape_Byte : constant Ada.Streams.Stream_Element := 16#1B#;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Bytes    : Ada.Streams.Stream_Element_Array;
      Event    : out Key_Event;
      Consumed : out Natural)
   is
      procedure Simple (Kind : Key_Kind; Used : Positive);

      procedure Simple (Kind : Key_Kind; Used : Positive) is
      begin
         Event := (Kind => Kind, Text => [others => ' '], Length => 0);
         Consumed := Used;
      end Simple;

   begin
      Event := (Kind => Key_Unknown, Text => [others => ' '], Length => 0);
      Consumed := 0;

      if Bytes'Length = 0 then
         Event.Kind := Key_Incomplete;
         return;
      end if;

      declare
         First : constant Ada.Streams.Stream_Element := Bytes (Bytes'First);
      begin
         --  Escape sequences. Anything beginning with escape is a sequence
         --  until proven otherwise, including a lone escape -- which is why a
         --  single escape byte is reported incomplete rather than guessed at.
         if First = Escape_Byte then
            if Bytes'Length = 1 then
               Event.Kind := Key_Incomplete;
               return;
            end if;

            declare
               Second : constant Ada.Streams.Stream_Element :=
                 Bytes (Bytes'First + 1);
            begin
               --  Alt-b and Alt-f: word movement, on terminals that send it
               --  this way.
               if Second = Character'Pos ('b') then
                  Simple (Key_Word_Left, 2);
                  return;
               elsif Second = Character'Pos ('f') then
                  Simple (Key_Word_Right, 2);
                  return;
               end if;

               if Second /= Character'Pos ('[')
                 and then Second /= Character'Pos ('O')
               then
                  --  Some other escape sequence. Consumed and ignored, so it
                  --  cannot be inserted as text.
                  Simple (Key_Unknown, 2);
                  return;
               end if;

               if Bytes'Length = 2 then
                  Event.Kind := Key_Incomplete;
                  return;
               end if;

               declare
                  Third : constant Ada.Streams.Stream_Element :=
                    Bytes (Bytes'First + 2);
               begin
                  case Third is
                     when Character'Pos ('A') => Simple (Key_Up, 3);    return;
                     when Character'Pos ('B') => Simple (Key_Down, 3);  return;
                     when Character'Pos ('C') => Simple (Key_Right, 3); return;
                     when Character'Pos ('D') => Simple (Key_Left, 3);  return;
                     when Character'Pos ('H') => Simple (Key_Home, 3);  return;
                     when Character'Pos ('F') => Simple (Key_End, 3);   return;
                     when others => null;
                  end case;

                  --  The numeric forms: ESC [ n ~ , and ESC [ 1 ; 5 C for
                  --  control-arrow. Both end in a byte outside the parameter
                  --  range, so scanning for that terminator is enough to
                  --  consume the whole sequence without a table.
                  declare
                     Index : Ada.Streams.Stream_Element_Offset := Bytes'First + 2;
                     Stop  : Ada.Streams.Stream_Element_Offset := 0;
                  begin
                     while Index <= Bytes'Last loop
                        if Bytes (Index) not in 16#30# .. 16#3F# then
                           Stop := Index;
                           exit;
                        end if;
                        Index := Index + 1;
                     end loop;

                     if Stop = 0 then
                        Event.Kind := Key_Incomplete;
                        return;
                     end if;

                     declare
                        Used : constant Positive :=
                          Positive (Stop - Bytes'First + 1);
                     begin
                        --  ESC [ 3 ~ is delete; ESC [ 1 ~ and ESC [ 7 ~ are
                        --  home; ESC [ 4 ~ and ESC [ 8 ~ are end. Everything
                        --  else in this shape is consumed and ignored.
                        if Bytes (Stop) = Character'Pos ('~') then
                           case Bytes (Bytes'First + 2) is
                              when Character'Pos ('3') =>
                                 Simple (Key_Delete, Used); return;
                              when Character'Pos ('1') | Character'Pos ('7') =>
                                 Simple (Key_Home, Used); return;
                              when Character'Pos ('4') | Character'Pos ('8') =>
                                 Simple (Key_End, Used); return;
                              when others =>
                                 Simple (Key_Unknown, Used); return;
                           end case;
                        end if;

                        --  Control-arrow, whose terminator is the same letter
                        --  as the plain form.
                        case Bytes (Stop) is
                           when Character'Pos ('C') =>
                              Simple (Key_Word_Right, Used); return;
                           when Character'Pos ('D') =>
                              Simple (Key_Word_Left, Used); return;
                           when Character'Pos ('A') =>
                              Simple (Key_Up, Used); return;
                           when Character'Pos ('B') =>
                              Simple (Key_Down, Used); return;
                           when Character'Pos ('H') =>
                              Simple (Key_Home, Used); return;
                           when Character'Pos ('F') =>
                              Simple (Key_End, Used); return;
                           when others =>
                              Simple (Key_Unknown, Used); return;
                        end case;
                     end;
                  end;
               end;
            end;
         end if;

         --  Control characters. The bindings are the ones every line editor
         --  has had for forty years; a shell that invented its own would be
         --  one whose users' hands are wrong.
         case First is
            when 16#0D# | 16#0A# => Simple (Key_Enter, 1);         return;
            when 16#09#          => Simple (Key_Complete, 1);      return;
            when 16#7F# | 16#08# => Simple (Key_Backspace, 1);     return;
            when 16#03#          => Simple (Key_Interrupt, 1);     return;
            when 16#04#          => Simple (Key_End_Of_Input, 1);  return;
            when 16#01#          => Simple (Key_Home, 1);          return;
            when 16#05#          => Simple (Key_End, 1);           return;
            when 16#02#          => Simple (Key_Left, 1);          return;
            when 16#06#          => Simple (Key_Right, 1);         return;
            when 16#0B#          => Simple (Key_Kill_To_End, 1);   return;
            when 16#15#          => Simple (Key_Kill_To_Start, 1); return;
            when 16#17#          => Simple (Key_Kill_Word, 1);     return;
            when 16#0C#          => Simple (Key_Refresh, 1);       return;
            when 16#10#          => Simple (Key_Up, 1);            return;
            when 16#0E#          => Simple (Key_Down, 1);          return;
            when others          => null;
         end case;

         --  Any other control byte is not text and is not inserted.
         if First < 16#20# then
            Simple (Key_Unknown, 1);
            return;
         end if;

         --  A character. How many bytes it takes is decided by its first byte;
         --  a truncated one is incomplete rather than inserted as fragments,
         --  because a half-written character in the buffer corrupts every
         --  later position calculation.
         declare
            Needed : Natural;
         begin
            if First < 16#80# then
               Needed := 1;
            elsif First in 16#C2# .. 16#DF# then
               Needed := 2;
            elsif First in 16#E0# .. 16#EF# then
               Needed := 3;
            elsif First in 16#F0# .. 16#F4# then
               Needed := 4;
            else
               --  A continuation byte with nothing in front of it, or one of
               --  the lead bytes UTF-8 forbids. Dropped: it cannot be part of
               --  a character, and keeping it would poison the ones after it.
               Simple (Key_Unknown, 1);
               return;
            end if;

            if Bytes'Length < Needed then
               Event.Kind := Key_Incomplete;
               return;
            end if;

            Event.Kind := Key_Character;
            Event.Length := Needed;

            for Index in 1 .. Needed loop
               Event.Text (Index) :=
                 Character'Val
                   (Bytes (Bytes'First + Ada.Streams.Stream_Element_Offset (Index) - 1));
            end loop;

            Consumed := Needed;
         end;
      end;
   end Decode;

   ---------------------------------------------------------------------
   --  The reader.
   ---------------------------------------------------------------------

   --  Bytes read but not yet decoded, kept **between calls** rather than
   --  inside Read_Line.
   --
   --  One read routinely carries more than one line: a user types ahead while
   --  a command is running, and a paste arrives all at once. A buffer local to
   --  Read_Line would throw away everything after the newline it returned on,
   --  so the second line of a paste would vanish -- silently, which is the
   --  worst way for input to be lost.
   --
   --  Process-wide because standard input is. There is one terminal and one
   --  reader of it; a second buffer could only disagree with this one about
   --  what had already been consumed.
   --
   --  Nor is this editor the only reader: a program can ask for a line too.
   --  What is held here is taken from Adash.Execution.Streams when a read
   --  begins and given back when it ends, so the bytes a user typed ahead are
   --  in one place and whoever asks next finds them. Keeping them here alone
   --  meant a program read nothing while the user's answer sat in this buffer.
   Pending : Ada.Streams.Stream_Element_Array (1 .. 1_024) := [others => 0];
   Held    : Ada.Streams.Stream_Element_Offset := 0;

   --  Fill Pending from the shared buffer.
   procedure Take_Shared;

   --  Hand back what this read did not consume.
   procedure Give_Back_Shared;

   procedure Take_Shared is
      Taken : constant String := Adash.Execution.Streams.Take_Held;
   begin
      for Index in Taken'Range loop
         exit when Held = Pending'Last;
         Held := Held + 1;
         Pending (Held) := Ada.Streams.Stream_Element (Character'Pos (Taken (Index)));
      end loop;
   end Take_Shared;

   procedure Give_Back_Shared is
      Left : String (1 .. Natural (Held));
   begin
      if Held = 0 then
         return;
      end if;

      for Index in Left'Range loop
         Left (Index) :=
           Character'Val (Natural (Pending (Ada.Streams.Stream_Element_Offset (Index))));
      end loop;

      Adash.Execution.Streams.Put_Back (Left);
      Held := 0;
   end Give_Back_Shared;

   -------------------------
   -- Supports_Editing --
   -------------------------

   function Supports_Editing return Boolean is
   begin
      --  Both ends. Reading keys needs raw input; drawing the line needs a
      --  terminal that can be drawn on. Either one missing means the editor
      --  would be half there, which is worse than not there at all.
      return Hostkit.Descriptors.Is_Terminal (Hostkit.Descriptors.Standard_Input)
        and then Hostkit.Terminal_Control.Supports_Cursor_Control
                   (Hostkit.Descriptors.Standard_Output);
   end Supports_Editing;

   --  Write a string to the terminal, resuming after a short write.
   function Emit (Item : String) return Boolean;

   function Emit (Item : String) return Boolean is
      Output : constant Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Standard_Output;
      Bytes  : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Item'Length));
      From   : Ada.Streams.Stream_Element_Offset := Bytes'First;
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      if Item'Length = 0 then
         return True;
      end if;

      for Index in Item'Range loop
         Bytes (Ada.Streams.Stream_Element_Offset (Index - Item'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Item (Index)));
      end loop;

      while From <= Bytes'Last loop
         case Hostkit.Descriptors.Write (Output, Bytes (From .. Bytes'Last), Last) is
            when Hostkit.Descriptors.Transfer_Ok =>
               exit when Last < From;
               From := Last + 1;

            when Hostkit.Descriptors.Transfer_Interrupted =>
               null;

            when others =>
               return False;
         end case;
      end loop;

      return From > Bytes'Last;
   end Emit;

   ----------------
   -- Read_Line --
   ----------------

   function Read_Line
     (Prompt       : String;
      Prompt_Width : Natural;
      Recall       : Adash.Interactive.History.Log;
      Allow_Editing : Boolean := True;
      Into         : out String;
      Last         : out Natural) return Read_Outcome
   is
      Input  : constant Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Standard_Input;
      Output : constant Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Standard_Output;

      Line : Buffer;

      --  Where in history the up key has walked to. Zero means "the line the
      --  user was typing", which is kept so that walking back down returns it
      --  rather than an empty line.
      Recall_Index : Natural := 0;
      Saved        : Buffer;

      --  Where the last redraw left the cursor and how far down it reached,
      --  counted in rows from the first row of the prompt.
      --
      --  A wrapped line cannot be repainted without this. The terminal will not
      --  say how many rows it used, and asking would need a reply nobody can
      --  wait for in the middle of a keystroke -- but it is computable, now
      --  that width is counted in cells rather than characters. That is what
      --  changed: with one cell per character the row count was wrong for any
      --  line containing an ideograph, and a wrong row count leaves debris on
      --  screen after every edit.
      Drawn_Row  : Natural := 0;
      Drawn_Rows : Natural := 0;

      procedure Redraw;
      procedure Complete_Here;
      function Finish (Outcome : Read_Outcome) return Read_Outcome;

      ------------
      -- Redraw --
      ------------

      procedure Redraw is
         Ignored : Boolean;

         Size : Hostkit.Terminal_Control.Window_Size;

         --  A terminal that will not say how wide it is gets the conventional
         --  eighty. Guessing wider would put the cursor in the wrong place on
         --  every line long enough to matter, and guessing narrower only costs
         --  a scroll the user did not need.
         Columns : constant Natural :=
           (if Hostkit.Terminal_Control.Size (Output, Size)
              and then Size.Columns > 0
            then Size.Columns
            else 80);

         Screen_Rows : constant Natural :=
           (if Hostkit.Terminal_Control.Size (Output, Size)
              and then Size.Rows > 0
            then Size.Rows
            else 24);

         --  One cell is left free at the right edge, and the line breaks are
         --  written rather than left to the terminal. Writing into the last
         --  column makes some terminals wrap and others not, and a redraw that
         --  guesses wrong leaves the cursor a line away from the text; break
         --  the row a cell early and the question never arises.
         Usable : constant Positive :=
           (if Columns > 1 then Columns - 1 else 1);

         Ends   : constant Screen_Position :=
           Place (Line, Prompt_Width, Usable, Natural'Last);
         Points : constant Screen_Position :=
           Place (Line, Prompt_Width, Usable, Line.Cursor);

         Last_Row   : constant Natural := Ends.Row;
         Cursor_Row : constant Natural := Points.Row;
         Cursor_Col : constant Natural := Points.Column;

         --  Text broken into rows, with the break written in.
         function Wrapped return String is
            Built : Ada.Strings.Unbounded.Unbounded_String;
            Text  : constant String := Line.Text;
            Used  : Natural := Prompt_Width;
            Index : Positive := Text'First;
         begin
            while Index <= Text'Last loop
               declare
                  Code   : Natural;
                  Length : Positive;
                  Wide   : Natural;
               begin
                  Adash.Display_Width.Decode (Text, Index, Code, Length);
                  Wide := Adash.Display_Width.Cells (Code);

                  --  A wide character that would straddle the break goes whole
                  --  to the next row. Half of one is not something a terminal
                  --  can draw.
                  if Used + Wide > Usable then
                     Ada.Strings.Unbounded.Append (Built, ASCII.CR);
                     Ada.Strings.Unbounded.Append (Built, ASCII.LF);
                     Used := 0;
                  end if;

                  Ada.Strings.Unbounded.Append
                    (Built, Text (Index .. Index + Length - 1));
                  Used := Used + Wide;
                  Index := Index + Length;
               end;
            end loop;

            return Ada.Strings.Unbounded.To_String (Built);
         end Wrapped;
      begin
         Ignored := Hostkit.Terminal_Control.Control
           (Output, Hostkit.Terminal_Control.Hide_Cursor);

         --  Back to the first row of what was drawn last time, and clear all
         --  of it. Erasing only the current row would leave the rest of a
         --  wrapped line on screen.
         for Step in 1 .. Drawn_Row loop
            Ignored := Hostkit.Terminal_Control.Control
              (Output, Hostkit.Terminal_Control.Move_Up);
         end loop;

         Ignored := Hostkit.Terminal_Control.Control
           (Output, Hostkit.Terminal_Control.To_First_Column);

         for Step in 0 .. Drawn_Rows loop
            Ignored := Hostkit.Terminal_Control.Control
              (Output, Hostkit.Terminal_Control.Erase_Line);

            if Step < Drawn_Rows then
               Ignored := Hostkit.Terminal_Control.Control
                 (Output, Hostkit.Terminal_Control.Move_Down);
            end if;
         end loop;

         for Step in 1 .. Drawn_Rows loop
            Ignored := Hostkit.Terminal_Control.Control
              (Output, Hostkit.Terminal_Control.Move_Up);
         end loop;

         Ignored := Hostkit.Terminal_Control.Control
           (Output, Hostkit.Terminal_Control.To_First_Column);

         if Last_Row >= Screen_Rows then
            --  Taller than the screen. Wrapping would scroll, and a redraw
            --  cannot find its way back to a row that has scrolled off, so
            --  this falls back to showing one row and moving the window along
            --  it -- which is what every line did before wrapping existed.
            declare
               Room    : constant Natural :=
                 (if Usable > Prompt_Width then Usable - Prompt_Width else 1);
               Skipped : constant Natural :=
                 (if Line.Cursor_Cells > Room
                  then Line.Cursor_Cells - Room else 0);

               Text  : constant String := Line.Text;
               First : Positive := Text'First;
               Seen  : Natural := 0;
               Shown : Natural := 0;
               Stop  : Natural := Text'Last;
            begin
               while First <= Text'Last and then Seen < Skipped loop
                  declare
                     Code   : Natural;
                     Length : Positive;
                  begin
                     Adash.Display_Width.Decode (Text, First, Code, Length);
                     Seen := Seen + Adash.Display_Width.Cells (Code);
                     First := First + Length;
                  end;
               end loop;

               declare
                  Index : Positive := First;
               begin
                  while Index <= Text'Last loop
                     declare
                        Code   : Natural;
                        Length : Positive;
                        Wide   : Natural;
                     begin
                        Adash.Display_Width.Decode (Text, Index, Code, Length);
                        Wide := Adash.Display_Width.Cells (Code);

                        if Shown + Wide > Room then
                           Stop := Index - 1;
                           exit;
                        end if;

                        Shown := Shown + Wide;
                        Index := Index + Length;
                     end;
                  end loop;
               end;

               Ignored := Emit (Prompt);
               Ignored := Emit (Text (First .. Stop));

               for Step in 1 .. Shown - (Line.Cursor_Cells - Skipped) loop
                  Ignored := Hostkit.Terminal_Control.Control
                    (Output, Hostkit.Terminal_Control.Move_Left);
               end loop;

               Drawn_Row  := 0;
               Drawn_Rows := 0;
            end;

         else
            Ignored := Emit (Prompt);
            Ignored := Emit (Wrapped);

            --  The cursor is at the end of what was written; bring it to where
            --  the point actually is.
            for Step in 1 .. Last_Row - Cursor_Row loop
               Ignored := Hostkit.Terminal_Control.Control
                 (Output, Hostkit.Terminal_Control.Move_Up);
            end loop;

            Ignored := Hostkit.Terminal_Control.Control
              (Output, Hostkit.Terminal_Control.To_First_Column);

            for Step in 1 .. Cursor_Col loop
               Ignored := Hostkit.Terminal_Control.Control
                 (Output, Hostkit.Terminal_Control.Move_Right);
            end loop;

            Drawn_Row  := Cursor_Row;
            Drawn_Rows := Last_Row;
         end if;

         Ignored := Hostkit.Terminal_Control.Control
           (Output, Hostkit.Terminal_Control.Show_Cursor);
      end Redraw;

      --------------------
      -- Complete_Here --
      --------------------

      procedure Complete_Here is
         Text : constant String := Line.Text;

         Candidates : constant Adash.Interactive.Completion.Candidate_List :=
           Adash.Interactive.Completion.Complete
             (Adash.Interactive.Completion.Make_Request
                (Text, Positive (Line.Cursor + 1)));

         Ignored : Boolean;

         procedure Replace (Span : Adash.Source.Span; With_Text : String);
         --  Put With_Text where Span was, and leave the cursor after it.

         procedure Replace (Span : Adash.Source.Span; With_Text : String) is
            First : constant Natural := Natural (Span.First);
         begin
            --  The span is what the user already typed of the word. Deleting
            --  it and inserting the whole candidate -- rather than appending
            --  the missing tail -- is what makes case-insensitive and
            --  abbreviated matches come out right.
            if not Adash.Source.Is_Empty (Span) then
               Line.Point := Span.Last;
               Remove (Line, First - 1, Span.Last);
            end if;

            Ignored := Line.Insert (With_Text);
         end Replace;

      begin
         if Candidates.Count = 0 then
            return;
         end if;

         if Candidates.Count = 1 then
            declare
               Only : constant Adash.Interactive.Completion.Candidate :=
                 Candidates.Element (1);
            begin
               Replace (Adash.Interactive.Completion.Replaces (Only),
                        Adash.Interactive.Completion.Insertion (Only));
               Redraw;
            end;
            return;
         end if;

         --  More than one. As much as is certain goes in; the rest is shown,
         --  never guessed at. A shell that picked the first candidate would be
         --  wrong often enough to be untrustworthy, and a user cannot tell the
         --  difference between a completion and a mistake until it has run.
         declare
            Shared : constant String := Candidates.Common_Prefix;
            Span   : constant Adash.Source.Span :=
              Adash.Interactive.Completion.Replaces (Candidates.Element (1));
            Typed  : constant Natural :=
              (if Adash.Source.Is_Empty (Span) then 0
               else Span.Last - Natural (Span.First) + 1);
         begin
            if Shared'Length > Typed then
               Replace (Span, Shared);
               Redraw;
               return;
            end if;
         end;

         --  Nothing more is certain, so list what there is. Names only: a
         --  candidate's description is a message identifier, and rendering one
         --  needs a catalog this package has no business holding. The names are
         --  what the user is choosing between.
         Ignored := Emit ([1 => Character'Val (16#0D#), 2 => Character'Val (16#0A#)]);

         for Index in 1 .. Candidates.Count loop
            Ignored := Emit
              (Adash.Interactive.Completion.Display (Candidates.Element (Index)));
            Ignored := Emit
              ([1 => Character'Val (16#0D#), 2 => Character'Val (16#0A#)]);
         end loop;

         Redraw;
      end Complete_Here;

      ------------
      -- Finish --
      ------------

      function Finish (Outcome : Read_Outcome) return Read_Outcome is
         Ignored : Boolean;
         Text    : constant String := Line.Text;
         Kept    : constant Natural := Natural'Min (Text'Length, Into'Length);
      begin
         Ignored := Emit ([1 => Character'Val (16#0D#), 2 => Character'Val (16#0A#)]);

         Into (Into'First .. Into'First + Kept - 1) :=
           Text (Text'First .. Text'First + Kept - 1);
         Last := Into'First + Kept - 1;

         --  Whatever was typed ahead belongs to whoever reads next, which may
         --  be a program in the submission about to run.
         Give_Back_Shared;
         return Outcome;
      end Finish;

      Chunk    : Ada.Streams.Stream_Element_Array (1 .. 64);
      Chunk_End : Ada.Streams.Stream_Element_Offset;

      Saved_Mode : Hostkit.Terminal_Control.Mode;
      Have_Mode  : Boolean := False;
      Ignored    : Boolean;

   begin
      Last := Into'First - 1;
      Take_Shared;

      --  No terminal, or one that cannot be edited on. Fall back to reading a
      --  whole line with no editing at all, which is what a script piped into
      --  the shell needs and what a user on an unknown host still gets.
      if not Allow_Editing or else not Supports_Editing then
         --  A prompt only when there is someone at the other end to read it.
         --  Input from a pipe is a script by another name, and a prompt
         --  written into its output is noise nothing can filter reliably.
         if Hostkit.Descriptors.Is_Terminal (Input) then
            Ignored := Emit (Prompt);
         end if;

         declare
            Buffer_In : Ada.Streams.Stream_Element_Array (1 .. 1);
            Read_Last : Ada.Streams.Stream_Element_Offset;
            Got_Any   : Boolean := False;
         begin
            loop
               declare
                  Have_Byte : Boolean := False;
                  Byte      : Ada.Streams.Stream_Element := 0;
               begin
                  --  What is already held comes first: it was read from this
                  --  same input, and reading past it would take the second
                  --  line before the first.
                  if Held > 0 then
                     Byte := Pending (1);
                     Pending (1 .. Held - 1) := Pending (2 .. Held);
                     Held := Held - 1;
                     Have_Byte := True;

                  else
                     case Hostkit.Descriptors.Read
                            (Input, Buffer_In, Read_Last)
                     is
                        when Hostkit.Descriptors.Transfer_Ok =>
                           exit when Read_Last < Buffer_In'First;
                           Byte := Buffer_In (Buffer_In'First);
                           Have_Byte := True;

                        when Hostkit.Descriptors.Transfer_End_Of_File =>
                           if not Got_Any and then Line.Length = 0 then
                              Last := Into'First - 1;
                              return Input_Ended;
                           end if;

                           exit;

                        when Hostkit.Descriptors.Transfer_Interrupted =>
                           --  A signal arrived before a byte did. Retrying is
                           --  what the contract asks for.
                           null;

                        when others =>
                           Last := Into'First - 1;
                           return Read_Failed;
                     end case;
                  end if;

                  if Have_Byte then
                     Got_Any := True;

                     exit when Byte = 16#0A#;

                     if Byte /= 16#0D# then
                        Ignored := Line.Insert ([1 => Character'Val (Byte)]);
                     end if;
                  end if;
               end;
            end loop;

            declare
               Text : constant String := Line.Text;
               Kept : constant Natural := Natural'Min (Text'Length, Into'Length);
            begin
               Into (Into'First .. Into'First + Kept - 1) :=
                 Text (Text'First .. Text'First + Kept - 1);
               Last := Into'First + Kept - 1;
               Give_Back_Shared;
               return Line_Read;
            end;
         end;
      end if;

      --  Raw mode, and the previous settings kept so they can be put back on
      --  every path out -- including the ones that fail.
      Have_Mode := Hostkit.Terminal_Control.Save_Mode (Input, Saved_Mode);

      if not Hostkit.Terminal_Control.Set_Raw (Input) then
         Last := Into'First - 1;
         return Read_Failed;
      end if;

      Redraw;

      loop
         --  Decode everything already held before reading more: one read can
         --  carry several keystrokes, and a paste carries hundreds.
         declare
            Event    : Key_Event;
            Consumed : Natural;
         begin
            while Held > 0 loop
               Decode (Pending (1 .. Held), Event, Consumed);

               exit when Event.Kind = Key_Incomplete;

               --  Shift the rest down.
               Pending (1 .. Held - Ada.Streams.Stream_Element_Offset (Consumed)) :=
                 Pending (Ada.Streams.Stream_Element_Offset (Consumed) + 1 .. Held);
               Held := Held - Ada.Streams.Stream_Element_Offset (Consumed);

               case Event.Kind is
                  when Key_Character =>
                     Ignored := Line.Insert (Event.Text (1 .. Event.Length));
                     Redraw;

                  when Key_Enter =>
                     if Have_Mode then
                        Ignored := Hostkit.Terminal_Control.Restore_Mode
                          (Input, Saved_Mode);
                     end if;
                     return Finish (Line_Read);

                  when Key_Interrupt =>
                     if Have_Mode then
                        Ignored := Hostkit.Terminal_Control.Restore_Mode
                          (Input, Saved_Mode);
                     end if;
                     return Finish (Line_Abandoned);

                  when Key_End_Of_Input =>
                     --  Only on an empty line. On a line with text it would
                     --  end the session over a keystroke the user meant as an
                     --  edit, which is unrecoverable.
                     if Line.Length = 0 then
                        if Have_Mode then
                           Ignored := Hostkit.Terminal_Control.Restore_Mode
                             (Input, Saved_Mode);
                        end if;
                        Ignored := Emit
                          ([1 => Character'Val (16#0D#),
                            2 => Character'Val (16#0A#)]);
                        Last := Into'First - 1;
                        return Input_Ended;
                     end if;

                  when Key_Backspace =>
                     Ignored := Line.Delete_Backward;
                     Redraw;

                  when Key_Delete =>
                     Ignored := Line.Delete_Forward;
                     Redraw;

                  when Key_Left =>
                     Ignored := Line.Move (Left);
                     Redraw;

                  when Key_Right =>
                     Ignored := Line.Move (Right);
                     Redraw;

                  when Key_Word_Left =>
                     Ignored := Line.Move (Word_Left);
                     Redraw;

                  when Key_Word_Right =>
                     Ignored := Line.Move (Word_Right);
                     Redraw;

                  when Key_Home =>
                     Ignored := Line.Move (To_Start);
                     Redraw;

                  when Key_End =>
                     Ignored := Line.Move (To_End);
                     Redraw;

                  when Key_Kill_To_End =>
                     Ignored := Line.Delete_To_End;
                     Redraw;

                  when Key_Kill_To_Start =>
                     Ignored := Line.Delete_To_Start;
                     Redraw;

                  when Key_Kill_Word =>
                     Ignored := Line.Delete_Word_Backward;
                     Redraw;

                  when Key_Up =>
                     if Recall_Index < Adash.Interactive.History.Count (Recall) then
                        --  The part-typed line is kept the first time up is
                        --  pressed, so walking back down returns it.
                        if Recall_Index = 0 then
                           Saved := Line;
                        end if;

                        Recall_Index := Recall_Index + 1;
                        Line.Set
                          (Adash.Interactive.History.Entry_At
                             (Recall,
                              Adash.Interactive.History.Count (Recall)
                              - Recall_Index + 1));
                        Redraw;
                     end if;

                  when Key_Down =>
                     if Recall_Index > 1 then
                        Recall_Index := Recall_Index - 1;
                        Line.Set
                          (Adash.Interactive.History.Entry_At
                             (Recall,
                              Adash.Interactive.History.Count (Recall)
                              - Recall_Index + 1));
                        Redraw;
                     elsif Recall_Index = 1 then
                        Recall_Index := 0;
                        Line := Saved;
                        Redraw;
                     end if;

                  when Key_Refresh =>
                     Redraw;

                  when Key_Complete =>
                     Complete_Here;

                  when Key_Unknown | Key_Incomplete =>
                     null;
               end case;
            end loop;
         end;

         case Hostkit.Descriptors.Read (Input, Chunk, Chunk_End) is
            when Hostkit.Descriptors.Transfer_Ok =>
               if Chunk_End < Chunk'First then
                  --  A terminal that returned nothing without saying end of
                  --  file. Treated as end rather than spun on.
                  if Have_Mode then
                     Ignored := Hostkit.Terminal_Control.Restore_Mode
                       (Input, Saved_Mode);
                  end if;
                  Last := Into'First - 1;
                  return Input_Ended;
               end if;

               for Index in Chunk'First .. Chunk_End loop
                  exit when Held = Pending'Last;
                  Held := Held + 1;
                  Pending (Held) := Chunk (Index);
               end loop;

            when Hostkit.Descriptors.Transfer_Interrupted =>
               null;

            when Hostkit.Descriptors.Transfer_End_Of_File =>
               if Have_Mode then
                  Ignored := Hostkit.Terminal_Control.Restore_Mode
                    (Input, Saved_Mode);
               end if;

               if Line.Length = 0 then
                  Last := Into'First - 1;
                  return Input_Ended;
               end if;

               return Finish (Line_Read);

            when others =>
               if Have_Mode then
                  Ignored := Hostkit.Terminal_Control.Restore_Mode
                    (Input, Saved_Mode);
               end if;
               Last := Into'First - 1;
               return Read_Failed;
         end case;
      end loop;
   end Read_Line;

end Adash.Interactive.Editing;

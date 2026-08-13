package body Adash.Display_Width is

   --  A span of code points that share a width.
   type Span is record
      First : Natural;
      Last  : Natural;
   end record;

   type Span_List is array (Positive range <>) of Span;

   --  Two cells: Unicode Standard Annex 11 Wide and Fullwidth.
   --
   --  Ordered, and searched linearly. The list is short enough that a binary
   --  search would cost more in code than it saves in comparisons, and a
   --  terminal redraw asks about a line's worth of characters at a time.
   Wide : constant Span_List :=
     [(16#1100#, 16#115F#),    --  Hangul Jamo, initial consonants
      (16#2E80#, 16#303E#),    --  CJK radicals, Kangxi, CJK symbols
      (16#3041#, 16#33FF#),    --  Kana, Bopomofo, Hangul compatibility, Kanbun
      (16#3400#, 16#4DBF#),    --  CJK unified ideographs extension A
      (16#4E00#, 16#9FFF#),    --  CJK unified ideographs
      (16#A000#, 16#A4CF#),    --  Yi syllables and radicals
      (16#AC00#, 16#D7A3#),    --  Hangul syllables
      (16#F900#, 16#FAFF#),    --  CJK compatibility ideographs
      (16#FE10#, 16#FE19#),    --  Vertical forms
      (16#FE30#, 16#FE6F#),    --  CJK compatibility forms, small form variants
      (16#FF00#, 16#FF60#),    --  Fullwidth forms
      (16#FFE0#, 16#FFE6#),    --  Fullwidth signs
      (16#1F300#, 16#1F64F#),  --  Symbols and pictographs, emoticons
      (16#1F900#, 16#1F9FF#),  --  Supplemental symbols and pictographs
      (16#20000#, 16#2FFFD#),  --  CJK extension B and later
      (16#30000#, 16#3FFFD#)];

   --  No cells: combining marks, and the zero-width formatting characters.
   --
   --  A combining mark is drawn on top of the character before it, so counting
   --  it would push everything after it one cell right of where it appears.
   Zero : constant Span_List :=
     [(16#0300#, 16#036F#),    --  Combining diacritical marks
      (16#0483#, 16#0489#),    --  Combining Cyrillic
      (16#0591#, 16#05BD#),    --  Hebrew points
      (16#0610#, 16#061A#),    --  Arabic marks
      (16#064B#, 16#065F#),    --  Arabic vowel marks
      (16#0670#, 16#0670#),    --  Arabic superscript alef
      (16#06D6#, 16#06DC#),    --  Arabic small high marks
      (16#0E31#, 16#0E31#),    --  Thai vowel above
      (16#0E34#, 16#0E3A#),    --  Thai vowels and tone marks
      (16#0E47#, 16#0E4E#),    --  Thai tone marks
      (16#200B#, 16#200F#),    --  Zero width space, joiners, direction marks
      (16#202A#, 16#202E#),    --  Bidirectional embedding and overrides
      (16#2060#, 16#2064#),    --  Word joiner, invisible operators
      (16#20D0#, 16#20F0#),    --  Combining marks for symbols
      (16#FE00#, 16#FE0F#),    --  Variation selectors
      (16#FE20#, 16#FE2F#),    --  Combining half marks
      (16#FEFF#, 16#FEFF#)];   --  Byte order mark, used as a zero width space

   function In_Any (Code : Natural; Spans : Span_List) return Boolean;

   ------------
   -- In_Any --
   ------------

   function In_Any (Code : Natural; Spans : Span_List) return Boolean is
   begin
      for Item of Spans loop
         --  Ordered, so a span starting past the code point ends the search.
         if Code < Item.First then
            return False;
         end if;

         if Code <= Item.Last then
            return True;
         end if;
      end loop;

      return False;
   end In_Any;

   -----------
   -- Cells --
   -----------

   function Cells (Code : Natural) return Natural is
   begin
      --  A control character has no width of its own: what it does to the
      --  screen is not a matter of cells, and counting it as one would put
      --  the cursor a place right of where the terminal left it.
      if Code < 16#20# or else (Code >= 16#7F# and then Code <= 16#9F#) then
         return 0;
      end if;

      if In_Any (Code, Zero) then
         return 0;
      end if;

      if In_Any (Code, Wide) then
         return 2;
      end if;

      return 1;
   end Cells;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Text   : String;
      From   : Positive;
      Code   : out Natural;
      Length : out Positive)
   is
      --  How many bytes the lead byte promises, and what the first one
      --  contributes. A byte that promises more than the string holds is
      --  treated as itself, so a truncated character still advances.
      function Continues (Index : Natural) return Boolean
      is (Index <= Text'Last
          and then Character'Pos (Text (Index)) in 16#80# .. 16#BF#);

      Lead : constant Natural := Character'Pos (Text (From));
   begin
      if Lead < 16#80# then
         Code := Lead;
         Length := 1;

      elsif Lead in 16#C2# .. 16#DF# and then Continues (From + 1) then
         Code := (Lead - 16#C0#) * 16#40#
                 + (Character'Pos (Text (From + 1)) - 16#80#);
         Length := 2;

      elsif Lead in 16#E0# .. 16#EF#
        and then Continues (From + 1) and then Continues (From + 2)
      then
         Code := (Lead - 16#E0#) * 16#1000#
                 + (Character'Pos (Text (From + 1)) - 16#80#) * 16#40#
                 + (Character'Pos (Text (From + 2)) - 16#80#);
         Length := 3;

      elsif Lead in 16#F0# .. 16#F4#
        and then Continues (From + 1) and then Continues (From + 2)
        and then Continues (From + 3)
      then
         Code := (Lead - 16#F0#) * 16#40000#
                 + (Character'Pos (Text (From + 1)) - 16#80#) * 16#1000#
                 + (Character'Pos (Text (From + 2)) - 16#80#) * 16#40#
                 + (Character'Pos (Text (From + 3)) - 16#80#);
         Length := 4;

      else
         --  Not valid UTF-8. Counted as one byte and one cell rather than
         --  skipped: source is validated on the way in, so this is a defect
         --  somewhere else, and hiding it would move the cursor instead.
         Code := Lead;
         Length := 1;
      end if;
   end Decode;

   -----------
   -- Cells --
   -----------

   function Cells (Text : String) return Natural is
   begin
      return Cells_Before (Text, Text'Last + 1);
   end Cells;

   -------------------
   -- Cells_Before --
   -------------------

   function Cells_Before (Text : String; Before : Positive) return Natural is
      Total : Natural := 0;
      Index : Positive := Text'First;
   begin
      while Index < Before and then Index <= Text'Last loop
         declare
            Code   : Natural;
            Length : Positive;
         begin
            Decode (Text, Index, Code, Length);
            Total := Total + Cells (Code);
            Index := Index + Length;
         end;
      end loop;

      return Total;
   end Cells_Before;

end Adash.Display_Width;

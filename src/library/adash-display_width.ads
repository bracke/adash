--  How much room text takes on a terminal.
--
--  A cell is not a character. An East Asian ideograph occupies two, a combining
--  accent occupies none, and an editor that counts characters puts its cursor
--  in the wrong place the moment either appears. This package answers in cells,
--  which is the unit a terminal actually works in.
--
--  **What it knows, and what it does not.** The ranges below are the ones
--  Unicode Standard Annex 11 calls Wide or Fullwidth, together with the
--  combining and zero-width ranges a shell is likely to meet. They are written
--  out here rather than derived from a Unicode data file: this repository has
--  no such file, and generating one would put a build step between the source
--  and the binary.
--
--  A code point in none of them is one cell. That is the same answer the editor
--  gave before this package existed, so nothing it does not cover has become
--  worse -- but it is a default rather than knowledge, and a script that needed
--  certainty should not ask this. The alternative, refusing to measure text
--  containing an unlisted character, would make the editor unusable for the
--  sake of a distinction nobody can see.
package Adash.Display_Width is

   --  How many cells one code point occupies.
   --
   --  @param Code The code point.
   --  @return Zero for a combining or zero-width character, two for a wide or
   --          fullwidth one, one otherwise.
   function Cells (Code : Natural) return Natural;

   --  How many cells a UTF-8 string occupies.
   --
   --  Bytes that are not valid UTF-8 count as one cell each. They should not
   --  reach here -- source is validated on the way in -- and counting them as
   --  nothing would let a corrupt byte hide the cursor.
   --
   --  @param Text UTF-8 text.
   --  @return Its width in cells.
   function Cells (Text : String) return Natural;

   --  How many cells the text before a byte offset occupies.
   --
   --  What an editor needs to turn a cursor's byte position into a column.
   --
   --  @param Text UTF-8 text.
   --  @param Before Count the bytes before this index; Text'First counts none.
   --  @return The width in cells of Text (Text'First .. Before - 1).
   function Cells_Before (Text : String; Before : Positive) return Natural;

   --  Decode one UTF-8 character.
   --
   --  @param Text UTF-8 text.
   --  @param From Index of the first byte.
   --  @param Code The code point, or the byte itself when it is not valid.
   --  @param Length How many bytes it took; at least one, so a caller always
   --         makes progress.
   procedure Decode
     (Text   : String;
      From   : Positive;
      Code   : out Natural;
      Length : out Positive);

end Adash.Display_Width;

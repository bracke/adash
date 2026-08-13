with Adash.Language.Tokens;
with Adash.Source;
with Adash.Terminal;

--  How a line is coloured.
--
--  Highlighting reads the tokens the lexer already produced. It does not have a
--  grammar of its own and never will: a second grammar would drift from the
--  first, and the drift shows up as a line coloured one way and parsed another.
--
--  It works on input that does not parse, which is most input most of the time
--  -- a user is halfway through typing. That is why it is driven by tokens
--  rather than by the syntax tree: there is a token stream long before there is
--  a tree, and the lexer recovers rather than stopping.
--
--  Colour is never load-bearing. Every distinction a highlight makes is also
--  present in the text, so the line reads the same to somebody whose terminal
--  cannot colour, whose palette is limited, or who cannot perceive the
--  difference. A highlighter that conveyed something the text did not would be
--  a defect rather than a feature.
package Adash.Interactive.Highlighting is

   package Tokens renames Adash.Language.Tokens;

   --  One coloured stretch of a line.
   type Span is record
      Extent : Adash.Source.Span := Adash.Source.Nowhere;
      Role   : Adash.Terminal.Style_Role := Adash.Terminal.Role_Plain;
   end record;

   --  The role a token should be shown in.
   --
   --  Exposed on its own so a completer can describe a candidate in the same
   --  colour the line will use for it, without building a whole highlight.
   --
   --  @param Item The token.
   --  @return Its role.
   function Role_For (Item : Tokens.Token) return Adash.Terminal.Style_Role;

   --  Largest number of spans one highlight holds.
   --
   --  A line longer than this is coloured up to the limit and left plain after
   --  it. Refusing to colour the line at all would be worse, and growing
   --  without bound to colour a pasted megabyte would be worse still.
   Max_Spans : constant := 512;

   type Span_Array is array (1 .. Max_Spans) of Span;

   --  A coloured line.
   type Highlight is record
      Count : Natural range 0 .. Max_Spans := 0;
      Spans : Span_Array;
   end record;

   --  Colour a token stream.
   --
   --  Spans come out in source order and do not overlap, so a renderer can
   --  walk them once alongside the text.
   --
   --  @param From The tokens, as the lexer produced them.
   --  @return The spans to colour.
   function Colour (From : Tokens.Token_Stream) return Highlight;

end Adash.Interactive.Highlighting;

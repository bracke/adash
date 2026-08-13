with Adash.Diagnostics;
with Adash.Language.Tokens;
with Adash.Source;

--  Text to tokens.
--
--  Deterministic and locale-independent. The same bytes produce the same tokens
--  on every machine, whatever the user's locale is set to -- a lexer that asked
--  the C library whether something was a letter would tokenize differently in
--  Turkey, and the difference would show up as a program that compiles on one
--  developer's machine and not another's.
--
--  It never stops. A byte that begins nothing lexical becomes an error token
--  and scanning continues from the next byte; an unterminated string ends at
--  the end of its line. That matters more here than in a batch compiler,
--  because the interactive frontend lexes text the user is *still typing* --
--  which is unterminated by definition, most of the time -- and needs tokens
--  for the part that is finished in order to highlight it and complete in it.
--
--  It does no semantic analysis. It does not know which identifiers are
--  declared, which reserved words Adash supports, or whether a literal fits in
--  an Integer. Those are later questions, and a lexer that answered them would
--  have to be changed whenever they changed.
--
--  There is one place where that line is genuinely hard, and Ada puts it there:
--  the apostrophe is both a character literal's quote and an attribute marker.
--  `'a'` is a literal; `X'Image` is not. The rule used here is the lexical one
--  -- an apostrophe directly after something a name can end with is an
--  attribute marker, and otherwise it opens a character literal -- which needs
--  the *previous token* and nothing more. It is context, but it is not
--  semantics: no table is consulted and no declaration is needed.
package Adash.Language.Lexer is

   --  Turn a buffer into tokens.
   --
   --  Always produces a stream ending in Token_End_Of_Input, even for empty
   --  input and even when every byte was rejected -- so a parser can read the
   --  first token without checking whether there is one.
   --
   --  Lexical problems are reported into Report and also appear in the stream
   --  as Token_Error, because the two callers want different things: a parser
   --  wants the diagnostics, and a highlighter wants to know which bytes it
   --  cannot colour.
   --
   --  @param From The buffer to scan. Must be loaded.
   --  @param Into The token stream, replaced.
   --  @param Report Where lexical diagnostics go.
   procedure Scan
     (From   : Adash.Source.Buffer;
      Into   : out Adash.Language.Tokens.Token_Stream;
      Report : in out Adash.Diagnostics.List);

   --  Whether a character may begin an identifier.
   --
   --  ASCII letters only, and this is a deliberate restriction rather than an
   --  unfinished one. Ada 2022 allows identifiers in any script, but comparing
   --  two of them requires Unicode case folding, which is locale-sensitive in
   --  the corners -- the Turkish dotless i being the usual example. A language
   --  where two names are the same on one machine and different on another is
   --  worse than one that keeps identifiers to ASCII and says so. Non-ASCII
   --  text is fine everywhere it is data: in string literals, in character
   --  literals and in comments.
   --
   --  @param Item The character.
   --  @return True when an identifier may start with it.
   function Is_Identifier_Start (Item : Character) return Boolean;

   --  Whether a character may continue an identifier.
   --
   --  @param Item The character.
   --  @return True for letters, digits and the underscore.
   function Is_Identifier_Part (Item : Character) return Boolean;

end Adash.Language.Lexer;

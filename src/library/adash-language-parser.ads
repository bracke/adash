with Adash.Diagnostics;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Source;

--  Tokens to a tree.
--
--  Recursive descent, following Ada's grammar and Ada's precedence: logical
--  operators bind loosest, then relational, then binary adding, then
--  multiplying, then exponentiation and the unary operators. The levels are
--  separate subprograms rather than a table, so each reads as the rule it
--  implements.
--
--  This is Adash's own parser, and it was Adash's own before the rest of the
--  front end was: the compiler this project once depended on parsed straight to
--  object code and kept no tree, so there was nothing to reuse even then.
--
--  Syntax only. The parser does not know what a name denotes, whether a call is
--  a function or an array index -- Ada spells both `X (1)` -- or whether an
--  expression's types agree. Those are the semantic pass's questions, and a
--  parser that answered them would have to change whenever they did.
--
--  It recovers rather than stopping. On something unexpected it reports once,
--  builds an error node covering what it could not use, and skips to the next
--  token that reliably starts something new -- a semicolon, or a keyword that
--  can only begin a statement. Reporting one problem per construct rather than
--  one per token is what keeps a single missing semicolon from producing forty
--  diagnostics.
package Adash.Language.Parser is

   --  Parse a token stream into a tree.
   --
   --  Always produces a walkable tree, even when nothing parsed: a highlighter
   --  wants it regardless. Whether it may be *evaluated* is a separate question
   --  answered by Syntax.Has_Errors and by the diagnostics, and both must be
   --  consulted -- a tree can be error-free and still have had a warning worth
   --  reporting.
   --
   --  @param From The tokens, as the lexer produced them.
   --  @param Origin Where the source came from, for diagnostics.
   --  @param Into The tree, replaced.
   --  @param Report Where syntax diagnostics go.
   procedure Parse
     (From   : Adash.Language.Tokens.Token_Stream;
      Origin : Adash.Source.Origin;
      Into   : out Adash.Language.Syntax.Tree;
      Report : in out Adash.Diagnostics.List);

   --  Whether a submission stops in the middle of something.
   --
   --  An interactive shell reads a line at a time and has to decide whether
   --  what it has is a program or the beginning of one. `if C then` is not a
   --  mistake, it is unfinished, and the two are told apart by the same
   --  grammar that will parse it: this reports whether parsing ran out of
   --  input rather than met something it did not expect. Counting `end`s
   --  against openers would be a second, quietly different grammar.
   --
   --  Nothing is reported. This is a question, asked before the text is
   --  submitted, and a diagnostic about text the user is still typing would be
   --  noise.
   --
   --  @param From The tokens so far.
   --  @param Origin Where the source came from.
   --  @return True when more input could still complete it.
   function Wants_More
     (From   : Adash.Language.Tokens.Token_Stream;
      Origin : Adash.Source.Origin) return Boolean;

   --  Parse a single expression.
   --
   --  For the places a shell needs one on its own: a prompt expression, a
   --  condition supplied by configuration, a completion request asking what
   --  the fragment under the cursor would mean. The tree's root is the
   --  expression rather than a sequence of statements.
   --
   --  @param From The tokens.
   --  @param Origin Where the source came from.
   --  @param Into The tree, replaced.
   --  @param Report Where syntax diagnostics go.
   procedure Parse_Expression
     (From   : Adash.Language.Tokens.Token_Stream;
      Origin : Adash.Source.Origin;
      Into   : out Adash.Language.Syntax.Tree;
      Report : in out Adash.Diagnostics.List);

end Adash.Language.Parser;

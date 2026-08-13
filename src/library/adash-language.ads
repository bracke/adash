--  The Adash language: a defined subset of Ada.
--
--  This package is the root of the language subsystem and holds no state. What
--  it is for is to name the one pipeline every piece of source takes, and to
--  state the rules the packages beneath it are required to keep.
--
--  One pipeline. Source acquisition, UTF-8 validation, lexing, parsing,
--  semantic analysis, evaluation -- in that order, for a line typed at the
--  prompt, a script file, a startup file, a command substitution and a prompt
--  expression alike. There is no second lexer for interactive input and no
--  second evaluator for scripts. A shell that has two eventually has two
--  dialects, and users rather than tests discover the difference.
--
--  Syntactic validity and semantic legality are different questions, answered
--  in that order and never merged. Something that parses may still be illegal,
--  and the parser must not be the place that decides -- a parser that knows
--  about types is a parser that has to be changed when the type rules change.
--
--  What the subsystem holds is data, not text. Every token, node, symbol and
--  value carries a span into an Adash.Source buffer and, when something is
--  wrong, a diagnostic identity from Adash.Diagnostics. Nothing here produces a
--  sentence.
--
--  The subsystem's layers, lowest first:
--
--    Adash.Language.Types    what a value can be
--    Adash.Language.Values   what a value is
--    Adash.Language.Symbols  what a name denotes
--    Adash.Language.Scopes   which names are visible where
--    Adash.Language.Lexer    text to tokens                    (Phase 4)
--    Adash.Language.Parser   tokens to syntax                   (Phase 5)
--    Adash.Language.Semantics legality and resolution          (Phase 6)
--    Adash.Language.Evaluation running it                      (Phase 7)
--
--  Each depends only on those above it in that list. A lexer that consulted a
--  scope, or a type descriptor that knew about syntax, would be a cycle.
package Adash.Language is
   pragma Pure;

   --  How deeply subprograms may nest, counting the submission itself as one.
   --
   --  Not a machine limit. The machine addresses an outer frame by walking
   --  static links and does not care how many there are; what this bounds is
   --  the front end, where the analyser and the lowering each recurse once per
   --  level. A stated limit that names the subprogram is a better answer than
   --  the compiler's own stack running out somewhere nobody can read.
   --
   --  Named here rather than in either of them because both enforce it, and a
   --  constant written twice is a constant that will differ once.
   Max_Nesting : constant := 20;

end Adash.Language;

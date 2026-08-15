private with Ada.Containers.Vectors;

with Adash.Errors;
with Adash.Source;
with Adash.Language.Symbols;

--  Which names are visible where.
--
--  A scope is a set of declarations and a link to the scope enclosing it. That
--  chain is what makes a name written in an inner block find an outer
--  declaration, and it is why lookup is two questions rather than one: is this
--  name declared *here*, and is it visible *at all*.
--
--  Ada's two rules, both of which a naive table gets wrong:
--
--  Redeclaring a name in the same scope is an error. Not a replacement -- an
--  error, reported with the position of the first declaration, because the
--  second one is almost always a typo or a copy-paste and silently replacing
--  the first makes the program mean something nobody wrote.
--
--  Redeclaring a name in an *inner* scope is legal and hides the outer one. The
--  inner declaration wins for as long as its scope lasts, and the outer one is
--  untouched and visible again afterwards. A table that treated the two cases
--  alike would either reject legal programs or accept broken ones.
--
--  This package is the structure, not the algorithm. Building scopes for a
--  particular program, deciding where one begins and ends, and resolving
--  overloads are Adash.Language.Semantics' work; what is here is the container
--  those decisions are recorded in, so that both the semantic pass and the
--  evaluator read the same one.
package Adash.Language.Scopes is

   package Symbols renames Adash.Language.Symbols;

   --  A chain of scopes: the innermost, and everything enclosing it.
   --
   --  Limited: it is the state of one analysis, and a copy would be a second
   --  set of declarations nobody merges back.
   type Chain is tagged limited private;

   --  How deep the chain is. One means only the outermost scope is open.
   --
   --  @param Item Chain to measure.
   --  @return Its depth; always at least one.
   function Depth (Item : Chain) return Positive;

   --  Open a nested scope.
   --
   --  @param Item Chain to push onto.
   procedure Enter (Item : in out Chain);

   --  Close the innermost scope, discarding its declarations.
   --
   --  Names hidden by it become visible again. Closing the outermost scope does
   --  nothing: a chain always has one, so that a lookup never has to ask
   --  whether there is anywhere to look.
   --
   --  @param Item Chain to pop.
   procedure Leave (Item : in out Chain);

   --  Declare a name in the innermost scope.
   --
   --  @param Item Chain to declare in.
   --  @param Entry_To_Add The symbol.
   --  @param Error Why it was refused, when this returns False. Where the
   --         existing declaration is comes back through Clashed_At: a span is
   --         what a chain has, and a line is what a buffer makes of one.
   --  @return True when the declaration was accepted.
   function Declare_Symbol
     (Item         : in out Chain;
      Entry_To_Add : Symbols.Symbol;
      Error        : out Adash.Errors.Error_Info) return Boolean;
   --  Where the symbol that refused the last declaration was declared.
   --
   --  "X is already declared" is only actionable if the reader is told where
   --  the other one is, and a scope chain cannot say it in words: it has the
   --  span and no buffer to turn a span into a line. So it keeps the span, the
   --  analyser attaches it to the diagnostic as a related place, and the
   --  engine gives it a line once it has the text.
   --
   --  Nowhere when the last declaration succeeded, or failed for another
   --  reason.
   --
   --  @param Item Chain to ask.
   --  @return The earlier declaration's extent.
   function Clashed_At (Item : Chain) return Adash.Source.Span;

   --  Most subprograms one name may denote at one point.
   --
   --  A limit rather than a vector, because the result is built on the stack at
   --  every call site that resolves a name. Beyond this many the program has a
   --  different problem than the one this bound creates.
   Max_Overloads : constant := 32;

   type Symbol_List is array (1 .. Max_Overloads) of Symbols.Symbol;

   --  Every declaration of a name that a call here could mean.
   --
   --  One name can denote several subprograms, and which one a call means is
   --  decided by its arguments rather than by the name. This gathers the
   --  candidates; choosing among them is the semantic pass's work, because only
   --  it knows what the arguments turned out to be.
   --
   --  Inner declarations come first. An inner declaration with the same profile
   --  hides the outer one, as Ada says; one with a different profile does not,
   --  so both are offered. A name that denotes something which is not callable
   --  is returned alone, because a variable hides a subprogram outright.
   --
   --  @param Item Chain to search.
   --  @param Name The name as written.
   --  @param Found The candidates, innermost first.
   --  @param Count How many; zero when the name is not visible.
   procedure Candidates
     (Item  : Chain;
      Name  : String;
      Found : out Symbol_List;
      Count : out Natural);

   --  Find a name, searching outwards from the innermost scope.
   --
   --  @param Item Chain to search.
   --  @param Name The name as written; folded here, so callers need not.
   --  @return The symbol, or Symbols.Nothing when the name is not visible.
   function Lookup (Item : Chain; Name : String) return Symbols.Symbol;

   --  Find a name in the innermost scope only.
   --
   --  What a declaration checks before adding, and what tells a hidden outer
   --  declaration apart from a duplicate inner one.
   --
   --  @param Item Chain to search.
   --  @param Name The name as written.
   --  @return The symbol, or Symbols.Nothing when it is not declared here.
   function Lookup_Local (Item : Chain; Name : String) return Symbols.Symbol;

   --  Whether a name is visible at all.
   --
   --  @param Item Chain to search.
   --  @param Name The name as written.
   --  @return True when Lookup would find something.
   function Is_Visible (Item : Chain; Name : String) return Boolean;

   --  Whether declaring this name here would hide an outer declaration.
   --
   --  Legal, and worth a warning rather than an error: hiding is sometimes
   --  deliberate and sometimes a mistake, and only the user can tell. Offered
   --  so the semantic pass can say so without searching twice.
   --
   --  @param Item Chain to search.
   --  @param Name The name as written.
   --  @return True when an enclosing scope declares this name.
   function Would_Hide (Item : Chain; Name : String) return Boolean;

   --  How many names the innermost scope declares.
   --
   --  @param Item Chain to inspect.
   --  @return The count.
   function Local_Count (Item : Chain) return Natural;

private

   use type Symbols.Symbol;

   package Symbol_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Symbols.Symbol);

   --  One scope's declarations, in declaration order.
   --
   --  A vector rather than a hashed map. Scopes in a shell language are small --
   --  a handful of names in a block, a few dozen at the outermost level -- and
   --  a linear scan over that is faster than hashing. Declaration order is also
   --  worth keeping for its own sake: a listing of what is in scope should not
   --  come out in hash order, which changes between runs.
   type Scope is record
      First : Natural := 0;
      Last  : Natural := 0;
   end record;

   package Scope_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Scope);

   type Chain is tagged limited record
      --  Every symbol in every open scope, innermost last. Each scope records
      --  the slice of this that belongs to it, so leaving a scope is a
      --  truncation rather than a walk.
      Entries : Symbol_Vectors.Vector;

      --  One entry per open scope. Never empty: a chain always has an outermost
      --  scope, so a lookup never has to ask whether there is anywhere to look.
      Levels : Scope_Vectors.Vector;

      Started : Boolean := False;

      --  Where the symbol that refused the last declaration was declared; see
      --  Clashed_At.
      Clash : Adash.Source.Span := Adash.Source.Nowhere;
   end record;

end Adash.Language.Scopes;

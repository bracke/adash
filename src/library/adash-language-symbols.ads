--  Visible rather than private since parameters gained names and defaults:
--  both are text, both are part of what a profile *is*, and a caller building
--  one has to be able to say so.
with Ada.Strings.Unbounded;

with Adash.Language.Types;
with Adash.Source;

--  What a name denotes.
--
--  A symbol is the thing a scope maps a name to: what sort of entity it is,
--  what type it has, whether it can be assigned to, and where it was declared.
--  That last part is not decoration -- "already declared, on line 12" is only
--  possible because the first declaration kept its span.
--
--  Names are case-insensitive, because Ada's are. `Count`, `count` and `COUNT`
--  are one name, and a language claiming to be a subset of Ada that treated
--  them as three would surprise every user it had. Two spellings are kept: the
--  folded form, which is what lookup compares, and the original, which is what
--  a diagnostic quotes back. Reporting the folded form would show a user a name
--  they did not write.
package Adash.Language.Symbols is

   package Types renames Adash.Language.Types;

   --  What sort of entity a name denotes.
   type Symbol_Kind is
     (
      --  A variable: has a type, and can be assigned to.
      Symbol_Variable,

      --  A constant: has a type, and cannot.
      Symbol_Constant,

      --  A value of an enumeration, named by its declaration. Not a constant,
      --  because a constant has storage and a place to be read from and this
      --  has neither: what it *is* is its position in its type, which the
      --  lowering pushes. Telling the two apart matters -- a loop parameter
      --  over an enumeration is a constant of that type, and pushing its
      --  position rather than reading its slot would make every turn of the
      --  loop the first one.
      Symbol_Literal,

      --  A formal parameter of the enclosing subprogram.
      Symbol_Parameter,

      --  A function: yields a value.
      Symbol_Function,

      --  A procedure: does not.
      Symbol_Procedure,

      --  An entry of a protected object. Called the way a procedure is, and
      --  told apart from one because only an entry has a barrier -- which is
      --  what `select` waits on, and what makes `select P.Some_Procedure;` a
      --  decision this language refuses rather than a gap in it.
      Symbol_Entry,

      --  A package: a name that groups declarations rather than denoting a
      --  value. What it holds is declared beside it under a dotted name, so a
      --  member is an ordinary symbol and `P.X` is a way of spelling one.
      --  That is why nothing here has to hold a scope: a package is a naming
      --  convention the analyser keeps, and every pass below it sees ordinary
      --  declarations.
      Symbol_Package,

      --  A generic subprogram: a template rather than something callable. A
      --  call to one is an error; an instantiation copies its body and
      --  analyses the copy with the formals bound.
      Symbol_Generic,

      --  A type name. Denotes a type rather than a value, so it can be written
      --  where a type is expected and nowhere else -- `X : Integer` is legal
      --  and `X := Integer` is not, and telling them apart needs this to be a
      --  kind rather than a convention about which names are types.
      Symbol_Type,

      --  An exception a program declared. It has no type and no storage: what
      --  it is is a name, and what a raise and a handler agree on is that
      --  name -- which is why the machine carries a raised exception as text
      --  rather than as a number nobody could read back.
      Symbol_Exception);

   --  Largest number of parameters a declared subprogram may have.
   --
   --  A limit rather than a vector, because a symbol is copied constantly --
   --  every lookup returns one -- and a bounded record keeps that free. Sixteen
   --  is past the point where a positional call is readable anyway.
   Max_Parameters : constant := 16;

   --  The types a subprogram's parameters have, by position.
   type Parameter_Types is array (1 .. Max_Parameters) of Types.Type_Kind;

   --  How a parameter is passed, and what the body may do with it.
   --
   --  The distinction is not decoration. An `in` parameter is a value the body
   --  reads; the other two are the caller's own variable, which the body
   --  writes through. That difference decides three separate things -- whether
   --  the body may assign to it, whether the actual must be a variable rather
   --  than any expression, and whether the call passes a value or an address --
   --  and getting it from one place is what keeps those three in step.
   type Parameter_Mode is (Mode_In, Mode_Out, Mode_In_Out);

   type Parameter_Modes is array (1 .. Max_Parameters) of Parameter_Mode;

   --  The names a subprogram's parameters were declared with, by position.
   --
   --  Kept because a call may name them: `Report (Text => S, Wide => True)` is
   --  Ada, and without the names here nothing downstream could match a name to
   --  a position. Folded on comparison, like every other name.
   type Parameter_Names is
     array (1 .. Max_Parameters) of Ada.Strings.Unbounded.Unbounded_String;

   --  A parameter's default, as the literal was written.
   --
   --  Source text rather than a value, for two reasons. The lowering emits a
   --  literal from its text, so a default reaches the machine by exactly the
   --  path a literal written at the call site does -- no second encoding to
   --  disagree with the first. And this package sits below Adash.Language.
   --  Values in the layering by choice: a symbol says what a name denotes, and
   --  storing evaluated values here would make it a place things are computed.
   --
   --  Only a literal, possibly signed. An arbitrary expression would have to be
   --  evaluated at the call site in the scope of the *declaration*, which is
   --  the one thing a name resolved at the call site cannot do.
   type Parameter_Defaults is
     array (1 .. Max_Parameters) of Ada.Strings.Unbounded.Unbounded_String;

   --  Which parameters have one. Separate from the text because the empty
   --  string is a perfectly good default for a String.
   type Parameter_Has_Default is array (1 .. Max_Parameters) of Boolean;

   --  One declared name.
   type Symbol is private;

   --  A symbol denoting nothing, which lookup returns when a name is not found.
   Nothing : constant Symbol;

   --  Declare a symbol.
   --
   --  @param Name The name as written, in the user's own spelling.
   --  @param Kind What sort of entity it is.
   --  @param Of_Type Its type. Type_None for a procedure, which has none.
   --  @param Origin Where the declaring source came from.
   --  @param Extent Where the declaration is.
   --  @return The symbol.
   --  @param Mode For a parameter, how it is passed. Ignored for anything else.
   --  @param Provided True when the shell puts this name in scope rather than
   --         a source declaring it.
   --  @param Position For an enumeration literal, where it sits in its type.
   --         Ignored for anything else.
   function Make
     (Name     : String;
      Kind     : Symbol_Kind;
      Of_Type  : Types.Type_Kind;
      Origin   : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent   : Adash.Source.Span := Adash.Source.Nowhere;
      Mode     : Parameter_Mode := Mode_In;
      Provided : Boolean := False;
      Position : Natural := 0) return Symbol;

   --  Whether the shell put this name in scope.
   --
   --  A predefined entity and a command are in scope without anything having
   --  declared them, so they have no position in any source. Asking where one
   --  was declared answers with a line nobody wrote, and a diagnostic that
   --  reported a collision with one used to say "already declared, on line 1"
   --  -- pointing at a line that has nothing to do with it. This is how the
   --  two are told apart.
   --
   --  @param Item Symbol to inspect.
   --  @return True when the shell provides it.
   function Is_Provided (Item : Symbol) return Boolean;

   --  The subprogram an exception was declared inside, or "".
   --
   --  Two exceptions of one name in two subprograms are two exceptions, and
   --  what runs tells them apart by the text they settled on -- so the text
   --  has to differ. A package prefixes what it holds and answers this by
   --  itself; a subprogram does not prefix its locals, and without this a
   --  handler naming an unrelated `Oops` caught the one raised inside
   --  `Attempt`.
   --
   --  Recorded rather than derived, and used only where a name is settled: it
   --  changes what a raise and a handler compare, and nothing about how a
   --  name is looked up.
   --
   --  @param Item Symbol to inspect.
   --  @return The enclosing subprogram's name, or "".
   function Declared_Within (Item : Symbol) return String;

   --  Say which subprogram this was declared inside.
   --
   --  @param Item Symbol to change.
   --  @param Unit The enclosing subprogram's name.
   procedure Declare_Within (Item : in out Symbol; Unit : String);

   --  Declare a subprogram.
   --
   --  Separate from Make because a subprogram carries something no other
   --  symbol does: what it accepts. Folding that into Make would give every
   --  variable a parameter list to ignore, and would let a caller build a
   --  callable symbol while forgetting to say what it takes -- which reads as
   --  "takes nothing" and would accept every wrong call in silence.
   --
   --  @param Name The name as written, in the user's own spelling.
   --  @param Kind Symbol_Function or Symbol_Procedure.
   --  @param Of_Type What it returns. Type_None for a procedure.
   --  @param Count How many parameters it has.
   --  @param Parameters Their types, by position; only the first Count are read.
   --  @param Modes How each is passed, by position.
   --  @param Names What each is called, by position.
   --  @param Defaults The literal each defaults to, by position.
   --  @param Defaulted Which of them have one.
   --  @param Origin Where the declaring source came from.
   --  @param Extent Where the declaration is.
   --  @return The symbol.
   function Make_Subprogram
     (Name       : String;
      Kind       : Symbol_Kind;
      Of_Type    : Types.Type_Kind;
      Count      : Natural;
      Parameters : Parameter_Types;
      Modes      : Parameter_Modes := [others => Mode_In];
      Names      : Parameter_Names := [others => <>];
      Defaults   : Parameter_Defaults := [others => <>];
      Defaulted  : Parameter_Has_Default := [others => False];
      Origin     : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent     : Adash.Source.Span := Adash.Source.Nowhere) return Symbol
     with Pre => Kind in Symbol_Function | Symbol_Procedure | Symbol_Entry
                 and then Count <= Max_Parameters;

   --  Whether this symbol carries a parameter profile of its own.
   --
   --  Not the same question as "has no parameters". A subprogram declared with
   --  an empty parameter list and a name that merely happens to be callable
   --  both report a count of zero, and treating the second as the first would
   --  say `Put_Line` takes nothing -- which is how the predefined names, all of
   --  which are in scope as symbols, would start rejecting their own arguments.
   --
   --  @param Item Symbol to ask about.
   --  @return True when Make_Subprogram built it.
   function Has_Profile (Item : Symbol) return Boolean;

   --  How many parameters a subprogram takes.
   --
   --  @param Item Symbol to inspect.
   --  @return Its parameter count; zero for anything that is not a subprogram.
   function Parameter_Count (Item : Symbol) return Natural;

   --  The type of one parameter.
   --
   --  @param Item Symbol to inspect.
   --  @param Index Which parameter, from one.
   --  @return Its type.
   function Parameter_Type
     (Item : Symbol; Index : Positive) return Types.Type_Kind
     with Pre => Index <= Max_Parameters;

   --  How one parameter is passed.
   --
   --  @param Item Symbol to inspect.
   --  @param Index Which parameter, from one.
   --  @return Its mode.
   function Parameter_Passing
     (Item : Symbol; Index : Positive) return Parameter_Mode
     with Pre => Index <= Max_Parameters;

   --  What one parameter is called.
   --
   --  @param Item Symbol to inspect.
   --  @param Index Which parameter, from one.
   --  @return Its name, as it was declared.
   function Parameter_Name
     (Item : Symbol; Index : Positive) return String
     with Pre => Index <= Max_Parameters;

   --  Which position a name denotes.
   --
   --  @param Item Symbol to inspect.
   --  @param Name The name a call wrote, in any case.
   --  @return Its position, or zero when this subprogram has no such
   --          parameter.
   function Parameter_At (Item : Symbol; Name : String) return Natural;

   --  Whether one parameter may be left out of a call.
   --
   --  @param Item Symbol to inspect.
   --  @param Index Which parameter, from one.
   --  @return True when it has a default.
   function Has_Default
     (Item : Symbol; Index : Positive) return Boolean
     with Pre => Index <= Max_Parameters;

   --  The literal one parameter defaults to, as it was written.
   --
   --  @param Item Symbol to inspect.
   --  @param Index Which parameter, from one.
   --  @return The source text of its default, or "" when it has none.
   function Default_Text
     (Item : Symbol; Index : Positive) return String
     with Pre => Index <= Max_Parameters;

   --  Where an enumeration literal sits in its type.
   --
   --  Zero for everything else, which is also the right answer for the first
   --  literal: what tells them apart is the type, and nothing asks this of a
   --  symbol that is not one.
   --
   --  @param Item Symbol to inspect.
   --  @return Its position, counting from zero.
   function Position (Item : Symbol) return Natural;

   --  How this parameter itself is passed.
   --
   --  @param Item Symbol to inspect; meaningful for a parameter.
   --  @return Its mode, Mode_In for anything else.
   function Passing (Item : Symbol) return Parameter_Mode;

   --  Whether two symbols are the same subprogram as far as overloading is
   --  concerned.
   --
   --  Same name, same number of parameters, same parameter types, same result
   --  type. Modes are not part of it -- Ada does not overload on them, and two
   --  subprograms differing only in a mode could not be told apart at a call.
   --
   --  The result type *is* part of it, which makes two subprograms differing
   --  only in what they return two subprograms rather than one declared twice.
   --  A call then has to be resolved by what the context expects, and where the
   --  context expects nothing the call is ambiguous -- which is Ada's answer
   --  too, and a better one than refusing the declaration.
   --
   --  @param Left First symbol.
   --  @param Right Second symbol.
   --  @return True when a call could not tell them apart.
   function Same_Profile (Left, Right : Symbol) return Boolean;

   --  @param Item Symbol to test.
   --  @return True when Item denotes nothing.
   function Is_Nothing (Item : Symbol) return Boolean;

   --  The name as the user wrote it.
   --
   --  What a diagnostic quotes. Showing the folded form instead would display a
   --  name the user did not type.
   --
   --  @param Item Symbol to inspect.
   --  @return Its original spelling.
   function Name (Item : Symbol) return String;

   --  The name folded for comparison.
   --
   --  @param Item Symbol to inspect.
   --  @return Its name in lower case.
   function Key (Item : Symbol) return String;

   --  @param Item Symbol to inspect.
   --  @return What sort of entity it denotes.
   function Kind (Item : Symbol) return Symbol_Kind;

   --  @param Item Symbol to inspect.
   --  @return Its type.
   function Of_Type (Item : Symbol) return Types.Type_Kind;

   --  @param Item Symbol to inspect.
   --  @return Where the declaring source came from.
   function Origin (Item : Symbol) return Adash.Source.Origin;

   --  @param Item Symbol to inspect.
   --  @return Where it was declared.
   function Extent (Item : Symbol) return Adash.Source.Span;

   --  Whether the language permits assigning to this symbol.
   --
   --  Asked here rather than decided at each assignment, so that "constants
   --  cannot be assigned to" is one rule rather than one per site.
   --
   --  @param Item Symbol to ask about.
   --  @return True for a variable, and for an `out` or `in out` parameter.
   function Is_Assignable (Item : Symbol) return Boolean;

   --  Whether this symbol can be called.
   --
   --  @param Item Symbol to ask about.
   --  @return True for a function or a procedure.
   function Is_Callable (Item : Symbol) return Boolean;

   --  Fold a name for comparison.
   --
   --  Exposed because a lookup by a name that has no symbol yet -- the usual
   --  case -- still has to fold it the same way. A caller doing its own folding
   --  is a caller that will disagree with this one about some character.
   --
   --  @param Name The name as written.
   --  @return Its folded form.
   function Fold (Name : String) return String;

private

   type Symbol is record
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Key     : Ada.Strings.Unbounded.Unbounded_String;
      Kind    : Symbol_Kind := Symbol_Variable;
      Of_Type : Types.Type_Kind := Types.Type_None;
      Origin  : Adash.Source.Origin;
      Extent  : Adash.Source.Span := Adash.Source.Nowhere;
      Present : Boolean := False;

      --  In scope because the shell put it there, rather than because a source
      --  declared it. Such a symbol has no position, so nothing may report one
      --  for it.
      Provided : Boolean := False;

      --  The subprogram this was declared inside, for an exception. Empty for
      --  everything else, and for one declared anywhere else.
      Within : Ada.Strings.Unbounded.Unbounded_String;

      --  Meaningful only for a function or a procedure. Zero elsewhere, which
      --  is also the right answer there: nothing else can be called, so
      --  nothing else has parameters to get wrong.
      Profiled   : Boolean := False;
      Count      : Natural range 0 .. Max_Parameters := 0;
      Parameters : Parameter_Types := [others => Types.Type_None];
      Modes      : Parameter_Modes := [others => Mode_In];
      Names      : Parameter_Names := [others => <>];
      Defaults   : Parameter_Defaults := [others => <>];
      Defaulted  : Parameter_Has_Default := [others => False];

      --  For a parameter symbol: how this one is passed.
      Passed_As  : Parameter_Mode := Mode_In;

      --  For an enumeration literal: where it sits in its type.
      Sits_At : Natural := 0;
   end record;

   Nothing : constant Symbol := (others => <>);

end Adash.Language.Symbols;

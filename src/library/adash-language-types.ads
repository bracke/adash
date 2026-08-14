--  What a value in the Adash language can be.
--
--  The type set is deliberately small and deliberately Ada's. Adash's command
--  language is a subset of Ada, so its types are Ada's types under Ada's names
--  and with Ada's semantics -- not a shell-flavoured approximation. A user who
--  knows what Integer means in Ada knows what it means here, and that is worth
--  more than any convenience a looser model would buy.
--
--  Five types are built in and a program may declare its own enumerations. A
--  type is therefore no longer a literal of an enumeration here: it is a
--  *shape* -- which of the six kinds of thing it is -- and, for one a program
--  declared, an identity telling one declaration from another. Two enumerations
--  with the same literals spelled the same way are still two types, exactly as
--  in Ada, and the identity is what says so.
--
--  The identity is a number this package does not interpret. What produces it
--  is the semantic pass, which uses the offset the declaration was written at:
--  unique within a submission by construction, and stable across the passes
--  because the source it points into is.
--
--  What is deliberately absent, and why:
--
--  There is no untyped scalar and no automatic conversion between types. A
--  language where "1" and 1 are interchangeable is a language where a
--  comparison silently means something other than it says, which is the single
--  most common source of shell bugs. Conversions here are written down.
--
--  A composite -- a record or an array -- is its parts laid end to end in the
--  machine's slots, and what it is made of is *not* here. A type travels inside
--  every symbol and every parameter profile, and those are copied constantly; a
--  component list riding along would make every scope lookup carry the whole
--  shape of every type in sight. What is here is the identity and the width;
--  Adash.Language.Semantics holds what the identity opens.
--
--  There are no access types. A shell script has nothing to point at that
--  outlives the statement that made it, and a language with pointers has an
--  aliasing question in every assignment.
--
--  There is nothing shell-specific here. No exit status, no path, no command.
--  Those live in Adash.Execution, which is a sibling subsystem rather than one
--  beneath this; a type descriptor that knew about them would invert the
--  dependency and make the language unusable without the execution engine.
package Adash.Language.Types is

   --  What kind of thing a type is.
   --
   --  What a case dispatches on. The five built-in types are one shape each
   --  because there is one of each; an enumeration is a shape with many types
   --  in it, told apart by identity.
   type Type_Shape is
     (
      --  No value at all. What a procedure yields, and what an expression whose
      --  evaluation failed carries -- so that "no result" is representable
      --  rather than being some other type's out-of-band value.
      Shape_None,

      --  Ada's Boolean. Two values, and the only type a condition accepts:
      --  there is no truthiness here, and an Integer is not a condition.
      Shape_Boolean,

      --  Ada's Integer. Signed, and the host's natural width.
      Shape_Integer,

      --  Ada's Float.
      Shape_Float,

      --  Ada's Character. A single Unicode code point rather than a byte:
      --  Adash source is UTF-8 and indexing a string by byte would hand back
      --  half a character.
      Shape_Character,

      --  Ada's String, as a value rather than as an array of Character. The
      --  distinction matters because Adash strings carry their own length and
      --  are not sliced by unconstrained array rules.
      Shape_String,

      --  A type the program declared: `type Colour is (Red, Green, Blue);`.
      --  Discrete, ordered by the order its literals were written in, and not
      --  the same type as any other enumeration however alike they look.
      Shape_Enumeration,

      --  `type Line is record Number : Integer; Text : String; end record;`.
      --  A fixed set of named components, each with a type of its own.
      Shape_Record,

      --  `type Counts is array (1 .. 10) of Integer;`. A fixed number of
      --  elements of one type, reached by position.
      Shape_Array,

      --  `task type Worker is entry Go; end Worker;`. A value of one names the
      --  task running it, which is why a task is a type at all: several
      --  objects of one task type are several tasks, and a rendezvous has to
      --  find the one it was written against rather than the routine they
      --  share.
      Shape_Task,

      --  `protected type Counter is ... end Counter;`. Not a value at all: an
      --  object of one is state and a lock, and what a program does with it is
      --  call its operations. It is a type so that a program can have more
      --  than one of them.
      Shape_Protected,

      --  What `A'Identity` yields: which task, as something a program can
      --  hold. A task object cannot be copied -- Ada's task types are limited
      --  and so are these -- so without a type of its own an identity could be
      --  compared and never kept, which is most of what one is for.
      Shape_Task_Id);

   --  How long a declared type's name may be, for the purpose of quoting it
   --  back in a diagnostic.
   --
   --  A bound rather than an unbounded string, because a type travels inside
   --  every symbol and every parameter profile and those are copied constantly.
   --  Identity is the number, not the name, so a longer name is quoted short
   --  rather than confused with another.
   Max_Name : constant := 31;

   type Type_Kind is private;

   --  Whether two types are the same type.
   --
   --  Shape and identity, and deliberately not the constraint or the name: a
   --  subtype *is* its base type in Ada, which is why a Percent may be
   --  assigned to an Integer and back. Every question of the form "is this an
   --  Integer?" means this one, and there are dozens of them; a `=` that
   --  compared bounds would answer no to all of them for a constrained
   --  subtype, which is how a subtype stops being usable anywhere its base is.
   --
   --  What the constraint is for is Has_Bounds and the check the lowering
   --  emits from it, and those ask for it by name.
   --
   --  @param Left One type.
   --  @param Right The other.
   --  @return True when they are the same type.
   overriding function "=" (Left, Right : Type_Kind) return Boolean;

   --  @param Item Type to inspect.
   --  @return What kind of thing it is.
   function Shape (Item : Type_Kind) return Type_Shape;

   --  Which declaration a program-declared type came from.
   --
   --  @param Item Type to inspect.
   --  @return Its identity, or zero for a built-in type.
   function Identity (Item : Type_Kind) return Natural;

   --  The five built-in types, and the absence of one.
   Type_Task_Id   : constant Type_Kind;
   Type_None      : constant Type_Kind;
   Type_Boolean   : constant Type_Kind;
   Type_Integer   : constant Type_Kind;
   Type_Float     : constant Type_Kind;
   Type_Character : constant Type_Kind;
   Type_String    : constant Type_Kind;

   --  How many slots a value of this type occupies.
   --
   --  One for everything that fits in a machine cell, which is every scalar
   --  and a String -- a String carries its own text in one cell. A composite
   --  is its components laid end to end, and *that* is what makes a record and
   --  an array work on a machine whose frames are arrays of cells: a variable
   --  of one is a run of slots, and reaching into it is arithmetic on where
   --  the run starts.
   --
   --  @param Item Type to measure.
   --  @return How many slots it takes.
   function Width (Item : Type_Kind) return Positive;

   --  Build the type a record declaration introduces.
   --
   --  What the components are is not here. A type travels inside every symbol
   --  and every parameter profile, and those are copied constantly; a
   --  component list riding along would make every scope lookup carry the
   --  whole shape of every type in sight. The identity is the key, and
   --  Adash.Language.Semantics holds what it opens.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @param Slots How many slots its components take together.
   --  @return The type.
   function Composite_Record
     (Id     : Positive;
      Called : String;
      Slots  : Positive) return Type_Kind;

   --  Build the type an array declaration introduces.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @param Slots How many slots its elements take together.
   --  @return The type.
   function Composite_Array
     (Id     : Positive;
      Called : String;
      Slots  : Positive) return Type_Kind;

   --  Build the type an unconstrained array declaration introduces.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @return The type.
   function Open_Array (Id : Positive; Called : String) return Type_Kind;

   --  Whether this array type's values carry their own length.
   --
   --  @param Item Type to ask about.
   --  @return True for `array (Integer range <>) of T`, and for nothing else.
   function Is_Open (Item : Type_Kind) return Boolean;

   --  Whether a value of this type is more than one thing.
   --
   --  @param Item Type to ask about.
   --  @return True for a record and an array.
   function Is_Composite (Item : Type_Kind) return Boolean;

   --  Build the type a subtype declaration introduces.
   --
   --  A subtype is the same *type* as what it names -- that is Ada's rule, and
   --  it is why a Percent may be assigned to an Integer and back -- with a
   --  narrower set of values and a name of its own. So the identity is the
   --  base's, unchanged, and what this adds is the bounds and the name.
   --
   --  @param Base The type it constrains.
   --  @param Called The name it was declared with.
   --  @param Low The first value it admits, as a position.
   --  @param High The last.
   --  @return The subtype.
   function Constrained
     (Base   : Type_Kind;
      Called : String;
      Low    : Long_Long_Integer;
      High   : Long_Long_Integer) return Type_Kind;

   --  Whether a type admits fewer values than the one it names.
   --
   --  @param Item Type to ask about.
   --  @return True when a range was written for it.
   function Has_Bounds (Item : Type_Kind) return Boolean;

   --  @param Item Type to ask about.
   --  @return The first value it admits, as a position.
   function Low_Bound (Item : Type_Kind) return Long_Long_Integer;

   --  @param Item Type to ask about.
   --  @return The last value it admits, as a position.
   function High_Bound (Item : Type_Kind) return Long_Long_Integer;

   --  Build the type an enumeration declaration introduces.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @param Literals How many values it has.
   --  @return The type.
   function Enumeration
     (Id       : Positive;
      Called   : String;
      Literals : Natural) return Type_Kind;

   --  Build the type a task type declaration introduces.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @return The type.
   function Task_Type (Id : Positive; Called : String) return Type_Kind;

   --  Whether a value of this type is a task.
   --
   --  @param Item Type to ask about.
   --  @return True for a task type.
   function Is_Task (Item : Type_Kind) return Boolean;

   --  Build the type a protected type declaration introduces.
   --
   --  @param Id Which declaration, as the caller identifies them.
   --  @param Called The name it was declared with.
   --  @return The type.
   function Protected_Type (Id : Positive; Called : String) return Type_Kind;

   --  Whether this type is a protected one.
   --
   --  @param Item Type to ask about.
   --  @return True for a protected type.
   function Is_Protected (Item : Type_Kind) return Boolean;

   --  How many values a type admits, counting a constraint.
   --
   --  Value_Count answers for the *type*, which is what a case has to cover;
   --  this answers for what a constrained subtype lets through, which is what
   --  a run of things indexed by one has to be long enough for. `subtype Lane
   --  is Integer range 1 .. 3` has three of these and as many of the other as
   --  an Integer has.
   --
   --  @param Item Type to measure.
   --  @return How many values it admits, or zero when it is not discrete.
   function Admitted_Count (Item : Type_Kind) return Long_Long_Integer;

   --  The type's name as the language spells it.
   --
   --  This is a language identifier, not text for a user: it is what a script
   --  writes and what a diagnostic quotes, and it must be the same in every
   --  locale. A user who reads "Integer" in an error and types "Integer" in
   --  their source has to get the same thing.
   --
   --  @param Item Type to name.
   --  @return Its Ada name, or "" for Type_None, which has no spelling in the
   --          language because it cannot be written down.
   function Name (Item : Type_Kind) return String;

   --  Whether a type has an ordering, so that <, <=, > and >= are defined.
   --
   --  Boolean is ordered in Ada -- False < True -- and saying so here rather
   --  than in the evaluator keeps one answer to the question.
   --
   --  @param Item Type to ask about.
   --  @return True when the relational operators apply.
   function Is_Ordered (Item : Type_Kind) return Boolean;

   --  Whether a type has a first value, a last value, and a successor for
   --  every value but the last.
   --
   --  What a case statement examines and what a for loop counts over. Float is
   --  not one of these and neither is String: between any two Floats there is
   --  another, and a String has no successor at all, so "covers every value"
   --  is not a question either can answer.
   --
   --  @param Item Type to ask about.
   --  @return True for Boolean, Integer, Character and an enumeration.
   function Is_Discrete (Item : Type_Kind) return Boolean;

   --  How many values a discrete type has.
   --
   --  @param Item Type to measure.
   --  @return Its number of values, or zero when it is not discrete.
   function Value_Count (Item : Type_Kind) return Long_Long_Integer;

   --  Whether a type supports arithmetic.
   --
   --  @param Item Type to ask about.
   --  @return True for the numeric types.
   function Is_Numeric (Item : Type_Kind) return Boolean;

   --  Whether a value of this type can be written as a literal in source.
   --
   --  An enumeration's values are written as the names its declaration gave
   --  them, which are names rather than literals: they resolve through the
   --  scope chain like any other, and a body may hide one.
   --
   --  @param Item Type to ask about.
   --  @return True when the language has a literal form for it.
   function Has_Literals (Item : Type_Kind) return Boolean;

   --  Whether a value of one type may be used where another is expected.
   --
   --  Only when the types are the same. There is no implicit conversion in
   --  Adash, including the ones Ada itself allows between numeric types: a
   --  language that quietly turns an Integer into a Float has a rounding rule
   --  nobody wrote down.
   --
   --  @param Found The type of the value in hand.
   --  @param Expected The type required.
   --  @return True when the value is acceptable as it stands.
   function Is_Acceptable (Found : Type_Kind; Expected : Type_Kind) return Boolean;

   --  Whether an explicit conversion between two types is defined.
   --
   --  Written down, never implied. Integer and Float convert to each other and
   --  to String; Character and String convert to each other; Boolean converts
   --  only to String. Nothing converts to or from Type_None.
   --
   --  @param From The source type.
   --  @param To The target type.
   --  @return True when a conversion exists.
   function Is_Convertible (From : Type_Kind; To : Type_Kind) return Boolean;

private

   subtype Name_Length is Natural range 0 .. Max_Name;
   subtype Name_Text is String (1 .. Max_Name);

   type Type_Kind is record
      Form : Type_Shape := Shape_None;

      --  Zero for a built-in type. For a declared one, which declaration --
      --  and that is what tells two enumerations apart, not the name and not
      --  the literals.
      Id : Natural := 0;

      --  The declared name, for quoting back. A built-in type's name is a
      --  literal of this package and is not kept here.
      Called : Name_Text := [others => ' '];
      Length : Name_Length := 0;

      --  How many values a declared type has.
      Literals : Natural := 0;

      --  How many machine slots a value takes. One for everything that fits
      --  in a cell; more for a composite, which is its parts end to end.
      Slots : Positive := 1;

      --  An array type whose values carry their own length: `array (Integer
      --  range <>) of T`. It has no width of its own -- a variable of one says
      --  how long it is where it is declared, and what a parameter of one
      --  receives says so at run time, in the place it travels as.
      Open : Boolean := False;

      --  For a subtype with a range: the values it admits, as positions.
      --  Bounded rather than open because that is what a constraint is, and
      --  because the check the machine emits is two comparisons either way.
      Narrowed : Boolean := False;
      Low      : Long_Long_Integer := 0;
      High     : Long_Long_Integer := 0;
   end record;

   Type_None      : constant Type_Kind := (others => <>);
   Type_Boolean   : constant Type_Kind := (Form => Shape_Boolean, others => <>);
   Type_Integer   : constant Type_Kind := (Form => Shape_Integer, others => <>);
   Type_Float     : constant Type_Kind := (Form => Shape_Float, others => <>);
   Type_Character : constant Type_Kind :=
     (Form => Shape_Character, others => <>);
   Type_String    : constant Type_Kind := (Form => Shape_String, others => <>);
   Type_Task_Id   : constant Type_Kind :=
     (Form => Shape_Task_Id, others => <>);

end Adash.Language.Types;

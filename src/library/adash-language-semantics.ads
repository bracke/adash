with Ada.Containers.Vectors;

with Ada.Strings.Unbounded;

with Adash.Diagnostics;
with Adash.Language.Symbols;
with Adash.Language.Syntax;
with Adash.Language.Types;
with Adash.Source;

--  Is this program legal, and what does it mean?
--
--  Parsing answered whether the text has a shape. This answers the separate
--  question of whether that shape means anything: whether every name is
--  declared, whether the operators have operands they are defined for, whether
--  a condition is Boolean, whether the thing being assigned to can be.
--
--  Those are different questions on purpose, and merging them is how a parser
--  ends up needing to know about types. `X (1)` parses the same whether X is a
--  function or an array; only this pass can say which, and only because it
--  knows what X was declared as.
--
--  **Nothing here mutates the tree.** Every conclusion -- the type an
--  expression has, the symbol a name denotes -- is recorded in a side table
--  keyed by `Node_Id`. That is what the arena in Adash.Language.Syntax was for.
--  A pass that wrote into the tree would leave no way to tell which pass a
--  value came from, and no way to run the pass twice on one tree, which an
--  interactive session does every time a line is edited.
--
--  It does not stop at the first problem. An expression whose type could not be
--  determined is given Type_None and analysis continues, so a user gets every
--  independent error at once rather than one per attempt. Type_None then
--  suppresses further complaints about the same expression, because a cascade
--  of errors derived from one unknown type tells a user nothing.
package Adash.Language.Semantics is

   package Types renames Adash.Language.Types;
   package Symbols renames Adash.Language.Symbols;
   package Syntax renames Adash.Language.Syntax;

   --  What analysis concluded about one tree.
   --
   --  Limited: it refers to a tree by node index, and a copy separated from
   --  that tree would be a set of conclusions about nothing.
   type Analysis is tagged limited private;

   --  Analyse a parsed tree.
   --
   --  The tree must have parsed: analysing one with error nodes in it would
   --  produce diagnostics about the recovery rather than about the program.
   --  Callers check Syntax.Has_Errors first, and this reports nothing at all
   --  for such a tree rather than guessing.
   --
   --  The tree is written to as well as read. A generic instantiation copies
   --  the generic's body so that the copy can be analysed with the formals
   --  bound -- conclusions are recorded per node, and two instantiations
   --  sharing nodes would overwrite each other's answers about every name in
   --  the generic. Nothing else here changes it.
   --
   --  @param Tree The parsed program; grown by an instantiation.
   --  @param Origin Where the source came from, for diagnostics.
   --  @param Into The conclusions, replaced.
   --  @param Report Where semantic diagnostics go.
   procedure Analyse
     (Tree   : in out Syntax.Tree;
      Origin : Adash.Source.Origin;
      Into   : out Analysis;
      Report : in out Adash.Diagnostics.List);

   --  Whether the program may be evaluated.
   --
   --  The one question every caller asks. False when anything was illegal, and
   --  also false when the tree was never analysed -- a caller that forgot to
   --  call Analyse must not get permission by default.
   --
   --  @param Item Analysis to inspect.
   --  @return True when evaluation may proceed.
   function Is_Legal (Item : Analysis) return Boolean;

   --  The type an expression has.
   --
   --  @param Item Analysis to inspect.
   --  @param Node The expression.
   --  @return Its type, or Type_None when it has none or could not be
   --          determined. The two are not distinguished on purpose: a caller
   --          that has to tell them apart is about to build the cascade this
   --          pass exists to avoid.
   function Type_Of
     (Item : Analysis;
      Node : Syntax.Node_Id) return Types.Type_Kind;

   --  The symbol a name denotes.
   --
   --  @param Item Analysis to inspect.
   --  @param Node The name.
   --  @return Its symbol, or Symbols.Nothing when the name did not resolve.
   function Symbol_Of
     (Item : Analysis;
      Node : Syntax.Node_Id) return Symbols.Symbol;

   --  The value of a static discrete choice.
   --
   --  Which forms are static is this pass's business, and the lowering has to
   --  agree with it exactly: a choice the analyser accepted and the emitter
   --  could not read would be an alternative that silently never runs. One
   --  implementation, asked twice.
   --
   --  @param Item Analysis to inspect.
   --  @param Tree The tree the node belongs to.
   --  @param Node The choice.
   --  @param Value Its value, as the position in its type, when this returns
   --         True.
   --  @return True when the choice is one this build can evaluate at analysis
   --          time.
   function Static_Choice
     (Item  : Analysis;
      Tree  : Syntax.Tree;
      Node  : Syntax.Node_Id;
      Value : out Long_Long_Integer) return Boolean;

   --  What a composite type is made of.
   --
   --  A record's components or an array's elements, by position. This lives
   --  here rather than inside Types because a type travels inside every symbol
   --  and every parameter profile, and those are copied constantly: a
   --  component list riding along would make every scope lookup carry the
   --  whole shape of every type in sight. The type carries an identity and a
   --  width; this is what the identity opens.
   --
   --  Both passes ask. The analyser asks what a component is called and what
   --  type it has; the lowering asks where it sits. Computing it twice from
   --  the tree would be two answers to one question.

   --  How many components a record has, or how many elements an array holds.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The composite type.
   --  @return Its part count; zero for anything that is not composite.
   function Part_Count
     (Item : Analysis; Of_Type : Types.Type_Kind) return Natural;

   --  What one part is called.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The composite type.
   --  @param Index Which part, from one.
   --  @return Its name; "" for an array, whose elements have positions rather
   --          than names.
   function Part_Name
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return String;

   --  What one part holds.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The composite type.
   --  @param Index Which part, from one.
   --  @return Its type.
   function Part_Type
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return Types.Type_Kind;

   --  Where one part sits, counted in slots from the start of the value.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The composite type.
   --  @param Index Which part, from one.
   --  @return Its offset.
   function Part_Offset
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return Natural;

   --  Which part a name denotes.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The record type.
   --  @param Name The name a program wrote, in any case.
   --  @return Its position, or zero when the type has no such component.
   function Part_At
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Name    : String) return Natural;

   --  The first index an array admits.
   --
   --  Ada lets an array begin anywhere; a script that indexes one has to be
   --  able to ask where.
   --
   --  @param Item Analysis to inspect.
   --  @param Of_Type The array type.
   --  @return Its first index.
   function First_Index
     (Item : Analysis; Of_Type : Types.Type_Kind) return Long_Long_Integer;

   --  The dotted name a chain of selections spells, or "" when it is not one.
   --
   --  `Server.Put` is one name with a dot in it, and what owns the entry is
   --  what stands before the last dot. The lowering asks, because that is
   --  where a rendezvous has to find the task.
   --
   --  @param Tree The parsed program.
   --  @param Node The name or selection.
   --  @return Its dotted spelling, or "".
   function Dotted_Name
     (Tree : Syntax.Tree; Node : Syntax.Node_Id) return String;

   --  Where each of a subprogram's parameters gets its value in one call.
   --
   --  A call may write its arguments in order, or name them, or leave out the
   --  ones with defaults -- so position in the call is not position in the
   --  profile, and every pass that walks a call needs the same answer about
   --  which is which. Computed rather than recorded: it depends only on the
   --  call and the callee, both of which the lowering already has, and a
   --  second copy kept beside the tree would be a second thing to keep true.
   type Argument_Map is
     array (1 .. Symbols.Max_Parameters) of Syntax.Node_Id;

   --  What became of matching a call to a profile.
   type Match_Outcome is
     (
      --  Every parameter has a value.
      Matched,

      --  A name the subprogram has not got.
      Unknown_Name,

      --  One parameter given twice, positionally and then by name or twice by
      --  name.
      Given_Twice,

      --  An argument without a name after one with a name. Ada's rule, and it
      --  exists because otherwise the position of the plain one would depend
      --  on the names around it.
      Out_Of_Order,

      --  A parameter with no value and no default.
      Not_Given,

      --  More arguments than parameters.
      Too_Many);

   --  Match a call's arguments to its callee's parameters.
   --
   --  @param Tree The parsed program.
   --  @param Arguments The call's argument sequence.
   --  @param Callee What it resolved to.
   --  @param Into Where each parameter's value comes from; No_Node for one
   --         left to its default.
   --  @param Where The argument the complaint is about, when there is one.
   --  @param Which Which parameter it is about, from one; zero when the
   --         complaint is not about a particular one.
   --  @return What became of it.
   function Match_Arguments
     (Tree      : Syntax.Tree;
      Arguments : Syntax.Node_Id;
      Callee    : Symbols.Symbol;
      Into      : out Argument_Map;
      Where     : out Syntax.Node_Id;
      Which     : out Natural) return Match_Outcome;

   --  The copy of a generic's body one instantiation is made of.
   --
   --  @param Item Analysis to inspect.
   --  @param Node The instantiation.
   --  @return The subprogram the instantiation declared, or No_Node.
   function Expansion_Of
     (Item : Analysis; Node : Syntax.Node_Id) return Syntax.Node_Id;

   --  What the program said about its queues and about its tasks ending.
   --
   --  Both are run-time questions, for the reason Max_Tasks is: what a program
   --  queues, and when a task runs out, are not things a reader can count. So
   --  this pass reads what was asked for and the machine keeps the count.
   --
   --  @param Item Analysis to inspect.
   --  @param Most How many callers at one entry, when it said.
   --  @return True when the program bounded them.
   function Queue_Bound (Item : Analysis; Most : out Natural) return Boolean;

   --  @param Item Analysis to inspect.
   --  @return True when the program said its tasks do not run out.
   function Forbids_Termination (Item : Analysis) return Boolean;

   --  How many tasks the program allowed itself at once, and whether it said.
   --
   --  Ada's `pragma Restrictions (Max_Tasks => N)`, which is checked while the
   --  program runs: what a loop starts is not something a reader can count. So
   --  this pass reads the number and the machine keeps the count.
   --
   --  @param Item Analysis to inspect.
   --  @param Most How many, when it said.
   --  @return True when the program bounded itself.
   function Task_Bound (Item : Analysis; Most : out Natural) return Boolean;

   --  How many slots the thing an attribute asked about takes.
   --
   --  Worked out here because this is where the answer lives: a protected
   --  object's size is what its body declares, and only this pass has been
   --  through the body. The lowering pushes the number rather than deriving it
   --  a second way.
   --
   --  @param Item Analysis to inspect.
   --  @param Node The attribute.
   --  @return How many slots, or zero when the node asked nothing.
   function Slots_Asked_About
     (Item : Analysis; Node : Syntax.Node_Id) return Natural;

   --  How many nodes carry a conclusion.
   --
   --  For a test that wants to know analysis actually walked the tree rather
   --  than returning early.
   --
   --  @param Item Analysis to inspect.
   --  @return The count.
   function Annotated_Count (Item : Analysis) return Natural;

private

   --  One component of a record, or the single element description of an
   --  array. Offset is in slots from the start of the value.
   type Part is record
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Of_Type : Types.Type_Kind;
      Offset  : Natural := 0;
   end record;

   package Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Part);

   --  What one declared composite type is made of.
   type Structure is record
      Id    : Natural := 0;
      Parts : Part_Vectors.Vector;

      --  For an array: where its index range begins. Zero for a record, which
      --  has names rather than positions.
      First : Long_Long_Integer := 0;
   end record;

   package Structure_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Structure);

   type Annotation is record
      Resolved_Type : Types.Type_Kind := Types.Type_None;
      Resolved      : Symbols.Symbol;
      Visited       : Boolean := False;
   end record;

   package Annotation_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Annotation);

   --  Which instantiation made which copy.
   type Expansion is record
      At_Node : Syntax.Node_Id := Syntax.No_Node;
      Made    : Syntax.Node_Id := Syntax.No_Node;
   end record;

   package Expansion_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Expansion);

   --  What one attribute that asked how much room something takes was told.
   type Measured is record
      At_Node : Syntax.Node_Id := Syntax.No_Node;
      Slots   : Natural := 0;
   end record;

   package Measure_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Measured);

   type Analysis is tagged limited record
      --  One entry per node, indexed as the tree indexes them. Sized to the
      --  tree at the start of Analyse rather than grown, so an annotation
      --  never moves and a caller holding a Node_Id keeps getting the same
      --  answer.
      Notes    : Annotation_Vectors.Vector;

      --  What each declared composite type is made of, keyed by the type's
      --  identity. Kept here rather than in the type because a type is copied
      --  on every scope lookup and this is not.
      Shapes   : Structure_Vectors.Vector;

      --  What each instantiation copied out of its generic. The lowering asks,
      --  because the copy is where the code it has to emit lives.
      Made     : Expansion_Vectors.Vector;

      --  What each attribute asking about size was told.
      Sizes    : Measure_Vectors.Vector;

      --  How many tasks at once the program allowed itself, how many callers
      --  at one entry, and whether its tasks may run out.
      Task_Limit  : Natural := 0;
      Bounded     : Boolean := False;
      Queue_Limit : Natural := 0;
      Queue_Given : Boolean := False;
      Endless     : Boolean := False;

      Legal    : Boolean := False;
      Analysed : Boolean := False;
   end record;

end Adash.Language.Semantics;

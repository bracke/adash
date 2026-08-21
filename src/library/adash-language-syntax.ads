private with Ada.Containers.Vectors;

with Ada.Strings.Unbounded;

with Adash.Source;

--  The shape of a program, as a tree.
--
--  Nodes are identified by index into an arena the tree owns, not by pointer.
--  That is the decision everything else here follows from, and it buys four
--  things at once:
--
--  Semantic analysis annotates without mutating. A `Node_Id` is a stable key,
--  so a resolved type or a resolved symbol lives in a side table the semantic
--  pass owns and the tree never learns about. A tree with an annotation field
--  is one that every later pass is tempted to write into, and then no reader
--  can tell which pass a value came from.
--
--  Traversal is deterministic and cheap. Children are a contiguous slice, so
--  walking a node's children is a loop over integers rather than a chase
--  through the heap, and two walks of one tree visit the same nodes in the same
--  order — which is what a formatter and a conformance case both need.
--
--  There is no aliasing and no ownership question. A `Node_Id` cannot dangle,
--  cannot be freed twice, and cannot be confused with a node from another tree
--  in any way that is not immediately visible.
--
--  And a tree is a value with a lifetime, not a graph of allocations. Dropping
--  the tree drops everything in it.
--
--  Every node carries its extent, so a diagnostic can point at a construct
--  rather than describe it, and a formatter can put text back where it found
--  it. Extents are byte spans into the buffer the tree was parsed from; the
--  tree does not hold the buffer, because a diagnostic outlives it.
--
--  Nothing here is serialized. A syntax tree is derived from source and is
--  cheaper to rebuild than to load, and a persisted tree is a second thing that
--  can disagree with the file it came from.
package Adash.Language.Syntax is

   --  What a node is.
   type Node_Kind is
     (
      --  Nothing. The result of asking for a child that is not there.
      Node_None,

      ------------------------------------------------------------------
      --  Expressions
      ------------------------------------------------------------------

      Node_Integer_Literal,
      Node_Real_Literal,
      Node_Character_Literal,
      Node_String_Literal,

      --  A name: an identifier standing for something. Resolution is the
      --  semantic pass's work; the parser only records that a name was written.
      Node_Name,

      --  An expression in parentheses. Kept rather than folded away, because a
      --  formatter has to reproduce it and because Ada's rule against mixing
      --  `and` with `or` is stated in terms of them.
      Node_Parenthesized,

      --  One operand; see Operation.
      Node_Unary_Operation,

      --  Two operands; see Operation.
      Node_Binary_Operation,

      --  Name (arguments). Whether this denotes a function or an array is a
      --  semantic question — Ada spells both the same way, and a parser that
      --  guessed would be doing name resolution.
      Node_Call,

      --  Name'Attribute.
      Node_Attribute,

      --  `(if A then B else C)`. Three children: the condition, the value
      --  when it holds, and the value when it does not.
      --
      --  Ada's if expression, and written with its parentheses: what tells a
      --  value from a statement here is where it stands, and `(` is where a
      --  value stands. An `elsif` is a nested if expression, as an `elsif` in
      --  a statement is a nested if -- so every later pass has one shape.
      Node_If_Expression,

      --  `(case X is when 1 => A, when others => B)`. Two children: what is
      --  examined, and the sequence of alternatives -- each a
      --  Node_Case_Alternative whose second child is one expression rather
      --  than a sequence of statements.
      --
      --  The choices are the statement's own: every value covered once, the
      --  bounds known before the program runs, `others` last. What differs is
      --  only what an alternative *is*.
      Node_Case_Expression,

      --  `Small'(Red)`. Two children: the type mark and the expression.
      --
      --  Ada writes it to say which of several readings is meant. This
      --  language resolves from the expected type and from the other operand,
      --  so a program rarely needs it -- but a reader who writes what Ada
      --  writes should not be told it is a syntax error, and where the two
      --  places do not settle an interpretation this is what settles it.
      Node_Qualified,

      ------------------------------------------------------------------
      --  Statements
      ------------------------------------------------------------------

      Node_Assignment,          --  target := value;
      Node_Procedure_Call,      --  a call as a statement
      Node_If,                  --  condition, then-part, else-part

      --  case Expression is <alternatives> end case;
      --
      --  Two children: what is being examined, and the sequence of
      --  alternatives. An alternative is a node of its own rather than a pair
      --  of sibling lists, because its choices and its statements belong
      --  together -- a walker that had to pair them by index could pair them
      --  wrongly and nothing would say so.
      Node_Case,

      --  when <choices> => <statements>
      --
      --  Two children, both sequences: the choices, and the statements.
      Node_Case_Alternative,

      --  Low .. High. Two children.
      --
      --  Written in two places and the same thing in both: a case choice
      --  covering a span of values, and a slice of a String. A second node
      --  kind for the second use would be two names for one shape.
      Node_Range,

      --  `others`, as a choice. A node rather than a name spelled "others",
      --  because it is not a name and nothing should have to compare text to
      --  find that out.
      Node_Others,
      --  `V in L .. H`, and `V not in L .. H`. Three children -- the value and
      --  the two bounds -- because that is what it is; the operator says which
      --  way round the answer goes.
      --
      --  Two children is the other form Ada writes, `V in Small`: the value
      --  and a type mark, whose bounds are the type's own. Which was written
      --  is a question about what the name denotes, so the parser records the
      --  shape and semantics decides -- the division a `for` loop over a named
      --  type makes, for the same reason.
      Node_Membership,

      Node_While_Loop,
      Node_For_Loop,

      --  `for I in reverse L .. H loop`. A kind of its own rather than a flag
      --  on the one above, because this tree carries children and nothing
      --  else: a direction stored as a fifth child, or as text, would be a
      --  field pretending to be a node. The four children are the same four,
      --  and everything but the counting is shared.
      Node_For_Reverse_Loop,
      Node_Loop,                --  a bare loop
      Node_Exit,
      Node_Return,
      Node_Null_Statement,
      --  declare <declarations> begin <statements> [exception <handlers>] end;
      --
      --  Three children, all sequences: what it declares, what it does, and
      --  what it does about what went wrong. One child holding the first two
      --  would lose the boundary the language draws at `begin`, and a reader
      --  of the tree would have to work out where it was by looking at kinds.
      Node_Block,

      --  when Constraint_Error | Storage_Error => <statements>
      --
      --  Two children, both sequences: the exceptions it answers for, and what
      --  it does about them. `others` appears among the first as Node_Others,
      --  which is the same node a case choice uses -- it means the same thing
      --  in both places.
      Node_Handler,

      ------------------------------------------------------------------
      --  Declarations
      ------------------------------------------------------------------

      --  `name : [constant] type [(actuals)] [:= value];`. Four children: the
      --  name, the type mark, the initial value, and what the object gives its
      --  type -- which today is what a task is elaborated with. The last two
      --  are absent when nothing was written.
      Node_Object_Declaration,

      --  procedure P (A : Integer) is <declarations> begin <statements> end P;
      --  function  F (A : Integer) return Integer is ... begin ... end F;
      --
      --  Five children in fixed positions: the name, the parameter list, the
      --  result type, the declarative part, and the statements. Fixed rather
      --  than counted, because which child holds the body must not depend on
      --  whether the subprogram happened to take parameters or return
      --  anything. The result type is No_Node for a procedure, and that
      --  absence is what tells the two apart -- a procedure is not a function
      --  returning nothing, and nothing downstream should have to ask twice.
      Node_Subprogram_Declaration,

      --  One formal parameter: name and type, in that order.
      --
      --  `A, B : Integer` becomes two of these. A parameter list is positional
      --  by nature, so one node per position means the position is the index
      --  rather than something a reader has to count out of a shared node.
      --  Two children, or three when a default was written: name, type, and
      --  the literal it defaults to.
      --  `type Colour is (Red, Green, Blue);`. Two children: the name, and the
      --  sequence of literal names in the order they were written -- which is
      --  the order that orders the type.
      Node_Type_Declaration,

      --  `type Line is record Number : Integer; Text : String; end record;`.
      --  Two children: the name, and the sequence of components, each of which
      --  is a Node_Parameter -- a name and a type, which is the same shape a
      --  formal parameter has and means the same thing.
      Node_Record_Declaration,

      --  `type Counts is array (1 .. 10) of Integer;`. Three children: the
      --  name, the index range, and the element type.
      Node_Array_Declaration,

      --  `R.Field`. Two children: what is being reached into, and the name of
      --  the component. A kind of its own rather than a binary operation,
      --  because the right side is not an expression -- it is a name that
      --  means nothing outside the type on the left.
      Node_Selected,

      --  `(1, 2, 3)` and `(Number => 1, Text => "x")`. One child: the sequence
      --  of values, each either an expression or a Node_Named_Argument.
      --
      --  Not a literal. What it holds is expressions, and two aggregates with
      --  the same text can mean different values at different points of a
      --  program -- which is why one cannot be a parameter's default.
      Node_Aggregate,

      --  `package P is <declarations> end P;`. Two children: the name and the
      --  sequence of declarations.
      --
      --  What it declares is declared beside it under a dotted name, so a
      --  package member is an ordinary symbol and `P.X` is a way of spelling
      --  one. Nothing below the analyser has to know a package exists.
      Node_Package_Declaration,

      --  `package body P is <declarations> end P;`. The same two children.
      --  Ada puts the bodies of what the specification promised here, and so
      --  does this: a subset that let a body stand in the specification would
      --  accept what Ada rejects.
      Node_Package_Body,

      --  `task T is <entries> end T;` and `task body T is ... end T;`.
      --  Four children: the name, the sequence -- of entry declarations for
      --  the first, of declarations and statements for the second -- what it
      --  does about what went wrong, and its discriminant part.
      --
      --  `type` as the node's text makes it a task *type*, whose objects are
      --  each a task of their own. Discriminants are written on the
      --  declaration only, as Ada writes them: they are what a task takes at
      --  elaboration where a subprogram takes parameters at a call, and the
      --  body has them in scope without repeating them.
      --
      --  A task starts when its body is elaborated and runs interleaved with
      --  what declared it, which does not finish until the task has. That is
      --  Ada's rule about masters and dependents, and it is what makes a task
      --  worth having in a shell script: the script waits.
      Node_Task_Declaration,
      Node_Task_Body,

      --  `protected P is <operations> private <data> end P;` and
      --  `protected body P is ... end P;`. Two children: the name and the
      --  sequence.
      Node_Protected_Declaration,
      Node_Protected_Body,

      --  `entry Wait when Ready is ... end Wait;` in a protected object, and
      --  `entry Put (Item : Integer);` in a task. Four children: the name, the
      --  barrier, the statements, and the formals.
      --
      --  The barrier is what an entry has and a procedure does not: a
      --  condition the caller waits on rather than a value it passes.
      --
      --  A *protected* entry has no parameters: it is a barrier and a body,
      --  which is the part a script wants from one. A *task* entry has them,
      --  because a rendezvous is how a task is given something and how it
      --  hands something back.
      --
      --  A fifth child, when it is present, is the index type of an entry
      --  *family*: `entry Request (Priority);` declares one entry per value of
      --  Priority, and a caller says which by writing `Request (High)`. A
      --  family is a run of entries rather than one, which is what makes it
      --  worth having -- an acceptor can serve one member and leave the rest
      --  queued.
      Node_Entry,

      --  `accept Put (Item : Integer) do ... end Put;`. Four children: the
      --  name, the formals, the statements -- absent for `accept Put;`, which
      --  meets the caller and lets it go again -- and which member of a family
      --  it serves, absent when the entry is not one.
      Node_Accept,

      --  A selective accept: `select accept A; ... or accept B; ... end
      --  select;`. Two children: the sequence of alternatives, and what to do
      --  when none of them can be taken -- absent when the select waits.
      --
      --  A task's way of saying "whichever of these happens first". Its
      --  alternatives are accepts, where the other `select` has an entry call:
      --  one is a task deciding what to serve and the other is a caller
      --  deciding how long to wait, and telling them apart is what the first
      --  word after `select` is for.
      Node_Selective_Accept,

      --  `select <trigger> <statements> then abort <part> end select;`. Three
      --  children: the trigger, which is an entry call or a delay, the
      --  statements that follow it when it fires, and the abortable part.
      --
      --  Ada's asynchronous transfer of control. The abortable part runs as a
      --  strand of its own and the trigger waits in the one that wrote the
      --  select: that is what the machine already has, and it is what makes
      --  "abandon this if that happens first" expressible at all on a machine
      --  that changes strand at defined points rather than pre-empting.
      Node_Then_Abort,

      --  One alternative of a selective accept. Three children: its guard --
      --  absent when it has none -- what it does when taken, which is an
      --  accept or a delay, and the statements that follow.
      --
      --  A guard is asked once, when the select is reached, which is Ada's
      --  rule: an alternative whose guard was closed then is closed for this
      --  execution of the select however the world changes while it waits.
      Node_Select_Alternative,

      --  `delay 0.5;` and `delay until 12.5;`. One child: how long, in
      --  seconds, or when, on the clock. `until` as the node's text tells the
      --  two apart, the way a parameter's node records its mode.
      --
      --  Ada has both because a loop that delays *for* a tenth of a second
      --  drifts by however long its own body takes, and one that delays
      --  *until* the next tenth does not.
      Node_Delay,

      --  `Wrong_Kind : exception;`. One child: the name. What it declares is
      --  a name a raise and a handler can agree on, and nothing else -- an
      --  exception has no type, no value and no storage.
      Node_Exception_Declaration,

      --  `raise Wrong_Kind;` and `raise;`. One child, or none: what to raise,
      --  where a bare one raises again what the handler it stands in caught.
      Node_Raise,

      --  `terminate;` as an alternative of a selective accept. No children:
      --  what it says is that this task has nothing more to do if nobody will
      --  ever call it again, and everything that decides whether that is so
      --  is outside the statement.
      Node_Terminate,

      --  `pragma Priority (5);`. Two children: the pragma's name and its
      --  arguments.
      --
      --  The one pragma this language has, and the node is shaped for one
      --  rather than for pragmas in general: a mechanism that took any name
      --  would be a second place to configure things, and what a program can
      --  say about itself belongs in the language rather than beside it.
      Node_Pragma,

      --  `requeue E;` and `requeue E with abort;`. Two children: the entry the
      --  caller is moved to, and which member of it when that entry is a
      --  family. The node's text is `abort` when `with abort` was written, the
      --  way a parameter's node records its mode.
      --
      --  Ada's way of saying "not this one, that one": the caller being served
      --  is put on another entry's queue and the body it was being served by
      --  is left. The caller does not resume and is not told -- from its own
      --  point of view it is still waiting for the call it made.
      Node_Requeue,

      --  `abort T;` and `abort T, U;`. One child per task named.
      --
      --  Ada aborts every task a statement names as one action, so the names
      --  travel together rather than as several statements: what one abort
      --  does to a caller must not happen between two of them.
      Node_Abort,

      --  A conditional or timed entry call:
      --
      --     select P.E; <taken> else <otherwise> end select;
      --     select P.E; <taken> or delay 0.5; <otherwise> end select;
      --
      --  Four children: the entry call, what follows it when it is taken, how
      --  long to wait -- absent for the `else` form -- and what to do when it
      --  is not.
      --
      --  Only an entry call, and only on a protected object. Ada's other
      --  `select` forms choose between task entries, which this language does
      --  not have, or transfer control asynchronously, which needs a task to
      --  abort in the middle of.
      Node_Select,

      --  `use P;`. One child: the package name. Makes what the package holds
      --  visible without its prefix, for as long as the enclosing region does.
      Node_Use,

      --  `generic <formals> procedure P (...) is ... end P;`. Two children:
      --  the sequence of formals, and the subprogram itself.
      Node_Generic_Declaration,

      --  One generic formal: `type T is private;`. One child, the name.
      Node_Generic_Formal,

      --  `procedure Q is new P (Integer);`. Four children: the new name, the
      --  generic's name, the sequence of actuals, and -- filled in by the
      --  analyser -- a copy of the generic's body to analyse with the formals
      --  bound.
      --
      --  A copy rather than a second reading of the same nodes: conclusions
      --  are recorded per node, and two instantiations of one generic would
      --  otherwise overwrite each other's answers about what every name in it
      --  means.
      Node_Instantiation,

      --  `subtype Percent is Integer range 0 .. 100;`. Three children: the
      --  name, the type it names, and the range -- or two when no range was
      --  written, which is a second name for the same set of values.
      Node_Subtype_Declaration,

      Node_Parameter,

      --  `Name => Expression`, one argument of a call. Two children: the name
      --  as written, and what it is given.
      --
      --  A node of its own rather than a flag, because a named argument is not
      --  in the position it appears in -- it is in the position its name
      --  denotes -- and anything walking an argument list has to see that.
      Node_Named_Argument,

      ------------------------------------------------------------------
      --  Structure
      ------------------------------------------------------------------

      --  An ordered list: statements in a body, arguments in a call, the
      --  alternatives of an if. Uniform, so a walker does not need a rule per
      --  parent about where its list lives.
      Node_Sequence,

      --  Something that did not parse. Carries the extent it covers, so the
      --  tree remains walkable and a highlighter can still colour around it.
      --  A tree containing one of these is not evaluated.
      Node_Error);

   --  Every operator the language has.
   type Operation is
     (Op_None,

      --  Unary.
      Op_Plus, Op_Minus, Op_Not, Op_Abs,

      --  Multiplying.
      Op_Multiply, Op_Divide, Op_Mod, Op_Rem,

      --  Adding and concatenation.
      Op_Add, Op_Subtract, Op_Concat,

      --  Exponentiation.
      Op_Power,

      --  Relational.
      Op_Equal, Op_Not_Equal, Op_Less, Op_Less_Equal, Op_Greater, Op_Greater_Equal,

      --  Membership. Relational in Ada`s grammar and written like an operator,
      --  so it lives here rather than as a kind of its own -- but it takes
      --  three operands, which is why the node that carries it has three
      --  children.
      Op_In, Op_Not_In,

      --  Logical. `and then` and `or else` are distinct operators rather than a
      --  flag on `and` and `or`: they short-circuit, which is a difference in
      --  meaning and not in spelling.
      Op_And, Op_Or, Op_Xor, Op_And_Then, Op_Or_Else);

   --  The operator's spelling, as the language writes it.
   --
   --  A language identifier, not text for a user.
   --
   --  @param Item Operation to spell.
   --  @return Its spelling, or "" for Op_None.
   function Spelling (Item : Operation) return String;

   --  A node's identity within one tree.
   type Node_Id is private;

   --  The identity of no node.
   No_Node : constant Node_Id;

   --  @param Item Node to test.
   --  @return True when Item denotes a node.
   function Is_Present (Item : Node_Id) return Boolean;

   --  A node's position in its tree, from one; zero for No_Node.
   --
   --  This is what makes a side table possible, and a side table is the whole
   --  reason nodes live in an arena: a later pass keys its conclusions by this
   --  and the tree never learns they exist. Positions are dense and stable --
   --  nodes are never removed — so a table sized to Node_Count has exactly one
   --  slot per node and an entry never moves.
   --
   --  It is not an invitation to invent a Node_Id. There is no conversion back,
   --  because a number that came from somewhere other than a tree would index
   --  one anyway and answer confidently about the wrong node.
   --
   --  @param Item Node to locate.
   --  @return Its position, or zero.
   function Index (Item : Node_Id) return Natural;

   --  A parsed program.
   type Tree is tagged limited private;

   --  The node the whole tree hangs from.
   --
   --  @param Item Tree to inspect.
   --  @return Its root, or No_Node when nothing was parsed.
   function Root (Item : Tree) return Node_Id;

   --  @param Item Tree to inspect.
   --  @return How many nodes it holds.
   function Node_Count (Item : Tree) return Natural;

   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return What it is, or Node_None for No_Node.
   function Kind (Item : Tree; Node : Node_Id) return Node_Kind;

   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Where it is in the source it was parsed from.
   function Extent (Item : Tree; Node : Node_Id) return Adash.Source.Span;

   --  The operator of a unary or binary operation.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Its operator, or Op_None when it has none.
   function Operator (Item : Tree; Node : Node_Id) return Operation;

   --  The text a leaf node carries: a name's spelling, a literal's value.
   --
   --  For a string literal this is the undoubled value rather than the source
   --  form; the source form is recoverable from the extent, and what a
   --  consumer of the tree wants is the meaning.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Its text, or "" when it carries none.
   function Text (Item : Tree; Node : Node_Id) return String;

   --  Settle a name on one spelling.
   --
   --  Ada compares names without regard to case, and a name reached through a
   --  `use` is the same name as the one written with its package's prefix. The
   --  analyser is the only phase that can tell which declaration a written
   --  name means, so it is the phase that writes the declared spelling back --
   --  and what runs afterwards compares text and gets the right answer.
   --
   --  Nothing else may rewrite a tree: a node's extent still points at what
   --  the user typed, so a diagnostic quoting the source stays truthful.
   --
   --  @param Item Tree to change.
   --  @param Node The node.
   --  @param Text What it should now say.
   procedure Set_Text (Item : in out Tree; Node : Node_Id; Text : String);

   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return How many children it has.
   function Child_Count (Item : Tree; Node : Node_Id) return Natural;

   --  A node's child.
   --
   --  Children are positional and their meaning depends on the parent's kind:
   --  a binary operation has left then right, an assignment has target then
   --  value, an if has condition, then-part and optionally else-part. The
   --  named accessors below say which is which, and exist so that a walker
   --  reads as the grammar rather than as indices.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @param Index Which child, from one.
   --  @return That child, or No_Node when Index is out of range.
   function Child (Item : Tree; Node : Node_Id; Index : Positive) return Node_Id;

   --  The left operand of a binary operation, the only operand of a unary one,
   --  the target of an assignment, the condition of an if or while, the prefix
   --  of a call or attribute.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Its first child.
   function First (Item : Tree; Node : Node_Id) return Node_Id;

   --  The right operand, the assigned value, the then-part.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Its second child.
   function Second (Item : Tree; Node : Node_Id) return Node_Id;

   --  The else-part of an if, the body of a for loop.
   --
   --  @param Item Tree to inspect.
   --  @param Node The node.
   --  @return Its third child.
   function Third (Item : Tree; Node : Node_Id) return Node_Id;

   --  Whether a tree contains anything that did not parse.
   --
   --  The one question every consumer of a tree asks before using it. A tree
   --  with an error node in it is walkable — a highlighter still wants it — but
   --  must not be evaluated.
   --
   --  @param Item Tree to inspect.
   --  @return True when any node is Node_Error.
   function Has_Errors (Item : Tree) return Boolean;

   ---------------------------------------------------------------------------
   --  Construction. Used by the parser; a tree is read-only to everyone else.
   ---------------------------------------------------------------------------

   --  Add a node with no children.
   --
   --  @param Item Tree to extend.
   --  @param Kind What the node is.
   --  @param Extent Where it is.
   --  @param Text Its text, for a leaf that carries one.
   --  @param Operator Its operator, for an operation.
   --  @return The new node.
   function Add_Leaf
     (Item     : in out Tree;
      Kind     : Node_Kind;
      Extent   : Adash.Source.Span;
      Text     : String := "";
      Operator : Operation := Op_None) return Node_Id;

   --  A list of children, for building a node.
   type Node_List is array (Positive range <>) of Node_Id;

   --  An empty child list.
   No_Children : constant Node_List;

   --  Add a node with children.
   --
   --  @param Item Tree to extend.
   --  @param Kind What the node is.
   --  @param Extent Where it is.
   --  @param Children Its children, in order.
   --  @param Text Its text, for a node that carries one.
   --  @param Operator Its operator, for an operation.
   --  @return The new node.
   function Add_Node
     (Item     : in out Tree;
      Kind     : Node_Kind;
      Extent   : Adash.Source.Span;
      Children : Node_List;
      Text     : String := "";
      Operator : Operation := Op_None) return Node_Id;

   --  One name to put in place of another while copying.
   type Renaming is record
      From : Ada.Strings.Unbounded.Unbounded_String;
      To   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Renamings is array (Positive range <>) of Renaming;

   --  No substitution at all.
   No_Renamings : constant Renamings;

   --  Copy a subtree, and say where the copy is.
   --
   --  What a generic instantiation is made of. A generic's body is analysed
   --  once per instantiation, with the formal types bound to different
   --  actuals -- and conclusions are recorded per node, so analysing the same
   --  nodes twice would have the second instantiation overwrite what the first
   --  concluded about every name in it.
   --
   --  A copy is the cheapest honest answer: fresh nodes, fresh conclusions,
   --  and the same spans -- so a diagnostic about an instantiation points at
   --  the generic's own source, which is where the reader has to look.
   --
   --  @param Item Tree to copy within.
   --  @param Node The subtree to copy.
   --  @return The copy's root, or No_Node when Node is not present.
   --  @param Bindings Names to replace as the copy is made. What binds a
   --         generic's formal type to an instantiation's actual, and the
   --         generic's own name to the instance's -- so a recursive call
   --         inside the generic calls the instance, which is what Ada means
   --         by it.
   --
   --         A substitution on *names in the tree*, not on source text. The
   --         difference is the whole of why this is not the textual expansion
   --         this project refuses elsewhere: what is replaced is what the
   --         parser already decided is a name, and nothing is re-lexed or
   --         re-parsed.
   function Graft
     (Item    : in out Tree;
      Node    : Node_Id;
      Bindings : Renamings := No_Renamings) return Node_Id;

   --  Name the node the tree hangs from.
   --
   --  @param Item Tree to complete.
   --  @param Node The root.
   procedure Set_Root (Item : in out Tree; Node : Node_Id);

   --  Forget everything.
   --
   --  @param Item Tree to empty.
   procedure Clear (Item : in out Tree);

private

   type Node_Id is new Natural;

   No_Node : constant Node_Id := 0;

   No_Children : constant Node_List (1 .. 0) := [others => No_Node];

   No_Renamings : constant Renamings (1 .. 0) := [others => <>];

   type Node_Record is record
      Kind        : Node_Kind := Node_None;
      Extent      : Adash.Source.Span := Adash.Source.Nowhere;
      Operator    : Operation := Op_None;
      Text        : Ada.Strings.Unbounded.Unbounded_String;

      --  Children are a contiguous slice of the tree's child arena, so walking
      --  them is a loop over integers rather than a chase through the heap.
      First_Child : Natural := 0;
      Child_Count : Natural := 0;
   end record;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Node_Record);

   package Child_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Node_Id);

   type Tree is tagged limited record
      Nodes    : Node_Vectors.Vector;
      Children : Child_Vectors.Vector;
      Root     : Node_Id := No_Node;
   end record;

end Adash.Language.Syntax;

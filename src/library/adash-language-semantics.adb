with Ada.Strings.Fixed;

with Adash.Errors;
with Adash.Language.Scopes;
with Adash.Predefined;
with Adash.Messages;

package body Adash.Language.Semantics is

   package D renames Adash.Diagnostics;
   package S renames Adash.Language.Syntax;

   use type S.Node_Kind;
   use type S.Operation;
   use type Types.Type_Kind;
   use type Types.Type_Shape;
   use type Symbols.Symbol_Kind;

   --  Whether a default is something this build can carry, and its spelling.
   --
   --  A literal, possibly with a sign in front of it, and `True` or `False`.
   --  Nothing else: an arbitrary expression would have to be evaluated at each
   --  call in the scope of the *declaration*, and a name resolved at the call
   --  site is exactly what cannot do that. Restricting it here means a default
   --  reaches the machine as the literal it is, by the same path a literal
   --  written at the call site takes.
   --
   --  The spelling is the node's own text, decoded, so the lowering emits it
   --  the way it emits any literal of that type -- not a second encoding to
   --  disagree with the first.
   --
   --  @param Tree The parsed program.
   --  @param Node The default expression.
   --  @param Of_Type What the parameter is declared as.
   --  @param Spelling The literal's text, when this returns True.
   --  @return True when the default can be carried.
   function Static_Default
     (Item     : Analysis;
      Tree     : S.Tree;
      Node     : S.Node_Id;
      Of_Type  : Types.Type_Kind;
      Spelling : out Ada.Strings.Unbounded.Unbounded_String) return Boolean;

   function Static_Default
     (Item     : Analysis;
      Tree     : S.Tree;
      Node     : S.Node_Id;
      Of_Type  : Types.Type_Kind;
      Spelling : out Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
      use Ada.Strings.Unbounded;
   begin
      Spelling := Null_Unbounded_String;

      if not S.Is_Present (Node) then
         return False;
      end if;

      case S.Kind (Tree, Node) is
         when S.Node_Parenthesized =>
            return Static_Default (Item, Tree, S.First (Tree, Node),
                                   Of_Type, Spelling);

         when S.Node_Unary_Operation =>
            --  A sign, and only on a number. `-1` is how half the useful
            --  defaults are written, and it is a unary operation rather than
            --  a literal in every Ada grammar including this one.
            if Of_Type not in Types.Type_Integer | Types.Type_Float then
               return False;
            end if;

            if S.Operator (Tree, Node) not in S.Op_Plus | S.Op_Minus then
               return False;
            end if;

            declare
               Inner : Unbounded_String;
            begin
               if not Static_Default
                        (Item, Tree, S.First (Tree, Node), Of_Type, Inner)
               then
                  return False;
               end if;

               Spelling :=
                 (if S.Operator (Tree, Node) = S.Op_Minus
                  then To_Unbounded_String ("-") & Inner else Inner);
               return True;
            end;

         when S.Node_Integer_Literal =>
            if Of_Type /= Types.Type_Integer then
               return False;
            end if;

            Spelling := To_Unbounded_String (S.Text (Tree, Node));
            return True;

         when S.Node_Real_Literal =>
            if Of_Type /= Types.Type_Float then
               return False;
            end if;

            Spelling := To_Unbounded_String (S.Text (Tree, Node));
            return True;

         when S.Node_Character_Literal =>
            if Of_Type /= Types.Type_Character then
               return False;
            end if;

            Spelling := To_Unbounded_String (S.Text (Tree, Node));
            return True;

         when S.Node_String_Literal =>
            if Of_Type /= Types.Type_String then
               return False;
            end if;

            Spelling := To_Unbounded_String (S.Text (Tree, Node));
            return True;

         when S.Node_Name =>
            --  An enumeration literal, carried as its position rather than as
            --  its name: the lowering pushes a position for one written at the
            --  call site too, so a default reaches the machine by exactly the
            --  same path.
            if Types.Shape (Of_Type) = Types.Shape_Enumeration then
               declare
                  Found : constant Symbols.Symbol := Symbol_Of (Item, Node);
               begin
                  if Symbols.Is_Nothing (Found)
                    or else Symbols.Kind (Found) /= Symbols.Symbol_Literal
                    or else not Types.Is_Acceptable
                                  (Symbols.Of_Type (Found), Of_Type)
                  then
                     return False;
                  end if;

                  Spelling := To_Unbounded_String
                    (Ada.Strings.Fixed.Trim
                       (Natural'Image (Symbols.Position (Found)),
                        Ada.Strings.Both));
                  return True;
               end;
            end if;

            --  True and False, which are how a Boolean default is written.
            --  Compared by folded text rather than by symbol because this runs
            --  while the profile is being built, before the body's own scope
            --  exists -- and a parameter shadowing `True` is not in scope in
            --  its own default anyway.
            if Of_Type /= Types.Type_Boolean then
               return False;
            end if;

            declare
               Folded : constant String :=
                 Symbols.Fold (S.Text (Tree, Node));
            begin
               if Folded not in "true" | "false" then
                  return False;
               end if;

               Spelling := To_Unbounded_String (Folded);
               return True;
            end;

         when others =>
            return False;
      end case;
   end Static_Default;

   --  The dotted name a chain of selections spells, or "" when it is not one.
   --
   --  `Config.Limit` is one name with a dot in it once a package has declared
   --  its members beside itself; `Outer.Inner.X` is the same idea twice. A
   --  chain over anything but names is a reach into a value and has no dotted
   --  spelling.
   function Dotted
     (Tree : S.Tree; Node : S.Node_Id) return String;

   function Dotted
     (Tree : S.Tree; Node : S.Node_Id) return String is
   begin
      case S.Kind (Tree, Node) is
         when S.Node_Name =>
            return S.Text (Tree, Node);

         when S.Node_Selected =>
            declare
               Left : constant String := Dotted (Tree, S.First (Tree, Node));
            begin
               if Left = "" then
                  return "";
               end if;

               return Left & "." & S.Text (Tree, S.Second (Tree, Node));
            end;

         when others =>
            return "";
      end case;
   end Dotted;

   function Dotted_Name
     (Tree : Syntax.Tree; Node : Syntax.Node_Id) return String
   is (Dotted (Tree, Node));

   --  What a package member is called, in full.
   --
   --  A package declares what it holds beside itself, under a dotted name --
   --  so `Config.Limit` is one symbol whose name has a dot in it, and every
   --  pass below the analyser sees an ordinary declaration. Nothing has to
   --  carry a scope, and nothing below here has to know a package exists.
   function Under (Prefix, Named : String) return String
   is (if Prefix = "" then Named else Prefix & "." & Named);

   --  How many members one entry family may have.
   --
   --  A family is a run of entries, and a run is counted: `entry E (Integer)`
   --  would ask for as many entries as an Integer has values. A bound rather
   --  than none, refused by name, which beats a machine that runs out of
   --  numbers to give them.
   Max_Family : constant := 256;

   --  How many elements one array may hold.
   --
   --  A bound rather than none, because an array is a run of slots in a frame
   --  and a frame is bounded: `array (1 .. 10_000_000)` would ask the machine
   --  for a frame it cannot make, and refusing by name beats a run that stops
   --  with no room left.
   Max_Elements : constant := 4_096;

   --  Whether a record being built already has a component of this name.
   function Part_At_Name (Built : Structure; Name : String) return Natural;

   function Part_At_Name (Built : Structure; Name : String) return Natural is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      for Index in 1 .. Natural (Built.Parts.Length) loop
         if Symbols.Fold
              (Ada.Strings.Unbounded.To_String
                 (Built.Parts.Element (Index).Name)) = Wanted
         then
            return Index;
         end if;
      end loop;

      return 0;
   end Part_At_Name;

   --  Which entry of the structure table describes this type, or zero.
   function Shape_Of
     (Item : Analysis; Of_Type : Types.Type_Kind) return Natural;

   function Shape_Of
     (Item : Analysis; Of_Type : Types.Type_Kind) return Natural
   is
      Wanted : constant Natural := Types.Identity (Of_Type);
   begin
      if not Types.Is_Composite (Of_Type) then
         return 0;
      end if;

      for Index in 1 .. Natural (Item.Shapes.Length) loop
         if Item.Shapes.Element (Index).Id = Wanted then
            return Index;
         end if;
      end loop;

      return 0;
   end Shape_Of;

   -------------------
   -- Part_Count --
   -------------------

   function Part_Count
     (Item : Analysis; Of_Type : Types.Type_Kind) return Natural
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0 then
         return 0;
      end if;

      --  An array's elements are counted from its width rather than listed.
      --  Several types share one declaration's parts -- the array itself, a
      --  slice of it, and a variable of an unconstrained type -- and what
      --  tells them apart is how wide they are, not what was written once.
      if Types.Shape (Of_Type) = Types.Shape_Array then
         if Types.Is_Open (Of_Type) then
            --  It has no length of its own; what a value of it holds travels
            --  with the value.
            return 0;
         end if;

         return Types.Width (Of_Type)
                / Types.Width
                    (Item.Shapes.Element (Where).Parts.Element (1).Of_Type);
      end if;

      return Natural (Item.Shapes.Element (Where).Parts.Length);
   end Part_Count;

   -----------------
   -- Part_Name --
   -----------------

   function Part_Name
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return String
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0
        or else Index > Natural (Item.Shapes.Element (Where).Parts.Length)
      then
         return "";
      end if;

      return Ada.Strings.Unbounded.To_String
        (Item.Shapes.Element (Where).Parts.Element (Index).Name);
   end Part_Name;

   -----------------
   -- Part_Type --
   -----------------

   function Part_Type
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return Types.Type_Kind
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0 then
         return Types.Type_None;
      end if;

      --  Every element of an array is the same type, so the one the
      --  declaration recorded answers for all of them however many there are.
      if Types.Shape (Of_Type) = Types.Shape_Array then
         return Item.Shapes.Element (Where).Parts.Element (1).Of_Type;
      end if;

      if Index > Natural (Item.Shapes.Element (Where).Parts.Length) then
         return Types.Type_None;
      end if;

      return Item.Shapes.Element (Where).Parts.Element (Index).Of_Type;
   end Part_Type;

   -------------------
   -- Part_Offset --
   -------------------

   function Part_Offset
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return Natural
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0 then
         return 0;
      end if;

      --  An element's offset is arithmetic, for the same reason its type is
      --  not looked up: the elements are alike and there may be any number.
      if Types.Shape (Of_Type) = Types.Shape_Array then
         return (Index - 1)
                * Types.Width
                    (Item.Shapes.Element (Where).Parts.Element (1).Of_Type);
      end if;

      if Index > Natural (Item.Shapes.Element (Where).Parts.Length) then
         return 0;
      end if;

      return Item.Shapes.Element (Where).Parts.Element (Index).Offset;
   end Part_Offset;

   ---------------
   -- Part_At --
   ---------------

   function Part_At
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Name    : String) return Natural
   is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      for Index in 1 .. Part_Count (Item, Of_Type) loop
         if Symbols.Fold (Part_Name (Item, Of_Type, Index)) = Wanted then
            return Index;
         end if;
      end loop;

      return 0;
   end Part_At;

   -------------------
   -- First_Index --
   -------------------

   function First_Index
     (Item : Analysis; Of_Type : Types.Type_Kind) return Long_Long_Integer
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0 then
         return 0;
      end if;

      return Item.Shapes.Element (Where).First;
   end First_Index;

   ----------------------
   -- Part_Has_Default --
   ----------------------

   function Part_Has_Default
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return Boolean
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0
        or else Index > Natural (Item.Shapes.Element (Where).Parts.Length)
      then
         return False;
      end if;

      return Item.Shapes.Element (Where).Parts.Element (Index).Has_Default;
   end Part_Has_Default;

   ------------------
   -- Part_Default --
   ------------------

   function Part_Default
     (Item    : Analysis;
      Of_Type : Types.Type_Kind;
      Index   : Positive) return String
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0
        or else Index > Natural (Item.Shapes.Element (Where).Parts.Length)
      then
         return "";
      end if;

      return Ada.Strings.Unbounded.To_String
               (Item.Shapes.Element (Where).Parts.Element (Index).Default);
   end Part_Default;

   ----------------
   -- As_Written --
   ----------------

   function As_Written
     (Item : Analysis; Of_Type : Types.Type_Kind) return String
   is
      Where : constant Natural := Shape_Of (Item, Of_Type);
   begin
      if Where = 0 then
         return "";
      end if;

      return Ada.Strings.Unbounded.To_String
               (Item.Shapes.Element (Where).Written);
   end As_Written;

   --------------------
   -- Expansion_Of --
   --------------------

   function Expansion_Of
     (Item : Analysis; Node : Syntax.Node_Id) return Syntax.Node_Id
   is
      use type Syntax.Node_Id;
   begin
      for Index in 1 .. Natural (Item.Made.Length) loop
         if Item.Made.Element (Index).At_Node = Node then
            return Item.Made.Element (Index).Made;
         end if;
      end loop;

      return Syntax.No_Node;
   end Expansion_Of;

   ----------------------
   -- Match_Arguments --
   ----------------------

   function Match_Arguments
     (Tree      : Syntax.Tree;
      Arguments : Syntax.Node_Id;
      Callee    : Symbols.Symbol;
      Into      : out Argument_Map;
      Where     : out Syntax.Node_Id;
      Which     : out Natural) return Match_Outcome
   is
      Wanted : constant Natural := Symbols.Parameter_Count (Callee);
      Given  : constant Natural := S.Child_Count (Tree, Arguments);
      Naming : Boolean := False;
   begin
      Into  := [others => S.No_Node];
      Where := S.No_Node;
      Which := 0;

      if Given > Wanted then
         Where := Arguments;
         return Too_Many;
      end if;

      for Index in 1 .. Given loop
         declare
            One : constant S.Node_Id := S.Child (Tree, Arguments, Index);
         begin
            if S.Kind (Tree, One) = S.Node_Named_Argument then
               Naming := True;

               declare
                  Position : constant Natural :=
                    Symbols.Parameter_At
                      (Callee, S.Text (Tree, S.First (Tree, One)));
               begin
                  if Position = 0 then
                     Where := One;
                     return Unknown_Name;
                  end if;

                  if S.Is_Present (Into (Position)) then
                     Where := One;
                     Which := Position;
                     return Given_Twice;
                  end if;

                  Into (Position) := S.Second (Tree, One);
               end;

            elsif Naming then
               --  Ada's rule. Without it the position of a plain argument
               --  would depend on the names written around it, which is a
               --  reading nobody could rely on.
               Where := One;
               return Out_Of_Order;

            else
               Into (Index) := One;
            end if;
         end;
      end loop;

      for Index in 1 .. Wanted loop
         if not S.Is_Present (Into (Index))
           and then not Symbols.Has_Default (Callee, Index)
         then
            Where := Arguments;
            Which := Index;
            return Not_Given;
         end if;
      end loop;

      return Matched;
   end Match_Arguments;

   -------------
   -- Analyse --
   -------------

   procedure Analyse
     (Tree   : in out Syntax.Tree;
      Origin : Adash.Source.Origin;
      Into   : out Analysis;
      Report : in out Adash.Diagnostics.List)
   is
      Chain : Adash.Language.Scopes.Chain;

      --  How many loops enclose the statement being analysed. An `exit` needs
      --  one; outside every loop it has nothing to leave, which is illegal Ada.
      Loop_Depth : Natural := 0;

      --  What the context wants of a case expression being analysed, and
      --  Type_None outside one.
      --
      --  A case expression's alternatives are the statement's, so they are
      --  analysed where the statement's are -- and what the context wants has
      --  to reach the arms, which are where the values stand. Saved and put
      --  back around each one, so a case expression inside an arm of another
      --  does not leave the outer one asking for the inner one's type.
      Wanted_Of_Case : Types.Type_Kind := Types.Type_None;

      --  What a declaration in the region being analysed is called, in full.
      --  Empty outside a package; `Config` inside one; `Outer.Inner` inside a
      --  package inside a package.
      Prefix : Ada.Strings.Unbounded.Unbounded_String;

      --  The packages a `use` has made visible without their prefix. A list
      --  rather than a second symbol per member, because declaring one would
      --  make a later declaration of the same name collide with something the
      --  user never wrote.
      package Name_Vectors is new Ada.Containers.Vectors
        (Index_Type   => Positive,
         Element_Type => Ada.Strings.Unbounded.Unbounded_String,
         "="          => Ada.Strings.Unbounded."=");

      In_Use : Name_Vectors.Vector;

      --  Whether what is being analysed stands in a package declaration.
      --
      --  What that changes is one thing: a subprogram specification there is
      --  completed in the package body, which is a submission of its own, so
      --  it must not be reported as a body that never arrived.
      In_Package_Spec : Boolean := False;

      --  Whether what is being analysed stands in a protected object rather
      --  than in a task. An entry means different things in the two: a task's
      --  is met at a rendezvous and may carry parameters, and a protected
      --  object's is a barrier with a body and has no second side to carry
      --  them to.
      In_Protected : Boolean := False;

      --  The generics in scope, and where each one's subprogram stands. A
      --  generic is a template rather than a declaration with a meaning of its
      --  own, so what a symbol table can hold about one is that it exists;
      --  this holds the tree an instantiation copies.
      type Template is record
         Key     : Ada.Strings.Unbounded.Unbounded_String;

         --  The `generic` declaration, which carries the formals, and the
         --  body that completes it -- which Ada writes separately, as a unit
         --  of its own, and which is therefore not analysed where it stands:
         --  what its names mean depends on what an instantiation binds.
         At_Node : S.Node_Id := S.No_Node;
         Made_Of : S.Node_Id := S.No_Node;
      end record;

      package Template_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Template);

      Templates : Template_Vectors.Vector;

      --  The protected types in scope, and where each one's declaration and
      --  body stand.
      --
      --  A protected type is a template in the same way a generic is: what an
      --  object of one has is state and a lock of its own, so each object is a
      --  copy of the declaration and the body with the type's name replaced by
      --  the object's. Everything below here then sees what it has always
      --  seen -- one protected object per declaration -- and the difference is
      --  a naming convention this pass keeps, which is exactly what a package
      --  is here too.
      Guarded_Types : Template_Vectors.Vector;

      --  What the program has forbidden itself.
      --
      --  Ada's `pragma Restrictions`, and the point of one is that a program
      --  says what it will not do so that a reader -- and this pass -- can
      --  rely on it. Each of these is a *statement* the program has given up,
      --  which is what makes them checkable where they are written rather than
      --  hoped for.
      type Restriction is
        (No_Abort_Statements,
         No_Delay,
         No_Select_Statements,
         No_Requeue_Statements,

         --  Every task depends directly on the outermost region: none is
         --  declared inside a subprogram, a task body, a block or an accept
         --  body. What it buys a reader is that the whole shape of a
         --  program's concurrency is written where the program begins.
         No_Task_Hierarchy,

         --  `delay D;` given up and `delay until` kept. Ravenscar's, and its
         --  reason is that a loop delaying *for* a length drifts by however
         --  long its own body takes.
         No_Relative_Delay,

         --  `X'Priority := N;` given up: what everything runs at is settled
         --  where it is declared, so a reader can see the whole of it.
         No_Dynamic_Priorities,

         --  Every protected object declared where the program begins, for the
         --  reason No_Task_Hierarchy has about tasks.
         No_Local_Protected_Objects,

         --  An entry barrier that is a name or a literal and nothing else.
         --  What it buys is that reading one is reading a variable, so what
         --  opens an entry can be seen rather than worked out.
         Simple_Barriers,

         --  An entry barrier that may be worked out, so long as working it
         --  out cannot do anything and cannot fail: no call, and no operation
         --  that raises. Jorvik's relaxation of Simple_Barriers, for programs
         --  whose barriers are honestly conditions -- and the reason the
         --  stricter one exists still holds for what is left out, since a
         --  barrier is asked at moments the program did not choose.
         Pure_Barriers,

         --  A task body that runs out. Ravenscar's tasks do not: a program
         --  whose concurrency is fixed when it starts has nothing to gain by
         --  a task ending, and something to lose in what it leaves behind.
         No_Task_Termination,

         --  How many tasks may run at once, how many entries a task or a
         --  protected object may have, and how many callers may be queued at
         --  one entry. The restrictions that carry a number.
         Max_Tasks,
         Max_Task_Entries,
         Max_Protected_Entries,
         Max_Entry_Queue_Length);

      Restricted : array (Restriction) of Boolean := [others => False];

      --  What a priority's dispatching policy was said to be, if anything.
      --
      --  Kept per priority rather than per program because Ada lets a program
      --  say it of a range, and kept at all so that two pragmas cannot give
      --  one priority two answers -- which would leave the reader to guess
      --  which of the two the machine took.
      type Dispatching is (Not_Said, Keeps_Its_Turn, Shares_It);
      Dispatch : array (0 .. 30) of Dispatching := [others => Not_Said];

      --  How callers are taken off an entry queue, if the program said.
      --  One answer for the whole program: Ada says a queuing policy of a
      --  partition, not of a priority or of an entry.
      type Queuing is (Nothing_Said, By_Arrival, By_Priority);
      Queued_As : Queuing := Nothing_Said;

      --  What each restriction that carries a number was given.
      Limits : array (Restriction) of Natural := [others => 0];

      --  How many handlers enclose what is being analysed.
      --
      --  A bare `raise` raises again what was caught, so it needs something to
      --  have been caught: outside a handler there is nothing, and Ada refuses
      --  it there for that reason rather than for a syntactic one.
      Handler_Depth : Natural := 0;

      --  How many regions that make a master enclose what is being analysed.
      --
      --  A task declared where this is not zero depends on something other
      --  than the outermost region, which is what No_Task_Hierarchy forbids.
      Master_Depth : Natural := 0;

      --  How a restriction is spelled, which is not how `'Image` spells it:
      --  what a diagnostic quotes back has to be what a program writes.
      function Spelling (Which : Restriction) return String
      is (case Which is
             when No_Abort_Statements        => "No_Abort_Statements",
             when No_Delay                   => "No_Delay",
             when No_Select_Statements       => "No_Select_Statements",
             when No_Requeue_Statements      => "No_Requeue_Statements",
             when No_Task_Hierarchy          => "No_Task_Hierarchy",
             when No_Relative_Delay          => "No_Relative_Delay",
             when No_Dynamic_Priorities      => "No_Dynamic_Priorities",
             when No_Local_Protected_Objects => "No_Local_Protected_Objects",
             when Simple_Barriers            => "Simple_Barriers",
             when Pure_Barriers              => "Pure_Barriers",
             when No_Task_Termination        => "No_Task_Termination",
             when Max_Tasks                  => "Max_Tasks",
             when Max_Task_Entries           => "Max_Task_Entries",
             when Max_Protected_Entries      => "Max_Protected_Entries",
             when Max_Entry_Queue_Length     => "Max_Entry_Queue_Length");

      --  Complain when a statement the program forbade itself is written.
      --
      --  @param Which What was forbidden.
      --  @param Node Where the statement is.
      procedure Refuse_If_Restricted
        (Which : Restriction; Node : Syntax.Node_Id);

      --  Read what the program forbids itself, before anything is analysed.
      --
      --  A configuration pragma says something about the whole program rather
      --  than about the point it stands at, so what it says has to be known
      --  before the first statement is looked at -- otherwise a program would
      --  be held to a restriction only from where it wrote it, which is not
      --  what one is.
      procedure Read_Restrictions;

      --  Which protected type each object was made from. An object is a copy
      --  of the type's body under the object's own name, and the copy is not
      --  under the root -- it was grafted onto the tree -- so a question about
      --  the object is answered by the type it came from.
      Guarded_Objects : Template_Vectors.Vector;

      --  Which protected type a name denotes, or zero.
      function Guarded_Template (Name : String) return Natural;

      --  What a name declared in the region being analysed is called in full.
      function Full_Name (Name : String) return String
      is (Under (Ada.Strings.Unbounded.To_String (Prefix), Name));

      --  The full name a written one resolves to, and what it denotes.
      --
      --  Three places to look, in Ada's order. A name inside a package means
      --  that package's member first -- a sibling is nearer than anything
      --  outside. Then the name as written, which is every declaration that is
      --  not in a package. Then the packages a `use` has opened, which is what
      --  a `use` is for.
      function Visible_Name (Name : String) return String;
      function Visible (Name : String) return Symbols.Symbol
      is (Chain.Lookup (Visible_Name (Name)));

      function Visible_Name (Name : String) return String is
         Whole : constant String :=
           Ada.Strings.Unbounded.To_String (Prefix);

         --  How much of the prefix is still being tried, as an index into it.
         Stop : Integer := Whole'Last;
      begin
         --  Outward through the enclosing prefixes, innermost first:
         --  `Ledger.Adding.Running`, then `Ledger.Running`, then `Running`. A
         --  name inside a body means that body's member before the enclosing
         --  one's, and what a body encloses it can see -- which is what a task
         --  or a package written inside another is for.
         --
         --  Trying only the innermost and the bare name left everything
         --  between them unreachable: a task declared inside a task body could
         --  not read that body's own variables, because they are declared
         --  under the outer body's name and it was looking under the inner
         --  one's.
         loop
            declare
               Tried : constant String :=
                 (if Stop < Whole'First then Name
                  else Whole (Whole'First .. Stop) & "." & Name);
            begin
               if not Symbols.Is_Nothing (Chain.Lookup (Tried)) then
                  return Tried;
               end if;
            end;

            exit when Stop < Whole'First;

            declare
               Cut : Integer := Whole'First - 1;
            begin
               for Position in reverse Whole'First .. Stop loop
                  if Whole (Position) = '.' then
                     Cut := Position - 1;
                     exit;
                  end if;
               end loop;

               Stop := Cut;
            end;
         end loop;

         for Opened of In_Use loop
            declare
               Tried : constant String :=
                 Ada.Strings.Unbounded.To_String (Opened) & "." & Name;
            begin
               if not Symbols.Is_Nothing (Chain.Lookup (Tried)) then
                  return Tried;
               end if;
            end;
         end loop;

         return Name;
      end Visible_Name;

      --  The discriminant part a task of this name was declared with.
      --
      --  Written on the declaration only, as Ada writes it, so a body asks
      --  the tree for it -- and so does an object, which supplies the values.
      --
      --  @param Name The task or task type.
      --  @return Its discriminants, or No_Node.
      function Discriminants_Of (Name : String) return Syntax.Node_Id;

      --  Whether every discriminant in a part has a default.
      --
      --  Either an object gives all of them or it gives none, which is Ada's
      --  rule: a constraint constrains the whole of a type, and a partial one
      --  would leave a program saying which discriminants it meant to leave
      --  out by counting.
      --
      --  @param Formals The discriminant part.
      --  @return True when every one of them has a default, and for a part
      --          with none at all -- which has nothing to be missing.
      function All_Defaulted (Formals : Syntax.Node_Id) return Boolean;

      --  What one discriminant defaults to, or No_Node.
      --
      --  @param Formals The discriminant part.
      --  @param Index Which one, from one.
      --  @return Its default expression, or No_Node.
      function Default_Of
        (Formals : Syntax.Node_Id; Index : Positive) return Syntax.Node_Id;

      --  A body with its object's discriminants declared at the head of it.
      --
      --  @param Contents The copied body.
      --  @param Formals The discriminant part.
      --  @param Actuals What the object gave it.
      --  @param Count How many there are.
      --  @param At_Node The object declaration, for the copies' spans.
      --  @return A sequence holding the constants and then the body.
      function With_Discriminants
        (Contents, Formals, Actuals : Syntax.Node_Id;
         Count : Natural;
         At_Node : Syntax.Node_Id) return Syntax.Node_Id;

      --  Make one object of a protected type.
      --
      --  @param Node The object declaration.
      --  @param Name What the object is called.
      --  @param Of_Type What the type is called.
      --  @param Where The type mark, for a complaint about it.
      procedure Make_Guarded_Object
        (Node : Syntax.Node_Id; Name, Of_Type : String;
         Where, Actuals : Syntax.Node_Id);

      --  Whether this submission holds a body for a task of this name.
      --
      --  @param Name The task or task type.
      --  @return True when a body for it stands in the tree.
      function Has_Task_Body (Name : String) return Boolean;

      --  The type a type mark names, complaining when it names none.
      function Named_Type (Node : S.Node_Id) return Types.Type_Kind;

      --  What a named number is, from the value it was given.
      --
      --  `Max : constant := 100;` is Ada's named number: nothing stands where
      --  a type mark would, and the value says what it is. Held to a literal,
      --  as a parameter's default is and for a related reason -- what a named
      --  number holds is a number known where it is written.
      --
      --  @param Node The object declaration.
      --  @return Its type, or Type_None when what was written is not one.
      function Number_Type (Node : S.Node_Id) return Types.Type_Kind;

      --  How many slots what a name denotes takes.
      --
      --  A protected object is not a value and asking a type for its width
      --  would answer about the wrong thing: what it takes is what its state
      --  takes, which is the run of slots its body declares.
      --
      --  @param Named The name, of a type or of an object.
      --  @return How many slots one of them occupies.
      function Slots_Of (Named : Syntax.Node_Id) return Natural;

      --  How many slots a protected body's declarations take together.
      function Guarded_State_Width (Held : Syntax.Node_Id) return Natural;

      --  The body of the protected object or type a name denotes, or No_Node.
      function Guarded_Body_Of (Named : Syntax.Node_Id) return Syntax.Node_Id;

      --  What a dotted name calls, which for a task object's entry is not
      --  what it is spelled.
      --
      --  `A.Go` names an entry of A's *type*, because several objects of one
      --  task type are several tasks sharing every entry -- so the entry is
      --  declared once, beside the type, and this is what turns the object's
      --  spelling into it. Everything else is its own spelling.
      --
      --  @param Named The name at the head of a call.
      --  @return What to look the callee up as.
      function Name_For_Call (Named : Syntax.Node_Id) return String;

      --  The name a chain of parts is written on: `F (1 .. 4) (1 .. 2)` is
      --  written on F, however many levels stand between. What it is for is
      --  the assignment's refusal, which has to name something a reader can
      --  find in the line.
      --
      --  @param Node A part, or anything else.
      --  @return The innermost name's spelling, or "".
      function Root_Name (Node : Syntax.Node_Id) return String;

      --  Whether what is being declared is a name of its own rather than a
      --  member of something.
      --
      --  A name the shell provides may not be declared again: the shell's own
      --  subprograms accept any type, so a user's version would fit every call
      --  the original does and every one of them would be ambiguous for the
      --  rest of the session.
      --
      --  A *member* is not that name. `Holder.Put` is one name with a dot in
      --  it, and nothing that resolves `Put` can reach it -- so a protected
      --  object with an operation the shell happens to provide was refused for
      --  a clash that could not happen.
      function Is_Its_Own_Name return Boolean
      is (Ada.Strings.Unbounded.Length (Prefix) = 0);

      --  Leave a task object's own symbol on the head of a dotted name.
      --
      --  `A.E` names an entry of the *type* and a task of the object, and a
      --  rendezvous needs both: the entry says which queue, the object says
      --  whose. The entry resolves by name like any package member, because
      --  that is what a member's name is here; this is what carries the other
      --  half down to the lowering.
      --
      --  @param Named The dotted name.
      procedure Note_Task_Object (Named : Syntax.Node_Id);

      --  How many subprogram bodies enclose the statement being analysed, and
      --  what the innermost one returns. Depth rather than a flag, because
      --  "am I inside one" and "may I declare one here" are different
      --  questions and only a count answers both.
      Subprogram_Depth : Natural := 0;

      --  A specification still waiting for its body.
      --
      --  Kept here rather than in the scope chain because it is a question
      --  about the program's shape rather than about visibility: the name is
      --  perfectly visible, and what is missing is the code behind it. The
      --  depth is the chain depth it was declared at, so that a body in a
      --  sibling body's declarative part cannot complete it.
      type Pending_Body is record
         Named : Symbols.Symbol;
         Where : S.Node_Id := S.No_Node;
         Depth : Positive := 1;
      end record;

      package Pending_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Pending_Body);

      Awaiting : Pending_Vectors.Vector;

      procedure Report_Missing_Bodies (Below : Natural);

      --  How deep the virtual machine's display goes. Named here because the
      --  limit belongs to the machine rather than to this language, and a
      --  reader should not have to find that out from the lowering.
      Returns          : Types.Type_Kind := Types.Type_None;

      Legal : Boolean := True;

      --  What a callable name accepts, whoever declared it.
      --
      --  A user's subprogram and a predefined one are checked by the same code
      --  below, so they have to arrive in the same shape. Two shapes would mean
      --  two places to keep the argument rules in step, and the one that got
      --  less use would drift.
      type Signature is record
         Known   : Boolean := False;
         Minimum : Natural := 0;
         Maximum : Natural := 0;
         Of_Type : Symbols.Parameter_Types := [others => Types.Type_None];

         --  All Mode_In for a predefined subprogram or a command: neither
         --  writes back through an argument.
         Modes : Symbols.Parameter_Modes := [others => Symbols.Mode_In];
      end record;

      function Signature_Of
        (Name : String; Found : Symbols.Symbol) return Signature;

      --  How to say what a signature accepts.
      --
      --  A command may accept a range -- `quit` takes a status or nothing --
      --  and naming only one bound would send the reader looking for a rule
      --  that does not exist. Three places report a wrong count; phrasing it
      --  once is what keeps them saying the same thing.
      --
      --  @param About The signature.
      --  @return The accepted count, as the diagnostic spells it.
      function Accepts (About : Signature) return String;

      --  Which of the subprograms a name denotes this call means.
      --
      --  Ada decides by the arguments rather than by the name, so this needs
      --  them analysed first. It reports nothing itself: the caller knows
      --  whether one candidate or several were on offer, and the useful
      --  diagnostic differs -- with one, the count or the type is worth naming;
      --  with several, that a call fits none of them or more than one is.
      function Is_Open_Call (Node : S.Node_Id) return Boolean;

      procedure Resolve_Call
        (Name      : String;
         Arguments : S.Node_Id;
         Given     : Natural;
         Expected  : Types.Type_Kind;
         Offered   : out Natural;
         Fitting   : out Natural;
         Chosen    : out Symbols.Symbol);

      procedure Note
        (Node          : S.Node_Id;
         Resolved_Type : Types.Type_Kind;
         Resolved      : Symbols.Symbol := Symbols.Nothing);

      --  @param Also Somewhere else the complaint is about -- the first of a
      --         pair, the declaration a name could have meant -- or No_Node
      --         when it is about one place only.
      --  @param Also_Says What to say about that place.
      procedure Complain
        (Code      : Adash.Errors.Error_Code;
         Node      : S.Node_Id;
         Arguments : Adash.Messages.Argument_List;
         Also      : S.Node_Id := S.No_Node;
         Also_Says : Adash.Messages.Message_Id :=
           Adash.Messages.Msg_Error_None);

      --  @param Expected What the context requires, or Type_None where it
      --         requires nothing. Only overload resolution reads it: a call to
      --         a name that denotes several subprograms differing in what they
      --         return can be settled no other way, and where the context
      --         expects nothing such a call is ambiguous.
      function Analyse_Expression
        (Node     : S.Node_Id;
         Expected : Types.Type_Kind := Types.Type_None) return Types.Type_Kind;
      procedure Analyse_Statement (Node : S.Node_Id);
      procedure Analyse_Sequence (Node : S.Node_Id);

      --  Analyse what stands where a condition does, complaining when it is
      --  not a Boolean. Declared here because an if *expression* asks it of
      --  its condition, and expressions are analysed above the statements.
      procedure Require_Condition (Node : S.Node_Id);
      procedure Analyse_Subprogram (Node : S.Node_Id);
      procedure Analyse_Handlers (Handlers : S.Node_Id);

      --  Read a formal list into a parameter profile.
      --
      --  What `A, B : out Integer := 1` means is one question, and a
      --  subprogram and an entry are both entitled to the same answer: a
      --  second copy of this is a second place for a default, a mode or a
      --  parameter's name to be read differently.
      --
      --  @param Formals The formal list.
      --  @param Count How many of them to read.
      --  @param Kinds What each parameter's type is.
      --  @param Names What each is called, for a call that names it.
      --  @param Modes Which way each one carries a value.
      --  @param Given What each defaults to, spelled.
      --  @param Has Which ones have a default at all.
      procedure Read_Formals
        (Formals : S.Node_Id;
         Count   : Natural;
         Kinds   : in out Symbols.Parameter_Types;
         Names   : in out Symbols.Parameter_Names;
         Modes   : in out Symbols.Parameter_Modes;
         Given   : in out Symbols.Parameter_Defaults;
         Has     : in out Symbols.Parameter_Has_Default);

      --  What types an expression could have, without settling which.
      --
      --  Resolution reaches inward from what a context expects, and sideways
      --  from whichever end of a pair is closed. Where *both* ends are open
      --  neither of those helps, and what settles it is that only one type is
      --  possible for both -- which needs the possibilities without choosing
      --  between them, and so without reporting anything.
      --
      --  Only the shapes that can be open answer: a name several declarations
      --  could satisfy, and a call to one of several subprograms. Anything
      --  else is closed and answers with nothing, which the callers read as
      --  "ask the ordinary way".
      --
      --  @param Node The expression.
      --  @param Found The types it could have.
      --  @param Count How many, zero when it is not open.
      --  As many as a name could have meanings, which is what the scope
      --  chain hands back at once.
      type Possible_List is
        array (1 .. Adash.Language.Scopes.Max_Overloads)
          of Types.Type_Kind;

      procedure Possible_Types
        (Node  : S.Node_Id;
         Found : out Possible_List;
         Count : out Natural);

      procedure Possible_Types
        (Node  : S.Node_Id;
         Found : out Possible_List;
         Count : out Natural)
      is
         Pool   : Adash.Language.Scopes.Symbol_List;
         Offers : Natural := 0;

         --  The name a call or a bare name spells, or "" for anything else.
         function Spelt return String is
           (case S.Kind (Tree, Node) is
               when S.Node_Name => S.Text (Tree, Node),
               when S.Node_Call => Dotted (Tree, S.First (Tree, Node)),
               when others => "");

         --  How many arguments a call was given, which decides whether a
         --  candidate could answer it at all.
         Args : constant Natural :=
           (if S.Kind (Tree, Node) = S.Node_Call
              and then S.Is_Present (S.Second (Tree, Node))
            then S.Child_Count (Tree, S.Second (Tree, Node)) else 0);
      begin
         Found := [others => Types.Type_None];
         Count := 0;

         if S.Kind (Tree, Node) = S.Node_Parenthesized then
            Possible_Types (S.First (Tree, Node), Found, Count);
            return;
         end if;

         if Spelt = "" then
            return;
         end if;

         Chain.Candidates (Visible_Name (Spelt), Pool, Offers);

         if Offers <= 1 then
            --  One meaning, or none. Either way there is nothing to choose
            --  between, and the ordinary path says what is wrong with it.
            return;
         end if;

         for Index in 1 .. Offers loop
            declare
               About : constant Signature := Signature_Of (Spelt, Pool (Index));
               Gives : constant Types.Type_Kind :=
                 Symbols.Of_Type (Pool (Index));
               Known : Boolean := False;
            begin
               --  A candidate that could not answer a call of this shape says
               --  nothing about what the expression could be.
               if Gives /= Types.Type_None
                 and then (not Symbols.Is_Callable (Pool (Index))
                           or else (About.Known
                                    and then Args >= About.Minimum
                                    and then Args <= About.Maximum))
               then
                  for Taken in 1 .. Count loop
                     if Found (Taken) = Gives then
                        Known := True;
                     end if;
                  end loop;

                  if not Known and then Count < Found'Last then
                     Count := Count + 1;
                     Found (Count) := Gives;
                  end if;
               end if;
            end;
         end loop;
      end Possible_Types;

      --  The one numeric type an open expression could have, or Type_None.
      --
      --  What a sign requires of what it is applied to when nothing requires
      --  anything of the sign. `-F` where F names three subprograms and one of
      --  them yields a number is that one; where two do, the sign says nothing
      --  and the ordinary ambiguity is reported.
      --
      --  @param Node An expression.
      --  @return Its one numeric reading, when it has exactly one.
      function Only_Numeric (Node : S.Node_Id) return Types.Type_Kind;

      function Only_Numeric (Node : S.Node_Id) return Types.Type_Kind is
         Could  : Possible_List;
         Many   : Natural := 0;
         Answer : Types.Type_Kind := Types.Type_None;
         Fits   : Natural := 0;
      begin
         Possible_Types (Node, Could, Many);

         for Index in 1 .. Many loop
            if Types.Is_Numeric (Could (Index)) and then Answer /= Could (Index)
            then
               Fits := Fits + 1;
               Answer := Could (Index);
            end if;
         end loop;

         return (if Fits = 1 then Answer else Types.Type_None);
      end Only_Numeric;

      --  The one type two open expressions could both have, or Type_None.
      --
      --  @param Left One expression.
      --  @param Right The other.
      --  @return The type they share, when they share exactly one.
      --  What an operator leaves an open operand able to be, given what the
      --  other operand turned out to be.
      --
      --  Most operators take one type on both sides, so the answer is the
      --  other operand's own. `&` is the exception: it takes a String or a
      --  Character on either side whatever the other one is, so what settles
      --  the open side is which of those two it could be -- `F & "x"` with an
      --  F that returns an Integer or a String is a String, because the other
      --  reading is not an operand this operator has.
      --
      --  @param Op The operator.
      --  @param Other What the settled operand is.
      --  @param Open The operand that is still open.
      --  @return What to require of it, or Type_None to require nothing.
      function Operand_Wanted
        (Op    : S.Operation;
         Other : Types.Type_Kind;
         Open  : S.Node_Id) return Types.Type_Kind;

      function Operand_Wanted
        (Op    : S.Operation;
         Other : Types.Type_Kind;
         Open  : S.Node_Id) return Types.Type_Kind
      is
         Could  : Possible_List;
         Many   : Natural := 0;
         Answer : Types.Type_Kind := Types.Type_None;
         Fits   : Natural := 0;
      begin
         if Other = Types.Type_None then
            return Types.Type_None;
         end if;

         if Op /= S.Op_Concat then
            return Other;
         end if;

         Possible_Types (Open, Could, Many);

         for Index in 1 .. Many loop
            if (Could (Index) = Types.Type_String
                or else Could (Index) = Types.Type_Character)
              and then Answer /= Could (Index)
            then
               Fits := Fits + 1;
               Answer := Could (Index);
            end if;
         end loop;

         return (if Fits = 1 then Answer else Types.Type_None);
      end Operand_Wanted;

      function Shared_Type (Left, Right : S.Node_Id) return Types.Type_Kind is
         Ours   : Possible_List;
         Theirs : Possible_List;
         Mine   : Natural;
         Yours  : Natural;
         Answer : Types.Type_Kind := Types.Type_None;
         Shared : Natural := 0;
      begin
         Possible_Types (Left, Ours, Mine);
         Possible_Types (Right, Theirs, Yours);

         if Mine = 0 or else Yours = 0 then
            return Types.Type_None;
         end if;

         for One in 1 .. Mine loop
            for Two in 1 .. Yours loop
               if Ours (One) = Theirs (Two) then
                  Shared := Shared + 1;
                  Answer := Ours (One);
               end if;
            end loop;
         end loop;

         return (if Shared = 1 then Answer else Types.Type_None);
      end Shared_Type;

      --------------------
      -- Is_Open_Call --
      --------------------

      --  Whether this expression is a call that more than one subprogram of
      --  that name could answer.
      --
      --  Asked before the operand is analysed, so it cannot use the answer;
      --  the candidate set is what it goes on. A name that denotes one thing,
      --  or nothing, or something that is not callable, is not open.
      function Is_Open_Call (Node : S.Node_Id) return Boolean is
         Pool  : Adash.Language.Scopes.Symbol_List;
         Count : Natural;
      begin
         case S.Kind (Tree, Node) is
            when S.Node_Name =>
               Chain.Candidates
                 (Visible_Name (S.Text (Tree, Node)), Pool, Count);

            when S.Node_Call =>
               Chain.Candidates
                 (Visible_Name (Dotted (Tree, S.First (Tree, Node))),
                  Pool, Count);

            when S.Node_Parenthesized =>
               return Is_Open_Call (S.First (Tree, Node));

            when others =>
               return False;
         end case;

         return Count > 1;
      end Is_Open_Call;

      -------------------
      -- Resolve_Call --
      -------------------

      procedure Resolve_Call
        (Name      : String;
         Arguments : S.Node_Id;
         Given     : Natural;
         Expected  : Types.Type_Kind;
         Offered   : out Natural;
         Fitting   : out Natural;
         Chosen    : out Symbols.Symbol)
      is
         Pool : Adash.Language.Scopes.Symbol_List;

         --  Whether this candidate could take the arguments as written.
         function Accepts (Candidate : Symbols.Symbol) return Boolean is
            About : constant Signature :=
              Signature_Of (Name, Candidate);

            --  Where each parameter's value would come from, if this were
            --  the one meant. A named argument is not in the position it is
            --  written in, so comparing types by position would reject the
            --  candidate that fits and accept the one that does not.
            Slots   : Argument_Map := [others => S.No_Node];
            At_Node : S.Node_Id := S.No_Node;
            Which   : Natural := 0;
         begin
            if not About.Known
              or else Given < About.Minimum
              or else Given > About.Maximum
            then
               return False;
            end if;

            if Symbols.Has_Profile (Candidate)
              and then Match_Arguments
                         (Tree, Arguments, Candidate, Slots, At_Node, Which)
                       /= Matched
            then
               --  A call that cannot be matched to this profile at all is not
               --  a call to it, whatever the types would say.
               return False;
            end if;

            for Index in 1 .. Natural'Min
              (Natural'Min
                 ((if Symbols.Has_Profile (Candidate)
                   then About.Maximum else Given),
                  About.Maximum),
               Symbols.Max_Parameters)
            loop
               declare
                  From : constant S.Node_Id :=
                    (if Symbols.Has_Profile (Candidate) then Slots (Index)
                     else S.Child (Tree, Arguments, Index));

                  Wanted : constant Types.Type_Kind := About.Of_Type (Index);
                  Actual : constant Types.Type_Kind :=
                    (if S.Is_Present (From) then Into.Type_Of (From)
                     else Types.Type_None);
               begin
                  --  A parameter typed Type_None accepts anything, which the
                  --  output procedures rely on. An argument whose own type is
                  --  unknown is let through so that one broken argument does
                  --  not turn into a second complaint about the call.
                  if Wanted /= Types.Type_None
                    and then Actual /= Types.Type_None
                    and then not Types.Is_Acceptable (Actual, Wanted)
                  then
                     return False;
                  end if;
               end;
            end loop;

            return True;
         end Accepts;
      begin
         Chain.Candidates (Visible_Name (Name), Pool, Offered);
         Fitting := 0;
         Chosen  := Symbols.Nothing;

         for Index in 1 .. Offered loop
            if Accepts (Pool (Index)) then
               Fitting := Fitting + 1;

               if Fitting = 1 then
                  --  Innermost first, so the first that fits is the one an
                  --  inner declaration would have hidden the others with.
                  Chosen := Pool (Index);
               end if;
            end if;
         end loop;

         if Fitting > 1 and then Expected /= Types.Type_None then
            --  The arguments did not settle it, so what the context requires
            --  does. This is the only way a pair differing solely in what they
            --  return can be told apart, and where the context requires
            --  nothing they stay ambiguous -- which is the honest answer, not
            --  a failure to try.
            declare
               Narrowed : Natural := 0;
               Taken    : Symbols.Symbol := Symbols.Nothing;
            begin
               for Index in 1 .. Offered loop
                  if Accepts (Pool (Index))
                    and then Types.Is_Acceptable
                               (Symbols.Of_Type (Pool (Index)), Expected)
                  then
                     Narrowed := Narrowed + 1;

                     if Narrowed = 1 then
                        Taken := Pool (Index);
                     end if;
                  end if;
               end loop;

               if Narrowed >= 1 then
                  Fitting := Narrowed;
                  Chosen  := Taken;
               end if;
            end;
         end if;

         if Offered = 1 then
            --  Only one thing it could mean. Reported against that one
            --  whether or not it fits, so the diagnostic can say what was
            --  wrong with the call rather than that nothing matched.
            Chosen := Pool (1);
         end if;
      end Resolve_Call;

      -------------
      -- Accepts --
      -------------

      function Accepts (About : Signature) return String is
      begin
         if About.Minimum = About.Maximum then
            return Natural'Image (About.Minimum);
         elsif About.Maximum = Natural'Last then
            return Natural'Image (About.Minimum) & " or more";
         else
            return Natural'Image (About.Minimum) & " .."
                   & Natural'Image (About.Maximum);
         end if;
      end Accepts;

      ------------------
      -- Signature_Of --
      ------------------

      function Signature_Of
        (Name : String; Found : Symbols.Symbol) return Signature
      is
         Result : Signature;
      begin
         --  A declared subprogram first, on the strength of the scope chain
         --  having found it. At submission level a name that collides with a
         --  predefined one is a redeclaration and was already refused, so
         --  there is no contest to settle there; inside a body there is, and
         --  a parameter named after a predefined subprogram hides it for as
         --  long as the body lasts. Asking the chain is what gets both right.
         if Symbols.Has_Profile (Found) then
            Result.Known   := True;
            Result.Maximum := Symbols.Parameter_Count (Found);

            --  The minimum is how many arguments a *positional* call has to
            --  write: the leading run of parameters without defaults. Ada
            --  allows a parameter with no default after one with one -- it can
            --  then only be given by name -- so this is a bound on the count
            --  rather than the whole rule, and Match_Arguments is what
            --  establishes that every parameter actually has a value.
            Result.Minimum := 0;

            for Index in 1 .. Symbols.Parameter_Count (Found) loop
               exit when Symbols.Has_Default (Found, Index);
               Result.Minimum := Index;
            end loop;

            for Index in 1 .. Symbols.Parameter_Count (Found) loop
               Result.Of_Type (Index) := Symbols.Parameter_Type (Found, Index);
               Result.Modes (Index) :=
                 Symbols.Parameter_Passing (Found, Index);
            end loop;

            return Result;
         end if;

         --  Adash.Predefined answers for the language's own subprograms and
         --  for the shell's commands, so this asks one question rather than
         --  two.
         declare
            About : constant Adash.Predefined.Profile :=
              Adash.Predefined.Profile_Of (Name);
         begin
            Result.Known   := About.Known;
            Result.Minimum := About.Minimum;
            Result.Maximum := About.Maximum;

            --  A command may take any number -- `start` does -- and its
            --  maximum is then Natural'Last. Both arrays are bounded, and only
            --  the smaller of the three bounds is safe to walk: reading past
            --  the profile is what an unbounded command used to do here.
            for Index in 1 .. Natural'Min
              (Natural'Min (About.Maximum, Symbols.Max_Parameters),
               Adash.Predefined.Max_Parameters)
            loop
               Result.Of_Type (Index) := About.Types_Of (Index).Of_Type;
            end loop;
         end;

         return Result;
      end Signature_Of;

      ----------
      -- Note --
      ----------

      procedure Note
        (Node          : S.Node_Id;
         Resolved_Type : Types.Type_Kind;
         Resolved      : Symbols.Symbol := Symbols.Nothing)
      is
         Index : constant Natural := S.Index (Node);
      begin
         if Index = 0 then
            return;
         end if;

         --  Grown to fit. The tree stops growing during analysis for every
         --  program but one: an instantiation copies a generic's body onto it,
         --  and the copy has to be able to carry conclusions like anything
         --  else. Sizing once at the start left every grafted node silently
         --  unannotated, and the lowering then found no body for the
         --  subprogram the instantiation had declared.
         while Natural (Into.Notes.Length) < Index loop
            Into.Notes.Append (Annotation'(others => <>));
         end loop;

         Into.Notes.Replace_Element
           (Index, (Resolved_Type => Resolved_Type,
                    Resolved      => Resolved,
                    Visited       => True));
      end Note;

      ---------------------------
      -- All_Defaulted --
      ---------------------------

      function All_Defaulted (Formals : Syntax.Node_Id) return Boolean is
      begin
         for Index in 1 .. S.Child_Count (Tree, Formals) loop
            if not S.Is_Present (Default_Of (Formals, Index)) then
               return False;
            end if;
         end loop;

         return True;
      end All_Defaulted;

      ------------------------
      -- Default_Of --
      ------------------------

      function Default_Of
        (Formals : Syntax.Node_Id; Index : Positive) return Syntax.Node_Id
      is
         One : constant S.Node_Id := S.Child (Tree, Formals, Index);
      begin
         --  A formal carries its default as a third child, and carries none
         --  when it has none.
         return (if S.Child_Count (Tree, One) = 3
                 then S.Child (Tree, One, 3) else S.No_Node);
      end Default_Of;

      ---------------------------------
      -- With_Discriminants --
      ---------------------------------

      function With_Discriminants
        (Contents, Formals, Actuals : Syntax.Node_Id;
         Count : Natural;
         At_Node : Syntax.Node_Id) return Syntax.Node_Id
      is
         Held : S.Node_List (1 .. Count + S.Child_Count (Tree, Contents));
         Filled : Natural := 0;
      begin
         if Count = 0 then
            return Contents;
         end if;

         for Index in 1 .. Count loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Formals, Index);

               --  One at a time and in order, because each of these appends
               --  to the same tree and Ada does not say which part of an
               --  aggregate is evaluated first.
               Called_It : constant S.Node_Id :=
                 S.Add_Leaf
                   (Tree, S.Node_Name, S.Extent (Tree, At_Node),
                    S.Text (Tree, S.First (Tree, One)));
               Of_Type : constant S.Node_Id :=
                 S.Graft (Tree, S.Second (Tree, One));
               --  What the object gave, or what the type says one is when
               --  the object gave nothing. Copied either way, so each object
               --  has nodes of its own to record conclusions on.
               Value : constant S.Node_Id :=
                 S.Graft
                   (Tree,
                    (if S.Child_Count (Tree, Actuals) >= Index
                     then S.Child (Tree, Actuals, Index)
                     else Default_Of (Formals, Index)));
            begin
               Filled := Filled + 1;
               Held (Filled) :=
                 S.Add_Node
                   (Tree, S.Node_Object_Declaration,
                    S.Extent (Tree, At_Node),
                    [Called_It, Of_Type, Value, S.No_Node],
                    Text => "constant");
            end;
         end loop;

         for Index in 1 .. S.Child_Count (Tree, Contents) loop
            Filled := Filled + 1;
            Held (Filled) := S.Child (Tree, Contents, Index);
         end loop;

         return S.Add_Node
           (Tree, S.Node_Sequence, S.Extent (Tree, Contents),
            Held (1 .. Filled));
      end With_Discriminants;

      ---------------------------------
      -- Make_Guarded_Object --
      ---------------------------------

      procedure Make_Guarded_Object
        (Node : Syntax.Node_Id; Name, Of_Type : String;
         Where, Actuals : Syntax.Node_Id)
      is
         Which : constant Natural := Guarded_Template (Of_Type);
      begin
         if Which = 0
           or else not S.Is_Present (Guarded_Types.Element (Which).Made_Of)
         then
            --  Declared and never given a body. An object of one would have
            --  nothing to copy, so it is said here rather than left to produce
            --  an object whose operations do nothing.
            Complain (Adash.Errors.Error_Body_Missing, Where,
                      [1 => Adash.Messages.Named ("name", Of_Type)]);
            return;
         end if;

         declare
            Declaration : constant S.Node_Id :=
              Guarded_Types.Element (Which).At_Node;
            Held_Body   : constant S.Node_Id :=
              Guarded_Types.Element (Which).Made_Of;

            --  The type's own name for the object's, everywhere it stands.
            --  Everything else in the copy means what it meant.
            Bindings : constant S.Renamings (1 .. 1) :=
              [1 => (From =>
                       Ada.Strings.Unbounded.To_Unbounded_String (Of_Type),
                     To   =>
                       Ada.Strings.Unbounded.To_Unbounded_String (Name))];

            --  Built rather than grafted whole, so the name carries *this*
            --  declaration's span: what identifies an operation to the
            --  lowering is where its name was written, and a grafted name
            --  would carry the type's -- so two objects would be one object
            --  and the second would call the first's.
            Declared_Name : constant S.Node_Id :=
              S.Add_Leaf (Tree, S.Node_Name, S.Extent (Tree, Node), Name);
            Members : constant S.Node_Id :=
              S.Graft (Tree, S.Second (Tree, Declaration), Bindings);

            Body_Name : constant S.Node_Id :=
              S.Add_Leaf (Tree, S.Node_Name, S.Extent (Tree, Node), Name);

            --  The discriminants, as constants at the head of the object's own
            --  body. That is what a discriminant *is* here: something the type
            --  is written against and the object fixes, which is a constant of
            --  the object -- so the body reads it by name like any other of
            --  its own declarations, and nothing below has a new idea to
            --  learn.
            Given : constant S.Node_Id :=
              Discriminants_Of (Of_Type);
            Count : constant Natural := S.Child_Count (Tree, Given);

            Contents : constant S.Node_Id :=
              With_Discriminants
                (S.Graft (Tree, S.Second (Tree, Held_Body), Bindings),
                 Given, Actuals, Count, Node);

            Object_Declaration : constant S.Node_Id :=
              S.Add_Node
                (Tree, S.Node_Protected_Declaration, S.Extent (Tree, Node),
                 [Declared_Name, Members, S.No_Node]);
            Object_Body : constant S.Node_Id :=
              S.Add_Node
                (Tree, S.Node_Protected_Body, S.Extent (Tree, Node),
                 [Body_Name, Contents, S.No_Node]);

            --  One node for the pair, because what the lowering asks for is
            --  what this declaration expanded to and a declaration expands to
            --  both halves of an object.
            Pair : constant S.Node_Id :=
              S.Add_Node (Tree, S.Node_Sequence, S.Extent (Tree, Node),
                          [Object_Declaration, Object_Body]);
         begin
            Into.Made.Append (Expansion'(At_Node => Node, Made => Pair));

            --  What it was made from, so that a question about the object --
            --  how much room it takes -- is answered by the body it is a copy
            --  of rather than by looking for one under its own name.
            Guarded_Objects.Append
              (Template'
                 (Key     =>
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Symbols.Fold (Name)),
                  At_Node => Node,
                  Made_Of => Object_Body));

            --  Analysed as the ordinary protected object it now is.
            Analyse_Statement (Object_Declaration);
            Analyse_Statement (Object_Body);
         end;
      end Make_Guarded_Object;

      ---------------------------
      -- Discriminants_Of --
      ---------------------------

      function Discriminants_Of (Name : String) return Syntax.Node_Id is
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) in S.Node_Task_Declaration
                                       | S.Node_Protected_Declaration
                 and then S.Child_Count (Tree, Node) >= 4
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = Symbols.Fold (Name)
               then
                  return S.Child (Tree, Node, 4);
               end if;
            end;
         end loop;

         return S.No_Node;
      end Discriminants_Of;

      ---------------------
      -- Has_Task_Body --
      ---------------------

      function Has_Task_Body (Name : String) return Boolean is
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Task_Body
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = Symbols.Fold (Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Has_Task_Body;

      ---------------------------
      -- Guarded_Body_Of --
      ---------------------------

      function Guarded_Body_Of (Named : Syntax.Node_Id) return Syntax.Node_Id
      is
         Wanted : constant String :=
           (if S.Kind (Tree, Named) = S.Node_Name
            then S.Text (Tree, Named) else "");

         --  An object of a protected type is a copy of the type's body under
         --  the object's own name, so either spelling finds a body: the
         --  object's copy, or the type's template.
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         if Wanted = "" then
            return S.No_Node;
         end if;

         for Index in 1 .. Natural (Guarded_Types.Length) loop
            if Ada.Strings.Unbounded.To_String
                 (Guarded_Types.Element (Index).Key)
               = Symbols.Fold (Wanted)
            then
               return Guarded_Types.Element (Index).Made_Of;
            end if;
         end loop;

         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, One) = S.Node_Protected_Body
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, One)))
                          = Symbols.Fold (Wanted)
               then
                  return One;
               end if;
            end;
         end loop;

         --  An object of a protected type: what it is made of is the type's.
         for Index in 1 .. Natural (Guarded_Objects.Length) loop
            if Ada.Strings.Unbounded.To_String
                 (Guarded_Objects.Element (Index).Key)
               = Symbols.Fold (Wanted)
            then
               return Guarded_Objects.Element (Index).Made_Of;
            end if;
         end loop;

         return S.No_Node;
      end Guarded_Body_Of;

      ---------------------------
      -- Guarded_State_Width --
      ---------------------------

      function Guarded_State_Width (Held : Syntax.Node_Id) return Natural is
         Total : Natural := 0;
      begin
         for Index in 1 .. S.Child_Count (Tree, Held) loop
            declare
               One : constant S.Node_Id := S.Child (Tree, Held, Index);
            begin
               if S.Kind (Tree, One) = S.Node_Object_Declaration then
                  Total :=
                    Total + Types.Width (Named_Type (S.Second (Tree, One)));
               end if;
            end;
         end loop;

         return Total;
      end Guarded_State_Width;

      -----------------------------
      -- Slots_Of --
      -----------------------------

      function Slots_Of (Named : Syntax.Node_Id) return Natural is
         Found : constant Symbols.Symbol :=
           (if S.Kind (Tree, Named) = S.Node_Name
            then Visible (S.Text (Tree, Named)) else Symbols.Nothing);

         --  What the name denotes: a type, or something with a type.
         Whose : constant Types.Type_Kind :=
           (if Symbols.Kind (Found) = Symbols.Symbol_Type
            then Symbols.Of_Type (Found)
            elsif Symbols.Kind (Found) = Symbols.Symbol_Package
            then Types.Type_None
            else Analyse_Expression (Named));
      begin
         --  An object of a protected type, or the type itself: what one takes
         --  is what its state takes, which is the run of slots its body
         --  declares. Not a value, so there is no width to ask a type for.
         declare
            Body_Of : constant Syntax.Node_Id := Guarded_Body_Of (Named);
         begin
            if S.Is_Present (Body_Of) then
               return Guarded_State_Width (S.Second (Tree, Body_Of));
            end if;
         end;

         return Types.Width (Whose);
      end Slots_Of;

      ---------------------
      -- Name_For_Call --
      ---------------------

      function Root_Name (Node : Syntax.Node_Id) return String is
         Walk : S.Node_Id := Node;
      begin
         while S.Kind (Tree, Walk) = S.Node_Call loop
            Walk := S.First (Tree, Walk);
         end loop;

         return (if S.Kind (Tree, Walk) = S.Node_Name
                 then S.Text (Tree, Walk) else "");
      end Root_Name;

      function Name_For_Call (Named : Syntax.Node_Id) return String is
         Spelt : constant String := Dotted (Tree, Named);
      begin
         if S.Kind (Tree, Named) /= S.Node_Selected then
            return Spelt;
         end if;

         declare
            Head   : constant S.Node_Id := S.First (Tree, Named);
            Object : constant Symbols.Symbol :=
              (if S.Kind (Tree, Head) = S.Node_Name
               then Visible (S.Text (Tree, Head)) else Symbols.Nothing);
         begin
            if not Types.Is_Task (Symbols.Of_Type (Object))
              or else Symbols.Kind (Object) = Symbols.Symbol_Type
            then
               return Spelt;
            end if;

            declare
               Under_Type : constant String :=
                 Types.Name (Symbols.Of_Type (Object)) & "."
                 & S.Text (Tree, S.Second (Tree, Named));
            begin
               return (if Symbols.Kind (Visible (Under_Type))
                          = Symbols.Symbol_Entry
                       then Under_Type else Spelt);
            end;
         end;
      end Name_For_Call;

      ----------------------------
      -- Guarded_Template --
      ----------------------------

      -----------------------------
      -- Read_Restrictions --
      -----------------------------

      procedure Read_Restrictions is
         Root : constant S.Node_Id := S.Root (Tree);

         --  Take a restriction on, with the number some of them carry. What
         --  the machine has to be told is passed on here rather than where
         --  each restriction is read, so that a profile and a `pragma
         --  Restrictions` saying the same thing mean the same thing.
         --
         --  @param Each Restriction taken on.
         --  @param How_Many What it is limited to, for the counted ones.
         --  @param Counted Whether a number was given at all.
         procedure Take_On
           (Each : Restriction; How_Many : Natural := 0;
            Counted : Boolean := False) is
         begin
            Restricted (Each) := True;

            if Each = No_Task_Termination then
               Into.Endless := True;
            end if;

            if Counted then
               Limits (Each) := How_Many;

               if Each = Max_Tasks then
                  Into.Task_Limit := How_Many;
                  Into.Bounded := True;

               elsif Each = Max_Entry_Queue_Length then
                  Into.Queue_Limit := How_Many;
                  Into.Queue_Given := True;
               end if;
            end if;
         end Take_On;

         --  Ravenscar, as far as this language can be held to it, and Jorvik,
         --  which Ada defines as Ravenscar with four things given back. What
         --  either names beyond this -- allocators, heap, interrupts, timing
         --  events, library dependencies -- names things this language does
         --  not have, so there is nothing for it to give up.
         --
         --  `No_Delay` is deliberately not here even for Ravenscar: it forbids
         --  a delay *for* a length and allows one *until* a time, which is
         --  what `No_Relative_Delay` says. Nor is `Max_Tasks`: a profile
         --  settles how many tasks there are by where they may be declared.
         --
         --  `Max_Task_Entries => 0` is in both: a task under either profile is
         --  talked to through a protected object rather than by rendezvous.
         --
         --  @param Relaxed Whether this is Jorvik rather than Ravenscar.
         procedure Take_On_Profile (Relaxed : Boolean) is
         begin
            Take_On (No_Abort_Statements);
            Take_On (No_Dynamic_Priorities);
            Take_On (No_Local_Protected_Objects);
            Take_On (No_Requeue_Statements);
            Take_On (No_Select_Statements);
            Take_On (No_Task_Hierarchy);
            Take_On (No_Task_Termination);
            Take_On (Max_Task_Entries, 0, Counted => True);

            --  What Jorvik gives back: a barrier worked out rather than read,
            --  more than one entry on an object, more than one caller queued
            --  at one, and a delay for a length. Each was Ravenscar's for a
            --  reason about *analysis* rather than about safety, and Jorvik is
            --  Ada saying that a program willing to pay for the analysis may
            --  have them.
            if Relaxed then
               Take_On (Pure_Barriers);
            else
               Take_On (No_Relative_Delay);
               Take_On (Simple_Barriers);
               Take_On (Max_Entry_Queue_Length, 1, Counted => True);
               Take_On (Max_Protected_Entries, 1, Counted => True);
            end if;
         end Take_On_Profile;

      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Pragma
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = "profile"
                 and then S.Child_Count (Tree, S.Second (Tree, Node)) = 1
                 and then S.Kind (Tree, S.Child (Tree, S.Second (Tree, Node),
                                                 1))
                          = S.Node_Name
                 and then Symbols.Fold
                            (S.Text (Tree,
                                     S.Child (Tree, S.Second (Tree, Node), 1)))
                          in "ravenscar" | "jorvik"
               then
                  Take_On_Profile
                    (Relaxed =>
                       Symbols.Fold
                         (S.Text (Tree,
                                  S.Child (Tree, S.Second (Tree, Node), 1)))
                       = "jorvik");

               elsif S.Kind (Tree, Node) = S.Node_Pragma
                 and then Symbols.Fold (S.Text (Tree, S.First (Tree, Node)))
                          = "restrictions"
               then
                  declare
                     Given : constant S.Node_Id := S.Second (Tree, Node);
                  begin
                     for Position in 1 .. S.Child_Count (Tree, Given) loop
                        declare
                           One : constant S.Node_Id :=
                             S.Child (Tree, Given, Position);

                           --  `Max_Tasks => 2` names the restriction on the
                           --  left of the arrow; every other names itself.
                           Asked : constant S.Node_Id :=
                             (if S.Kind (Tree, One) = S.Node_Named_Argument
                              then S.First (Tree, One) else One);
                        begin
                           for Each in Restriction loop
                              if S.Kind (Tree, Asked) = S.Node_Name
                                and then Symbols.Fold (Spelling (Each))
                                         = Symbols.Fold (S.Text (Tree, Asked))
                              then
                                 Take_On (Each);

                                 if S.Kind (Tree, One)
                                    = S.Node_Named_Argument
                                 then
                                    declare
                                       How_Many : Long_Long_Integer;
                                    begin
                                       if Static_Choice
                                            (Into, Tree,
                                             S.Second (Tree, One), How_Many)
                                         and then How_Many >= 0
                                       then
                                          Take_On
                                            (Each, Natural (How_Many),
                                             Counted => True);
                                       end if;
                                    end;
                                 end if;
                              end if;
                           end loop;
                        end;
                     end loop;
                  end;
               end if;
            end;
         end loop;
      end Read_Restrictions;

      -----------------------------------
      -- Refuse_If_Restricted --
      -----------------------------------

      --  Whether a barrier may be worked out without doing anything and
      --  without failing: what Ada calls a pure barrier.
      --
      --  What is left out is what could do something (a call) and what could
      --  raise (a division, a remainder, an exponentiation, a join). What is
      --  in is what reads a value and what combines values: a barrier is
      --  asked at moments the program did not choose, so it has to be
      --  answerable at any of them.
      --
      --  @param Node The barrier, or a part of one.
      --  @return Whether this part is pure.
      --  Give a range of priorities a dispatching policy, and complain if
      --  something else already gave one of them another.
      --
      --  Saying the same thing twice is not a conflict: a configuration
      --  pragma repeated is Ada's own, and what is refused is two answers to
      --  one question.
      --
      --  @param Which The policy said.
      --  @param First Lowest priority it was said of.
      --  @param Last Highest priority it was said of.
      --  @param Named How the pragma that said it is spelled.
      --  @param Node Where to say it.
      procedure Give_Dispatching
        (Which : Dispatching; First : Natural; Last : Natural;
         Named : String; Node : Syntax.Node_Id)
      is
         Clashed : Boolean := False;
      begin
         for Each in Natural'Max (First, Dispatch'First)
                     .. Natural'Min (Last, Dispatch'Last)
         loop
            if Dispatch (Each) not in Not_Said | Which then
               Clashed := True;
            end if;

            Dispatch (Each) := Which;
         end loop;

         if Clashed then
            Complain
              (Adash.Errors.Error_Dispatching_Twice, Node,
               [1 => Adash.Messages.Named ("name", Named)]);
         end if;
      end Give_Dispatching;

      function Pure_Barrier (Node : Syntax.Node_Id) return Boolean is
      begin
         case S.Kind (Tree, Node) is
            when S.Node_Integer_Literal | S.Node_Real_Literal
               | S.Node_Character_Literal | S.Node_String_Literal
               | S.Node_Selected | S.Node_Attribute =>
               return True;

            --  A function called without parentheses is a name to the parser
            --  and a call to everybody else, so what it denotes is what
            --  decides. This is the whole reason the check cannot be done on
            --  the shape of the barrier alone.
            when S.Node_Name =>
               return Symbols.Kind (Visible (S.Text (Tree, Node)))
                        not in Symbols.Symbol_Function
                             | Symbols.Symbol_Procedure;

            when S.Node_Parenthesized =>
               return Pure_Barrier (S.First (Tree, Node));

            when S.Node_Unary_Operation =>
               return S.Operator (Tree, Node)
                        in S.Op_Plus | S.Op_Minus | S.Op_Not | S.Op_Abs
                 and then Pure_Barrier (S.First (Tree, Node));

            when S.Node_Binary_Operation | S.Node_Membership =>
               if S.Operator (Tree, Node)
                  in S.Op_Divide | S.Op_Mod | S.Op_Rem | S.Op_Power
                   | S.Op_Concat
               then
                  return False;
               end if;

               for Index in 1 .. S.Child_Count (Tree, Node) loop
                  if not Pure_Barrier (S.Child (Tree, Node, Index)) then
                     return False;
                  end if;
               end loop;

               return True;

            when S.Node_Range =>
               return Pure_Barrier (S.First (Tree, Node))
                 and then Pure_Barrier (S.Second (Tree, Node));

            when others =>
               return False;
         end case;
      end Pure_Barrier;

      procedure Refuse_If_Restricted
        (Which : Restriction; Node : Syntax.Node_Id) is
      begin
         if Restricted (Which) then
            Complain
              (Adash.Errors.Error_Restriction_Broken, Node,
               [1 => Adash.Messages.Named ("name", Spelling (Which))]);
         end if;
      end Refuse_If_Restricted;

      function Guarded_Template (Name : String) return Natural is
      begin
         for Index in 1 .. Natural (Guarded_Types.Length) loop
            if Ada.Strings.Unbounded.To_String
                 (Guarded_Types.Element (Index).Key)
               = Symbols.Fold (Name)
            then
               return Index;
            end if;
         end loop;

         return 0;
      end Guarded_Template;

      -------------------------
      -- Note_Task_Object --
      -------------------------

      procedure Note_Task_Object (Named : Syntax.Node_Id) is
      begin
         if S.Kind (Tree, Named) /= S.Node_Selected then
            return;
         end if;

         declare
            Head   : constant S.Node_Id := S.First (Tree, Named);
            Object : constant Symbols.Symbol :=
              (if S.Kind (Tree, Head) = S.Node_Name
               then Visible (S.Text (Tree, Head)) else Symbols.Nothing);
         begin
            --  An object, not a type: a type is what objects are made from
            --  and there is no task to find behind one.
            if Types.Is_Task (Symbols.Of_Type (Object))
              and then Symbols."/=" (Symbols.Kind (Object),
                                     Symbols.Symbol_Type)
            then
               Note (Head, Symbols.Of_Type (Object), Object);
            end if;
         end;
      end Note_Task_Object;

      --------------
      -- Complain --
      --------------

      procedure Complain
        (Code      : Adash.Errors.Error_Code;
         Node      : S.Node_Id;
         Arguments : Adash.Messages.Argument_List;
         Also      : S.Node_Id := S.No_Node;
         Also_Says : Adash.Messages.Message_Id :=
           Adash.Messages.Msg_Error_None)
      is
         Said : D.Diagnostic :=
           D.Make
              (Message   => Adash.Errors.Message (Code),
               Level     => D.Severity_Error,
               Of_Kind   => D.Category_Semantic,
               Raised_By => D.Owner_Language,
               Origin    => Origin,
               Extent    => S.Extent (Tree, Node),
               Arguments => Arguments);
      begin
         Legal := False;

         --  The other place, when there is one. A complaint about a pair --
         --  the second of two declarations, the second of two choices, a name
         --  two subprograms answer to -- is only actionable when a reader can
         --  see both.
         if S.Is_Present (Also) then
            D.Add_Related
              (Said,
               (Origin  => Origin,
                Extent  => S.Extent (Tree, Also),
                Place   => (Line => 1, Column => 1),
                Message => Also_Says));
         end if;

         Report.Emit (Said);
      end Complain;

      --  Complain about a name several declarations answer to, and say where
      --  each of them is.
      --
      --  An ambiguity is the diagnostic a reader can do least with on its own:
      --  what they have to decide is which of the things called that they
      --  meant, and they cannot decide it without seeing them. Up to four,
      --  which is what a diagnostic carries; a name with five meanings is
      --  already past what a reader will work through.
      --
      --  @param Code Which ambiguity.
      --  @param Node Where the name was written.
      --  @param Arguments What the message says.
      --  @param Name The name, as the scope chain knows it.
      procedure Complain_Of_Candidates
        (Code      : Adash.Errors.Error_Code;
         Node      : S.Node_Id;
         Arguments : Adash.Messages.Argument_List;
         Name      : String);

      procedure Complain_Of_Candidates
        (Code      : Adash.Errors.Error_Code;
         Node      : S.Node_Id;
         Arguments : Adash.Messages.Argument_List;
         Name      : String)
      is
         Pool  : Adash.Language.Scopes.Symbol_List;
         Count : Natural := 0;

         Said : D.Diagnostic :=
           D.Make
              (Message   => Adash.Errors.Message (Code),
               Level     => D.Severity_Error,
               Of_Kind   => D.Category_Semantic,
               Raised_By => D.Owner_Language,
               Origin    => Origin,
               Extent    => S.Extent (Tree, Node),
               Arguments => Arguments);
      begin
         Legal := False;
         Chain.Candidates (Name, Pool, Count);

         for Index in 1 .. Count loop
            if not Adash.Source.Is_Empty (Symbols.Extent (Pool (Index))) then
               D.Add_Related
                 (Said,
                  (Origin  => Origin,
                   Extent  => Symbols.Extent (Pool (Index)),
                   Place   => (Line => 1, Column => 1),
                   Message => Adash.Messages.Msg_Note_Declared_Here));
            end if;
         end loop;

         Report.Emit (Said);
      end Complain_Of_Candidates;

      --  The type a type name denotes, or Type_None when it is not a type.
      function Number_Type (Node : S.Node_Id) return Types.Type_Kind is
         Name_Node : constant S.Node_Id := S.First (Tree, Node);
         Name      : constant String := S.Text (Tree, Name_Node);
         Value     : constant S.Node_Id := S.Third (Tree, Node);

         Spelling : Ada.Strings.Unbounded.Unbounded_String;
         Found    : Types.Type_Kind;
      begin
         if not S.Is_Present (Value) then
            Complain (Adash.Errors.Error_Number_Not_A_Literal, Name_Node,
                      [1 => Adash.Messages.Named ("name", Name)]);
            return Types.Type_None;
         end if;

         Found := Analyse_Expression (Value);

         if Found = Types.Type_None then
            return Types.Type_None;
         end if;

         if not Types.Is_Numeric (Found) then
            --  Ada's named number is a number. A Boolean or a text with no
            --  type mark in front of it is a declaration missing its type
            --  rather than a named number, and saying which is the useful
            --  half.
            Complain (Adash.Errors.Error_Number_Not_Numeric, Value,
                      [Adash.Messages.Named ("name", Name),
                       Adash.Messages.Named ("found", Types.Name (Found))]);
            return Types.Type_None;
         end if;

         if not Static_Default (Into, Tree, Value, Found, Spelling) then
            Complain (Adash.Errors.Error_Number_Not_A_Literal, Value,
                      [1 => Adash.Messages.Named ("name", Name)]);
            return Types.Type_None;
         end if;

         return Found;
      end Number_Type;

      function Named_Type (Node : S.Node_Id) return Types.Type_Kind is
      begin
         --  `A : array (1 .. 3) of Integer;`. The type is written where its
         --  name would stand, so it is declared here -- at the point the
         --  object is declared, which is where Ada elaborates it too -- and
         --  then read back under the name the parser gave it.
         if S.Kind (Tree, Node) = S.Node_Array_Declaration then
            Analyse_Statement (Node);
            return Named_Type (S.First (Tree, Node));
         end if;

         declare
            Name  : constant String := S.Text (Tree, Node);
            Found : constant Symbols.Symbol := Visible (Name);
         begin
            if Symbols.Is_Nothing (Found) then
               Complain (Adash.Errors.Error_Name_Undeclared, Node,
                         [1 => Adash.Messages.Named ("name", Name)]);
               return Types.Type_None;
            end if;

            if Symbols.Kind (Found) /= Symbols.Symbol_Type then
               Complain (Adash.Errors.Error_Not_A_Type, Node,
                         [1 => Adash.Messages.Named ("name", Name)]);
               return Types.Type_None;
            end if;

            Note (Node, Symbols.Of_Type (Found), Found);
            return Symbols.Of_Type (Found);
         end;
      end Named_Type;

      --  Report a declaration the scope chain refused.
      --
      --  "X is already declared" is only actionable if the reader is told
      --  where the other one is. The chain has that place as a span and
      --  cannot say it in words -- what turns a span into a line is the
      --  buffer -- so it comes across as a related location, and the engine
      --  gives it a line once it has the text in front of it.
      --
      --  @param Refused What the chain said.
      --  @param At_Node Where this declaration is.
      procedure Refuse_Declaration
        (Refused : Adash.Errors.Error_Info; At_Node : S.Node_Id);

      procedure Refuse_Declaration
        (Refused : Adash.Errors.Error_Info; At_Node : S.Node_Id)
      is
         Earlier : constant Adash.Source.Span := Chain.Clashed_At;

         Said : D.Diagnostic :=
           D.From_Error
             (Refused, D.Severity_Error, D.Category_Semantic,
              D.Owner_Language, Origin, S.Extent (Tree, At_Node));
      begin
         if not Adash.Source.Is_Empty (Earlier) then
            D.Add_Related
              (Said,
               (Origin  => Origin,
                Extent  => Earlier,
                Place   => (Line => 1, Column => 1),
                Message => Adash.Messages.Msg_Note_Declared_Here));
         end if;

         Report.Emit (Said);
      end Refuse_Declaration;

      --  Report an operator that has no definition for these operands, unless
      --  one of them is already unknown -- a cascade of errors derived from
      --  one unknown type tells a user nothing.
      procedure Undefined_Operator
        (Node        : S.Node_Id;
         Op          : S.Operation;
         Left, Right : Types.Type_Kind)
      is
      begin
         if Left = Types.Type_None or else Right = Types.Type_None then
            Legal := False;
            return;
         end if;

         Complain (Adash.Errors.Error_Operator_Not_Defined, Node,
                   [Adash.Messages.Named ("operator", S.Spelling (Op)),
                    Adash.Messages.Named ("left", Types.Name (Left)),
                    Adash.Messages.Named ("right", Types.Name (Right))]);
      end Undefined_Operator;

      ------------------------
      -- Analyse_Expression --
      ------------------------

      function Analyse_Expression
        (Node     : S.Node_Id;
         Expected : Types.Type_Kind := Types.Type_None) return Types.Type_Kind
      is
      begin
         case S.Kind (Tree, Node) is
            when S.Node_Integer_Literal =>
               Note (Node, Types.Type_Integer);
               return Types.Type_Integer;

            when S.Node_Real_Literal =>
               Note (Node, Types.Type_Float);
               return Types.Type_Float;

            when S.Node_Character_Literal =>
               Note (Node, Types.Type_Character);
               return Types.Type_Character;

            when S.Node_String_Literal =>
               Note (Node, Types.Type_String);
               return Types.Type_String;

            when S.Node_Name =>
               declare
                  Name  : constant String := S.Text (Tree, Node);
                  Found : constant Symbols.Symbol := Visible (Name);
               begin
                  if Symbols.Is_Nothing (Found) then
                     Complain (Adash.Errors.Error_Name_Undeclared, Node,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     return Types.Type_None;
                  end if;

                  --  A type name is not a value. `X := Integer` parses and is
                  --  not legal, and telling the two apart is what Symbol_Type
                  --  is for.
                  --
                  --  Said as what it is rather than as its opposite: this
                  --  reported that a type was *not* a type, which is the same
                  --  complaint a misspelled type mark gets and reads as
                  --  nonsense here -- `Counter.Bump` for a protected type
                  --  Counter is a program that wants an object, and being told
                  --  Counter is not a type helps nobody.
                  if Symbols.Kind (Found) = Symbols.Symbol_Type then
                     Complain (Adash.Errors.Error_Is_A_Type, Node,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     return Types.Type_None;
                  end if;

                  --  An enumeration literal may be one of several: two types
                  --  may each name a Red, and which is meant is what the
                  --  context expects. Ada settles it the way it settles a
                  --  call to two functions differing only in what they
                  --  return, because a literal *is* such a function -- and
                  --  the plain lookup above answers with whichever type was
                  --  declared last, which is nobody's intention.
                  if Symbols."=" (Symbols.Kind (Found),
                                  Symbols.Symbol_Literal)
                  then
                     declare
                        Pool  : Adash.Language.Scopes.Symbol_List;
                        Named : Natural;
                        Fits  : Natural := 0;
                        Taken : Symbols.Symbol := Symbols.Nothing;
                     begin
                        Chain.Candidates (Visible_Name (Name), Pool, Named);

                        if Named > 1 then
                           for Index in 1 .. Named loop
                              if Symbols."=" (Symbols.Kind (Pool (Index)),
                                              Symbols.Symbol_Literal)
                                and then Expected /= Types.Type_None
                                and then Symbols.Of_Type (Pool (Index))
                                         = Expected
                              then
                                 Fits := Fits + 1;

                                 if Fits = 1 then
                                    Taken := Pool (Index);
                                 end if;
                              end if;
                           end loop;

                           if Fits /= 1 and then Expected = Types.Type_None
                           then
                              --  Nothing here says which. Ada's answer as
                              --  well: a literal named by two types and used
                              --  where either would do is ambiguous, and
                              --  taking one of them silently would make the
                              --  program mean whichever was written last.
                              Complain_Of_Candidates
                                (Adash.Errors.Error_Ambiguous_Literal, Node,
                                 [Adash.Messages.Named ("name", Name),
                                  Adash.Messages.Named
                                    ("count", Natural'Image (Named))],
                                 Visible_Name (Name));
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           --  Something was expected and no declaration of
                           --  this name has that type. What is wrong is the
                           --  type rather than the choice, so the answer is
                           --  the ordinary mismatch, said about one of them
                           --  and against what the context asked for.

                           Note (Node, Symbols.Of_Type (Taken), Taken);
                           return Symbols.Of_Type (Taken);
                        end if;
                     end;
                  end if;

                  --  A bare name denoting a subprogram is a call with no
                  --  arguments, and with overloading the plain lookup above
                  --  answers with whichever was declared last. `G` alongside
                  --  `G (Integer)` resolved to the second, and the call went
                  --  out one argument short.
                  if Symbols.Is_Callable (Found) then
                     declare
                        Offered : Natural;
                        Fitting : Natural;
                        Taken   : Symbols.Symbol;
                     begin
                        Resolve_Call (Name, S.No_Node, 0, Expected,
                                      Offered, Fitting, Taken);

                        if Fitting = 1 then
                           Note (Node, Symbols.Of_Type (Taken), Taken);
                           return Symbols.Of_Type (Taken);
                        end if;

                        if Offered > 1 then
                           --  Several subprograms of this name take no
                           --  arguments, and nothing here says which is meant.
                           --  Falling through would have taken whichever was
                           --  declared last, silently.
                           Complain_Of_Candidates
                             ((if Fitting = 0
                               then Adash.Errors.Error_No_Matching_Subprogram
                               else Adash.Errors.Error_Ambiguous_Call),
                              Node,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("count",
                                  Natural'Image (if Fitting = 0 then Offered
                                                 else Fitting))],
                              Visible_Name (Name));
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        --  One candidate, and it wants arguments this
                        --  reference does not give. Falling through answered
                        --  with its result type, and the shortfall surfaced
                        --  from the lowering as a call this build cannot run
                        --  -- which is not what is wrong with it. The
                        --  statement form of the same mistake, `Put_Line;`,
                        --  was already reported; the expression form,
                        --  `S : String := Env_Value;`, was not.
                        declare
                           About : constant Signature :=
                             Signature_Of (Name, Found);
                        begin
                           if About.Known and then About.Minimum > 0 then
                              Complain
                                (Adash.Errors.Error_Wrong_Argument_Count, Node,
                                 [Adash.Messages.Named ("name", Name),
                                  Adash.Messages.Named
                                    ("expected", Accepts (About)),
                                  Adash.Messages.Named
                                    ("found", Natural'Image (0))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;
                        end;
                     end;
                  end if;

                  Note (Node, Symbols.Of_Type (Found), Found);
                  return Symbols.Of_Type (Found);
               end;

            when S.Node_Parenthesized =>
               declare
                  --  Parentheses group; they do not change what the context
                  --  requires, so the expectation goes straight through.
                  Inner : constant Types.Type_Kind :=
                    Analyse_Expression (S.First (Tree, Node), Expected);
               begin
                  Note (Node, Inner);
                  return Inner;
               end;

            when S.Node_Unary_Operation =>
               declare
                  Op      : constant S.Operation := S.Operator (Tree, Node);

                  --  `-X` and `abs X` have the type of what they are applied
                  --  to, so what the context requires of the whole is what it
                  --  requires of the operand.
                  --
                  --  `not` is Boolean either way -- which is a statement about
                  --  its *operand* as much as about its result, and requiring
                  --  it is what settles a name several declarations could
                  --  answer. Passing nothing down instead left `not F` unable
                  --  to choose between the F that yields a Boolean and the
                  --  ones that do not, in a place where only one of them can
                  --  be meant.
                  --
                  --  A sign with nothing required of it says only that its
                  --  operand is numeric, and that rules out the readings which
                  --  are not: when one numeric reading is left, it is the one.
                  Sign_Wants : constant Types.Type_Kind :=
                    (if Op in S.Op_Plus | S.Op_Minus | S.Op_Abs
                       and then Expected = Types.Type_None
                     then Only_Numeric (S.First (Tree, Node))
                     else Expected);

                  Operand : constant Types.Type_Kind :=
                    Analyse_Expression
                      (S.First (Tree, Node),
                       (if Op in S.Op_Plus | S.Op_Minus | S.Op_Abs
                        then Sign_Wants
                        elsif Op = S.Op_Not then Types.Type_Boolean
                        else Types.Type_None));
                  Result  : Types.Type_Kind := Types.Type_None;
               begin
                  case Op is
                     when S.Op_Plus | S.Op_Minus | S.Op_Abs =>
                        if Types.Is_Numeric (Operand) then
                           Result := Operand;
                        end if;

                     when S.Op_Not =>
                        if Operand = Types.Type_Boolean then
                           Result := Types.Type_Boolean;
                        end if;

                     when others =>
                        null;
                  end case;

                  if Result = Types.Type_None then
                     Undefined_Operator (Node, Op, Operand, Operand);
                  end if;

                  Note (Node, Result);
                  return Result;
               end;

            when S.Node_Named_Argument =>
               --  A named argument is its value, as far as a type is
               --  concerned. Which parameter it belongs to is settled by
               --  Match_Arguments, against a callee this does not know.
               declare
                  Of_Value : constant Types.Type_Kind :=
                    Analyse_Expression (S.Second (Tree, Node), Expected);
               begin
                  Note (Node, Of_Value, Into.Symbol_Of (S.Second (Tree, Node)));
                  return Of_Value;
               end;

            when S.Node_Selected =>
               declare
                  Prefix : constant S.Node_Id := S.First (Tree, Node);
                  Field  : constant S.Node_Id := S.Second (Tree, Node);
                  Name   : constant String := S.Text (Tree, Field);
               begin
                  --  `A.E` where A is a task object. An entry belongs to the
                  --  *type*, because several objects of one task type are
                  --  several tasks that share it, so the entry is looked up
                  --  under the type's name rather than the object's -- and for
                  --  `task T`, whose type is named after it, that is the same
                  --  lookup written once.
                  --
                  --  The object's own symbol is left on the prefix, because
                  --  what a rendezvous has to find is the task rather than the
                  --  entry: the entry says which queue, the object says whose.
                  declare
                     Object : constant Symbols.Symbol :=
                       (if S.Kind (Tree, Prefix) = S.Node_Name
                        then Visible (S.Text (Tree, Prefix))
                        else Symbols.Nothing);
                  begin
                     if Types.Is_Task (Symbols.Of_Type (Object)) then
                        declare
                           Of_Entry : constant Symbols.Symbol :=
                             Visible (Name_For_Call (Node));
                        begin
                           if Symbols.Kind (Of_Entry) = Symbols.Symbol_Entry
                           then
                              Note_Task_Object (Node);
                              Note (Node, Types.Type_None, Of_Entry);
                              return Types.Type_None;
                           end if;

                           --  A task holds nothing a program can reach into:
                           --  what it has is entries, and this is not one.
                           --  Said here rather than left to the record path,
                           --  which would report that a task has no
                           --  components -- true, and about the wrong thing.
                           Complain
                             (Adash.Errors.Error_Not_An_Entry, Node,
                              [1 => Adash.Messages.Named
                                      ("name", Dotted (Tree, Node))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end;
                     end if;
                  end;

                  --  `P.X` where P is a package is a *name*, not a reach into
                  --  a value: what a package holds is declared beside it under
                  --  a dotted name, so this resolves one symbol. Checked first
                  --  because analysing the prefix as an expression would
                  --  report that a package is not a value, which is true and
                  --  unhelpful.
                  declare
                     Whole : constant String := Dotted (Tree, Node);
                  begin
                     if Whole /= "" then
                        declare
                           Found : constant Symbols.Symbol := Visible (Whole);
                        begin
                           if not Symbols.Is_Nothing (Found) then
                              Note (Node, Symbols.Of_Type (Found), Found);
                              return Symbols.Of_Type (Found);
                           end if;

                           if Symbols.Kind (Visible (S.Text (Tree, Prefix)))
                              = Symbols.Symbol_Package
                           then
                              Complain
                                (Adash.Errors.Error_Name_Undeclared, Node,
                                 [1 => Adash.Messages.Named
                                         ("name", Whole)]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;
                        end;
                     end if;
                  end;

                  declare
                     Of_Prefix : constant Types.Type_Kind :=
                       Analyse_Expression (Prefix);
                  begin
                        if Of_Prefix = Types.Type_None then
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        if Types.Shape (Of_Prefix) /= Types.Shape_Record then
                           Complain (Adash.Errors.Error_Not_A_Record, Node,
                                     [Adash.Messages.Named ("name", Name),
                                      Adash.Messages.Named
                                        ("found", Types.Name (Of_Prefix))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        declare
                           Which : constant Natural :=
                             Part_At (Into, Of_Prefix, Name);
                        begin
                           if Which = 0 then
                              Complain
                                (Adash.Errors.Error_No_Such_Component, Field,
                                 [Adash.Messages.Named ("name", Name),
                                  Adash.Messages.Named
                                    ("found", Types.Name (Of_Prefix))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           --  The component's own symbol travels with the node, so
                           --  assignment can ask whether what it names may be
                           --  written -- a component of a variable may, a component
                           --  of a constant may not, and the answer is the
                           --  variable's.
                           Note (Node, Part_Type (Into, Of_Prefix, Which),
                                 Into.Symbol_Of (Prefix));
                           return Part_Type (Into, Of_Prefix, Which);
                        end;
                  end;
               end;

            when S.Node_Aggregate =>
               declare
                  Values : constant S.Node_Id := S.First (Tree, Node);
                  Given  : constant Natural := S.Child_Count (Tree, Values);
                  Wanted : constant Natural := Part_Count (Into, Expected);
               begin
                  --  An aggregate has no type of its own: what it builds is
                  --  what the context asked for. Ada says the same, and it is
                  --  why one cannot stand where nothing is expected.
                  if not Types.Is_Composite (Expected) then
                     Complain
                       (Adash.Errors.Error_Aggregate_Not_Expected, Node,
                        [1 => Adash.Messages.Named
                                ("found", Types.Name (Expected))]);

                     for Index in 1 .. Given loop
                        declare
                           Ignored : constant Types.Type_Kind :=
                             Analyse_Expression (S.Child (Tree, Values, Index));
                           pragma Unreferenced (Ignored);
                        begin
                           null;
                        end;
                     end loop;

                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  --  A positional aggregate says how many it has by how many
                  --  it writes. One that names its parts does not, so the
                  --  counting is done afterwards, over what was covered.
                  declare
                     Names_Any : Boolean := False;
                  begin
                     for Index in 1 .. Given loop
                        if S.Kind (Tree, S.Child (Tree, Values, Index))
                           = S.Node_Named_Argument
                        then
                           Names_Any := True;
                        end if;
                     end loop;

                     if not Names_Any and then Given /= Wanted then
                        Complain
                          (Adash.Errors.Error_Aggregate_Wrong_Count, Node,
                           [Adash.Messages.Named
                              ("name", Types.Name (Expected)),
                            Adash.Messages.Named
                              ("expected", Natural'Image (Wanted)),
                            Adash.Messages.Named
                              ("found", Natural'Image (Given))]);
                        Note (Node, Types.Type_None);
                        return Types.Type_None;
                     end if;
                  end;

                  --  Positional, or named against the record's components.
                  --  The same shape a call takes, and told apart the same way.
                  declare
                     --  Which value filled each part, so that a part given
                     --  twice can point at the first one rather than only
                     --  saying that there was one.
                     Filled : array (1 .. Wanted) of S.Node_Id :=
                       [others => S.No_Node];
                     Naming : Boolean := False;
                     Sound  : Boolean := True;

                     --  What `others` gives to every part nothing else named.
                     Rest : S.Node_Id := S.No_Node;
                  begin
                     for Index in 1 .. Given loop
                        declare
                           One : constant S.Node_Id :=
                             S.Child (Tree, Values, Index);
                           Slot : Natural := Index;
                           Value : S.Node_Id := One;
                        begin
                           if S.Kind (Tree, One) = S.Node_Named_Argument
                             and then S.Kind (Tree, S.First (Tree, One))
                                      = S.Node_Others
                           then
                              --  The rest of them, whatever is left. Last,
                              --  because it says what nothing else said.
                              Naming := True;
                              Value  := S.Second (Tree, One);
                              Slot   := 0;
                              Rest   := Value;

                              if Index /= Given then
                                 Complain
                                   (Adash.Errors.Error_Case_Others_Not_Last,
                                    One, Adash.Messages.No_Arguments);
                                 Sound := False;
                              end if;

                           elsif S.Kind (Tree, One) = S.Node_Named_Argument
                             and then Types.Shape (Expected)
                                      = Types.Shape_Array
                           then
                              --  An array names a part by its index, which is
                              --  a value this build has to know before it
                              --  runs: the slot it fills is decided here.
                              declare
                                 Choice : constant S.Node_Id :=
                                   S.First (Tree, One);
                                 Where  : Long_Long_Integer;

                                 --  A run of them, `1 .. 3 => 0`, which fills
                                 --  every slot between its ends. `X'Range` is
                                 --  written as one of these by the parser,
                                 --  because that is what it stands for.
                                 Spread : constant Boolean :=
                                   S.Kind (Tree, Choice) = S.Node_Range;

                                 --  Looked at before it is asked about: an
                                 --  index may be written as an attribute --
                                 --  `Counts'First` -- and what makes that a
                                 --  value known before the program runs is
                                 --  what it denotes.
                                 Of_Choice : constant Types.Type_Kind :=
                                   (if Spread then Types.Type_Integer
                                    else Analyse_Expression (Choice));
                              begin
                                 if Spread then
                                    declare
                                       Ignored : constant Types.Type_Kind :=
                                         Analyse_Expression
                                           (S.First (Tree, Choice));
                                       Second  : constant Types.Type_Kind :=
                                         Analyse_Expression
                                           (S.Second (Tree, Choice));
                                       pragma Unreferenced (Ignored, Second);
                                    begin
                                       null;
                                    end;
                                 end if;

                                 Naming := True;
                                 Value  := S.Second (Tree, One);
                                 Slot   := 0;

                                 if Spread then
                                    --  Every slot the run covers. Each is
                                    --  filled once, so a run that overlaps
                                    --  another is caught the same way a
                                    --  repeated index is.
                                    declare
                                       Low, High : Long_Long_Integer;
                                       Base : constant Long_Long_Integer :=
                                         First_Index (Into, Expected);
                                    begin
                                       if not Static_Choice
                                                (Into, Tree,
                                                 S.First (Tree, Choice), Low)
                                         or else not Static_Choice
                                                       (Into, Tree,
                                                        S.Second (Tree,
                                                                  Choice),
                                                        High)
                                       then
                                          Complain
                                            (Adash.Errors.Error_Case_Choice_Not_Static,
                                             Choice,
                                             Adash.Messages.No_Arguments);
                                          Sound := False;

                                       elsif Low < Base
                                         or else High > Base
                                                 + Long_Long_Integer (Wanted)
                                                 - 1
                                       then
                                          Complain
                                            (Adash.Errors.Error_No_Such_Component,
                                             One,
                                             [Adash.Messages.Named
                                                ("name",
                                                 Long_Long_Integer'Image
                                                   (if Low < Base then Low
                                                    else High)),
                                              Adash.Messages.Named
                                                ("found",
                                                 Types.Name (Expected))]);
                                          Sound := False;

                                       else
                                          for Each in Low .. High loop
                                             declare
                                                Here : constant Natural :=
                                                  Natural (Each - Base) + 1;
                                             begin
                                                if S.Is_Present (Filled (Here))
                                                then
                                                   Complain
                                                     (Adash.Errors.Error_Part_Given_Twice,
                                                      One,
                                                      [1 => Adash.Messages.Named
                                                              ("name",
                                                               Long_Long_Integer'Image
                                                                 (Each))],
                                                      Also      => Filled (Here),
                                                      Also_Says =>
                                                        Adash.Messages
                                                          .Msg_Note_First_Here);
                                                   Sound := False;
                                                else
                                                   Filled (Here) := One;
                                                end if;
                                             end;
                                          end loop;

                                          --  Analysed once, against what the
                                          --  parts hold: one value goes into
                                          --  every slot the run covers.
                                          declare
                                             Holds : constant Types.Type_Kind :=
                                               Part_Type (Into, Expected, 1);
                                             Found : constant Types.Type_Kind :=
                                               Analyse_Expression (Value,
                                                                   Holds);
                                          begin
                                             if Found /= Types.Type_None
                                               and then not Types.Is_Acceptable
                                                              (Found, Holds)
                                             then
                                                Complain
                                                  (Adash.Errors.Error_Type_Mismatch,
                                                   Value,
                                                   [Adash.Messages.Named
                                                      ("found",
                                                       Types.Name (Found)),
                                                    Adash.Messages.Named
                                                      ("expected",
                                                       Types.Name (Holds))]);
                                             end if;
                                          end;
                                       end if;
                                    end;

                                    Slot := 0;

                                 elsif Of_Choice = Types.Type_None then
                                    --  Already reported as whatever it is.
                                    Sound := False;

                                 elsif not Static_Choice (Into, Tree, Choice,
                                                          Where)
                                 then
                                    Complain
                                      (Adash.Errors.Error_Case_Choice_Not_Static,
                                       Choice, Adash.Messages.No_Arguments);
                                    Sound := False;

                                 elsif Where < First_Index (Into, Expected)
                                   or else Where
                                           > First_Index (Into, Expected)
                                             + Long_Long_Integer (Wanted) - 1
                                 then
                                    Complain
                                      (Adash.Errors.Error_No_Such_Component,
                                       One,
                                       [Adash.Messages.Named
                                          ("name",
                                           Long_Long_Integer'Image (Where)),
                                        Adash.Messages.Named
                                          ("found", Types.Name (Expected))]);
                                    Sound := False;
                                 else
                                    Slot :=
                                      Natural (Where
                                               - First_Index (Into, Expected))
                                      + 1;

                                    if S.Is_Present (Filled (Slot)) then
                                       Complain
                                         (Adash.Errors.Error_Part_Given_Twice,
                                          One,
                                          [1 => Adash.Messages.Named
                                                  ("name",
                                                   Long_Long_Integer'Image (Where))],
                                          Also      => Filled (Slot),
                                          Also_Says =>
                                            Adash.Messages.Msg_Note_First_Here);
                                       Sound := False;
                                    end if;
                                 end if;
                              end;

                           elsif S.Kind (Tree, One) = S.Node_Named_Argument
                           then
                              Naming := True;
                              Value  := S.Second (Tree, One);
                              Slot   :=
                                Part_At
                                  (Into, Expected,
                                   S.Text (Tree, S.First (Tree, One)));

                              if Slot = 0 then
                                 Complain
                                   (Adash.Errors.Error_No_Such_Component, One,
                                    [Adash.Messages.Named
                                       ("name",
                                        S.Text (Tree, S.First (Tree, One))),
                                     Adash.Messages.Named
                                       ("found", Types.Name (Expected))]);
                                 Sound := False;
                              elsif S.Is_Present (Filled (Slot)) then
                                 Complain
                                   (Adash.Errors.Error_Part_Given_Twice, One,
                                    [1 => Adash.Messages.Named
                                            ("name",
                                             Part_Name
                                               (Into, Expected, Slot))],
                                    Also      => Filled (Slot),
                                    Also_Says =>
                                      Adash.Messages.Msg_Note_First_Here);
                                 Sound := False;
                              end if;

                           elsif Naming then
                              Complain
                                (Adash.Errors.Error_Positional_After_Named,
                                 One,
                                 [1 => Adash.Messages.Named
                                         ("name", Types.Name (Expected))]);
                              Sound := False;
                           end if;

                           if Sound and then Slot in 1 .. Wanted then
                              Filled (Slot) := One;

                              declare
                                 Holds : constant Types.Type_Kind :=
                                   Part_Type (Into, Expected, Slot);
                                 Found : constant Types.Type_Kind :=
                                   Analyse_Expression (Value, Holds);
                              begin
                                 if Found /= Types.Type_None
                                   and then not Types.Is_Acceptable
                                                  (Found, Holds)
                                 then
                                    Complain
                                      (Adash.Errors.Error_Type_Mismatch,
                                       Value,
                                       [Adash.Messages.Named
                                          ("found", Types.Name (Found)),
                                        Adash.Messages.Named
                                          ("expected", Types.Name (Holds))]);
                                 end if;
                              end;
                           end if;
                        end;
                     end loop;

                     --  What `others` covers, and what nothing covers. A part
                     --  with no value would be read as whatever its slot
                     --  happened to hold, which is the defect an aggregate
                     --  exists to prevent.
                     if S.Is_Present (Rest) then
                        declare
                           Left : Natural := 0;
                        begin
                           for Index in Filled'Range loop
                              if not S.Is_Present (Filled (Index)) then
                                 Left := Left + 1;
                                 Filled (Index) := Rest;
                              end if;
                           end loop;

                           if Left = 0 then
                              --  Every part was named, so `others` answers for
                              --  nothing and its value would never be read.
                              Complain
                                (Adash.Errors.Error_Aggregate_Others_Covers_Nothing,
                                 Rest, Adash.Messages.No_Arguments);
                           end if;
                        end;

                        declare
                           Holds : constant Types.Type_Kind :=
                             Part_Type (Into, Expected, 1);
                           Found : constant Types.Type_Kind :=
                             Analyse_Expression (Rest, Holds);
                        begin
                           if Found /= Types.Type_None
                             and then not Types.Is_Acceptable (Found, Holds)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, Rest,
                                 [Adash.Messages.Named
                                    ("found", Types.Name (Found)),
                                  Adash.Messages.Named
                                    ("expected", Types.Name (Holds))]);
                           end if;
                        end;
                     end if;

                     if Sound and then Naming then
                        declare
                           Covered : Natural := 0;
                        begin
                           for Index in Filled'Range loop
                              if S.Is_Present (Filled (Index)) then
                                 Covered := Covered + 1;
                              end if;
                           end loop;

                           if Covered /= Wanted then
                              Complain
                                (Adash.Errors.Error_Aggregate_Wrong_Count,
                                 Node,
                                 [Adash.Messages.Named
                                    ("name", Types.Name (Expected)),
                                  Adash.Messages.Named
                                    ("expected", Natural'Image (Wanted)),
                                  Adash.Messages.Named
                                    ("found", Natural'Image (Covered))]);
                           end if;
                        end;
                     end if;
                  end;

                  Note (Node, Expected);
                  return Expected;
               end;

            when S.Node_Membership =>
               --  Two children is a type mark, `X in Small`, and the bounds
               --  are then the type's own. The name settles the value here
               --  rather than the other way round: a type mark is not in
               --  doubt, so it is what an open call on the left resolves
               --  against.
               if S.Child_Count (Tree, Node) = 2 then
                  declare
                     Marked : constant Types.Type_Kind :=
                       Named_Type (S.Second (Tree, Node));

                     Value : constant Types.Type_Kind :=
                       Analyse_Expression (S.First (Tree, Node), Marked);
                  begin
                     if Marked /= Types.Type_None
                       and then not Types.Is_Discrete (Marked)
                     then
                        --  What the check compares is two bounds, and a type
                        --  with no first value has none to compare against.
                        --  Ada admits `X in Float`, where the answer is always
                        --  True; this refuses it rather than emitting a test
                        --  that cannot fail.
                        Complain
                          (Adash.Errors.Error_Case_Not_Discrete,
                           S.Second (Tree, Node),
                           [1 => Adash.Messages.Named
                                   ("found", Types.Name (Marked))]);

                     elsif Marked /= Types.Type_None
                       and then Value /= Types.Type_None
                       and then not Types.Is_Acceptable (Value, Marked)
                     then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch,
                           S.First (Tree, Node),
                           [Adash.Messages.Named ("found", Types.Name (Value)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Marked))]);
                     end if;

                     Note (Node, Types.Type_Boolean);
                     return Types.Type_Boolean;
                  end;
               end if;

               declare
                  --  The value settles the bounds, not the other way round.
                  --  `X in 1 .. 5` where X is a Character has two Integer
                  --  bounds to complain about, and complaining about X instead
                  --  would name the one thing that is not in doubt.
                  --
                  --  Unless the value is the one in doubt: a name several
                  --  declarations could answer is settled by the bound, which
                  --  is the rule the comparisons use and for the same reason.
                  --  Only when exactly one of the two is open, because two
                  --  open ends say nothing about each other.
                  Settle_From_Bound : constant Boolean :=
                    Is_Open_Call (S.First (Tree, Node))
                      and then not Is_Open_Call (S.Second (Tree, Node));

                  Bound_First : constant Types.Type_Kind :=
                    (if Settle_From_Bound
                     then Analyse_Expression (S.Second (Tree, Node))
                     else Types.Type_None);

                  Value : constant Types.Type_Kind :=
                    Analyse_Expression (S.First (Tree, Node), Bound_First);

                  Low  : constant Types.Type_Kind :=
                    (if Settle_From_Bound then Bound_First
                     else Analyse_Expression (S.Second (Tree, Node), Value));
                  High : constant Types.Type_Kind :=
                    Analyse_Expression (S.Third (Tree, Node), Value);
               begin
                  if Value /= Types.Type_None then
                     if not Types.Is_Acceptable (Low, Value) then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch,
                           S.Second (Tree, Node),
                           [Adash.Messages.Named ("found", Types.Name (Low)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Value))]);
                     end if;

                     if not Types.Is_Acceptable (High, Value) then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch,
                           S.Third (Tree, Node),
                           [Adash.Messages.Named ("found", Types.Name (High)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Value))]);
                     end if;
                  end if;

                  Note (Node, Types.Type_Boolean);
                  return Types.Type_Boolean;
               end;

            when S.Node_Binary_Operation =>
               declare
                  Op : constant S.Operation := S.Operator (Tree, Node);

                  --  An operator whose result is its operands' type passes the
                  --  context's requirement down to both: `S : String := F &
                  --  "!"` requires a String of the whole and therefore of F.
                  --
                  --  A comparison does not. Its result is Boolean and its
                  --  operands are not, so requiring Boolean of them would
                  --  resolve them to the wrong thing rather than to nothing.
                  Wanted : constant Types.Type_Kind :=
                    (if Op in S.Op_And | S.Op_Or | S.Op_Xor | S.Op_And_Then
                            | S.Op_Or_Else
                     then
                       --  Boolean on both sides, whatever the context says --
                       --  and where it says nothing, this is what settles a
                       --  name several declarations could answer. In this
                       --  subset there is nothing else `and` applies to.
                       Types.Type_Boolean
                     elsif Op in S.Op_Multiply | S.Op_Divide | S.Op_Add
                            | S.Op_Subtract | S.Op_Mod | S.Op_Rem
                            | S.Op_Power | S.Op_Concat
                     then Expected else Types.Type_None);

                  --  A comparison's operands have each other's type, even
                  --  though neither has the comparison's. So when exactly one
                  --  of them is a call that several subprograms could answer,
                  --  the other is analysed first and its type is what settles
                  --  it -- which is how Ada reads `if F = 1`.
                  --
                  --  Only when exactly one is open. Two ambiguous operands say
                  --  nothing about each other, and neither does the operator,
                  --  so the call stays ambiguous and is reported as such.
                  --  The same rule for the operators whose result *is* their
                  --  operands' type, and for the same reason: when the
                  --  context requires nothing, what the closed operand turns
                  --  out to be is the only thing that can settle the open one.
                  --  `put_line (F & "x")` reads that way and no other.
                  Settle_Right_First : constant Boolean :=
                    Is_Open_Call (S.First (Tree, Node))
                      and then not Is_Open_Call (S.Second (Tree, Node))
                      and then
                        (Op in S.Op_Equal | S.Op_Not_Equal | S.Op_Less
                             | S.Op_Less_Equal | S.Op_Greater
                             | S.Op_Greater_Equal
                         or else (Wanted = Types.Type_None
                                  and then Op in S.Op_Multiply | S.Op_Divide
                                               | S.Op_Add | S.Op_Subtract
                                               | S.Op_Mod | S.Op_Rem
                                               | S.Op_Power | S.Op_Concat
                                               | S.Op_And | S.Op_Or | S.Op_Xor
                                               | S.Op_And_Then
                                               | S.Op_Or_Else));

                  --  Both ends open, and neither says anything about the
                  --  other by being analysed first. What settles it is that
                  --  only one type is possible for both: `F = G` where each
                  --  names two subprograms and they share one result, or a
                  --  literal two enumerations name beside one only one of
                  --  them names. Asked without choosing, so nothing is
                  --  reported for an expression that is about to be resolved.
                  Between : constant Types.Type_Kind :=
                    (if Op in S.Op_Equal | S.Op_Not_Equal | S.Op_Less
                            | S.Op_Less_Equal | S.Op_Greater
                            | S.Op_Greater_Equal
                       and then Is_Open_Call (S.First (Tree, Node))
                       and then Is_Open_Call (S.Second (Tree, Node))
                     then Shared_Type (S.First (Tree, Node),
                                       S.Second (Tree, Node))
                     else Types.Type_None);

                  --  Evaluated in the order the two declarations are written,
                  --  which is what chooses which operand goes first.
                  First_Type : constant Types.Type_Kind :=
                    (if Between /= Types.Type_None
                     then Analyse_Expression (S.First (Tree, Node), Between)
                     elsif Settle_Right_First
                     then Analyse_Expression (S.Second (Tree, Node), Wanted)
                     else Analyse_Expression (S.First (Tree, Node), Wanted));

                  Second_Type : constant Types.Type_Kind :=
                    (if Between /= Types.Type_None
                     then Analyse_Expression (S.Second (Tree, Node), Between)
                     elsif Settle_Right_First
                     then Analyse_Expression
                            (S.First (Tree, Node),
                             Operand_Wanted
                               (Op, First_Type, S.First (Tree, Node)))
                     else Analyse_Expression
                            (S.Second (Tree, Node),
                             (if Op in S.Op_Equal | S.Op_Not_Equal | S.Op_Less
                                     | S.Op_Less_Equal | S.Op_Greater
                                     | S.Op_Greater_Equal
                              then First_Type
                              elsif Wanted = Types.Type_None
                              then Operand_Wanted
                                     (Op, First_Type, S.Second (Tree, Node))
                              else Wanted)));

                  Left  : constant Types.Type_Kind :=
                    (if Settle_Right_First and then Between = Types.Type_None
                     then Second_Type else First_Type);
                  Right : constant Types.Type_Kind :=
                    (if Settle_Right_First and then Between = Types.Type_None
                     then First_Type else Second_Type);
                  Result : Types.Type_Kind := Types.Type_None;
               begin
                  case Op is
                     when S.Op_Multiply | S.Op_Divide | S.Op_Add | S.Op_Subtract
                        | S.Op_Power =>
                        --  Both numeric and the same. There is no implicit
                        --  widening here, as Adash.Language.Types says: a
                        --  language that quietly converts has a rounding rule
                        --  nobody wrote down.
                        if Left = Right and then Types.Is_Numeric (Left) then
                           Result := Left;
                        end if;

                     when S.Op_Mod | S.Op_Rem =>
                        --  Integer only. Ada defines these for integer types;
                        --  Float has no remainder in this sense.
                        if Left = Types.Type_Integer
                          and then Right = Types.Type_Integer
                        then
                           Result := Types.Type_Integer;
                        end if;

                     when S.Op_Concat =>
                        --  Ada's rule for a one-dimensional array: two of them,
                        --  or one and a component. A String and a Character is
                        --  the second, and is what a loop building text out of
                        --  the characters it took apart writes.
                        if (Left = Types.Type_String
                            or else Left = Types.Type_Character)
                          and then (Right = Types.Type_String
                                    or else Right = Types.Type_Character)
                          and then not (Left = Types.Type_Character
                                        and then Right = Types.Type_Character)
                        then
                           --  Two Characters are refused, as Ada refuses them:
                           --  neither is an array, so there is nothing to say
                           --  which array type the result would be.
                           Result := Types.Type_String;
                        end if;

                     when S.Op_Equal | S.Op_Not_Equal =>
                        --  Any two values of one type may be compared for
                        --  equality, including Booleans.
                        if Left = Right and then Left /= Types.Type_None then
                           Result := Types.Type_Boolean;
                        end if;

                     when S.Op_Less | S.Op_Less_Equal | S.Op_Greater
                        | S.Op_Greater_Equal =>
                        if Left = Right and then Types.Is_Ordered (Left) then
                           Result := Types.Type_Boolean;
                        end if;

                     when S.Op_And | S.Op_Or | S.Op_Xor | S.Op_And_Then
                        | S.Op_Or_Else =>
                        if Left = Types.Type_Boolean
                          and then Right = Types.Type_Boolean
                        then
                           Result := Types.Type_Boolean;
                        end if;

                     when others =>
                        null;
                  end case;

                  if Result = Types.Type_None then
                     Undefined_Operator (Node, Op, Left, Right);
                  end if;

                  Note (Node, Result);
                  return Result;
               end;

            when S.Node_Call =>
               declare
                  Prefix    : constant S.Node_Id := S.First (Tree, Node);
                  Arguments : constant S.Node_Id := S.Second (Tree, Node);

                  --  The whole spelling, dots and all. `P.F (4)` calls one
                  --  subprogram whose name has a dot in it, because that is
                  --  what a package member's name is here.
                  Name      : constant String := Name_For_Call (Prefix);

                  Given : constant Natural := S.Child_Count (Tree, Arguments);

                  --  What the prefix denotes, when it denotes an object rather
                  --  than a subprogram. Ada writes indexing and calling the
                  --  same way, so this is the question that tells them apart --
                  --  and it has to be asked of the symbol rather than of the
                  --  text, because a parameter named after a function is a
                  --  parameter.
                  Prefixed : constant Symbols.Symbol :=
                    (if S.Kind (Tree, Prefix) = S.Node_Name
                     then Visible (Name) else Symbols.Nothing);

                  Indexes : constant Boolean :=
                    not Symbols.Is_Nothing (Prefixed)
                      and then not Symbols.Is_Callable (Prefixed)
                      and then Symbols.Of_Type (Prefixed) = Types.Type_String;

                  --  An array reached by position, which Ada also writes the
                  --  way a call is written. Told apart the same way: by what
                  --  the name denotes rather than by the shape of the text.
                  Subscripts : constant Boolean :=
                    not Symbols.Is_Nothing (Prefixed)
                      and then not Symbols.Is_Callable (Prefixed)
                      and then Types.Shape (Symbols.Of_Type (Prefixed))
                               = Types.Shape_Array;

                  --  A range where an argument would stand. A range is not an
                  --  expression and cannot be one, so a call cannot be meant.
                  Ranged : constant Boolean :=
                    Given = 1
                      and then S.Kind (Tree, S.Child (Tree, Arguments, 1))
                               = S.Node_Range;

                  --  A part of what an expression *yields*, rather than of
                  --  what a name denotes: `F (2 .. 4)` slices what a function
                  --  returned, and `S (2 .. 5) (1 .. 2)` slices a slice. Ada
                  --  takes both, and writes them the way it writes everything
                  --  else here.
                  --
                  --  Two shapes say so. A prefix that is itself a call has
                  --  already been decided -- whatever it yields is a value,
                  --  and a value is not called. A prefix that is a name for
                  --  something callable is a call *unless* what follows is a
                  --  range, which no call could take.
                  Yields_Part : constant Boolean :=
                    Given = 1
                      and then (S.Kind (Tree, Prefix) = S.Node_Call
                                or else (Ranged
                                         and then Symbols.Is_Callable
                                                    (Prefixed)));

                  --  The variable a chain of parts bottoms out at, or Nothing
                  --  when it bottoms out at a call. `S (2 .. 5) (1 .. 2)` is a
                  --  part of a part of S, and what may be assigned to is what
                  --  S may be -- so the symbol travels out with the part, as
                  --  it does for one level.
                  function Owner_Of (From : S.Node_Id) return Symbols.Symbol;

                  function Owner_Of (From : S.Node_Id) return Symbols.Symbol is
                     Walk : S.Node_Id := From;
                  begin
                     while S.Kind (Tree, Walk) = S.Node_Call loop
                        Walk := S.First (Tree, Walk);
                     end loop;

                     if S.Kind (Tree, Walk) /= S.Node_Name then
                        return Symbols.Nothing;
                     end if;

                     declare
                        Found : constant Symbols.Symbol :=
                          Visible (S.Text (Tree, Walk));
                     begin
                        --  A String or an array: the two things here with
                        --  parts, and the two a chain of parts can bottom out
                        --  at. Anything else is a value and owns nothing.
                        if Symbols.Is_Nothing (Found)
                          or else Symbols.Is_Callable (Found)
                          or else (Symbols.Of_Type (Found) /= Types.Type_String
                                   and then Types.Shape
                                              (Symbols.Of_Type (Found))
                                            /= Types.Shape_Array)
                        then
                           return Symbols.Nothing;
                        end if;

                        return Found;
                     end;
                  end Owner_Of;

                  --  One element of an array, or a run of them. Asked of
                  --  the array's own type rather than of a name, because the
                  --  prefix may be a slice: `A (2 .. 4) (1 .. 2)` is a part of
                  --  a part, and each level answers about the level outside
                  --  it.
                  --
                  --  How many elements a type holds comes from its width
                  --  rather than from what its identity was declared with: a
                  --  slice shares the array's identity and is shorter, and
                  --  asking the declaration would bound an inner slice by the
                  --  whole array.
                  function Part_Of_Array
                    (Of_Array : Types.Type_Kind;
                     Owner    : Symbols.Symbol) return Types.Type_Kind;

                  function Part_Of_Array
                    (Of_Array : Types.Type_Kind;
                     Owner    : Symbols.Symbol) return Types.Type_Kind
                  is
                     Held : constant Types.Type_Kind :=
                       Part_Type (Into, Of_Array, 1);
                     Count : constant Long_Long_Integer :=
                       Long_Long_Integer (Types.Width (Of_Array))
                       / Long_Long_Integer (Types.Width (Held));
                     Base : constant Long_Long_Integer :=
                       First_Index (Into, Of_Array);
                     Ends : constant Long_Long_Integer := Base + Count - 1;
                  begin
                     --  A slice: `A (2 .. 4)`, a run of the array's own
                     --  elements. Its ends are known before the program runs,
                     --  as the array's own bounds and a case choice are,
                     --  because what it becomes is a distance from the start
                     --  of the run and a count of slots -- both written into
                     --  the instruction rather than computed.
                     if Ranged then
                        declare
                           Only : constant S.Node_Id :=
                             S.Child (Tree, Arguments, 1);

                           Low, High : Long_Long_Integer;

                           --  Analysed for their own sake first: whatever is
                           --  wrong inside a bound is reported there, and only
                           --  then is the bound itself judged.
                           Of_Low : constant Types.Type_Kind :=
                             Analyse_Expression
                               (S.First (Tree, Only), Types.Type_Integer);
                           Of_High : constant Types.Type_Kind :=
                             Analyse_Expression
                               (S.Second (Tree, Only), Types.Type_Integer);
                        begin
                           if (Of_Low /= Types.Type_None
                               and then not Types.Is_Acceptable
                                              (Of_Low, Types.Type_Integer))
                             or else
                               (Of_High /= Types.Type_None
                                and then not Types.Is_Acceptable
                                               (Of_High, Types.Type_Integer))
                           then
                              Complain
                                (Adash.Errors.Error_String_Index_Malformed,
                                 Only, Adash.Messages.No_Arguments);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           if not Static_Choice
                                    (Into, Tree, S.First (Tree, Only), Low)
                             or else not Static_Choice
                                           (Into, Tree,
                                            S.Second (Tree, Only), High)
                           then
                              Complain
                                (Adash.Errors.Error_Array_Bound_Not_Static,
                                 Only, Adash.Messages.No_Arguments);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           --  Empty as well as outside. Ada's null slice is a
                           --  value of no elements; a value here is a run of
                           --  slots and a run of none is not one, so the two
                           --  are refused together rather than one of them
                           --  being half-supported.
                           --
                           --  How far the run reaches is not asked of a type
                           --  whose values carry their own length. That end is
                           --  checked where the program runs, against what the
                           --  caller passed, which is the only thing that
                           --  knows.
                           if Low < Base or else Low > High
                             or else (not Types.Is_Open (Of_Array)
                                      and then High > Ends)
                           then
                              Complain
                                (Adash.Errors.Error_No_Such_Slice, Node,
                                 [Adash.Messages.Named
                                    ("name", Types.Name (Of_Array)),
                                  Adash.Messages.Named
                                    ("first", Long_Long_Integer'Image (Low)),
                                  Adash.Messages.Named
                                    ("last", Long_Long_Integer'Image (High))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           declare
                              --  The same type, of fewer elements. The
                              --  identity is the array's, because a slice of a
                              --  Row is a Row -- what differs is how many
                              --  slots it is, which is what stops one from
                              --  being assigned where another length is
                              --  wanted. The name carries the ends so that a
                              --  diagnostic naming both says which is which.
                              Sliced : constant Types.Type_Kind :=
                                Types.Composite_Array
                                  (Id     => Types.Identity (Of_Array),
                                   Called => Types.Name (Of_Array) & " ("
                                             & Ada.Strings.Fixed.Trim
                                                 (Long_Long_Integer'Image
                                                    (Low),
                                                  Ada.Strings.Both)
                                             & " .. "
                                             & Ada.Strings.Fixed.Trim
                                                 (Long_Long_Integer'Image
                                                    (High),
                                                  Ada.Strings.Both)
                                             & ")",
                                   Slots  => Positive
                                               (Long_Long_Integer
                                                  (Types.Width (Held))
                                                * (High - Low + 1)));
                           begin
                              Note (Only, Types.Type_Integer);
                              Note (Node, Sliced, Owner);
                              return Sliced;
                           end;
                        end;
                     end if;

                     if Given /= 1 then
                        Complain
                          (Adash.Errors.Error_Wrong_Argument_Count, Node,
                           [Adash.Messages.Named ("name", Name),
                            Adash.Messages.Named
                              ("expected", Natural'Image (1)),
                            Adash.Messages.Named
                              ("found", Natural'Image (Given))]);
                        Note (Node, Types.Type_None);
                        return Types.Type_None;
                     end if;

                     declare
                        Where : constant Types.Type_Kind :=
                          Analyse_Expression
                            (S.Child (Tree, Arguments, 1),
                             Types.Type_Integer);
                     begin
                        if Where /= Types.Type_None
                          and then Where /= Types.Type_Integer
                        then
                           Complain
                             (Adash.Errors.Error_Type_Mismatch,
                              S.Child (Tree, Arguments, 1),
                              [Adash.Messages.Named
                                 ("found", Types.Name (Where)),
                               Adash.Messages.Named
                                 ("expected",
                                  Types.Name (Types.Type_Integer))]);
                        end if;
                     end;

                     Note (Node, Held, Owner);
                     return Held;
                  end Part_Of_Array;

                  Offered : Natural;
                  Fitting : Natural;
                  Found   : Symbols.Symbol;

                  --  How much had been reported before the arguments were
                  --  analysed, so that a complaint about one of them can be
                  --  told from silence.
                  Said_Before : Natural := 0;

                  --  What every subprogram of this name that could take a call
                  --  of this shape requires at one position, or Type_None
                  --  where they disagree.
                  --
                  --  Ada resolves a call and its arguments together; this
                  --  resolves an argument only when the answer cannot depend
                  --  on which candidate wins. That covers the ordinary case --
                  --  one candidate, or several agreeing at this position --
                  --  and leaves the rest to be settled by the arguments' own
                  --  types, as before.
                  --  What this argument can only be, asked without choosing
                  --  between meanings and so without reporting anything.
                  --
                  --  A literal is its own type, and a name or a call with one
                  --  meaning is that meaning's. Anything that could be several
                  --  things -- or that this cannot read without deciding
                  --  something -- answers with Type_None, which every caller
                  --  reads as "says nothing".
                  function Settled_Value (Value : S.Node_Id)
                                          return Types.Type_Kind;

                  --  Which parameter of this candidate the argument written
                  --  at this position denotes, or zero when none does.
                  --
                  --  A named argument stands in the position its name denotes
                  --  rather than the one it is written in, and that position
                  --  is the candidate's own: two subprograms of one name may
                  --  call their parameters differently. Ada requires the
                  --  positional arguments to come first, so a positional one
                  --  denotes the parameter it is written at.
                  function Parameter_For
                    (Candidate : Symbols.Symbol;
                     Written   : Positive) return Natural;

                  --  Whether this candidate could take every argument whose
                  --  type is settled.
                  --
                  --  What makes resolution travel *sideways*: an argument
                  --  whose type is known rules out the candidates that could
                  --  not take it, and what is left says what the *other*
                  --  argument must be. `P (F, X)` with X a Float and one P
                  --  taking (String, Float) resolves F to String that way,
                  --  which is how Ada reads it.
                  --
                  --  Asked only when some candidate could take them all;
                  --  where none could, the call is wrong rather than
                  --  ambiguous and one report about it beats a cascade about
                  --  its arguments. A named argument stands in the position
                  --  its name denotes rather than the one it is written in,
                  --  so a call using one is left to the ordinary path.
                  function Takes_The_Arguments
                    (Candidate : Symbols.Symbol) return Boolean;

                  --  Whether any of them does.
                  function Some_Take_The_Arguments return Boolean;

                  --  The two together, as the loops below ask it.
                  function Fits_The_Others
                    (Candidate : Symbols.Symbol) return Boolean;

                  function Settled_Value (Value : S.Node_Id)
                                          return Types.Type_Kind
                  is
                     --  What the expression is, once parentheses and a name
                     --  written for a parameter are past.
                     function Beneath (Node : S.Node_Id) return S.Node_Id
                     is (if not S.Is_Present (Node) then Node
                         elsif S.Kind (Tree, Node) = S.Node_Parenthesized
                         then Beneath (S.First (Tree, Node))
                         elsif S.Kind (Tree, Node) = S.Node_Named_Argument
                         then Beneath (S.Second (Tree, Node))
                         else Node);

                     Inner : constant S.Node_Id := Beneath (Value);
                     Pool  : Adash.Language.Scopes.Symbol_List;
                     Count : Natural := 0;
                  begin
                     if not S.Is_Present (Inner) then
                        return Types.Type_None;
                     end if;

                     case S.Kind (Tree, Inner) is
                        when S.Node_Integer_Literal =>
                           return Types.Type_Integer;

                        when S.Node_Real_Literal =>
                           return Types.Type_Float;

                        when S.Node_Character_Literal =>
                           return Types.Type_Character;

                        when S.Node_String_Literal =>
                           return Types.Type_String;

                        when S.Node_Name | S.Node_Call =>
                           declare
                              Spelt : constant String :=
                                (if S.Kind (Tree, Inner) = S.Node_Name
                                 then S.Text (Tree, Inner)
                                 else Dotted (Tree, S.First (Tree, Inner)));
                           begin
                              if Spelt = "" then
                                 return Types.Type_None;
                              end if;

                              Chain.Candidates
                                (Visible_Name (Spelt), Pool, Count);

                              if Count /= 1 then
                                 return Types.Type_None;
                              end if;

                              --  `A (1)` is an element of an array and `S (2)`
                              --  a position in a String: the name's own type
                              --  is not what the expression is, and answering
                              --  with it would rule out the candidate that
                              --  fits. Only a call to something callable says
                              --  what it yields.
                              if S.Kind (Tree, Inner) = S.Node_Call
                                and then not Symbols.Is_Callable (Pool (1))
                              then
                                 return Types.Type_None;
                              end if;

                              if Symbols.Kind (Pool (1)) = Symbols.Symbol_Type
                              then
                                 return Types.Type_None;
                              end if;

                              return Symbols.Of_Type (Pool (1));
                           end;

                        when S.Node_Qualified =>
                           --  `Integer'(F)` says what it is whatever F could
                           --  be. That is the whole point of writing one.
                           return Named_Type (S.First (Tree, Inner));

                        when S.Node_Membership =>
                           --  Boolean in every reading that is legal at all.
                           return Types.Type_Boolean;

                        when S.Node_Unary_Operation =>
                           declare
                              Op : constant S.Operation :=
                                S.Operator (Tree, Inner);

                              Operand : constant Types.Type_Kind :=
                                Settled_Value (S.First (Tree, Inner));
                           begin
                              case Op is
                                 when S.Op_Not =>
                                    return Types.Type_Boolean;

                                 when S.Op_Plus | S.Op_Minus | S.Op_Abs =>
                                    --  The operand's type is the whole's.
                                    return (if Types.Is_Numeric (Operand)
                                            then Operand else Types.Type_None);

                                 when others =>
                                    return Types.Type_None;
                              end case;
                           end;

                        when S.Node_Binary_Operation =>
                           --  What the operator yields, from whichever operand
                           --  says what it is. The rules are the ones the
                           --  analysis of a binary operation applies below,
                           --  read the other way round: there it knows both
                           --  operands and asks what the result is, and here it
                           --  knows one and asks the same question of the
                           --  readings that are legal at all.
                           declare
                              Op : constant S.Operation :=
                                S.Operator (Tree, Inner);

                              Left  : constant Types.Type_Kind :=
                                Settled_Value (S.First (Tree, Inner));
                              Right : constant Types.Type_Kind :=
                                Settled_Value (S.Second (Tree, Inner));

                              --  Either end will do. An operator whose result
                              --  is its operands' type takes one type on both
                              --  sides, so a settled end says what the other
                              --  has to be as well as what the whole is.
                              Known : constant Types.Type_Kind :=
                                (if Left /= Types.Type_None then Left
                                 else Right);
                           begin
                              case Op is
                                 when S.Op_Multiply | S.Op_Divide | S.Op_Add
                                    | S.Op_Subtract | S.Op_Power =>
                                    return (if Types.Is_Numeric (Known)
                                            then Known else Types.Type_None);

                                 when S.Op_Mod | S.Op_Rem =>
                                    return (if Known = Types.Type_Integer
                                            then Types.Type_Integer
                                            else Types.Type_None);

                                 when S.Op_Concat =>
                                    --  A String on either side makes the whole
                                    --  a String. A settled *Character* does
                                    --  not: with a String beside it the whole
                                    --  is a String, and with another Character
                                    --  it is nothing at all -- Ada refuses two
                                    --  of them -- so one Character alone
                                    --  answers nothing.
                                    return (if Left = Types.Type_String
                                              or else Right = Types.Type_String
                                            then Types.Type_String
                                            else Types.Type_None);

                                 when S.Op_Equal | S.Op_Not_Equal | S.Op_Less
                                    | S.Op_Less_Equal | S.Op_Greater
                                    | S.Op_Greater_Equal | S.Op_And | S.Op_Or
                                    | S.Op_Xor | S.Op_And_Then | S.Op_Or_Else =>
                                    --  Boolean in every reading that is legal,
                                    --  whatever the operands turn out to be.
                                    return Types.Type_Boolean;

                                 when others =>
                                    return Types.Type_None;
                              end case;
                           end;

                        when others =>
                           return Types.Type_None;
                     end case;
                  end Settled_Value;

                  function Parameter_For
                    (Candidate : Symbols.Symbol;
                     Written   : Positive) return Natural
                  is
                     Value : constant S.Node_Id :=
                       (if Written <= S.Child_Count (Tree, Arguments)
                        then S.Child (Tree, Arguments, Written)
                        else S.No_Node);
                  begin
                     if not S.Is_Present (Value) then
                        return 0;
                     end if;

                     if S.Kind (Tree, Value) = S.Node_Named_Argument then
                        if not Symbols.Has_Profile (Candidate) then
                           return 0;
                        end if;

                        return Symbols.Parameter_At
                                 (Candidate,
                                  S.Text (Tree, S.First (Tree, Value)));
                     end if;

                     return Written;
                  end Parameter_For;

                  function Takes_The_Arguments
                    (Candidate : Symbols.Symbol) return Boolean
                  is
                     About : constant Signature :=
                       Signature_Of (Name, Candidate);
                  begin
                     if not About.Known
                       or else Given < About.Minimum
                       or else Given > About.Maximum
                     then
                        return False;
                     end if;

                     for Written in 1 .. Given loop
                        declare
                           Value : constant S.Node_Id :=
                             S.Child (Tree, Arguments, Written);

                           Position : constant Natural :=
                             Parameter_For (Candidate, Written);
                        begin
                           if Position = 0
                             or else Position > Natural'Min
                                       (About.Maximum,
                                        Symbols.Max_Parameters)
                           then
                              --  A name this candidate does not have, or a
                              --  position past its profile: not a call to it
                              --  whatever the types would say.
                              return False;
                           end if;

                           declare
                              Wanted : constant Types.Type_Kind :=
                                About.Of_Type (Position);
                              Only   : constant Types.Type_Kind :=
                                Settled_Value (Value);

                              Could : Possible_List;
                              Many  : Natural := 0;
                              Fits  : Boolean := False;
                           begin
                              if Wanted = Types.Type_None then
                                 --  A parameter that takes anything, which
                                 --  the output procedures rely on.
                                 null;

                              elsif Only /= Types.Type_None then
                                 if not Types.Is_Acceptable (Only, Wanted)
                                 then
                                    return False;
                                 end if;

                              else
                                 Possible_Types
                                   ((if S.Kind (Tree, Value)
                                        = S.Node_Named_Argument
                                     then S.Second (Tree, Value)
                                     else Value),
                                    Could, Many);

                                 if Many > 0 then
                                    for Taken in 1 .. Many loop
                                       if Types.Is_Acceptable
                                            (Could (Taken), Wanted)
                                       then
                                          Fits := True;
                                       end if;
                                    end loop;

                                    if not Fits then
                                       return False;
                                    end if;
                                 end if;
                              end if;
                           end;
                        end;
                     end loop;

                     return True;
                  end Takes_The_Arguments;

                  function Some_Take_The_Arguments return Boolean is
                     Pool  : Adash.Language.Scopes.Symbol_List;
                     Count : Natural := 0;
                  begin
                     Chain.Candidates (Visible_Name (Name), Pool, Count);

                     for Index in 1 .. Count loop
                        if Takes_The_Arguments (Pool (Index)) then
                           return True;
                        end if;
                     end loop;

                     return False;
                  end Some_Take_The_Arguments;

                  function Fits_The_Others
                    (Candidate : Symbols.Symbol) return Boolean
                  is (not Some_Take_The_Arguments
                      or else Takes_The_Arguments (Candidate));

                  --  Whether what the context requires leaves this candidate
                  --  standing.
                  --
                  --  A call's arguments are resolved against the subprograms
                  --  that could answer for it, and where the context asks for
                  --  a type, only the ones returning it can. `Show (Make)`
                  --  written where an Integer is wanted is settled this way
                  --  and no other: both Shows take what both Makes return,
                  --  and only one Show returns an Integer.
                  --
                  --  Asked only when some candidate does return what the
                  --  context asks for. Where none does, the call is wrong
                  --  rather than ambiguous, and narrowing to nothing would
                  --  turn one report into a cascade about its arguments.
                  function Answers_The_Context
                    (Candidate : Symbols.Symbol) return Boolean;

                  --  Whether any of them does.
                  function Some_Answer_The_Context return Boolean;

                  function Some_Answer_The_Context return Boolean is
                     Pool  : Adash.Language.Scopes.Symbol_List;
                     Count : Natural;
                  begin
                     if Expected = Types.Type_None then
                        return False;
                     end if;

                     Chain.Candidates (Visible_Name (Name), Pool, Count);

                     for Index in 1 .. Count loop
                        if Types.Is_Acceptable
                             (Symbols.Of_Type (Pool (Index)), Expected)
                        then
                           return True;
                        end if;
                     end loop;

                     return False;
                  end Some_Answer_The_Context;

                  function Answers_The_Context
                    (Candidate : Symbols.Symbol) return Boolean
                  is (Expected = Types.Type_None
                      or else not Some_Answer_The_Context
                      or else Types.Is_Acceptable
                                (Symbols.Of_Type (Candidate), Expected));

                  --  The one type both the candidates and the argument
                  --  written at this position could have, or Type_None.
                  function Only_Fitting
                    (Position : Positive) return Types.Type_Kind
                  is
                     Pool   : Adash.Language.Scopes.Symbol_List;
                     Count  : Natural;
                     Could  : Possible_List;
                     Many   : Natural;
                     Answer : Types.Type_Kind := Types.Type_None;
                     Shared : Natural := 0;

                     Written : constant S.Node_Id :=
                       (if Position <= S.Child_Count (Tree, Arguments)
                        then S.Child (Tree, Arguments, Position)
                        else S.No_Node);
                  begin
                     if not S.Is_Present (Written) then
                        return Types.Type_None;
                     end if;

                     Possible_Types
                       ((if S.Kind (Tree, Written) = S.Node_Named_Argument
                         then S.Second (Tree, Written) else Written),
                        Could, Many);

                     if Many = 0 then
                        return Types.Type_None;
                     end if;

                     Chain.Candidates (Visible_Name (Name), Pool, Count);

                     for Index in 1 .. Count loop
                        declare
                           About : constant Signature :=
                             Signature_Of (Name, Pool (Index));

                           At_Parameter : constant Natural :=
                             Parameter_For (Pool (Index), Position);
                        begin
                           if About.Known
                             and then Answers_The_Context (Pool (Index))
                             and then Fits_The_Others (Pool (Index))
                             and then Given >= About.Minimum
                             and then Given <= About.Maximum
                             and then At_Parameter in
                                        1 .. Natural'Min
                                               (About.Maximum,
                                                Symbols.Max_Parameters)
                           then
                              for Taken in 1 .. Many loop
                                 if Could (Taken)
                                    = About.Of_Type (At_Parameter)
                                   and then Answer /= Could (Taken)
                                 then
                                    Shared := Shared + 1;
                                    Answer := Could (Taken);
                                 end if;
                              end loop;
                           end if;
                        end;
                     end loop;

                     return (if Shared = 1 then Answer else Types.Type_None);
                  end Only_Fitting;

                  function Agreed_Parameter
                    (Position : Positive) return Types.Type_Kind
                  is
                     Pool   : Adash.Language.Scopes.Symbol_List;
                     Count  : Natural;
                     Wanted : Types.Type_Kind := Types.Type_None;
                     Seen   : Boolean := False;
                  begin
                     Chain.Candidates (Visible_Name (Name), Pool, Count);

                     for Index in 1 .. Count loop
                        declare
                           About : constant Signature :=
                             Signature_Of (Name, Pool (Index));

                           At_Parameter : constant Natural :=
                             Parameter_For (Pool (Index), Position);
                        begin
                           if About.Known
                             and then Answers_The_Context (Pool (Index))
                             and then Fits_The_Others (Pool (Index))
                             and then Given >= About.Minimum
                             and then Given <= About.Maximum
                             and then At_Parameter in
                                        1 .. Natural'Min
                                               (About.Maximum,
                                                Symbols.Max_Parameters)
                           then
                              if not Seen then
                                 Wanted := About.Of_Type (At_Parameter);
                                 Seen := True;

                              elsif Wanted /= About.Of_Type (At_Parameter) then
                                 --  They disagree, so what this position
                                 --  requires depends on which candidate wins.
                                 --  Unless the argument written there could
                                 --  only be one of the types they ask for:
                                 --  then that is the answer whichever wins,
                                 --  which is what settles `Show (F)` where
                                 --  both the call and its argument are open.
                                 return Only_Fitting (Position);
                              end if;
                           end if;
                        end;
                     end loop;

                     return Wanted;
                  end Agreed_Parameter;
               begin
                  --  A call whose name has a dot in it may be an entry of a
                  --  task, and the object is the half the name does not carry.
                  --  Left here because a call resolves its whole spelling at
                  --  once rather than analysing its prefix.
                  Note_Task_Object (Prefix);

                  --  `Server.Request (High)` -- one member of an entry family
                  --  rather than a call with an argument. Told apart by what
                  --  the name denotes, which is how indexing and calling are
                  --  told apart here too: only a family has members, and what
                  --  says a name is one is the type its entry carries.
                  declare
                     Family : constant Symbols.Symbol := Visible (Name);
                  begin
                     if Symbols.Kind (Family) = Symbols.Symbol_Entry
                       and then Symbols.Of_Type (Family) /= Types.Type_None
                     then
                        if Given /= 1 then
                           Complain
                             (Adash.Errors.Error_Family_Needs_A_Member,
                              Prefix,
                              [1 => Adash.Messages.Named ("name", Name)]);
                        else
                           declare
                              Wants : constant Types.Type_Kind :=
                                Symbols.Of_Type (Family);
                              Gets  : constant Types.Type_Kind :=
                                Analyse_Expression
                                  (S.Child (Tree, Arguments, 1), Wants);
                           begin
                              if Gets /= Types.Type_None
                                and then not Types.Is_Acceptable (Gets, Wants)
                              then
                                 Complain
                                   (Adash.Errors.Error_Type_Mismatch,
                                    S.Child (Tree, Arguments, 1),
                                    [Adash.Messages.Named
                                       ("found", Types.Name (Gets)),
                                     Adash.Messages.Named
                                       ("expected", Types.Name (Wants))]);
                              end if;
                           end;
                        end if;

                        Note (Prefix, Types.Type_None, Family);
                        Note (Node, Types.Type_None, Family);
                        return Types.Type_None;
                     end if;
                  end;

                  --  `Integer'Value ("42")` and `Integer'Image (N)`: an
                  --  attribute of a *type*, applied to something. Ada writes
                  --  both this way and writes them nowhere else, so this is
                  --  the shape rather than a call to anything.
                  if S.Kind (Tree, Prefix) = S.Node_Attribute then
                     declare
                        Type_Node : constant S.Node_Id :=
                          S.First (Tree, Prefix);
                        Attribute : constant S.Node_Id :=
                          S.Second (Tree, Prefix);
                        Asked     : constant String :=
                          Symbols.Fold (S.Text (Tree, Attribute));

                        --  Named_Type reports for itself when the prefix is
                        --  not a type, which is the same complaint a
                        --  declaration written with a non-type gets.
                        Of_Type : constant Types.Type_Kind :=
                          Named_Type (Type_Node);
                     begin
                        if Of_Type = Types.Type_None then
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        if Asked not in "value" | "image"
                                       | "pos" | "val" | "succ" | "pred"
                        then
                           Complain
                             (Adash.Errors.Error_Attribute_Not_Defined,
                              Attribute,
                              [Adash.Messages.Named
                                 ("attribute", S.Text (Tree, Attribute)),
                               Adash.Messages.Named
                                 ("found", Types.Name (Of_Type))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        if Given /= 1 then
                           Complain
                             (Adash.Errors.Error_Wrong_Argument_Count, Node,
                              [Adash.Messages.Named
                                 ("name", S.Text (Tree, Attribute)),
                               Adash.Messages.Named
                                 ("expected", Natural'Image (1)),
                               Adash.Messages.Named
                                 ("found", Natural'Image (Given))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        --  The four position attributes are for discrete
                        --  types only, which is Ada's rule: a Float has no
                        --  next value and a String has no position.
                        if Asked in "pos" | "val" | "succ" | "pred"
                          and then not Types.Is_Discrete (Of_Type)
                        then
                           Complain
                             (Adash.Errors.Error_Attribute_Not_Defined,
                              Attribute,
                              [Adash.Messages.Named
                                 ("attribute", S.Text (Tree, Attribute)),
                               Adash.Messages.Named
                                 ("found", Types.Name (Of_Type))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        declare
                           --  'Value reads text and answers with the type;
                           --  'Image is the other direction. 'Pos takes the
                           --  type and answers with a position; 'Val is that
                           --  the other way round; 'Succ and 'Pred stay in the
                           --  type.
                           Wanted : constant Types.Type_Kind :=
                             (if Asked = "value" then Types.Type_String
                              elsif Asked = "val" then Types.Type_Integer
                              else Of_Type);

                           Yields : constant Types.Type_Kind :=
                             (if Asked = "value" then Of_Type
                              elsif Asked = "image" then Types.Type_String
                              elsif Asked = "pos" then Types.Type_Integer
                              else Of_Type);

                           Found : constant Types.Type_Kind :=
                             Analyse_Expression
                               (S.Child (Tree, Arguments, 1), Wanted);
                        begin
                           --  Nothing is known about the argument, so nothing
                           --  can be said about whether it fits. Whatever went
                           --  wrong with it was reported already, and a second
                           --  complaint naming no type at all is the cascade
                           --  this pass exists to avoid.
                           if Found /= Types.Type_None
                             and then not Types.Is_Acceptable (Found, Wanted)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch,
                                 S.Child (Tree, Arguments, 1),
                                 [Adash.Messages.Named
                                    ("found", Types.Name (Found)),
                                  Adash.Messages.Named
                                    ("expected", Types.Name (Wanted))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           if Of_Type = Types.Type_String then
                              --  Neither direction is defined for a String.
                              --  Ada 2022 gives it an image -- the text in
                              --  quotes with the non-graphic characters
                              --  bracketed -- which is not the text itself,
                              --  and reading one back is not defined at all.
                              Complain
                                (Adash.Errors.Error_Attribute_Not_Defined,
                                 Attribute,
                                 [Adash.Messages.Named
                                    ("attribute", S.Text (Tree, Attribute)),
                                  Adash.Messages.Named
                                    ("found", Types.Name (Of_Type))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           Note (Prefix, Of_Type);
                           Note (Node, Yields);
                           return Yields;
                        end;
                     end;
                  end if;

                  --  An array element, which Ada writes the way a call is
                  --  written. One subscript, and it is the index rather than
                  --  an argument: an array has no profile to match against.
                  if Subscripts then
                     declare
                        Of_Array : constant Types.Type_Kind :=
                          Symbols.Of_Type (Prefixed);
                     begin
                        Note (Prefix, Of_Array, Prefixed);
                        return Part_Of_Array (Of_Array, Prefixed);
                     end;
                  end if;

                  --  A part of what an expression yields. The prefix is
                  --  analysed as the expression it is -- which is what calls
                  --  the function -- and what comes back has to be a String,
                  --  because a String is the only value here that has parts
                  --  and is not a run of slots a name has to own.
                  if Yields_Part then
                     declare
                        Of_Prefix : constant Types.Type_Kind :=
                          Analyse_Expression (Prefix);
                        Only : constant S.Node_Id :=
                          S.Child (Tree, Arguments, 1);
                     begin
                        if Of_Prefix = Types.Type_None then
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        --  A part of a part of an array: `A (2 .. 4) (1 .. 2)`
                        --  and `A (2 .. 4) (2)`. The level outside answered
                        --  with a type of its own length, so this level asks
                        --  that type rather than the array's declaration --
                        --  which is what makes an inner slice bounded by the
                        --  outer one.
                        if Types.Shape (Of_Prefix) = Types.Shape_Array then
                           return Part_Of_Array (Of_Prefix, Owner_Of (Prefix));
                        end if;

                        if Of_Prefix /= Types.Type_String then
                           Complain
                             (Adash.Errors.Error_Not_Taken_Apart, Node,
                              [1 => Adash.Messages.Named
                                      ("found", Types.Name (Of_Prefix))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        --  No symbol travels with this one, unlike a part of a
                        --  variable: what it is a part of has no name to
                        --  assign to, which is what the assignment asks about.
                        if Ranged then
                           declare
                              Low : constant Types.Type_Kind :=
                                Analyse_Expression
                                  (S.First (Tree, Only), Types.Type_Integer);
                              High : constant Types.Type_Kind :=
                                Analyse_Expression
                                  (S.Second (Tree, Only), Types.Type_Integer);
                           begin
                              if (Low /= Types.Type_None
                                  and then not Types.Is_Acceptable
                                                 (Low, Types.Type_Integer))
                                or else (High /= Types.Type_None
                                         and then not Types.Is_Acceptable
                                                        (High,
                                                         Types.Type_Integer))
                              then
                                 Complain
                                   (Adash.Errors.Error_String_Index_Malformed,
                                    Only, Adash.Messages.No_Arguments);
                              end if;
                           end;

                           Note (Only, Types.Type_Integer);
                           Note (Node, Types.Type_String, Owner_Of (Prefix));
                           return Types.Type_String;
                        end if;

                        declare
                           Where : constant Types.Type_Kind :=
                             Analyse_Expression (Only, Types.Type_Integer);
                        begin
                           if Where /= Types.Type_None
                             and then not Types.Is_Acceptable
                                            (Where, Types.Type_Integer)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, Only,
                                 [Adash.Messages.Named
                                    ("found", Types.Name (Where)),
                                  Adash.Messages.Named
                                    ("expected",
                                     Types.Name (Types.Type_Integer))]);
                           end if;
                        end;

                        Note (Node, Types.Type_Character, Owner_Of (Prefix));
                        return Types.Type_Character;
                     end;
                  end if;

                  --  A String taken apart, which Ada writes exactly as it
                  --  writes a call. One position yields the Character there;
                  --  one range yields the String between.
                  if Indexes then
                     Note (Prefix, Types.Type_String, Prefixed);

                     if Given /= 1 then
                        Complain
                          (Adash.Errors.Error_String_Index_Malformed, Node,
                           Adash.Messages.No_Arguments);
                        Note (Node, Types.Type_None);
                        return Types.Type_None;
                     end if;

                     declare
                        Only  : constant S.Node_Id :=
                          S.Child (Tree, Arguments, 1);
                        Whole : constant Boolean :=
                          S.Kind (Tree, Only) = S.Node_Range;

                        --  Both ends of a range, or the one position.
                        procedure Require_Position (At_Node : S.Node_Id);

                        procedure Require_Position (At_Node : S.Node_Id) is
                           Found : constant Types.Type_Kind :=
                             Analyse_Expression (At_Node, Types.Type_Integer);
                        begin
                           if not Types.Is_Acceptable
                                    (Found, Types.Type_Integer)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, At_Node,
                                 [Adash.Messages.Named
                                    ("found", Types.Name (Found)),
                                  Adash.Messages.Named
                                    ("expected",
                                     Types.Name (Types.Type_Integer))]);
                           end if;
                        end Require_Position;
                     begin
                        --  The prefix's symbol travels with the part, as it
                        --  does for an array element: what a part of a String
                        --  may be assigned to is what the String may be, and
                        --  the assignment asks the node it was given.
                        if Whole then
                           Require_Position (S.First (Tree, Only));
                           Require_Position (S.Second (Tree, Only));
                           Note (Only, Types.Type_Integer);
                           Note (Node, Types.Type_String, Prefixed);
                           return Types.Type_String;
                        end if;

                        Require_Position (Only);
                        Note (Node, Types.Type_Character, Prefixed);
                        return Types.Type_Character;
                     end;
                  end if;

                  --  Arguments are analysed whatever the prefix turns out to
                  --  be, so an error inside one is reported even when the call
                  --  itself is wrong.
                  Said_Before := Report.Count;

                  for Index in 1 .. S.Child_Count (Tree, Arguments) loop
                     declare
                        Ignored : constant Types.Type_Kind :=
                          Analyse_Expression
                            (S.Child (Tree, Arguments, Index),
                             Agreed_Parameter (Index));
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  end loop;

                  --  Which subprogram this call means, decided by the
                  --  arguments just analysed rather than by the name alone.
                  Resolve_Call (Name, Arguments, Given,
                                Expected, Offered, Fitting, Found);

                  if Offered = 0 then
                     Complain (Adash.Errors.Error_Name_Undeclared, Prefix,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  if Offered > 1 and then Fitting /= 1 then
                     --  Several things it could mean, and the arguments do not
                     --  single one out. Whether it is *said* depends on
                     --  whether an argument was already complained about: a
                     --  call cannot be resolved from an argument whose own
                     --  type could not be worked out, so saying the call is
                     --  ambiguous as well is the same fault counted twice --
                     --  and the second telling names this call rather than the
                     --  argument, which is where the reader has to go. The
                     --  argument's type is let through the resolution for the
                     --  same reason; this is the other half of that.
                     --
                     --  Unresolved either way. Falling through to a candidate
                     --  because the complaint was left unsaid would make the
                     --  program mean whichever body was declared first.
                     if Report.Count = Said_Before then
                        --  Reporting the count says whether the problem is
                        --  that none fit or that too many do.
                        Complain_Of_Candidates
                          ((if Fitting = 0
                            then Adash.Errors.Error_No_Matching_Subprogram
                            else Adash.Errors.Error_Ambiguous_Call),
                           Node,
                           [Adash.Messages.Named ("name", Name),
                            Adash.Messages.Named
                              ("count",
                               Natural'Image (if Fitting = 0 then Offered
                                              else Fitting))],
                           Visible_Name (Name));
                     end if;

                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  --  `Integer (F)` and `Float (I)` -- a type mark applied to
                  --  a value, which is Ada's explicit conversion and the only
                  --  way a value crosses between the two numeric types here.
                  --  Written out, where a reader sees it happen: what this
                  --  language refuses is the conversion nobody wrote.
                  if Symbols.Kind (Found) = Symbols.Symbol_Type
                    and then Given = 1
                    and then S.Kind (Tree, S.Child (Tree, Arguments, 1))
                             /= S.Node_Named_Argument
                  then
                     declare
                        Target : constant Types.Type_Kind :=
                          Symbols.Of_Type (Found);
                        Value  : constant S.Node_Id :=
                          S.Child (Tree, Arguments, 1);
                        Source : constant Types.Type_Kind :=
                          Into.Type_Of (Value);
                     begin
                        if Source = Types.Type_None then
                           --  Already reported against the value itself.
                           Legal := False;
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        if not Types.Is_Numeric (Target)
                          or else not Types.Is_Numeric (Source)
                        then
                           --  Ada converts between types that are related,
                           --  and here that is the two numeric ones. A
                           --  Character's position and an enumeration's are
                           --  what `'Pos` and `'Val` are for, and a text form
                           --  is what `'Image` and `'Value` are for.
                           Complain
                             (Adash.Errors.Error_Type_Mismatch, Value,
                              [Adash.Messages.Named
                                 ("found", Types.Name (Source)),
                               Adash.Messages.Named
                                 ("expected", Types.Name (Target))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        Note (Node, Target, Found);
                        return Target;
                     end;
                  end if;

                  if Symbols.Kind (Found) = Symbols.Symbol_Type then
                     --  A type mark with anything but one value after it.
                     --  Said as the count rather than as `not callable`,
                     --  which would describe what it is not.
                     Complain
                       (Adash.Errors.Error_Wrong_Argument_Count, Node,
                        [Adash.Messages.Named ("name", Name),
                         Adash.Messages.Named ("expected", " 1"),
                         Adash.Messages.Named
                           ("found", Natural'Image (Given))]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  if not Symbols.Is_Callable (Found) then
                     Complain (Adash.Errors.Error_Not_Callable, Prefix,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  --  Parameter association, against the one it resolved to.
                  --  Only reached when a single candidate was on offer or one
                  --  fitted; otherwise the report above already said so.
                  declare
                     About : constant Signature := Signature_Of (Name, Found);
                  begin
                     if About.Known then
                        declare
                           Expected : constant String := Accepts (About);
                        begin
                           --  Too few is left to Match_Arguments below, which
                           --  can say *which* parameter was not given -- and
                           --  saying both would be two complaints about one
                           --  mistake. A callee with no profile has no such
                           --  check, so the count is all there is to report.
                           if Given > About.Maximum
                             or else (Given < About.Minimum
                                      and then not Symbols.Has_Profile (Found))
                           then
                              Complain
                                (Adash.Errors.Error_Wrong_Argument_Count, Node,
                                 [Adash.Messages.Named ("name", Name),
                                  Adash.Messages.Named ("expected", Expected),
                                  Adash.Messages.Named
                                    ("found", Natural'Image (Given))]);
                           end if;

                           --  Where each parameter's value comes from. A call
                           --  may name its arguments or leave defaulted ones
                           --  out, so position in the call is not position in
                           --  the profile and everything below reads the map
                           --  rather than the sequence.
                           declare
                              --  Initialised, because Match_Arguments is not
                              --  called at all when the callee has no profile
                              --  -- a predefined name or a command -- and an
                              --  out parameter that was never written is
                              --  whatever the stack held.
                              Slots : Argument_Map := [others => S.No_Node];
                              At_Node : S.Node_Id := S.No_Node;
                              Which : Natural := 0;

                              Fitted : constant Match_Outcome :=
                                (if Symbols.Has_Profile (Found)
                                 then Match_Arguments
                                        (Tree, Arguments, Found,
                                         Slots, At_Node, Which)
                                 else Matched);

                              --  The parameter's own name, for a complaint
                              --  about it. Empty when the complaint is about
                              --  the call rather than one parameter.
                              Called : constant String :=
                                (if Which = 0 then ""
                                 else Symbols.Parameter_Name (Found, Which));
                           begin
                              case Fitted is
                                 when Matched | Too_Many =>
                                    --  Too_Many is already reported as a
                                    --  wrong count above, and saying it twice
                                    --  would be two complaints about one
                                    --  mistake.
                                    null;

                                 when Unknown_Name =>
                                    Complain
                                      (Adash.Errors.Error_No_Such_Parameter,
                                       At_Node,
                                       [Adash.Messages.Named ("name", Name),
                                        Adash.Messages.Named
                                          ("parameter",
                                           S.Text (Tree,
                                                   S.First (Tree, At_Node)))]);

                                 when Given_Twice =>
                                    Complain
                                      (Adash.Errors.Error_Parameter_Given_Twice,
                                       At_Node,
                                       [Adash.Messages.Named ("name", Name),
                                        Adash.Messages.Named
                                          ("parameter", Called)]);

                                 when Out_Of_Order =>
                                    Complain
                                      (Adash.Errors.Error_Positional_After_Named,
                                       At_Node,
                                       [1 => Adash.Messages.Named
                                               ("name", Name)]);

                                 when Not_Given =>
                                    Complain
                                      (Adash.Errors.Error_Parameter_Not_Given,
                                       Node,
                                       [Adash.Messages.Named ("name", Name),
                                        Adash.Messages.Named
                                          ("parameter", Called)]);
                              end case;

                              --  A named argument to a predefined entity or a
                              --  command. Those are not symbols with profiles,
                              --  so the check above skipped them entirely and
                              --  what a wrong name got was the lowering's
                              --  "cannot run this expression" -- a true
                              --  sentence about the wrong thing.
                              if not Symbols.Has_Profile (Found) then
                                 declare
                                    About_Names : constant
                                      Adash.Predefined.Profile :=
                                        Adash.Predefined.Profile_Of (Name);
                                    Taken : array (1 .. Symbols.Max_Parameters)
                                              of Boolean := [others => False];
                                 begin
                                    for Index in 1 .. Given loop
                                       declare
                                          One : constant S.Node_Id :=
                                            S.Child (Tree, Arguments, Index);
                                          Where : Natural := 0;
                                       begin
                                          if S.Kind (Tree, One)
                                             = S.Node_Named_Argument
                                          then
                                             for Position in
                                               1 .. Natural'Min
                                                 (About_Names.Types_Of'Last,
                                                  Symbols.Max_Parameters)
                                             loop
                                                if Symbols.Fold
                                                     (Adash.Messages.Value
                                                        (About_Names.Types_Of
                                                           (Position).Name))
                                                   = Symbols.Fold
                                                       (S.Text
                                                          (Tree,
                                                           S.First (Tree,
                                                                    One)))
                                                then
                                                   Where := Position;
                                                end if;
                                             end loop;

                                             if Where = 0 then
                                                Complain
                                                  (Adash.Errors.Error_No_Such_Parameter,
                                                   One,
                                                   [Adash.Messages.Named
                                                      ("name", Name),
                                                    Adash.Messages.Named
                                                      ("parameter",
                                                       S.Text
                                                         (Tree,
                                                          S.First (Tree,
                                                                   One)))]);

                                             elsif Taken (Where) then
                                                Complain
                                                  (Adash.Errors.Error_Parameter_Given_Twice,
                                                   One,
                                                   [Adash.Messages.Named
                                                      ("name", Name),
                                                    Adash.Messages.Named
                                                      ("parameter",
                                                       S.Text
                                                         (Tree,
                                                          S.First (Tree,
                                                                   One)))]);
                                             else
                                                Taken (Where) := True;
                                             end if;
                                          end if;
                                       end;
                                    end loop;
                                 end;
                              end if;

                              --  A parameter typed Type_None accepts anything --
                              --  the output procedures image whatever they are
                              --  given -- so only a stated type is checked.
                              for Index in 1 .. Natural'Min
                                (Natural'Min (About.Maximum, Symbols.Max_Parameters),
                                 Symbols.Max_Parameters)
                              loop
                                 declare
                                    Given_Node : constant S.Node_Id :=
                                      (if Symbols.Has_Profile (Found)
                                       then Slots (Index)
                                       elsif Index <= Given
                                       then S.Child (Tree, Arguments, Index)
                                       else S.No_Node);

                                    Wanted : constant Types.Type_Kind :=
                                      About.Of_Type (Index);
                                    Actual : constant Types.Type_Kind :=
                                      (if S.Is_Present (Given_Node)
                                       then Into.Type_Of (Given_Node)
                                       else Types.Type_None);
                                    Passed : constant Symbols.Parameter_Mode :=
                                      About.Modes (Index);

                                    use type Symbols.Parameter_Mode;
                                 begin
                                    if not S.Is_Present (Given_Node) then
                                       --  Left to its default, or already
                                       --  reported as missing.
                                       goto Continue;
                                    end if;

                                    if Wanted = Types.Type_None
                                      and then Types.Is_Composite (Actual)
                                    then
                                       --  A parameter that accepts anything is
                                       --  one of the output procedures, and a
                                       --  composite has no one text: an
                                       --  aggregate is expressions rather than
                                       --  a literal, so there is nothing to
                                       --  write. Said here rather than left to
                                       --  the lowering, which would report it
                                       --  as something not built yet.
                                       Complain
                                         (Adash.Errors.Error_Cannot_Write,
                                          Given_Node,
                                          [Adash.Messages.Named
                                             ("name", Name),
                                           Adash.Messages.Named
                                             ("found",
                                              Types.Name (Actual))]);
                                       goto Continue;
                                    end if;

                                    --  A subprogram that writes back needs
                                    --  somewhere to write. An expression has no
                                    --  address that outlives the call, so this is
                                    --  not a style rule -- there is nowhere for
                                    --  the value to go.
                                    if Passed /= Symbols.Mode_In
                                      and then not Symbols.Is_Assignable
                                                     (Into.Symbol_Of (Given_Node))
                                    then
                                       Complain
                                         (Adash.Errors.Error_Actual_Not_Variable,
                                          Given_Node,
                                          [Adash.Messages.Named
                                             ("position", Natural'Image (Index)),
                                           Adash.Messages.Named
                                             ("mode",
                                              (if Passed = Symbols.Mode_Out
                                               then "out" else "in out"))]);
                                    end if;

                                    if Wanted /= Types.Type_None
                                      and then Actual /= Types.Type_None
                                      and then not Types.Is_Acceptable (Actual, Wanted)
                                    then
                                       Complain
                                         (Adash.Errors.Error_Type_Mismatch,
                                          Given_Node,
                                          [Adash.Messages.Named
                                             ("found", Types.Name (Actual)),
                                           Adash.Messages.Named
                                             ("expected", Types.Name (Wanted))]);
                                    end if;

                                    <<Continue>>
                                 end;
                              end loop;
                           end;
                        end;
                     end if;
                  end;

                  Note (Prefix, Symbols.Of_Type (Found), Found);
                  Note (Node, Symbols.Of_Type (Found));
                  return Symbols.Of_Type (Found);
               end;

            when S.Node_If_Expression =>
               declare
                  When_True  : Types.Type_Kind;
                  When_False : Types.Type_Kind;
               begin
                  Require_Condition (S.First (Tree, Node));

                  --  What the context wants reaches both arms, and the first
                  --  arm's type reaches the second: `(if A then F else 0)`
                  --  settles F against the Integer the other arm is, which is
                  --  the rule the two sides of a comparison already follow.
                  When_True := Analyse_Expression (S.Second (Tree, Node),
                                                   Expected);
                  When_False :=
                    Analyse_Expression
                      (S.Third (Tree, Node),
                       (if When_True /= Types.Type_None
                        then When_True else Expected));

                  if When_True = Types.Type_None
                    or else When_False = Types.Type_None
                  then
                     Legal := False;
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  if not Types.Is_Acceptable (When_False, When_True) then
                     --  One type for the whole, as Ada requires: an
                     --  expression whose type depended on which arm ran would
                     --  have none a declaration could be checked against.
                     Complain
                       (Adash.Errors.Error_Type_Mismatch, S.Third (Tree, Node),
                        [Adash.Messages.Named
                           ("found", Types.Name (When_False)),
                         Adash.Messages.Named
                           ("expected", Types.Name (When_True))]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  Note (Node, When_True);
                  return When_True;
               end;

            when S.Node_Case_Expression =>
               --  The alternatives are the statement's, choice for choice --
               --  every value covered once, the bounds known before the
               --  program runs, `others` last -- so they are analysed where
               --  the statement's are rather than in a second copy that could
               --  drift from it. What the context wants travels there in
               --  Wanted_Of_Case, because an arm is where a value stands.
               declare
                  Outer : constant Types.Type_Kind := Wanted_Of_Case;
               begin
                  Wanted_Of_Case := Expected;
                  Analyse_Statement (Node);
                  Wanted_Of_Case := Outer;
               end;

               return Into.Type_Of (Node);

            when S.Node_Qualified =>
               declare
                  Marked : constant Types.Type_Kind :=
                    Named_Type (S.First (Tree, Node));

                  --  The whole point: the type reaches the expression, which
                  --  is what settles a call several subprograms could answer
                  --  or a literal two enumerations declare.
                  Found : constant Types.Type_Kind :=
                    Analyse_Expression (S.Second (Tree, Node), Marked);
               begin
                  if Marked /= Types.Type_None
                    and then Found /= Types.Type_None
                    and then not Types.Is_Acceptable (Found, Marked)
                  then
                     Complain
                       (Adash.Errors.Error_Type_Mismatch,
                        S.Second (Tree, Node),
                        [Adash.Messages.Named ("found", Types.Name (Found)),
                         Adash.Messages.Named
                           ("expected", Types.Name (Marked))]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  Note (Node, Marked);
                  return Marked;
               end;

            when S.Node_Attribute =>
               declare
                  Prefix    : constant S.Node_Id := S.First (Tree, Node);
                  Attribute : constant S.Node_Id := S.Second (Tree, Node);
                  Name      : constant String := S.Text (Tree, Attribute);

                  --  A type's attribute is a call -- `Integer'Value ("42")` --
                  --  and reaches this branch only when it was written without
                  --  its argument. Analysing the prefix as an expression would
                  --  say `Integer is not a type`, which is both wrong and
                  --  baffling.
                  Names_A_Type : constant Boolean :=
                    S.Kind (Tree, Prefix) = S.Node_Name
                      and then not Symbols.Is_Nothing
                                     (Chain.Lookup (S.Text (Tree, Prefix)))
                      and then Symbols.Kind
                                 (Chain.Lookup (S.Text (Tree, Prefix)))
                               = Symbols.Symbol_Type;
               begin
                  --  What a task or a protected object runs at. Ada gives a
                  --  protected object `'Priority` and a task
                  --  `Get_Priority`; this language has one spelling for asking
                  --  something about a value and uses it for both.
                  if Symbols.Fold (Name) = "priority" then
                     declare
                        Of_It : constant Symbols.Symbol :=
                          (if S.Kind (Tree, Prefix) = S.Node_Name
                           then Visible (S.Text (Tree, Prefix))
                           else Symbols.Nothing);

                        --  A protected object is a name for what it holds
                        --  rather than a value, so what it is is asked of what
                        --  it was made from.
                        Guarded : constant Boolean :=
                          S.Is_Present (Guarded_Body_Of (Prefix));
                     begin
                        if Guarded
                          or else Types.Is_Task (Symbols.Of_Type (Of_It))
                        then
                           --  What it is, so the lowering knows whether to
                           --  ask the type's declaration or the object's.
                           Note (Prefix, Symbols.Of_Type (Of_It), Of_It);
                           Note (Node, Types.Type_Integer);
                           return Types.Type_Integer;
                        end if;

                        Complain
                          (Adash.Errors.Error_Attribute_Not_Defined,
                           Attribute,
                           [Adash.Messages.Named ("attribute", Name),
                            Adash.Messages.Named
                              ("found", S.Text (Tree, Prefix))]);
                        Note (Node, Types.Type_None);
                        return Types.Type_None;
                     end;
                  end if;

                  --  How much room something takes, in slots. Asked of a type
                  --  or of an object and answered the same way for both: what
                  --  a value of it occupies is a property of the type.
                  --
                  --  Slots rather than bits, which is what Ada counts. A slot
                  --  here holds a value of any type, so a bit count would be a
                  --  number nothing in this machine means -- and a plausible
                  --  wrong answer is worse than an honest different one.
                  if Symbols.Fold (Name) in "size" | "storage_size" then
                     declare
                        Whose : constant Types.Type_Kind :=
                          (if S.Kind (Tree, Prefix) = S.Node_Name
                             and then Symbols.Kind
                                           (Visible (S.Text (Tree, Prefix)))
                                         in Symbols.Symbol_Type
                                          | Symbols.Symbol_Package
                           then Symbols.Of_Type
                                  (Visible (S.Text (Tree, Prefix)))
                           else Analyse_Expression (Prefix));

                        Room : constant Natural := Slots_Of (Prefix);
                     begin
                        if Symbols.Fold (Name) = "storage_size"
                          and then not Types.Is_Task (Whose)
                        then
                           --  Ada's `'Storage_Size` is what a task is given to
                           --  run in. Nothing else here is given a region of
                           --  its own, so nothing else has one to report.
                           Complain
                             (Adash.Errors.Error_Attribute_Not_Defined,
                              Attribute,
                              [Adash.Messages.Named ("attribute", Name),
                               Adash.Messages.Named
                                 ("found", Types.Name (Whose))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        Note (Prefix, Whose);
                        --  What `'Size` answers. `'Storage_Size` is what the
                        --  *machine* gives a task, which this pass has no
                        --  business knowing: it sits above the machine, and a
                        --  number from down there would be a dependency the
                        --  wrong way round.
                        Into.Sizes.Append
                          (Measured'(At_Node => Node, Slots => Room));

                        Note (Node, Types.Type_Integer);
                        return Types.Type_Integer;
                     end;
                  end if;

                  if Names_A_Type then
                     --  `Integer'First` and `Integer'Last` take no argument:
                     --  they are the type's own bounds rather than a question
                     --  about a value. Every scalar type has them; a String
                     --  does not, because a String has no bounds until there
                     --  is one to ask about -- and `S'First` on an actual
                     --  String is answered further down.
                     if Symbols.Fold (Name) in "first" | "last" then
                        declare
                           Of_Type : constant Types.Type_Kind :=
                             Named_Type (Prefix);
                        begin
                           if Of_Type = Types.Type_None
                             or else Of_Type = Types.Type_String
                           then
                              Complain
                                (Adash.Errors.Error_Attribute_Not_Defined,
                                 Attribute,
                                 [Adash.Messages.Named ("attribute", Name),
                                  Adash.Messages.Named
                                    ("found", S.Text (Tree, Prefix))]);
                              Note (Node, Types.Type_None);
                              return Types.Type_None;
                           end if;

                           --  The symbol as well as the type, so the lowering
                           --  can tell `Integer'First` -- the type's own
                           --  bound, a constant -- from `S'First`, which is a
                           --  question about a value.
                           Note (Prefix, Of_Type,
                                 Chain.Lookup (S.Text (Tree, Prefix)));
                           Note (Node, Of_Type);
                           return Of_Type;
                        end;
                     end if;

                     if Symbols.Fold (Name)
                          in "value" | "image" | "pos" | "val" | "succ" | "pred"
                     then
                        Complain
                          (Adash.Errors.Error_Wrong_Argument_Count, Node,
                           [Adash.Messages.Named ("name", Name),
                            Adash.Messages.Named
                              ("expected", Natural'Image (1)),
                            Adash.Messages.Named
                              ("found", Natural'Image (0))]);
                     else
                        Complain
                          (Adash.Errors.Error_Attribute_Not_Defined, Attribute,
                           [Adash.Messages.Named ("attribute", Name),
                            Adash.Messages.Named
                              ("found", S.Text (Tree, Prefix))]);
                     end if;

                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end if;

                  --  How many callers are queued at an entry.
                  --
                  --  Asked before the prefix is analysed as an expression,
                  --  because an entry is not one: analysing it would report a
                  --  call to it with no arguments, which is a true statement
                  --  about a call nobody wrote.
                  --
                  --  Ada allows it only inside the body of the unit that
                  --  declares the entry, and that is not fussiness: the
                  --  count is a queue's length at an instant, and a caller
                  --  reading it from outside would be told something that
                  --  had already changed by the time it acted. Inside, the
                  --  object is held and the answer keeps.
                  --
                  --  Which is what makes the rule checkable here: the entry
                  --  must be a member of the unit being analysed, which is
                  --  what the enclosing prefix says.
                  if Symbols.Fold (Name) = "count" then
                     declare
                        --  `E'Count` names the entry; `E (I)'Count` names one
                        --  member of a family, whose head is the entry.
                        Head : constant S.Node_Id :=
                          (if S.Kind (Tree, Prefix) = S.Node_Call
                           then S.First (Tree, Prefix) else Prefix);

                        Simple : constant String :=
                          (if S.Kind (Tree, Head) = S.Node_Name
                           then S.Text (Tree, Head) else "");
                        Whole  : constant String := Dotted (Tree, Prefix);
                        Found  : constant Symbols.Symbol :=
                          Chain.Lookup (Full_Name (Simple));
                     begin
                        if Simple /= ""
                          and then Symbols.Kind (Found)
                                   = Symbols.Symbol_Entry
                        then
                           --  A family's member is an expression of the type
                           --  the family is indexed by, analysed here because
                           --  nothing else will look inside an attribute's
                           --  prefix once this has answered.
                           if S.Kind (Tree, Prefix) = S.Node_Call
                             and then S.Child_Count
                                        (Tree, S.Second (Tree, Prefix)) = 1
                           then
                              declare
                                 Ignored : constant Types.Type_Kind :=
                                   Analyse_Expression
                                     (S.Child
                                        (Tree, S.Second (Tree, Prefix), 1),
                                      Symbols.Of_Type (Found));
                                 pragma Unreferenced (Ignored);
                              begin
                                 null;
                              end;
                           end if;

                           Note (Head, Types.Type_None, Found);
                           Note (Prefix, Types.Type_None, Found);
                           Note (Node, Types.Type_Integer);
                           return Types.Type_Integer;
                        end if;

                        Complain
                          (Adash.Errors.Error_Count_Outside_Its_Unit,
                           Attribute,
                           [1 => Adash.Messages.Named
                                   ("name",
                                    (if Whole = "" then Name else Whole))]);
                        Note (Node, Types.Type_None);
                        return Types.Type_None;
                     end;
                  end if;

                  declare
                     Of_Prefix : constant Types.Type_Kind :=
                       Analyse_Expression (Prefix);
                     Folded    : constant String := Symbols.Fold (Name);
                  begin
                     --  'Image is the one a shell needs. Other attributes are
                     --  refused rather than guessed at: an attribute that
                     --  silently produced the wrong type would be worse than one
                     --  that is not supported.
                     if Folded = "image" then
                        if Of_Prefix = Types.Type_None then
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        --  Every *scalar* type, which is not the same as every
                        --  type. Ada 2022 does define `S'Image` for a String, and
                        --  what it yields is the text in quotes with the
                        --  non-graphic characters bracketed -- not the text
                        --  itself. Returning the text would be the plausible
                        --  wrong answer, and a program relying on it would mean
                        --  something else under a real compiler.
                        if Of_Prefix = Types.Type_String then
                           Complain
                             (Adash.Errors.Error_Attribute_Not_Defined, Attribute,
                              [Adash.Messages.Named ("attribute", "Image"),
                               Adash.Messages.Named
                                 ("found", Types.Name (Of_Prefix))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        Note (Node, Types.Type_String);
                        return Types.Type_String;
                     end if;

                     --  What a task can be asked about itself. Ada's two
                     --  questions about one: whether it has ended, and whether
                     --  a call to it would be met. They are not each other's
                     --  negation -- a task that has run its body out but is
                     --  still waiting for what depends on it has ended
                     --  nothing and will meet nobody.
                     if Folded in "terminated" | "callable"
                       and then (Types.Is_Task (Of_Prefix)
                                 or else Of_Prefix = Types.Type_Task_Id)
                     then
                        Note (Node, Types.Type_Boolean);
                        return Types.Type_Boolean;
                     end if;

                     --  How long it has run for. Run for, not waited: a task
                     --  that spends its life at a barrier has used none of it,
                     --  which is what makes this worth asking rather than
                     --  reading the clock twice.
                     if Folded = "execution_time"
                       and then (Types.Is_Task (Of_Prefix)
                                 or else Of_Prefix = Types.Type_Task_Id)
                     then
                        Note (Node, Types.Type_Float);
                        return Types.Type_Float;
                     end if;

                     --  `A'Identity` is the task itself. Ada needs the
                     --  attribute because a task object is not a value there
                     --  and an identity has a type of its own; here a task
                     --  *is* a value -- what it holds is which strand runs it
                     --  -- so this is a spelling of the same thing, and two
                     --  identities compare exactly when they are one task.
                     if Folded = "identity" and then Types.Is_Task (Of_Prefix)
                     then
                        Note (Node, Types.Type_Task_Id);
                        return Types.Type_Task_Id;
                     end if;

                     --  What an array can be asked about itself. Ada defines
                     --  these for every array, and now there is more than one
                     --  kind here: a String, and any type a program declared.
                     if Folded in "length" | "first" | "last"
                       and then Types.Shape (Of_Prefix) = Types.Shape_Array
                     then
                        Note (Node, Types.Type_Integer);
                        return Types.Type_Integer;
                     end if;

                     --  What a String can be asked about itself. Ada defines
                     --  these for every array; the three together are what a
                     --  loop over its characters needs.
                     if Folded in "length" | "first" | "last" then
                        if Of_Prefix = Types.Type_None then
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        if Of_Prefix /= Types.Type_String then
                           Complain
                             (Adash.Errors.Error_Attribute_Not_Defined, Attribute,
                              [Adash.Messages.Named ("attribute", Name),
                               Adash.Messages.Named
                                 ("found", Types.Name (Of_Prefix))]);
                           Note (Node, Types.Type_None);
                           return Types.Type_None;
                        end if;

                        Note (Node, Types.Type_Integer);
                        return Types.Type_Integer;
                     end if;

                     --  An attribute rather than a name: `X'Size` is not an
                     --  undeclared identifier, and saying so sent the reader
                     --  looking for a declaration they never wrote.
                     Complain
                       (Adash.Errors.Error_Attribute_Not_Defined, Attribute,
                        [Adash.Messages.Named ("attribute", Name),
                         Adash.Messages.Named
                           ("found", Types.Name (Of_Prefix))]);
                     Note (Node, Types.Type_None);
                     return Types.Type_None;
                  end;
               end;

            when others =>
               return Types.Type_None;
         end case;
      end Analyse_Expression;

      --  A condition has to be Boolean. There is no truthiness in Adash: an
      --  Integer is not a condition, and accepting one would make `if X` mean
      --  something the language does not say.
      procedure Require_Condition (Node : S.Node_Id) is
         Found : constant Types.Type_Kind :=
           Analyse_Expression (Node, Types.Type_Boolean);
      begin
         if Found = Types.Type_Boolean then
            return;
         end if;

         if Found = Types.Type_None then
            Legal := False;
            return;
         end if;

         Complain (Adash.Errors.Error_Condition_Not_Boolean, Node,
                   [1 => Adash.Messages.Named ("found", Types.Name (Found))]);
      end Require_Condition;

      -----------------------
      -- Analyse_Statement --
      -----------------------

      procedure Analyse_Statement (Node : S.Node_Id) is
      begin
         case S.Kind (Tree, Node) is
            when S.Node_Generic_Declaration =>
               declare
                  Held  : constant S.Node_Id := S.Second (Tree, Node);
                  Named : constant S.Node_Id := S.First (Tree, Held);
                  Name  : constant String := S.Text (Tree, Named);
                  Error : Adash.Errors.Error_Info;
               begin
                  --  The body is *not* analysed. A generic is a template, and
                  --  what its names mean depends on what an instantiation
                  --  binds its formals to -- so there is nothing to conclude
                  --  about it until one does.
                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (Name), Symbols.Symbol_Generic,
                        Types.Type_None, Origin, S.Extent (Tree, Named)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Named);
                  end if;

                  Templates.Append
                    (Template'(Key =>
                                 Ada.Strings.Unbounded.To_Unbounded_String
                                   (Symbols.Fold (Full_Name (Name))),
                               At_Node => Node,
                               Made_Of =>
                                 (if S.Is_Present (S.Child (Tree, Held, 5))
                                  then Held else S.No_Node)));

                  Note (Named, Types.Type_None,
                        Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Instantiation =>
               declare
                  Named  : constant S.Node_Id := S.First (Tree, Node);
                  From   : constant S.Node_Id := S.Second (Tree, Node);
                  Given  : constant S.Node_Id := S.Third (Tree, Node);

                  Name   : constant String := S.Text (Tree, Named);
                  Source : constant String := Dotted (Tree, From);
                  Found  : constant Symbols.Symbol := Visible (Source);

                  Which : Natural := 0;
               begin
                  if Symbols.Is_Nothing (Found) then
                     Complain (Adash.Errors.Error_Name_Undeclared, From,
                               [1 => Adash.Messages.Named
                                       ("name", Source)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if Symbols.Kind (Found) /= Symbols.Symbol_Generic then
                     Complain (Adash.Errors.Error_Not_A_Generic, From,
                               [1 => Adash.Messages.Named
                                       ("name", Source)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  for Index in 1 .. Natural (Templates.Length) loop
                     if Ada.Strings.Unbounded.To_String
                          (Templates.Element (Index).Key)
                        = Symbols.Fold (Visible_Name (Source))
                     then
                        Which := Index;
                        exit;
                     end if;
                  end loop;

                  if Which = 0 then
                     Complain (Adash.Errors.Error_Not_A_Generic, From,
                               [1 => Adash.Messages.Named
                                       ("name", Source)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  declare
                     Template_Node : constant S.Node_Id :=
                       Templates.Element (Which).At_Node;
                     Template_Body : constant S.Node_Id :=
                       Templates.Element (Which).Made_Of;
                     Formals : constant S.Node_Id :=
                       S.First (Tree, Template_Node);
                     Wanted  : constant Natural :=
                       S.Child_Count (Tree, Formals);
                     Offered : constant Natural :=
                       S.Child_Count (Tree, Given);
                  begin
                     if not S.Is_Present (Template_Body) then
                        --  Declared and never given a body. An instantiation
                        --  of one would have nothing to copy, so it is said
                        --  here rather than left to produce a subprogram that
                        --  does nothing.
                        Complain
                          (Adash.Errors.Error_Body_Missing, From,
                           [1 => Adash.Messages.Named ("name", Source)]);
                        Note (Node, Types.Type_None);
                        return;
                     end if;

                     if Offered /= Wanted then
                        Complain
                          (Adash.Errors.Error_Generic_Wrong_Actuals, Node,
                           [Adash.Messages.Named ("name", Source),
                            Adash.Messages.Named
                              ("expected", Natural'Image (Wanted)),
                            Adash.Messages.Named
                              ("found", Natural'Image (Offered))]);
                        Note (Node, Types.Type_None);
                        return;
                     end if;

                     declare
                        --  One binding per formal, and one for the generic's
                        --  own name -- so a call to itself inside the generic
                        --  calls *this* instance, which is what Ada means by
                        --  a recursive generic.
                        Bindings : S.Renamings (1 .. Wanted + 1);
                     begin
                        for Index in 1 .. Wanted loop
                           Bindings (Index) :=
                             (From =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (S.Text
                                     (Tree,
                                      S.First
                                        (Tree,
                                         S.Child (Tree, Formals, Index)))),
                              To   =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (S.Text (Tree,
                                           S.Child (Tree, Given, Index))));
                        end loop;

                        Bindings (Wanted + 1) :=
                          (From =>
                             Ada.Strings.Unbounded.To_Unbounded_String
                               (S.Text (Tree, S.First (Tree, Template_Body))),
                           To   =>
                             Ada.Strings.Unbounded.To_Unbounded_String (Name));

                        declare
                           --  Built rather than grafted whole, so that the
                           --  name carries *this* instantiation's span. What
                           --  identifies a subprogram to the lowering is where
                           --  its name was written, and a grafted name would
                           --  carry the generic's -- so two instantiations
                           --  would be one routine and the second would call
                           --  the first.
                           --  One at a time and in order, because each call
                           --  appends to the same tree and Ada does not say
                           --  which actual of an aggregate runs first.
                           Fresh   : constant S.Node_Id :=
                             S.Add_Leaf (Tree, S.Node_Name,
                                         S.Extent (Tree, Named), Name);
                           Formals_Copy : constant S.Node_Id :=
                             S.Graft (Tree, S.Child (Tree, Template_Body, 2),
                                      Bindings);
                           Result_Copy : constant S.Node_Id :=
                             S.Graft (Tree, S.Child (Tree, Template_Body, 3),
                                      Bindings);
                           Declared_Copy : constant S.Node_Id :=
                             S.Graft (Tree, S.Child (Tree, Template_Body, 4),
                                      Bindings);
                           Statements_Copy : constant S.Node_Id :=
                             S.Graft (Tree, S.Child (Tree, Template_Body, 5),
                                      Bindings);

                           Copy : constant S.Node_Id :=
                             S.Add_Node
                               (Tree, S.Node_Subprogram_Declaration,
                                S.Extent (Tree, Node),
                                [Fresh, Formals_Copy, Result_Copy,
                                 Declared_Copy, Statements_Copy]);
                        begin
                           Into.Made.Append
                             (Expansion'(At_Node => Node, Made => Copy));

                           --  Analysed as the ordinary subprogram it now is.
                           --  Everything a generic needs -- a scope, a
                           --  profile, a body, a name in the enclosing region
                           --  -- is what analysing one does.
                           Analyse_Statement (Copy);
                        end;
                     end;
                  end;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Use =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Found : constant Symbols.Symbol := Chain.Lookup (Name);
               begin
                  if Symbols.Is_Nothing (Found) then
                     Complain (Adash.Errors.Error_Name_Undeclared, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);

                  elsif Symbols.Kind (Found) /= Symbols.Symbol_Package then
                     Complain (Adash.Errors.Error_Not_A_Package, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);

                  else
                     --  Remembered rather than copied. A `use` makes what a
                     --  package holds visible without its prefix, and doing
                     --  that by declaring a second symbol per member would
                     --  make a later declaration of the same name a collision
                     --  with something the user never wrote.
                     In_Use.Append
                       (Ada.Strings.Unbounded.To_Unbounded_String
                          (Symbols.Name (Found)));
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Delay =>
               Refuse_If_Restricted (No_Delay, Node);

               if S.Text (Tree, Node) /= "until" then
                  Refuse_If_Restricted (No_Relative_Delay, Node);
               end if;

               declare
                  How_Long : constant Types.Type_Kind :=
                    Analyse_Expression (S.First (Tree, Node),
                                        Types.Type_Float);
               begin
                  --  Seconds, as a Float. Ada's `delay` takes a Duration,
                  --  which is a fixed-point type this language does not have;
                  --  Float is the closest thing it does have and the mapping
                  --  is written down rather than guessed at.
                  if How_Long /= Types.Type_None
                    and then How_Long /= Types.Type_Float
                    and then How_Long /= Types.Type_Integer
                  then
                     Complain (Adash.Errors.Error_Type_Mismatch,
                               S.First (Tree, Node),
                               [Adash.Messages.Named
                                  ("found", Types.Name (How_Long)),
                                Adash.Messages.Named
                                  ("expected",
                                   Types.Name (Types.Type_Float))]);
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Pragma =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Given : constant S.Node_Id := S.Second (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
               begin
                  --  One pragma, and the analyser is where that is said. A
                  --  mechanism that took any name would be a second place to
                  --  configure things, and what a program can say about itself
                  --  belongs in the language rather than beside it.
                  if Symbols.Fold (Name)
                     not in "priority" | "detect_blocking" | "restrictions"
                          | "task_dispatching_policy" | "locking_policy"
                          | "profile" | "priority_specific_dispatching"
                          | "queuing_policy"
                  then
                     Complain (Adash.Errors.Error_Unknown_Pragma, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);

                  elsif Symbols.Fold (Name) = "profile" then
                     --  A profile is a name for a set of these pragmas said
                     --  at once. One this language does not have is refused
                     --  rather than accepted, for the reason an unknown
                     --  restriction is: a program would be told it had given
                     --  something up and go on doing it.
                     declare
                        Only : constant Boolean :=
                          S.Child_Count (Tree, Given) = 1;
                        Asked : constant String :=
                          (if Only
                           then S.Text (Tree, S.Child (Tree, Given, 1))
                           else "");
                        Named : constant Boolean :=
                          Only
                          and then S.Kind (Tree, S.Child (Tree, Given, 1))
                                   = S.Node_Name;
                     begin
                        if not Only then
                           Complain
                             (Adash.Errors.Error_Wrong_Argument_Count, Node,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("expected", Natural'Image (1)),
                               Adash.Messages.Named
                                 ("found",
                                  Natural'Image
                                    (S.Child_Count (Tree, Given)))]);

                        elsif not Named
                          or else Symbols.Fold (Asked)
                                  not in "ravenscar" | "jorvik"
                        then
                           Complain
                             (Adash.Errors.Error_Unknown_Profile,
                              S.Child (Tree, Given, 1),
                              [1 => Adash.Messages.Named
                                      ("name",
                                       (if Asked = "" then Name
                                        else Asked))]);

                        else
                           --  A profile says a dispatching policy about every
                           --  priority, so it is one of the things that can
                           --  give a priority two answers.
                           Give_Dispatching
                             (Keeps_Its_Turn, Dispatch'First, Dispatch'Last,
                              Name, Node);
                        end if;
                     end;

                  elsif Symbols.Fold (Name)
                        in "task_dispatching_policy" | "locking_policy"
                  then
                     --  A policy names one thing, and the ones this machine
                     --  can honestly be told about are the ones it does or
                     --  can do. A policy accepted and not implemented would
                     --  be the same lie a restriction nobody checks is.
                     declare
                        Only : constant Boolean :=
                          S.Child_Count (Tree, Given) = 1;
                        --  Whatever stands there, spelled as it was written:
                        --  a policy is named, so anything else is refused,
                        --  and the user is shown what they wrote.
                        Asked : constant String :=
                          (if Only
                           then S.Text (Tree, S.Child (Tree, Given, 1))
                           else "");

                        --  A policy is named. A string spelling one is not
                        --  one, however it reads.
                        Named : constant Boolean :=
                          Only
                          and then S.Kind (Tree, S.Child (Tree, Given, 1))
                                   = S.Node_Name;
                     begin
                        if not Only then
                           Complain
                             (Adash.Errors.Error_Wrong_Argument_Count, Node,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("expected", Natural'Image (1)),
                               Adash.Messages.Named
                                 ("found",
                                  Natural'Image
                                    (S.Child_Count (Tree, Given)))]);

                        elsif Symbols.Fold (Name) = "locking_policy" then
                           if not Named
                             or else Symbols.Fold (Asked) /= "ceiling_locking"
                           then
                              Complain
                                (Adash.Errors.Error_Unknown_Policy,
                                 S.Child (Tree, Given, 1),
                                 [1 => Adash.Messages.Named
                                         ("name",
                                          (if Asked = "" then Name
                                           else Asked))]);
                           end if;

                        elsif not Named
                          or else Symbols.Fold (Asked)
                                  not in "fifo_within_priorities"
                                       | "round_robin_within_priorities"
                        then
                           Complain
                             (Adash.Errors.Error_Unknown_Policy,
                              S.Child (Tree, Given, 1),
                              [1 => Adash.Messages.Named
                                      ("name",
                                       (if Asked = "" then Name
                                        else Asked))]);

                        else
                           Give_Dispatching
                             ((if Symbols.Fold (Asked)
                                  = "fifo_within_priorities"
                               then Keeps_Its_Turn else Shares_It),
                              Dispatch'First, Dispatch'Last, Name, Node);
                        end if;
                     end;

                  elsif Symbols.Fold (Name) = "queuing_policy" then
                     --  How callers are taken off an entry queue. Both of
                     --  Ada's are implemented, so both are accepted: order of
                     --  arrival, which is what the machine does when nobody
                     --  says, and priority, which is that among callers of
                     --  equal priority.
                     declare
                        Only : constant Boolean :=
                          S.Child_Count (Tree, Given) = 1;
                        Asked : constant String :=
                          (if Only
                           then S.Text (Tree, S.Child (Tree, Given, 1))
                           else "");
                        Named : constant Boolean :=
                          Only
                          and then S.Kind (Tree, S.Child (Tree, Given, 1))
                                   = S.Node_Name;
                     begin
                        if not Only then
                           Complain
                             (Adash.Errors.Error_Wrong_Argument_Count, Node,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("expected", Natural'Image (1)),
                               Adash.Messages.Named
                                 ("found",
                                  Natural'Image
                                    (S.Child_Count (Tree, Given)))]);

                        elsif not Named
                          or else Symbols.Fold (Asked)
                                  not in "fifo_queuing" | "priority_queuing"
                        then
                           Complain
                             (Adash.Errors.Error_Unknown_Policy,
                              S.Child (Tree, Given, 1),
                              [1 => Adash.Messages.Named
                                      ("name",
                                       (if Asked = "" then Name
                                        else Asked))]);

                        else
                           declare
                              Said : constant Queuing :=
                                (if Symbols.Fold (Asked) = "priority_queuing"
                                 then By_Priority else By_Arrival);
                           begin
                              --  Two answers to one question, which would
                              --  leave the reader to guess which the machine
                              --  took. Saying the same thing twice is not
                              --  that.
                              if Queued_As not in Nothing_Said | Said then
                                 Complain
                                   (Adash.Errors.Error_Queuing_Twice, Node,
                                    [1 => Adash.Messages.Named
                                            ("name", Name)]);
                              end if;

                              Queued_As := Said;
                           end;
                        end if;
                     end;

                  elsif Symbols.Fold (Name)
                        = "priority_specific_dispatching"
                  then
                     --  A policy given to a range of priorities rather than
                     --  to all of them: a program may want the strands doing
                     --  its important work left alone and the rest shared
                     --  out, and Ada lets it say so.
                     declare
                        Three : constant Boolean :=
                          S.Child_Count (Tree, Given) = 3;
                        Asked : constant String :=
                          (if Three
                           then S.Text (Tree, S.Child (Tree, Given, 1))
                           else "");
                        Named : constant Boolean :=
                          Three
                          and then S.Kind (Tree, S.Child (Tree, Given, 1))
                                   = S.Node_Name;
                        First : Long_Long_Integer := 0;
                        Last  : Long_Long_Integer := 0;
                     begin
                        if not Three then
                           Complain
                             (Adash.Errors.Error_Wrong_Argument_Count, Node,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("expected", Natural'Image (3)),
                               Adash.Messages.Named
                                 ("found",
                                  Natural'Image
                                    (S.Child_Count (Tree, Given)))]);

                        elsif not Named
                          or else Symbols.Fold (Asked)
                                  not in "fifo_within_priorities"
                                       | "round_robin_within_priorities"
                        then
                           Complain
                             (Adash.Errors.Error_Unknown_Policy,
                              S.Child (Tree, Given, 1),
                              [1 => Adash.Messages.Named
                                      ("name",
                                       (if Asked = "" then Name
                                        else Asked))]);

                        elsif not Static_Choice
                                 (Into, Tree, S.Child (Tree, Given, 2), First)
                          or else First < Long_Long_Integer (Dispatch'First)
                          or else First > Long_Long_Integer (Dispatch'Last)
                        then
                           Complain
                             (Adash.Errors.Error_Priority_Not_Static,
                              S.Child (Tree, Given, 2), []);

                        elsif not Static_Choice
                                 (Into, Tree, S.Child (Tree, Given, 3), Last)
                          or else Last < Long_Long_Integer (Dispatch'First)
                          or else Last > Long_Long_Integer (Dispatch'Last)
                        then
                           Complain
                             (Adash.Errors.Error_Priority_Not_Static,
                              S.Child (Tree, Given, 3), []);

                        elsif Last < First then
                           --  A range that runs backwards names no priority
                           --  at all, so a program that wrote one meant
                           --  something it did not get.
                           Complain
                             (Adash.Errors.Error_Empty_Priority_Range, Node,
                              [Adash.Messages.Named
                                 ("first", Long_Long_Integer'Image (First)),
                               Adash.Messages.Named
                                 ("last", Long_Long_Integer'Image (Last))]);

                        else
                           Give_Dispatching
                             ((if Symbols.Fold (Asked)
                                  = "fifo_within_priorities"
                               then Keeps_Its_Turn else Shares_It),
                              Natural (First), Natural (Last), Name, Node);
                        end if;
                     end;

                  elsif Symbols.Fold (Name) = "restrictions" then
                     --  Read before anything was analysed, so that what a
                     --  program forbids itself holds for the whole of it
                     --  rather than for what happens to follow the pragma.
                     --  What is left here is saying whether each name is one
                     --  this language knows.
                     for Index in 1 .. S.Child_Count (Tree, Given) loop
                        declare
                           One : constant S.Node_Id :=
                             S.Child (Tree, Given, Index);
                           --  `Max_Tasks => 2` names the restriction on the
                           --  left of the arrow.
                           Named_It : constant S.Node_Id :=
                             (if S.Kind (Tree, One) = S.Node_Named_Argument
                              then S.First (Tree, One) else One);
                           Asked : constant String :=
                             (if S.Kind (Tree, Named_It) = S.Node_Name
                              then S.Text (Tree, Named_It) else "");
                           Known : Boolean := False;
                        begin
                           for Each in Restriction loop
                              if Symbols.Fold (Spelling (Each))
                                 = Symbols.Fold (Asked)
                              then
                                 Known := True;
                              end if;
                           end loop;

                           if not Known then
                              Complain
                                (Adash.Errors.Error_Unknown_Restriction, One,
                                 [1 => Adash.Messages.Named
                                         ("name",
                                          (if Asked = "" then Name
                                           else Asked))]);
                           end if;
                        end;
                     end loop;

                  elsif Symbols.Fold (Name) = "detect_blocking" then
                     --  A configuration pragma: it says something about the
                     --  whole program rather than about the point it stands
                     --  at, so it takes nothing and there is nothing to check
                     --  but that.
                     if S.Child_Count (Tree, Given) /= 0 then
                        Complain
                          (Adash.Errors.Error_Wrong_Argument_Count, Node,
                           [Adash.Messages.Named ("name", Name),
                            Adash.Messages.Named
                              ("expected", Natural'Image (0)),
                            Adash.Messages.Named
                              ("found",
                               Natural'Image (S.Child_Count (Tree, Given)))]);
                     end if;

                  elsif S.Child_Count (Tree, Given) /= 1 then
                     Complain
                       (Adash.Errors.Error_Wrong_Argument_Count, Node,
                        [Adash.Messages.Named ("name", Name),
                         Adash.Messages.Named
                           ("expected", Natural'Image (1)),
                         Adash.Messages.Named
                           ("found",
                            Natural'Image (S.Child_Count (Tree, Given)))]);

                  else
                     declare
                        Level : constant S.Node_Id :=
                          S.Child (Tree, Given, 1);
                        Gets  : constant Types.Type_Kind :=
                          Analyse_Expression (Level, Types.Type_Integer);
                        Value : Long_Long_Integer;
                     begin
                        if Gets /= Types.Type_None
                          and then Gets /= Types.Type_Integer
                        then
                           Complain
                             (Adash.Errors.Error_Type_Mismatch, Level,
                              [Adash.Messages.Named
                                 ("found", Types.Name (Gets)),
                               Adash.Messages.Named
                                 ("expected",
                                  Types.Name (Types.Type_Integer))]);

                        elsif not Static_Choice (Into, Tree, Level, Value)
                          or else Value < 0
                          or else Value > 30
                        then
                           --  A priority is settled where it is written: what
                           --  a task runs at is decided when it starts, and a
                           --  number worked out later would be a priority the
                           --  scheduler had already acted without.
                           Complain
                             (Adash.Errors.Error_Priority_Not_Static, Level,
                              Adash.Messages.No_Arguments);
                        end if;
                     end;
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Requeue =>
               Refuse_If_Restricted (No_Requeue_Statements, Node);

               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Which_One : constant S.Node_Id :=
                    (if S.Child_Count (Tree, Node) >= 2
                     then S.Second (Tree, Node) else S.No_Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Found : constant Symbols.Symbol :=
                    Chain.Lookup (Full_Name (Name));
               begin
                  --  An entry of the unit being analysed, which is where a
                  --  requeue may stand and what it may name. Ada allows the
                  --  target to be any entry at all; here it is one of the same
                  --  unit, because what the caller is moved to has to be a
                  --  queue this unit can put it on -- another object's is
                  --  reached through a name the body may not even have.
                  if Symbols.Kind (Found) /= Symbols.Symbol_Entry then
                     Complain (Adash.Errors.Error_Requeue_Not_An_Entry, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  Ada's rule about profiles: the target takes nothing, or
                  --  takes what the caller already gave. Only the first is
                  --  possible here, because what the caller gave sits in a run
                  --  of its own slots and a target with a profile of its own
                  --  would be reading it by somebody else's layout.
                  if Symbols.Parameter_Count (Found) /= 0 then
                     Complain (Adash.Errors.Error_Requeue_Takes_Nothing, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);

                  elsif Symbols.Of_Type (Found) = Types.Type_None then
                     if S.Is_Present (Which_One) then
                        Complain (Adash.Errors.Error_Not_A_Family, Named,
                                  [1 => Adash.Messages.Named ("name", Name)]);
                     end if;

                  elsif not S.Is_Present (Which_One) then
                     Complain (Adash.Errors.Error_Family_Needs_A_Member, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);

                  else
                     declare
                        Wants : constant Types.Type_Kind :=
                          Symbols.Of_Type (Found);
                        Gets  : constant Types.Type_Kind :=
                          Analyse_Expression (Which_One, Wants);
                     begin
                        if Gets /= Types.Type_None
                          and then not Types.Is_Acceptable (Gets, Wants)
                        then
                           Complain
                             (Adash.Errors.Error_Type_Mismatch, Which_One,
                              [Adash.Messages.Named
                                 ("found", Types.Name (Gets)),
                               Adash.Messages.Named
                                 ("expected", Types.Name (Wants))]);
                        end if;
                     end;
                  end if;

                  Note (Named, Types.Type_None, Found);
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Abort =>
               Refuse_If_Restricted (No_Abort_Statements, Node);

               for Index in 1 .. S.Child_Count (Tree, Node) loop
                  declare
                     Named : constant S.Node_Id := S.Child (Tree, Node, Index);
                     Name  : constant String := S.Text (Tree, Named);
                     Found : constant Symbols.Symbol := Visible (Name);
                  begin
                     if Symbols.Is_Nothing (Found) then
                        Complain (Adash.Errors.Error_Name_Undeclared, Named,
                                  [1 => Adash.Messages.Named ("name", Name)]);
                     elsif not Types.Is_Task (Symbols.Of_Type (Found))
                       or else Symbols.Kind (Found) = Symbols.Symbol_Type
                     then
                        --  A task *object*, not a task type: what an abort
                        --  stops is something running, and a type is not
                        --  running.
                        Complain (Adash.Errors.Error_Not_A_Task, Named,
                                  [1 => Adash.Messages.Named ("name", Name)]);
                     end if;

                     Note (Named, Types.Type_None, Found);
                  end;
               end loop;

               Note (Node, Types.Type_None);

            when S.Node_Select =>
               Refuse_If_Restricted (No_Select_Statements, Node);

               declare
                  Call      : constant S.Node_Id := S.First (Tree, Node);
                  Taken     : constant S.Node_Id := S.Second (Tree, Node);
                  How_Long  : constant S.Node_Id := S.Third (Tree, Node);
                  Otherwise : constant S.Node_Id := S.Child (Tree, Node, 4);
                  Named : constant S.Node_Id :=
                    (if S.Kind (Tree, Call) = S.Node_Procedure_Call
                     then S.First (Tree, Call) else Call);

                  Wanted : constant String := Name_For_Call (Named);
               begin
                  Analyse_Statement (Call);

                  --  A select waits on an *entry*, and an entry is the one
                  --  callable thing with a barrier. Said here rather than left
                  --  to the lowering, which would report it as something not
                  --  built yet.
                  if Wanted /= ""
                    and then Symbols.Kind (Visible (Wanted))
                             /= Symbols.Symbol_Entry
                  then
                     Complain (Adash.Errors.Error_Not_An_Entry, Named,
                               [1 => Adash.Messages.Named
                                       ("name", Wanted)]);
                  end if;

                  if S.Is_Present (How_Long) then
                     declare
                        Ignored : constant Types.Type_Kind :=
                          Analyse_Expression (How_Long, Types.Type_Float);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  end if;

                  Analyse_Sequence (Taken);
                  Analyse_Sequence (Otherwise);
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Then_Abort =>
               Refuse_If_Restricted (No_Select_Statements, Node);
               Refuse_If_Restricted (No_Abort_Statements, Node);

               declare
                  Trigger : constant S.Node_Id := S.First (Tree, Node);
                  Taken   : constant S.Node_Id := S.Second (Tree, Node);
                  Part    : constant S.Node_Id := S.Third (Tree, Node);

                  Named : constant S.Node_Id :=
                    (if S.Kind (Tree, Trigger) = S.Node_Procedure_Call
                     then S.First (Tree, Trigger) else Trigger);
               begin
                  Analyse_Statement (Trigger);

                  --  A trigger is an entry call or a delay: something that
                  --  happens on somebody else's terms, which is the whole
                  --  point of abandoning work when it does.
                  if S.Kind (Tree, Trigger) /= S.Node_Delay then
                     declare
                        Wanted : constant String := Name_For_Call (Named);
                     begin
                        if Wanted = "" then
                           Complain (Adash.Errors.Error_Select_Trigger,
                                     Trigger, Adash.Messages.No_Arguments);

                        elsif Symbols.Kind (Visible (Wanted))
                              /= Symbols.Symbol_Entry
                        then
                           Complain (Adash.Errors.Error_Not_An_Entry, Named,
                                     [1 => Adash.Messages.Named
                                             ("name", Wanted)]);
                        end if;
                     end;
                  end if;

                  Analyse_Sequence (Taken);

                  --  The abortable part is a scope of its own, because it
                  --  runs as a strand of its own: what it declares belongs to
                  --  the frame that is abandoned with it.
                  Chain.Enter;
                  Analyse_Sequence (Part);
                  Chain.Leave;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Selective_Accept =>
               Refuse_If_Restricted (No_Select_Statements, Node);

               declare
                  Choices   : constant S.Node_Id := S.First (Tree, Node);
                  Otherwise : constant S.Node_Id := S.Second (Tree, Node);

                  --  How many alternatives bound the wait rather than serving
                  --  a caller. At most one, and none at all beside an `else`:
                  --  the two say different things about what to do when
                  --  nothing can be accepted, and a select that said both
                  --  would have to decide which it meant.
                  Delays : Natural := 0;

                  --  How many say the task may end instead of waiting. At
                  --  most one, and none beside a delay or an `else`: those
                  --  say what to do when nothing can be accepted *now*, and
                  --  this says the task has nothing left to wait for at all.
                  Ends : Natural := 0;
               begin
                  for Index in 1 .. S.Child_Count (Tree, Choices) loop
                     declare
                        One   : constant S.Node_Id :=
                          S.Child (Tree, Choices, Index);
                        Guard : constant S.Node_Id := S.First (Tree, One);
                        Taken : constant S.Node_Id := S.Second (Tree, One);
                        Rest  : constant S.Node_Id := S.Third (Tree, One);
                     begin
                        if S.Is_Present (Guard) then
                           declare
                              Of_Guard : constant Types.Type_Kind :=
                                Analyse_Expression (Guard, Types.Type_Boolean);
                           begin
                              if Of_Guard /= Types.Type_None
                                and then Of_Guard /= Types.Type_Boolean
                              then
                                 Complain
                                   (Adash.Errors.Error_Condition_Not_Boolean,
                                    Guard,
                                    [1 => Adash.Messages.Named
                                            ("found", Types.Name (Of_Guard))]);
                              end if;
                           end;
                        end if;

                        case S.Kind (Tree, Taken) is
                           when S.Node_Accept =>
                              null;

                           when S.Node_Terminate =>
                              Ends := Ends + 1;

                           when S.Node_Delay =>
                              Delays := Delays + 1;

                           when others =>
                              --  An alternative is what the select is waiting
                              --  for, and there are two things a task waits
                              --  for: a caller, and the clock.
                              Complain
                                (Adash.Errors.Error_Select_Alternative,
                                 Taken, Adash.Messages.No_Arguments);
                        end case;

                        --  A terminate alternative has no parts to analyse
                        --  and is refused wherever else it stands, so it is
                        --  not handed on as a statement: reaching it here is
                        --  what makes it legal.
                        if S.Kind (Tree, Taken) /= S.Node_Terminate then
                           Analyse_Statement (Taken);
                        else
                           Note (Taken, Types.Type_None);
                        end if;

                        Analyse_Sequence (Rest);
                     end;
                  end loop;

                  if Delays > 1
                    or else (Delays > 0 and then S.Is_Present (Otherwise))
                    or else Ends > 1
                    or else (Ends > 0
                             and then (Delays > 0
                                       or else S.Is_Present (Otherwise)))
                  then
                     Complain (Adash.Errors.Error_Select_Waits_Twice, Node,
                               Adash.Messages.No_Arguments);
                  end if;

                  Analyse_Sequence (Otherwise);
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Exception_Declaration =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Error : Adash.Errors.Error_Info;
               begin
                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (Name), Symbols.Symbol_Exception,
                        Types.Type_None, Origin, S.Extent (Tree, Named)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Named);
                  end if;

                  Note (Node, Types.Type_None);
                  Note (Named, Types.Type_None);
               end;

            when S.Node_Raise =>
               declare
                  What : constant S.Node_Id := S.First (Tree, Node);
               begin
                  if not S.Is_Present (What) then
                     --  `raise;` alone, which raises again what the handler it
                     --  stands in caught. Outside one there is nothing to
                     --  raise again, and Ada says so.
                     if Handler_Depth = 0 then
                        Complain
                          (Adash.Errors.Error_Raise_Outside_A_Handler, Node,
                           Adash.Messages.No_Arguments);
                     end if;

                  elsif not Adash.Predefined.Is_Exception
                              (S.Text (Tree, What))
                    and then Symbols."/=" (Symbols.Kind
                                             (Visible (S.Text (Tree, What))),
                                           Symbols.Symbol_Exception)
                  then
                     Complain
                       (Adash.Errors.Error_Not_An_Exception, What,
                        [1 => Adash.Messages.Named
                                ("name", S.Text (Tree, What))]);
                  else
                     Note (What, Types.Type_None);
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Terminate =>
               --  Reached as a statement rather than through the select that
               --  would give it a meaning. What it says is about a task with
               --  nothing left to wait for, and there is nothing to wait for
               --  where no select is waiting.
               Complain (Adash.Errors.Error_Terminate_Outside_Select, Node,
                         Adash.Messages.No_Arguments);
               Note (Node, Types.Type_None);

            when S.Node_Select_Alternative =>
               --  Reached only through the select that holds it, which
               --  analyses its parts in the order their meanings depend on.
               Note (Node, Types.Type_None);

            when S.Node_Task_Declaration | S.Node_Protected_Declaration =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Held  : constant S.Node_Id := S.Second (Tree, Node);
                  Outer : constant String :=
                    Ada.Strings.Unbounded.To_String (Prefix);
                  Error : Adash.Errors.Error_Info;

                  --  How many entries it has. Counted where they are
                  --  declared, which is the one place they are all together.
                  Entries : Natural := 0;

                  Bounded_By : constant Restriction :=
                    (if S.Kind (Tree, Node) = S.Node_Task_Declaration
                     then Max_Task_Entries else Max_Protected_Entries);
               begin
                  if Master_Depth > 0 then
                     --  Declared where something other than the outermost
                     --  region is its master. What the restrictions buy a
                     --  reader is that the whole shape of a program's
                     --  concurrency is written where the program begins.
                     if S.Kind (Tree, Node) = S.Node_Task_Declaration then
                        Refuse_If_Restricted (No_Task_Hierarchy, Node);
                     else
                        Refuse_If_Restricted
                          (No_Local_Protected_Objects, Node);
                     end if;
                  end if;

                  for Index in 1 .. S.Child_Count (Tree, Held) loop
                     if S.Kind (Tree, S.Child (Tree, Held, Index))
                        = S.Node_Entry
                     then
                        Entries := Entries + 1;
                     end if;
                  end loop;

                  if Restricted (Bounded_By)
                    and then Entries > Limits (Bounded_By)
                  then
                     Refuse_If_Restricted (Bounded_By, Node);
                  end if;

                  if Adash.Predefined.Profile_Of (Name).Known
                    and then Is_Its_Own_Name
                  then
                     Complain (Adash.Errors.Error_Name_Is_Predefined, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  A protected *type* is a template: what an object of one
                  --  has is state and a lock of its own, so nothing is
                  --  declared here beyond the type's own name. The members
                  --  belong to the objects, and each object is a copy.
                  if S.Kind (Tree, Node) = S.Node_Protected_Declaration
                    and then S.Text (Tree, Node) = "type"
                  then
                     declare
                        Error : Adash.Errors.Error_Info;
                     begin
                        if not Chain.Declare_Symbol
                          (Symbols.Make
                             (Under (Outer, Name), Symbols.Symbol_Type,
                              Types.Protected_Type
                                (S.Extent (Tree, Named).First,
                                 Under (Outer, Name)),
                              Origin, S.Extent (Tree, Named)),
                           Error)
                        then
                           Legal := False;
                           Refuse_Declaration (Error, Named);
                        end if;

                        if Guarded_Template (Under (Outer, Name)) = 0 then
                           Guarded_Types.Append
                             (Template'
                                (Key =>
                                   Ada.Strings.Unbounded
                                     .To_Unbounded_String
                                       (Symbols.Fold (Under (Outer, Name))),
                                 At_Node => Node,
                                 Made_Of => S.No_Node));
                        end if;
                     end;

                     Note (Named, Types.Type_None,
                           Chain.Lookup (Under (Outer, Name)));
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  What its discriminants default to, analysed here rather
                  --  than at each object: a default belongs to the type, and
                  --  what a name in one means is settled by what is in scope
                  --  where the type was written.
                  if S.Text (Tree, Node) = "type"
                    and then S.Child_Count (Tree, Node) >= 4
                  then
                     declare
                        Given : constant S.Node_Id := S.Child (Tree, Node, 4);
                     begin
                        for Index in 1 .. S.Child_Count (Tree, Given) loop
                           declare
                              One : constant S.Node_Id :=
                                S.Child (Tree, Given, Index);
                              Falls_Back : constant S.Node_Id :=
                                Default_Of (Given, Index);
                              Wants : constant Types.Type_Kind :=
                                Named_Type (S.Second (Tree, One));
                           begin
                              if S.Is_Present (Falls_Back) then
                                 declare
                                    Gets : constant Types.Type_Kind :=
                                      Analyse_Expression
                                        (Falls_Back, Wants);
                                 begin
                                    if Gets /= Types.Type_None
                                      and then Wants /= Types.Type_None
                                      and then not Types.Is_Acceptable
                                                     (Gets, Wants)
                                    then
                                       Complain
                                         (Adash.Errors.Error_Type_Mismatch,
                                          Falls_Back,
                                          [Adash.Messages.Named
                                             ("found", Types.Name (Gets)),
                                           Adash.Messages.Named
                                             ("expected",
                                              Types.Name (Wants))]);
                                    end if;
                                 end;
                              end if;
                           end;
                        end loop;
                     end;
                  end if;

                  --  Discriminants belong to a *type*. A single task or a
                  --  single protected object is elaborated where it is
                  --  declared and there is nowhere to write what it would
                  --  take; Ada's answer is a default on every one of them,
                  --  which is a second way of giving one something when it
                  --  already has operations.
                  if S.Text (Tree, Node) /= "type"
                    and then S.Child_Count (Tree, Node) >= 4
                    and then S.Child_Count (Tree, S.Child (Tree, Node, 4)) > 0
                  then
                     Complain (Adash.Errors.Error_Discriminants_Need_A_Type,
                               Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                  end if;

                  --  A package as far as names go: what it holds is declared
                  --  beside it under a dotted name, and `P.Set (1)` reaches
                  --  one exactly as a package member is reached. What makes it
                  --  a task or a protected object is what the *lowering* does
                  --  with the bodies, not how the names work.
                  --
                  --  A task is the exception, because a task is a value: what
                  --  it holds names the strand running it, and a rendezvous
                  --  has to find that rather than the routine. `task T` is one
                  --  object; `task type W` is a type whose objects are each a
                  --  task of their own. Both declare their entries beside
                  --  themselves under a dotted name, which is what lets one
                  --  rule find an entry for either.
                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Under (Outer, Name),
                        (if S.Kind (Tree, Node) /= S.Node_Task_Declaration
                         then Symbols.Symbol_Package
                         elsif S.Text (Tree, Node) = "type"
                         then Symbols.Symbol_Type
                         else Symbols.Symbol_Variable),
                        (if S.Kind (Tree, Node) = S.Node_Task_Declaration
                         then Types.Task_Type
                                (S.Extent (Tree, Named).First,
                                 Under (Outer, Name))
                         else Types.Type_None),
                        Origin, S.Extent (Tree, Named)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Named);
                  end if;

                  declare
                     Was_Spec : constant Boolean := In_Package_Spec;
                     Was_Held : constant Boolean := In_Protected;
                  begin
                     In_Package_Spec := True;
                     In_Protected :=
                       S.Kind (Tree, Node) = S.Node_Protected_Declaration;
                     Prefix :=
                       Ada.Strings.Unbounded.To_Unbounded_String
                         (Under (Outer, Name));
                     Analyse_Sequence (Held);
                     Prefix :=
                       Ada.Strings.Unbounded.To_Unbounded_String (Outer);
                     In_Package_Spec := Was_Spec;
                     In_Protected := Was_Held;
                  end;

                  Note (Named, Types.Type_None,
                        Chain.Lookup (Under (Outer, Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Task_Body | S.Node_Protected_Body =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Held  : constant S.Node_Id := S.Second (Tree, Node);
                  Outer : constant String :=
                    Ada.Strings.Unbounded.To_String (Prefix);

                  --  A body completes what was declared: a protected object
                  --  is named like a package, and a task or a task type is a
                  --  value or a type whose values are tasks.
                  Completes : constant Symbols.Symbol :=
                    Chain.Lookup (Under (Outer, Name));
               begin
                  --  A protected type's body is a template too, and is not
                  --  analysed where it stands: what its names mean depends on
                  --  which object they belong to, and there is nothing to
                  --  conclude until one is declared.
                  if S.Kind (Tree, Node) = S.Node_Protected_Body
                    and then Guarded_Template (Under (Outer, Name)) /= 0
                  then
                     declare
                        Which : constant Positive :=
                          Guarded_Template (Under (Outer, Name));
                        Held_Template : Template :=
                          Guarded_Types.Element (Which);
                     begin
                        Held_Template.Made_Of := Node;
                        Guarded_Types.Replace_Element (Which, Held_Template);
                     end;

                     Note (Named, Types.Type_None, Completes);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if Symbols.Kind (Completes) /= Symbols.Symbol_Package
                    and then not Types.Is_Task (Symbols.Of_Type (Completes))
                    and then not Types.Is_Protected
                                   (Symbols.Of_Type (Completes))
                  then
                     Complain (Adash.Errors.Error_Package_Not_Declared, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  Prefix :=
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Under (Outer, Name));

                  if S.Kind (Tree, Node) = S.Node_Task_Body then
                     --  A task body is statements rather than declarations:
                     --  what it holds is what it does. Analysed as a scope of
                     --  its own, because its own declarations are its own.
                     Chain.Enter;
                     Master_Depth := Master_Depth + 1;

                     --  Its discriminants, which were written on the
                     --  declaration and are in scope here without being
                     --  repeated. Constants: a discriminant is what the object
                     --  was elaborated with, and there is nothing to assign to
                     --  after that.
                     declare
                        Given : constant S.Node_Id :=
                          Discriminants_Of (Under (Outer, Name));
                        Fault : Adash.Errors.Error_Info;
                     begin
                        for Index in 1 .. S.Child_Count (Tree, Given) loop
                           declare
                              One : constant S.Node_Id :=
                                S.Child (Tree, Given, Index);
                              Of_It : constant Types.Type_Kind :=
                                Named_Type (S.Second (Tree, One));
                           begin
                              if not Chain.Declare_Symbol
                                (Symbols.Make
                                   (S.Text (Tree, S.First (Tree, One)),
                                    Symbols.Symbol_Constant, Of_It, Origin,
                                    S.Extent (Tree, S.First (Tree, One))),
                                 Fault)
                              then
                                 Legal := False;
                                 Refuse_Declaration (Fault, One);
                              end if;

                              Note (S.First (Tree, One), Of_It,
                                    Chain.Lookup
                                      (S.Text (Tree, S.First (Tree, One))));
                           end;
                        end loop;
                     end;

                     Analyse_Sequence (Held);

                     if S.Child_Count (Tree, Node) >= 3
                       and then S.Is_Present (S.Third (Tree, Node))
                     then
                        Analyse_Handlers (S.Third (Tree, Node));
                     end if;

                     Master_Depth := Master_Depth - 1;
                     Chain.Leave;
                  else
                     Analyse_Sequence (Held);
                  end if;

                  Prefix := Ada.Strings.Unbounded.To_Unbounded_String (Outer);

                  Note (Named, Types.Type_None,
                        Chain.Lookup (Under (Outer, Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Accept =>
               declare
                  Named   : constant S.Node_Id := S.First (Tree, Node);
                  Formals : constant S.Node_Id := S.Second (Tree, Node);
                  Held    : constant S.Node_Id := S.Third (Tree, Node);
                  Name    : constant String := S.Text (Tree, Named);
                  Found   : constant Symbols.Symbol := Visible (Name);
                  Error   : Adash.Errors.Error_Info;
               begin
                  if Symbols.Is_Nothing (Found)
                    or else Symbols.Kind (Found) /= Symbols.Symbol_Entry
                  then
                     Complain (Adash.Errors.Error_Not_An_Entry, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  The formals are the entry's, written again as Ada writes
                  --  them, and they name the caller's own arguments: the
                  --  accept body reaches through to where the caller put them,
                  --  which is what makes an `out` parameter come back.
                  --
                  --  Which member of a family it serves. An entry that is one
                  --  needs an index and an entry that is not takes none: what
                  --  says which is the type the entry carries, because an
                  --  entry yields nothing and that is what the type is free to
                  --  say.
                  declare
                     Which_One : constant S.Node_Id :=
                       (if S.Child_Count (Tree, Node) >= 4
                        then S.Child (Tree, Node, 4) else S.No_Node);
                     Indexed_By : constant Types.Type_Kind :=
                       Symbols.Of_Type (Found);
                  begin
                     if Indexed_By = Types.Type_None then
                        if S.Is_Present (Which_One) then
                           Complain
                             (Adash.Errors.Error_Not_A_Family, Named,
                              [1 => Adash.Messages.Named ("name", Name)]);
                        end if;

                     elsif not S.Is_Present (Which_One) then
                        Complain
                          (Adash.Errors.Error_Family_Needs_A_Member, Named,
                           [1 => Adash.Messages.Named ("name", Name)]);

                     else
                        declare
                           Gets : constant Types.Type_Kind :=
                             Analyse_Expression (Which_One, Indexed_By);
                        begin
                           if Gets /= Types.Type_None
                             and then not Types.Is_Acceptable
                                            (Gets, Indexed_By)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, Which_One,
                                 [Adash.Messages.Named
                                    ("found", Types.Name (Gets)),
                                  Adash.Messages.Named
                                    ("expected", Types.Name (Indexed_By))]);
                           end if;
                        end;
                     end if;
                  end;

                  --  Written again, and so checked against what was declared.
                  --  The caller writes its arguments by the entry's profile
                  --  and the body reads them by this one, so an accept that
                  --  repeated the profile differently would have one side
                  --  writing a number where the other reads text.
                  if S.Child_Count (Tree, Formals)
                     /= Symbols.Parameter_Count (Found)
                  then
                     Complain (Adash.Errors.Error_Accept_Differs, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                  end if;

                  Chain.Enter;

                  for Index in 1 .. S.Child_Count (Tree, Formals) loop
                     declare
                        One : constant S.Node_Id :=
                          S.Child (Tree, Formals, Index);
                        Spelt : constant String := S.Text (Tree, One);
                        Of_Formal : constant Types.Type_Kind :=
                          Named_Type (S.Second (Tree, One));
                        Passing : constant Symbols.Parameter_Mode :=
                          (if Spelt = "out" then Symbols.Mode_Out
                           elsif Spelt = "in out" then Symbols.Mode_In_Out
                           else Symbols.Mode_In);
                     begin
                        if Index <= Symbols.Parameter_Count (Found)
                          and then
                            (Of_Formal
                               /= Symbols.Parameter_Type (Found, Index)
                             or else Symbols."/="
                                       (Passing,
                                        Symbols.Parameter_Passing
                                          (Found, Index)))
                        then
                           Complain
                             (Adash.Errors.Error_Accept_Differs, One,
                              [1 => Adash.Messages.Named ("name", Name)]);
                        end if;

                        if not Chain.Declare_Symbol
                          (Symbols.Make
                             (S.Text (Tree, S.First (Tree, One)),
                              Symbols.Symbol_Parameter, Of_Formal, Origin,
                              S.Extent (Tree, S.First (Tree, One)),
                              Mode => Passing),
                           Error)
                        then
                           Legal := False;
                           Refuse_Declaration (Error, One);
                        end if;

                        Note (S.First (Tree, One), Of_Formal,
                              Chain.Lookup (S.Text (Tree, S.First (Tree, One))));
                     end;
                  end loop;

                  if S.Is_Present (Held) then
                     Analyse_Sequence (Held);
                  end if;

                  Chain.Leave;

                  Note (Named, Types.Type_None, Found);
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Entry =>
               declare
                  Named   : constant S.Node_Id := S.First (Tree, Node);
                  Barrier : constant S.Node_Id := S.Second (Tree, Node);
                  Held    : constant S.Node_Id := S.Third (Tree, Node);
                  Formals : constant S.Node_Id := S.Child (Tree, Node, 4);
                  Name    : constant String := S.Text (Tree, Named);
                  Error   : Adash.Errors.Error_Info;

                  --  `entry Request (Priority);` -- one entry per value of
                  --  Priority. A discrete type, because what indexes a run of
                  --  entries has to be counted.
                  Indexed_By : constant S.Node_Id :=
                    (if S.Child_Count (Tree, Node) >= 5
                     then S.Child (Tree, Node, 5) else S.No_Node);
                  Family_Index : constant Types.Type_Kind :=
                    (if S.Is_Present (Indexed_By)
                     then Named_Type (Indexed_By) else Types.Type_None);

                  --  What the body calls the member it is running for, on the
                  --  body of a family and nowhere else.
                  Index_Named : constant S.Node_Id :=
                    (if S.Child_Count (Tree, Node) >= 6
                     then S.Child (Tree, Node, 6) else S.No_Node);

                  Named_The_Index : Boolean := False;

                  Kinds : Symbols.Parameter_Types :=
                    [others => Types.Type_None];
                  Modes : Symbols.Parameter_Modes :=
                    [others => Symbols.Mode_In];
                  Names : Symbols.Parameter_Names := [others => <>];
                  Given : Symbols.Parameter_Defaults := [others => <>];
                  Has   : Symbols.Parameter_Has_Default := [others => False];
                  Count : constant Natural :=
                    Natural'Min (S.Child_Count (Tree, Formals),
                                 Symbols.Max_Parameters);
               begin
                  --  A family's body is one body for all its members and says
                  --  what to call the member it is running for. In scope for
                  --  the barrier as well as for the statements, because a
                  --  barrier that could not ask which member it was would make
                  --  a family of them no different from one entry.
                  if S.Is_Present (Index_Named) then
                     Chain.Enter;
                     Named_The_Index := True;

                     declare
                        Fault : Adash.Errors.Error_Info;
                     begin
                        if not Chain.Declare_Symbol
                          (Symbols.Make
                             (S.Text (Tree, Index_Named),
                              Symbols.Symbol_Constant, Family_Index, Origin,
                              S.Extent (Tree, Index_Named)),
                           Fault)
                        then
                           Legal := False;
                           Refuse_Declaration (Fault, Index_Named);
                        end if;

                        Note (Index_Named, Family_Index,
                              Chain.Lookup (S.Text (Tree, Index_Named)));
                     end;
                  end if;

                  --  A barrier that is a name or a literal and nothing else.
                  --  What it buys is that reading one is reading a variable,
                  --  so what opens an entry can be seen rather than worked
                  --  out.
                  --  A name, and not one that means a call: the stricter
                  --  restriction cannot admit what the relaxed one refuses.
                  if S.Is_Present (Barrier)
                    and then (S.Kind (Tree, Barrier) not in S.Node_Name
                                                          | S.Node_Selected
                              or else not Pure_Barrier (Barrier))
                  then
                     Refuse_If_Restricted (Simple_Barriers, Barrier);
                  end if;

                  --  The relaxation: worked out is allowed, so long as
                  --  working it out cannot do anything and cannot fail.
                  if S.Is_Present (Barrier)
                    and then Restricted (Pure_Barriers)
                    and then not Pure_Barrier (Barrier)
                  then
                     Refuse_If_Restricted (Pure_Barriers, Barrier);
                  end if;

                  if S.Is_Present (Barrier) then
                     declare
                        Of_Barrier : constant Types.Type_Kind :=
                          Analyse_Expression (Barrier, Types.Type_Boolean);
                     begin
                        if Of_Barrier /= Types.Type_None
                          and then Of_Barrier /= Types.Type_Boolean
                        then
                           Complain
                             (Adash.Errors.Error_Condition_Not_Boolean,
                              Barrier,
                              [1 => Adash.Messages.Named
                                      ("found",
                                       Types.Name (Of_Barrier))]);
                        end if;
                     end;
                  end if;

                  if S.Is_Present (Held) then
                     Chain.Enter;
                     Analyse_Sequence (Held);
                     Chain.Leave;
                  else
                     --  A declaration. Declared with its profile, which is
                     --  what a call to it is matched against -- a task entry
                     --  takes parameters, and a rendezvous is how a task is
                     --  given something and hands something back.
                     if S.Is_Present (Indexed_By) then
                        if not Types.Is_Discrete (Family_Index)
                          or else Types.Admitted_Count (Family_Index)
                                  > Max_Family
                        then
                           --  A run of entries is counted, so what indexes it
                           --  has to be countable.
                           Complain
                             (Adash.Errors.Error_Family_Index_Not_Discrete,
                              Indexed_By,
                              [1 => Adash.Messages.Named
                                      ("found",
                                       Types.Name (Family_Index))]);

                        elsif Count > 0 then
                           --  What a member takes is nothing. The arguments of
                           --  a rendezvous are laid out by the entry that was
                           --  called, and Ada writes a family member with
                           --  parameters as two parenthesised lists -- a
                           --  second shape for a call, where this language has
                           --  one.
                           Complain
                             (Adash.Errors.Error_Family_Takes_Nothing, Named,
                              [1 => Adash.Messages.Named ("name", Name)]);
                        end if;
                     end if;

                     if In_Protected and then Count > 0 then
                        Complain
                          (Adash.Errors.Error_Protected_Entry_Parameters,
                           Named,
                           [1 => Adash.Messages.Named ("name", Name)]);
                     end if;

                     Read_Formals
                       (Formals, Count, Kinds, Names, Modes, Given, Has);

                     for Index in 1 .. Count loop
                        --  The arguments of a rendezvous live in a run of the
                        --  caller's slots, one slot each, and a composite is
                        --  itself a run: it would need a run inside a run, and
                        --  every place that walks an argument would have to
                        --  know how far the next one is rather than that it is
                        --  one along. Refused where it is written.
                        if Types.Is_Composite (Kinds (Index)) then
                           Complain
                             (Adash.Errors.Error_Entry_Parameter_Not_Simple,
                              S.Child (Tree, Formals, Index),
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("found", Types.Name (Kinds (Index)))]);

                           --  The type is left as written. Analysis has
                           --  already refused the program, so nothing will be
                           --  emitted, and clearing it would make the accept
                           --  that repeats it faithfully look wrong too.
                        end if;
                     end loop;

                     if not Chain.Declare_Symbol
                       (Symbols.Make_Subprogram
                          (Name       => Full_Name (Name),
                           Kind       => Symbols.Symbol_Entry,

                           --  What a family's members are indexed by. An
                           --  entry yields nothing, so the type it carries is
                           --  free to say this -- and every pass that asks
                           --  whether an entry is a family asks one question
                           --  rather than keeping a list.
                           Of_Type    => Family_Index,
                           Count      => Count,
                           Parameters => Kinds,
                           Modes      => Modes,
                           Names      => Names,
                           Defaults   => Given,
                           Defaulted  => Has,
                           Origin     => Origin,
                           Extent     => S.Extent (Tree, Named)),
                        Error)
                     then
                        Legal := False;
                        Refuse_Declaration (Error, Named);
                     end if;
                  end if;

                  if Named_The_Index then
                     Chain.Leave;
                  end if;

                  Note (Named, Types.Type_None,
                        Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Package_Declaration | S.Node_Package_Body =>
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);
                  Name  : constant String := S.Text (Tree, Named);
                  Held  : constant S.Node_Id := S.Second (Tree, Node);

                  Outer : constant String :=
                    Ada.Strings.Unbounded.To_String (Prefix);
                  Error : Adash.Errors.Error_Info;
               begin
                  if S.Kind (Tree, Node) = S.Node_Package_Declaration then
                     if Adash.Predefined.Profile_Of (Name).Known
                       and then Is_Its_Own_Name
                     then
                        Complain (Adash.Errors.Error_Name_Is_Predefined,
                                  Named,
                                  [1 => Adash.Messages.Named ("name", Name)]);
                        Note (Node, Types.Type_None);
                        return;
                     end if;

                     if not Chain.Declare_Symbol
                       (Symbols.Make
                          (Under (Outer, Name), Symbols.Symbol_Package,
                           Types.Type_None, Origin, S.Extent (Tree, Named)),
                        Error)
                     then
                        Legal := False;
                        Refuse_Declaration (Error, Named);
                     end if;

                  elsif Symbols.Kind (Chain.Lookup (Under (Outer, Name)))
                        /= Symbols.Symbol_Package
                  then
                     --  A body without a specification. Ada requires one, and
                     --  so does this: the specification is what a caller reads
                     --  and what a name resolves against.
                     Complain (Adash.Errors.Error_Package_Not_Declared, Named,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  What it holds, declared beside it. The declarations go
                  --  into the *enclosing* scope under a dotted name rather
                  --  than into a scope of their own, which is what makes a
                  --  member an ordinary symbol everywhere below here.
                  declare
                     Was_Spec : constant Boolean := In_Package_Spec;
                  begin
                     In_Package_Spec :=
                       S.Kind (Tree, Node) = S.Node_Package_Declaration;

                     Prefix :=
                       Ada.Strings.Unbounded.To_Unbounded_String
                         (Under (Outer, Name));
                     Analyse_Sequence (Held);
                     Prefix :=
                       Ada.Strings.Unbounded.To_Unbounded_String (Outer);

                     In_Package_Spec := Was_Spec;
                  end;

                  Note (Named, Types.Type_None,
                        Chain.Lookup (Under (Outer, Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Record_Declaration | S.Node_Array_Declaration =>
               declare
                  Is_Record : constant Boolean :=
                    S.Kind (Tree, Node) = S.Node_Record_Declaration;

                  Name_Node : constant S.Node_Id := S.First (Tree, Node);
                  Name      : constant String := S.Text (Tree, Name_Node);

                  Built : Structure;
                  Slots : Natural := 0;
                  Sound : Boolean := True;

                  Introduced : Types.Type_Kind := Types.Type_None;
                  Error      : Adash.Errors.Error_Info;

                  --  Whether the name is one the parser made rather than one
                  --  a user wrote: `A : array (1 .. 3) of Integer;` has a
                  --  type with no name, and what stands in for one carries an
                  --  apostrophe, which no name a user can write does.
                  --
                  --  The type is then *called* what it was written as, so
                  --  that carrying the variable into the next submission
                  --  writes the definition again -- which is what Ada writes,
                  --  and what makes the carried text something this language
                  --  can read.
                  Unnamed : constant Boolean :=
                    Ada.Strings.Fixed.Index (Name, "'") > 0;

                  --  Whether a part may hold this. A composite inside a
                  --  composite is refused: reaching into one would need an
                  --  offset made of two offsets, and every place that walks a
                  --  value would have to recur. Said plainly rather than
                  --  half-supported.
                  function Fits (Part_Of : Types.Type_Kind) return Boolean
                  is (Part_Of /= Types.Type_None
                      and then not Types.Is_Composite (Part_Of));
               begin
                  if Adash.Predefined.Profile_Of (Name).Known
                    and then Is_Its_Own_Name
                  then
                     Complain (Adash.Errors.Error_Name_Is_Predefined,
                               Name_Node,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  Built.Id := S.Extent (Tree, Name_Node).First;

                  if Is_Record then
                     declare
                        Fields : constant S.Node_Id := S.Second (Tree, Node);
                     begin
                        for Index in 1 .. S.Child_Count (Tree, Fields) loop
                           declare
                              One : constant S.Node_Id :=
                                S.Child (Tree, Fields, Index);
                              Called : constant String :=
                                S.Text (Tree, S.First (Tree, One));
                              Held : constant Types.Type_Kind :=
                                Named_Type (S.Second (Tree, One));
                           begin
                              if not Fits (Held) then
                                 if Held /= Types.Type_None then
                                    Complain
                                      (Adash.Errors.Error_Part_Not_Simple,
                                       S.Second (Tree, One),
                                       [Adash.Messages.Named
                                          ("name", Called),
                                        Adash.Messages.Named
                                          ("found", Types.Name (Held))]);
                                 end if;

                                 Sound := False;

                              elsif Part_At_Name (Built, Called) /= 0 then
                                 Complain
                                   (Adash.Errors.Error_Part_Given_Twice,
                                    S.First (Tree, One),
                                    [1 => Adash.Messages.Named
                                            ("name", Called)]);
                                 Sound := False;

                              else
                                 declare
                                    --  `A : Integer := 5;`. Held to a literal
                                    --  exactly as a parameter's default is,
                                    --  and for the same reason: it is read
                                    --  where an object is declared rather
                                    --  than where the type was, so a name
                                    --  resolved here would be the one thing
                                    --  it cannot be.
                                    Written : constant Boolean :=
                                      S.Child_Count (Tree, One) = 3;

                                    Given : constant S.Node_Id :=
                                      (if Written then S.Third (Tree, One)
                                       else S.No_Node);

                                    Spelling : Ada.Strings.Unbounded.
                                                 Unbounded_String;
                                    Settled  : Boolean := False;
                                 begin
                                    if Written then
                                       declare
                                          Offered : constant Types.Type_Kind :=
                                            Analyse_Expression (Given, Held);
                                       begin
                                          if Offered /= Types.Type_None
                                            and then not Types.Is_Acceptable
                                                           (Offered, Held)
                                          then
                                             Complain
                                               (Adash.Errors.
                                                  Error_Type_Mismatch,
                                                Given,
                                                [Adash.Messages.Named
                                                   ("found",
                                                    Types.Name (Offered)),
                                                 Adash.Messages.Named
                                                   ("expected",
                                                    Types.Name (Held))]);
                                             Sound := False;

                                          elsif not Static_Default
                                                      (Into, Tree, Given,
                                                       Held, Spelling)
                                          then
                                             Complain
                                               (Adash.Errors.
                                                  Error_Default_Not_Literal,
                                                Given,
                                                [1 => Adash.Messages.Named
                                                        ("name", Called)]);
                                             Sound := False;

                                          else
                                             Settled := True;
                                          end if;
                                       end;
                                    end if;

                                    Built.Parts.Append
                                      (Part'(Name =>
                                               Ada.Strings.Unbounded.
                                                 To_Unbounded_String (Called),
                                             Of_Type => Held,
                                             Offset  => Slots,
                                             Default => Spelling,
                                             Has_Default => Settled));
                                 end;

                                 Slots := Slots + Types.Width (Held);
                              end if;
                           end;
                        end loop;

                        if Sound and then Natural (Built.Parts.Length) = 0
                        then
                           --  Ada writes an empty record as `null record`, a
                           --  spelling this language does not have. A record
                           --  with nothing in it holds nothing and cannot be
                           --  told from any other, so there is no reading of
                           --  it worth accepting.
                           --
                           --  Only when nothing else was wrong: a record whose
                           --  one component was refused is empty as a
                           --  consequence, and saying so is a second complaint
                           --  about one mistake.
                           Complain
                             (Adash.Errors.Error_Record_Is_Empty, Node,
                              [1 => Adash.Messages.Named ("name", Name)]);
                           Sound := False;
                        end if;

                        if Sound then
                           Introduced :=
                             Types.Composite_Record (Built.Id, Name, Slots);
                        end if;
                     end;
                  else
                     declare
                        Bounds : constant S.Node_Id := S.Second (Tree, Node);
                        Held   : constant Types.Type_Kind :=
                          Named_Type (S.Third (Tree, Node));

                        --  `array (Integer range <>) of T`: the middle child
                        --  is the index type's name where the constrained
                        --  form has a range. Its values carry their own
                        --  length, so there is nothing to work out here --
                        --  what a variable of it is long is said where the
                        --  variable is declared.
                        Unbounded : constant Boolean :=
                          S.Kind (Tree, Bounds) /= S.Node_Range;

                        Ignored_Low : constant Types.Type_Kind :=
                          (if Unbounded then Types.Type_None
                           else Analyse_Expression (S.First (Tree, Bounds),
                                                    Types.Type_Integer));
                        Ignored_High : constant Types.Type_Kind :=
                          (if Unbounded then Types.Type_None
                           else Analyse_Expression (S.Second (Tree, Bounds),
                                                    Types.Type_Integer));

                        pragma Unreferenced (Ignored_Low, Ignored_High);

                        Low, High : Long_Long_Integer := 0;
                     begin
                        if Unbounded and then Fits (Held) then
                           --  Indexed by Integer, which is what every array
                           --  here is indexed by. Ada admits any discrete
                           --  index type; a second one would need a position
                           --  where this build has a number.
                           if Named_Type (Bounds) /= Types.Type_Integer then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, Bounds,
                                 [Adash.Messages.Named
                                    ("found",
                                     Types.Name (Named_Type (Bounds))),
                                  Adash.Messages.Named
                                    ("expected",
                                     Types.Name (Types.Type_Integer))]);
                              Sound := False;
                           else
                              --  One part, which says what an element is. How
                              --  many there are is not the type's business
                              --  here: it travels with the value.
                              Built.First := 1;
                              Built.Parts.Append
                                (Part'(Name    => <>,
                                       Of_Type => Held,
                                       Offset  => 0,
                                       others  => <>));
                              if Unnamed then
                                 Built.Written :=
                                   Ada.Strings.Unbounded.To_Unbounded_String
                                     ("array (" & S.Text (Tree, Bounds)
                                      & " range <>) of "
                                      & Types.Name (Held));
                              end if;

                              Introduced := Types.Open_Array
                                (Built.Id,
                                 (if Unnamed
                                  then Ada.Strings.Unbounded.To_String
                                         (Built.Written)
                                  else Name));
                           end if;

                        elsif not Fits (Held) then
                           if Held /= Types.Type_None then
                              Complain
                                (Adash.Errors.Error_Part_Not_Simple,
                                 S.Third (Tree, Node),
                                 [Adash.Messages.Named ("name", Name),
                                  Adash.Messages.Named
                                    ("found", Types.Name (Held))]);
                           end if;

                           Sound := False;

                        elsif not Static_Choice
                                    (Into, Tree, S.First (Tree, Bounds), Low)
                          or else not Static_Choice
                                        (Into, Tree,
                                         S.Second (Tree, Bounds), High)
                        then
                           --  The length has to be known now: an array is a
                           --  run of slots in a frame whose size is decided
                           --  when the program is built.
                           Complain
                             (Adash.Errors.Error_Array_Bound_Not_Static,
                              Bounds, Adash.Messages.No_Arguments);
                           Sound := False;

                        elsif Low > High then
                           Complain
                             (Adash.Errors.Error_Array_Is_Empty, Bounds,
                              [1 => Adash.Messages.Named ("name", Name)]);
                           Sound := False;

                        elsif High - Low + 1 > Long_Long_Integer (Max_Elements)
                        then
                           Complain
                             (Adash.Errors.Error_Array_Too_Long, Bounds,
                              [Adash.Messages.Named ("name", Name),
                               Adash.Messages.Named
                                 ("limit", Natural'Image (Max_Elements))]);
                           Sound := False;

                        else
                           Built.First := Low;

                           for Position in Low .. High loop
                              Built.Parts.Append
                                (Part'(Name    => <>,
                                       Of_Type => Held,
                                       Offset  => Slots,
                                       others  => <>));
                              Slots := Slots + Types.Width (Held);
                           end loop;

                           if Unnamed then
                              Built.Written :=
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  ("array ("
                                   & Ada.Strings.Fixed.Trim
                                       (Low'Image, Ada.Strings.Both)
                                   & " .. "
                                   & Ada.Strings.Fixed.Trim
                                       (High'Image, Ada.Strings.Both)
                                   & ") of " & Types.Name (Held));
                           end if;

                           Introduced :=
                             Types.Composite_Array
                               (Built.Id,
                                (if Unnamed
                                 then Ada.Strings.Unbounded.To_String
                                        (Built.Written)
                                 else Name),
                                Slots);
                        end if;
                     end;
                  end if;

                  if not Sound then
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  Into.Shapes.Append (Built);

                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (Name), Symbols.Symbol_Type, Introduced,
                        Origin, S.Extent (Tree, Name_Node)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Name_Node);
                  end if;

                  Note (Name_Node, Introduced, Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Subtype_Declaration =>
               declare
                  Name_Node : constant S.Node_Id := S.First (Tree, Node);
                  Named     : constant S.Node_Id := S.Second (Tree, Node);
                  Name      : constant String := S.Text (Tree, Name_Node);
                  Base      : constant Types.Type_Kind := Named_Type (Named);

                  Bounded : constant Boolean :=
                    S.Child_Count (Tree, Node) = 3;

                  Low, High : Long_Long_Integer := 0;
                  Settled   : Boolean := True;

                  Introduced : Types.Type_Kind := Base;
                  Error      : Adash.Errors.Error_Info;
               begin
                  if Base = Types.Type_None then
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if Bounded then
                     declare
                        Range_Node : constant S.Node_Id :=
                          S.Third (Tree, Node);
                        From_Node : constant S.Node_Id :=
                          S.First (Tree, Range_Node);
                        To_Node : constant S.Node_Id :=
                          S.Second (Tree, Range_Node);

                        Ignored_Low : constant Types.Type_Kind :=
                          Analyse_Expression (From_Node, Base);
                        Ignored_High : constant Types.Type_Kind :=
                          Analyse_Expression (To_Node, Base);

                        pragma Unreferenced (Ignored_Low, Ignored_High);
                     begin
                        if not Types.Is_Discrete (Base) then
                           --  A range on a Float or a String is not something
                           --  this build checks. Ada allows one on a Float;
                           --  admitting it here without the check would be a
                           --  constraint that does nothing.
                           Complain
                             (Adash.Errors.Error_Subtype_Not_Discrete, Named,
                              [1 => Adash.Messages.Named
                                      ("found", Types.Name (Base))]);
                           Settled := False;

                        elsif not Static_Choice (Into, Tree, From_Node, Low)
                          or else not Static_Choice
                                        (Into, Tree, To_Node, High)
                        then
                           --  The bounds have to be known now: the check the
                           --  lowering emits is two numbers in an
                           --  instruction, and a bound computed at run time
                           --  would be a different mechanism entirely.
                           Complain
                             (Adash.Errors.Error_Subtype_Bound_Not_Static,
                              Range_Node, Adash.Messages.No_Arguments);
                           Settled := False;
                        end if;
                     end;

                     if Settled then
                        if Low > High then
                           --  Ada allows a null subtype; this refuses one,
                           --  because every value would fail the check and a
                           --  declaration nothing can satisfy is a mistake
                           --  rather than an intention.
                           Complain
                             (Adash.Errors.Error_Subtype_Range_Is_Empty,
                              S.Third (Tree, Node),
                              Adash.Messages.No_Arguments);
                        else
                           Introduced :=
                             Types.Constrained (Base, Name, Low, High);
                        end if;
                     end if;
                  else
                     --  No range: a second name for the same set of values,
                     --  which is what Ada calls it too.
                     Introduced := Types.Constrained
                       (Base, Name,
                        Types.Low_Bound (Base), Types.High_Bound (Base));

                     if not Types.Has_Bounds (Base) then
                        Introduced := Base;
                     end if;
                  end if;

                  if Adash.Predefined.Profile_Of (Name).Known
                    and then Is_Its_Own_Name
                  then
                     Complain (Adash.Errors.Error_Name_Is_Predefined,
                               Name_Node,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (Name), Symbols.Symbol_Type, Introduced,
                        Origin, S.Extent (Tree, Name_Node)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Name_Node);
                  end if;

                  Note (Name_Node, Introduced, Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Type_Declaration =>
               declare
                  Name_Node : constant S.Node_Id := S.First (Tree, Node);
                  Literals  : constant S.Node_Id := S.Second (Tree, Node);
                  Count     : constant Natural :=
                    S.Child_Count (Tree, Literals);
                  Name      : constant String := S.Text (Tree, Name_Node);

                  --  What tells this type from every other. The offset the
                  --  declaration was written at: unique within a submission by
                  --  construction, and the same number in every pass because
                  --  the source it points into does not move. Two enumerations
                  --  with the same literals spelled the same way are two
                  --  types, and this is what says so.
                  Introduced : constant Types.Type_Kind :=
                    Types.Enumeration
                      (S.Extent (Tree, Name_Node).First, Name, Count);

                  Error : Adash.Errors.Error_Info;
               begin
                  if Adash.Predefined.Profile_Of (Name).Known
                    and then Is_Its_Own_Name
                  then
                     --  A type named after one the shell provides would be a
                     --  second Integer, and every call taking one would be
                     --  ambiguous for the rest of the session.
                     Complain (Adash.Errors.Error_Name_Is_Predefined,
                               Name_Node,
                               [1 => Adash.Messages.Named ("name", Name)]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (Name), Symbols.Symbol_Type, Introduced,
                        Origin, S.Extent (Tree, Name_Node)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Name_Node);
                  end if;

                  --  The literals, in the order they were written, which is
                  --  the order that orders the type. Each is a constant of the
                  --  type carrying its position, so nothing downstream has to
                  --  go back to the declaration to find out where a value sits.
                  for Index in 1 .. Count loop
                     declare
                        One : constant S.Node_Id :=
                          S.Child (Tree, Literals, Index);
                        Spelt : constant String := S.Text (Tree, One);
                     begin
                        if Adash.Predefined.Profile_Of (Spelt).Known then
                           Complain (Adash.Errors.Error_Name_Is_Predefined,
                                     One,
                                     [1 => Adash.Messages.Named
                                             ("name", Spelt)]);

                        elsif not Chain.Declare_Symbol
                          (Symbols.Make
                             (Full_Name (Spelt), Symbols.Symbol_Literal,
                              Introduced, Origin, S.Extent (Tree, One),
                              Position => Index - 1),
                           Error)
                        then
                           Legal := False;
                           Refuse_Declaration (Error, One);
                        end if;

                        Note (One, Introduced,
                              Chain.Lookup (Full_Name (Spelt)));
                     end;
                  end loop;

                  Note (Name_Node, Introduced, Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
               end;

            when S.Node_Object_Declaration =>
               declare
                  Name_Node : constant S.Node_Id := S.First (Tree, Node);
                  Type_Node : constant S.Node_Id := S.Second (Tree, Node);
                  Value     : constant S.Node_Id := S.Third (Tree, Node);
                  Actuals   : constant S.Node_Id := S.Child (Tree, Node, 4);
                  --  A named number has no type mark, and its value says
                  --  what it is.
                  Named_As  : constant Types.Type_Kind :=
                    (if S.Is_Present (Type_Node) then Named_Type (Type_Node)
                     else Number_Type (Node));
                  Is_Const  : constant Boolean := S.Text (Tree, Node) = "constant";
                  Error     : Adash.Errors.Error_Info;

                  --  What the initial value turned out to be, when it had to
                  --  be worked out before the variable's type was known. Left
                  --  as Type_None when the type said how long it was, so that
                  --  the value is analysed once either way: analysing it twice
                  --  would report whatever is wrong with it twice.
                  Initial : Types.Type_Kind := Types.Type_None;

                  --  What the variable's type is, which for an unconstrained
                  --  array is not what its type mark names: `X : Line (1 .. 4)`
                  --  is a Line of four, and the four is the variable's rather
                  --  than the type's. Everything below wants that type, so it
                  --  is worked out here and named Declared as before.
                  function Bounded return Types.Type_Kind;

                  --  How many elements a value written where a length would
                  --  stand says the variable has, or zero when it says
                  --  nothing. `X : Line := (1, 2, 3)` is a Line of three, as
                  --  Ada reads it: a positional aggregate has as many
                  --  elements as it has values.
                  --
                  --  Only a positional one. `(others => 0)` answers for the
                  --  parts nothing else named, and where nothing says how many
                  --  there are it answers for no number at all.
                  function Length_From_The_Value return Natural;

                  function Length_From_The_Value return Natural is
                  begin
                     if not S.Is_Present (Value) then
                        return 0;
                     end if;

                     if S.Kind (Tree, Value) = S.Node_Aggregate then
                        declare
                           Listed : constant S.Node_Id :=
                             S.First (Tree, Value);
                        begin
                           for Index in 1 .. S.Child_Count (Tree, Listed) loop
                              if S.Kind (Tree, S.Child (Tree, Listed, Index))
                                 in S.Node_Named_Argument | S.Node_Others
                              then
                                 return 0;
                              end if;
                           end loop;

                           return S.Child_Count (Tree, Listed);
                        end;
                     end if;

                     --  Anything else is a value with a type, and its type
                     --  says how long it is: another array of this one, or a
                     --  slice of one.
                     Initial := Analyse_Expression (Value);

                     if Types.Shape (Initial) /= Types.Shape_Array
                       or else Types.Is_Open (Initial)
                       or else Types.Identity (Initial)
                               /= Types.Identity (Named_As)
                     then
                        return 0;
                     end if;

                     return Types.Width (Initial)
                            / Types.Width (Part_Type (Into, Named_As, 1));
                  end Length_From_The_Value;

                  function Bounded return Types.Type_Kind is
                     Held : Types.Type_Kind;
                     Low, High : Long_Long_Integer;
                  begin
                     if not Types.Is_Open (Named_As) then
                        return Named_As;
                     end if;

                     --  `X : Line := (1, 2, 3);` -- the value says how long it
                     --  is, which is Ada's rule for an object of an
                     --  unconstrained type and the reading a script wants: the
                     --  length is written once, in the thing that has it.
                     --  A value of another type says nothing about how long
                     --  this variable is, and the honest complaint is about
                     --  the value rather than about a missing length.
                     if not S.Is_Present (Actuals)
                       and then Length_From_The_Value = 0
                       and then Initial /= Types.Type_None
                     then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch, Value,
                           [Adash.Messages.Named
                              ("found", Types.Name (Initial)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Named_As))]);
                        return Types.Type_None;
                     end if;

                     if not S.Is_Present (Actuals)
                       and then Length_From_The_Value > 0
                     then
                        declare
                           Count : constant Natural :=
                             Length_From_The_Value;
                           Element : constant Types.Type_Kind :=
                             Part_Type (Into, Named_As, 1);
                        begin
                           if Count > Max_Elements then
                              Complain
                                (Adash.Errors.Error_Array_Too_Long, Value,
                                 [Adash.Messages.Named
                                    ("name", Types.Name (Named_As)),
                                  Adash.Messages.Named
                                    ("limit", Natural'Image (Max_Elements))]);
                              return Types.Type_None;
                           end if;

                           return Types.Composite_Array
                             (Id     => Types.Identity (Named_As),
                              Called => Types.Name (Named_As) & " (1 .. "
                                        & Ada.Strings.Fixed.Trim
                                            (Natural'Image (Count),
                                             Ada.Strings.Both)
                                        & ")",
                              Slots  => Count * Types.Width (Element));
                        end;
                     end if;

                     --  A range, and one beginning at one. A value of an
                     --  unconstrained type begins at one here, as a String
                     --  does and as every part of one does: there is nowhere
                     --  to carry a first index that is not one, since the
                     --  value carries a length and nothing else.
                     if S.Child_Count (Tree, Actuals) /= 1
                       or else S.Kind (Tree, S.First (Tree, Actuals))
                               /= S.Node_Range
                       or else not Static_Choice
                                     (Into, Tree,
                                      S.First (Tree,
                                               S.First (Tree, Actuals)), Low)
                       or else not Static_Choice
                                     (Into, Tree,
                                      S.Second (Tree,
                                                S.First (Tree, Actuals)), High)
                       or else Low /= 1
                     then
                        Complain
                          (Adash.Errors.Error_Needs_Bounds, Type_Node,
                           [1 => Adash.Messages.Named
                                   ("name", Types.Name (Named_As))]);
                        return Types.Type_None;
                     end if;

                     if High < Low then
                        Complain
                          (Adash.Errors.Error_Array_Is_Empty, Actuals,
                           [1 => Adash.Messages.Named
                                   ("name", Types.Name (Named_As))]);
                        return Types.Type_None;
                     end if;

                     if High - Low + 1 > Long_Long_Integer (Max_Elements) then
                        Complain
                          (Adash.Errors.Error_Array_Too_Long, Actuals,
                           [Adash.Messages.Named
                              ("name", Types.Name (Named_As)),
                            Adash.Messages.Named
                              ("limit", Natural'Image (Max_Elements))]);
                        return Types.Type_None;
                     end if;

                     Held := Part_Type (Into, Named_As, 1);

                     return Types.Composite_Array
                       (Id     => Types.Identity (Named_As),
                        Called => Types.Name (Named_As) & " (1 .. "
                                  & Ada.Strings.Fixed.Trim
                                      (Long_Long_Integer'Image (High),
                                       Ada.Strings.Both)
                                  & ")",
                        Slots  => Positive
                                    (Long_Long_Integer (Types.Width (Held))
                                     * High));
                  end Bounded;

                  Declared : constant Types.Type_Kind := Bounded;
               begin
                  --  An identity with nothing in it names no task. Ada's
                  --  answer is Null_Task_Id, a value that names none on
                  --  purpose; this build has no way to write one, so an
                  --  identity is declared with the task it means.
                  if Declared = Types.Type_Task_Id
                    and then not S.Is_Present (Value)
                  then
                     Complain (Adash.Errors.Error_Identity_Needs_A_Task,
                               Name_Node,
                               [1 => Adash.Messages.Named
                                       ("name",
                                        S.Text (Tree, Name_Node))]);
                  end if;

                  --  A task and a protected object are limited, which is
                  --  Ada's word for what cannot be copied: what one *is* is
                  --  the thing that runs or the state that is shared, and a
                  --  second name for it would be a second of it or a lie about
                  --  which one. `A'Identity` is how a program keeps which task
                  --  it meant.
                  if S.Is_Present (Value)
                    and then (Types.Is_Task (Declared)
                              or else Types.Is_Protected (Declared))
                  then
                     Complain (Adash.Errors.Error_Cannot_Be_Copied, Value,
                               [1 => Adash.Messages.Named
                                       ("name", Types.Name (Declared))]);
                  end if;

                  if S.Is_Present (Value) then
                     declare
                        --  Analysed here unless working out the type needed it
                        --  analysed already, which happens only for a variable
                        --  whose length comes from what it is given.
                        Given : constant Types.Type_Kind :=
                          (if Initial /= Types.Type_None then Initial
                           else Analyse_Expression (Value, Declared));
                     begin
                        if Declared /= Types.Type_None
                          and then Given /= Types.Type_None
                          and then not Types.Is_Acceptable (Given, Declared)
                        then
                           Complain (Adash.Errors.Error_Type_Mismatch, Value,
                                     [Adash.Messages.Named ("found", Types.Name (Given)),
                                      Adash.Messages.Named
                                        ("expected", Types.Name (Declared))]);
                        end if;
                     end;
                  end if;

                  --  An object of a protected type is state and a lock of its
                  --  own, made by copying the type's declaration and body with
                  --  the type's name replaced by this object's. That is what a
                  --  generic instantiation already does, and it leaves
                  --  everything below here seeing what it has always seen: one
                  --  protected object per declaration.
                  if Types.Is_Task (Declared) and then Master_Depth > 0 then
                     Refuse_If_Restricted (No_Task_Hierarchy, Node);
                  end if;

                  --  An object of a task type is a task, and a task runs a
                  --  body. Asked here rather than when the type is declared,
                  --  because a declaration whose body is still to be typed is
                  --  the ordinary way a session gets one -- what cannot wait
                  --  is an object, which starts running where it stands.
                  if Types.Is_Task (Declared)
                    and then not Has_Task_Body (Types.Name (Declared))
                  then
                     Complain (Adash.Errors.Error_Body_Missing, Type_Node,
                               [1 => Adash.Messages.Named
                                       ("name", Types.Name (Declared))]);
                  end if;

                  --  What the object gives its type. A task takes its
                  --  discriminants at elaboration where a subprogram takes
                  --  parameters at a call, and this is where they are given:
                  --  by position, all of them, because a discriminant has no
                  --  default here and an object with one missing would run
                  --  with a value nobody wrote.
                  declare
                     Wanted : constant S.Node_Id :=
                       (if Types.Is_Task (Declared)
                          or else Types.Is_Protected (Declared)
                        then Discriminants_Of (Types.Name (Declared))
                        else S.No_Node);

                     --  An unconstrained array's actual is its length, not a
                     --  discriminant. Bounded has already read it and said
                     --  what was wrong with it, so nothing below applies.
                     Constrains_An_Array : constant Boolean :=
                       Types.Is_Open (Named_As);

                     Expected : constant Natural :=
                       S.Child_Count (Tree, Wanted);
                     Offered  : constant Natural :=
                       S.Child_Count (Tree, Actuals);
                  begin
                     if Constrains_An_Array then
                        null;

                     elsif Declared = Types.Type_None then
                        --  Nothing is known about the type, so nothing can be
                        --  said about what it takes. The undeclared name was
                        --  reported already, and a second complaint naming
                        --  nothing would be the cascade this pass avoids.
                        null;

                     elsif not Types.Is_Task (Declared)
                       and then not Types.Is_Protected (Declared)
                       and then not Types.Is_Open (Named_As)
                       and then S.Is_Present (Actuals)
                     then
                        Complain
                          (Adash.Errors.Error_Nothing_To_Constrain, Type_Node,
                           [1 => Adash.Messages.Named
                                   ("name", Types.Name (Declared))]);

                     elsif Offered = 0 and then All_Defaulted (Wanted) then
                        --  None given, and every one has a default. Ada calls
                        --  such a type unconstrained and lets an object stand
                        --  without a constraint; what each discriminant is
                        --  then is what the type said it would be.
                        null;

                     elsif Expected /= Offered then
                        Complain
                          (Adash.Errors.Error_Discriminants_Wrong_Count, Node,
                           [Adash.Messages.Named
                              ("name", Types.Name (Declared)),
                            Adash.Messages.Named
                              ("expected", Natural'Image (Expected)),
                            Adash.Messages.Named
                              ("found", Natural'Image (Offered))]);

                     else
                        for Index in 1 .. Offered loop
                           declare
                              Formal : constant S.Node_Id :=
                                S.Child (Tree, Wanted, Index);
                              Wants  : constant Types.Type_Kind :=
                                Named_Type (S.Second (Tree, Formal));
                              Gets   : constant Types.Type_Kind :=
                                Analyse_Expression
                                  (S.Child (Tree, Actuals, Index), Wants);
                           begin
                              if Gets /= Types.Type_None
                                and then Wants /= Types.Type_None
                                and then not Types.Is_Acceptable (Gets, Wants)
                              then
                                 Complain
                                   (Adash.Errors.Error_Type_Mismatch,
                                    S.Child (Tree, Actuals, Index),
                                    [Adash.Messages.Named
                                       ("found", Types.Name (Gets)),
                                     Adash.Messages.Named
                                       ("expected", Types.Name (Wants))]);
                              end if;
                           end;
                        end loop;
                     end if;
                  end;

                  if Types.Is_Protected (Declared) then
                     Make_Guarded_Object
                       (Node, S.Text (Tree, Name_Node),
                        Types.Name (Declared), Type_Node, Actuals);
                     Note (Name_Node, Declared);
                     Note (Node, Declared);
                     return;
                  end if;

                  --  Declared after its own initial value is analysed, so
                  --  `X : Integer := X;` reports X as undeclared rather than
                  --  quietly reading the variable being declared.
                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (Full_Name (S.Text (Tree, Name_Node)),
                        (if Is_Const then Symbols.Symbol_Constant
                         else Symbols.Symbol_Variable),
                        Declared, Origin, S.Extent (Tree, Name_Node)),
                     Error)
                  then
                     Legal := False;
                     Refuse_Declaration (Error, Name_Node);
                  end if;

                  Note (Name_Node, Declared,
                        Chain.Lookup (Full_Name (S.Text (Tree, Name_Node))));
                  Note (Node, Declared);
               end;

            when S.Node_Assignment =>
               declare
                  Target : constant S.Node_Id := S.First (Tree, Node);
                  Value  : constant S.Node_Id := S.Second (Tree, Node);
                  Left   : constant Types.Type_Kind := Analyse_Expression (Target);

                  --  The target's type is what the value has to be, so it is
                  --  also what settles an overloaded call on the right.
                  Right  : constant Types.Type_Kind :=
                    Analyse_Expression (Value, Left);
                  Denoted : constant Symbols.Symbol := Into.Symbol_Of (Target);
               begin
                  --  `A'Priority := 20;` -- what a task runs at, and what a
                  --  protected object may be called by, changed while the
                  --  program runs. Ada assigns to a protected object's
                  --  `'Priority` and calls Set_Priority for a task; this
                  --  language has one spelling for asking something about a
                  --  value, and this is that spelling written the other way.
                  --
                  --  The only attribute a program may assign to. An attribute
                  --  is a question about something, and most questions have no
                  --  answer to put back.
                  if S.Kind (Tree, Target) = S.Node_Attribute then
                     Refuse_If_Restricted (No_Dynamic_Priorities, Node);

                     if Symbols.Fold (S.Text (Tree, S.Second (Tree, Target)))
                        /= "priority"
                     then
                        Complain
                          (Adash.Errors.Error_Not_Assignable, Target,
                           [1 => Adash.Messages.Named
                                   ("name",
                                    S.Text (Tree, S.Second (Tree, Target)))]);

                     elsif Right /= Types.Type_None
                       and then Right /= Types.Type_Integer
                     then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch, Value,
                           [Adash.Messages.Named
                              ("found", Types.Name (Right)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Types.Type_Integer))]);
                     end if;

                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  `F (1 .. 2) := "XY";` -- a part of what a call yielded,
                  --  which is a value and has nowhere to put anything. Said
                  --  here rather than left to the lowering, which can only
                  --  report that it has no place to store to.
                  --  The name it is written on, however many levels stand
                  --  between: `F (1 .. 4) (1 .. 2) := "XY"` names F. A chain
                  --  that bottoms out at a variable carries that variable's
                  --  symbol instead, so it is assigned to rather than refused,
                  --  and only a chain rooted in a call reaches here.
                  if S.Kind (Tree, Target) = S.Node_Call
                    and then Symbols.Is_Nothing (Denoted)
                    and then Left in Types.Type_String | Types.Type_Character
                    and then Root_Name (Target) /= ""
                  then
                     Complain
                       (Adash.Errors.Error_Not_Assignable, Target,
                        [1 => Adash.Messages.Named
                                ("name", Root_Name (Target))]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  --  A run whose length is the caller's is not assigned to
                  --  as a whole: how many slots to copy is a number this
                  --  build writes into the instruction, and here it has none.
                  if Types.Is_Open (Left) then
                     Complain
                       (Adash.Errors.Error_Open_By_Element, Target,
                        [1 => Adash.Messages.Named
                                ("name", Root_Name (Target))]);
                     Note (Node, Types.Type_None);
                     return;
                  end if;

                  if Types.Is_Task (Left)
                    or else Types.Is_Protected (Left)
                  then
                     --  Limited, in Ada's sense and for Ada's reason: what one
                     --  is is the thing that runs or the state that is shared.
                     Complain (Adash.Errors.Error_Cannot_Be_Copied, Target,
                               [1 => Adash.Messages.Named
                                       ("name", Types.Name (Left))]);

                  elsif not Symbols.Is_Nothing (Denoted)
                    and then not Symbols.Is_Assignable (Denoted)
                  then
                     Complain (Adash.Errors.Error_Not_Assignable, Target,
                               [1 => Adash.Messages.Named
                                       ("name", Symbols.Name (Denoted))]);

                  elsif Left /= Types.Type_None
                    and then Right /= Types.Type_None
                    and then not Types.Is_Acceptable (Right, Left)
                  then
                     Complain (Adash.Errors.Error_Type_Mismatch, Value,
                               [Adash.Messages.Named ("found", Types.Name (Right)),
                                Adash.Messages.Named ("expected", Types.Name (Left))]);
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_Procedure_Call =>
               declare
                  Callee : constant S.Node_Id := S.First (Tree, Node);
                  Yields : constant Types.Type_Kind :=
                    Analyse_Expression (Callee);

                  --  The name at the head of the call, whichever form it
                  --  took: `F;` puts it directly under the statement, `F (2);`
                  --  under the call node.
                  Head   : constant S.Node_Id :=
                    (if S.Kind (Tree, Callee) = S.Node_Call
                     then S.First (Tree, Callee) else Callee);
               begin
                  --  A statement calls a procedure. Anything that yields a
                  --  value is an expression, and one written here reached the
                  --  lowering, which answered `this build cannot yet run a
                  --  call to F` -- naming a limitation that does not exist
                  --  instead of the mistake that does. A user's function was
                  --  worse off still: it ran, and its result was dropped
                  --  without a word.
                  --
                  --  A name that yields a value without being callable at all
                  --  -- `X;` for a variable X -- is the older complaint, and
                  --  still the right one.
                  if Yields /= Types.Type_None
                    and then S.Kind (Tree, Head) = S.Node_Name
                  then
                     declare
                        Called : constant String := S.Text (Tree, Head);
                     begin
                        Complain
                          ((if Symbols.Is_Callable (Chain.Lookup (Called))
                            then Adash.Errors.Error_Function_As_Statement
                            else Adash.Errors.Error_Not_Callable),
                           Node,
                           [1 => Adash.Messages.Named ("name", Called)]);
                     end;
                  end if;

                  --  `set;` is a procedure call written without parentheses,
                  --  so its callee is a plain name and not a call node -- and
                  --  the parameter association above, which hangs off the call
                  --  node, never sees it. Resolving again here re-notes the
                  --  callee, which its own analysis annotated with an
                  --  arbitrary candidate when several were on offer.
                  --
                  --  A count that is short is reported by that analysis
                  --  rather than here: a bare name is a bare name whether it
                  --  stands as a statement or inside an expression, and two
                  --  checks meant one submission was told twice.
                  if S.Kind (Tree, Callee) = S.Node_Name then
                     declare
                        Name    : constant String := S.Text (Tree, Callee);
                        Offered : Natural;
                        Fitting : Natural;
                        Found   : Symbols.Symbol;
                     begin
                        --  A call with no arguments still has to choose, and
                        --  the one it means is whichever takes none.
                        Resolve_Call (Name, S.No_Node, 0, Types.Type_None,
                                      Offered, Fitting, Found);

                        if Offered > 0 and then Fitting = 1 then
                           Note (Callee, Symbols.Of_Type (Found), Found);
                        end if;

                     end;
                  end if;

                  Note (Node, Types.Type_None);
               end;

            when S.Node_If =>
               Require_Condition (S.First (Tree, Node));
               Analyse_Sequence (S.Second (Tree, Node));

               if S.Is_Present (S.Third (Tree, Node)) then
                  --  An elsif is a nested if rather than a sequence, so this
                  --  dispatches on what is actually there.
                  if S.Kind (Tree, S.Third (Tree, Node)) = S.Node_Sequence then
                     Analyse_Sequence (S.Third (Tree, Node));
                  else
                     Analyse_Statement (S.Third (Tree, Node));
                  end if;
               end if;

            when S.Node_Case | S.Node_Case_Expression =>
               declare
                  Subject : constant S.Node_Id := S.First (Tree, Node);
                  Listed  : constant S.Node_Id := S.Second (Tree, Node);
                  Of_Type : constant Types.Type_Kind :=
                    Analyse_Expression (Subject);

                  --  Whether the alternatives hold values rather than
                  --  statements. Everything about the choices is the same
                  --  either way, which is why one routine answers for both.
                  Values : constant Boolean :=
                    S.Kind (Tree, Node) = S.Node_Case_Expression;

                  --  What the context wants of each arm, taken here because
                  --  an arm of an inner case expression will overwrite it.
                  Wanted : constant Types.Type_Kind :=
                    (if Values then Wanted_Of_Case else Types.Type_None);

                  --  What the whole expression yields: the first arm's type,
                  --  which every other arm must agree with.
                  Yields : Types.Type_Kind := Types.Type_None;

                  --  Analyse one alternative's right-hand side, whichever it
                  --  is, and hold the arms to one type.
                  procedure Analyse_Arm (Alternative : S.Node_Id);

                  procedure Analyse_Arm (Alternative : S.Node_Id) is
                     Given : constant S.Node_Id := S.Second (Tree, Alternative);
                  begin
                     if not Values then
                        Analyse_Sequence (Given);
                        return;
                     end if;

                     declare
                        Outer : constant Types.Type_Kind := Wanted_Of_Case;
                        Arm   : Types.Type_Kind;
                     begin
                        Wanted_Of_Case := Wanted;
                        Arm := Analyse_Expression (Given, Wanted);
                        Wanted_Of_Case := Outer;

                        if Arm = Types.Type_None then
                           Legal := False;

                        elsif Yields = Types.Type_None then
                           Yields := Arm;

                        elsif not Types.Is_Acceptable (Arm, Yields) then
                           --  Ada holds every arm to one type, and so does
                           --  this: an expression whose type depended on which
                           --  arm ran would have no type a declaration could
                           --  be checked against.
                           Complain
                             (Adash.Errors.Error_Type_Mismatch, Given,
                              [Adash.Messages.Named
                                 ("found", Types.Name (Arm)),
                               Adash.Messages.Named
                                 ("expected", Types.Name (Yields))]);
                        end if;
                     end;
                  end Analyse_Arm;

                  --  What the choices so far cover. Kept as ranges rather than
                  --  as a set of values because `when 1 .. 1_000_000 =>` is one
                  --  choice and a set would be a million entries.
                  type Covered is record
                     Low  : Long_Long_Integer := 0;
                     High : Long_Long_Integer := 0;

                     --  Which choice covered it, so that a value covered twice
                     --  can point at the one that got there first.
                     By   : S.Node_Id := S.No_Node;
                  end record;

                  Spans   : array (1 .. 256) of Covered;
                  Count   : Natural := 0;
                  Total   : Long_Long_Integer := 0;
                  Catch   : Boolean := False;
                  Whole   : constant Long_Long_Integer :=
                    Types.Value_Count (Of_Type);

                  --  Record what a choice covers, reporting an overlap.
                  procedure Cover
                    (At_Node : S.Node_Id;
                     Low     : Long_Long_Integer;
                     High    : Long_Long_Integer);

                  procedure Cover
                    (At_Node : S.Node_Id;
                     Low     : Long_Long_Integer;
                     High    : Long_Long_Integer) is
                  begin
                     for Index in 1 .. Count loop
                        if Low <= Spans (Index).High
                          and then High >= Spans (Index).Low
                        then
                           Complain
                             (Adash.Errors.Error_Case_Choice_Covered_Twice,
                              At_Node, Adash.Messages.No_Arguments,
                              Also      => Spans (Index).By,
                              Also_Says =>
                                Adash.Messages.Msg_Note_First_Here);
                           return;
                        end if;
                     end loop;

                     if Count = Spans'Last then
                        --  More distinct choices than this build tracks.
                        --  Refused rather than stopping the overlap check
                        --  silently, which would let a later duplicate
                        --  through.
                        Complain
                          (Adash.Errors.Error_Case_Choice_Not_Static,
                           At_Node, Adash.Messages.No_Arguments);
                        return;
                     end if;

                     Count := Count + 1;
                     Spans (Count) := (Low => Low, High => High, By => At_Node);

                     --  How many values this span covers, worked out without
                     --  a number too big to hold at any step. `Integer'First
                     --  .. Integer'Last` covers every value there is, and both
                     --  its width and the difference between its ends are one
                     --  more than the largest -- so a case that named the whole
                     --  of Integer used to end the analyser rather than the
                     --  program. Saturating is enough: what the count is for
                     --  is a comparison against how many values the type has.
                     declare
                        Width : constant Long_Long_Integer :=
                          (if Low <= 0
                             and then High > Long_Long_Integer'Last + Low - 1
                           then Long_Long_Integer'Last
                           else High - Low + 1);
                     begin
                        if Width >= Long_Long_Integer'Last - Total then
                           Total := Long_Long_Integer'Last;
                        else
                           Total := Total + Width;
                        end if;
                     end;
                  end Cover;

                  --  One choice: `others`, a range, or a value.
                  procedure Examine (Choice : S.Node_Id; Last : Boolean);

                  procedure Examine (Choice : S.Node_Id; Last : Boolean) is
                     Low  : Long_Long_Integer := 0;
                     High : Long_Long_Integer := 0;
                  begin
                     if S.Kind (Tree, Choice) = S.Node_Others then
                        if not Last then
                           Complain
                             (Adash.Errors.Error_Case_Others_Not_Last,
                              Choice, Adash.Messages.No_Arguments);
                        end if;

                        Catch := True;
                        return;
                     end if;

                     if S.Kind (Tree, Choice) = S.Node_Range then
                        declare
                           From_Node : constant S.Node_Id :=
                             S.First (Tree, Choice);
                           To_Node   : constant S.Node_Id :=
                             S.Second (Tree, Choice);

                           --  Analysed for its type, and read for its value.
                           --  Both: a range of the wrong type is a type error
                           --  and a range that is not static is a different
                           --  one, and a reader is owed whichever applies.
                           From_Type : constant Types.Type_Kind :=
                             Analyse_Expression (From_Node, Of_Type);
                           To_Type   : constant Types.Type_Kind :=
                             Analyse_Expression (To_Node, Of_Type);
                        begin
                           if not Types.Is_Acceptable (From_Type, Of_Type)
                             or else not Types.Is_Acceptable (To_Type, Of_Type)
                           then
                              Complain
                                (Adash.Errors.Error_Type_Mismatch, Choice,
                                 [Adash.Messages.Named
                                    ("found",
                                     Types.Name
                                       (if Types.Is_Acceptable
                                              (From_Type, Of_Type)
                                        then To_Type else From_Type)),
                                  Adash.Messages.Named
                                    ("expected", Types.Name (Of_Type))]);
                              return;
                           end if;

                           if not Static_Choice (Into, Tree, From_Node, Low)
                             or else not Static_Choice
                                           (Into, Tree, To_Node, High)
                           then
                              Complain
                                (Adash.Errors.Error_Case_Choice_Not_Static,
                                 Choice, Adash.Messages.No_Arguments);
                              return;
                           end if;

                           if Low > High then
                              Complain
                                (Adash.Errors.Error_Case_Range_Is_Empty,
                                 Choice, Adash.Messages.No_Arguments);
                              return;
                           end if;

                           Cover (Choice, Low, High);
                           return;
                        end;
                     end if;

                     declare
                        Found : constant Types.Type_Kind :=
                          Analyse_Expression (Choice, Of_Type);
                     begin
                        if not Types.Is_Acceptable (Found, Of_Type) then
                           Complain
                             (Adash.Errors.Error_Type_Mismatch, Choice,
                              [Adash.Messages.Named
                                 ("found", Types.Name (Found)),
                               Adash.Messages.Named
                                 ("expected", Types.Name (Of_Type))]);
                           return;
                        end if;

                        if not Static_Choice (Into, Tree, Choice, Low) then
                           Complain
                             (Adash.Errors.Error_Case_Choice_Not_Static,
                              Choice, Adash.Messages.No_Arguments);
                           return;
                        end if;

                        Cover (Choice, Low, Low);
                     end;
                  end Examine;

               begin
                  if not Types.Is_Discrete (Of_Type) then
                     --  Type_None means the expression itself was already
                     --  reported; saying it again would describe the recovery
                     --  rather than the program.
                     if Of_Type /= Types.Type_None then
                        Complain
                          (Adash.Errors.Error_Case_Not_Discrete, Subject,
                           [1 => Adash.Messages.Named
                                   ("found", Types.Name (Of_Type))]);
                     end if;

                     --  Still walked, so a mistake inside an alternative is
                     --  reported too rather than waiting for the next run.
                     for Index in 1 .. S.Child_Count (Tree, Listed) loop
                        Analyse_Arm (S.Child (Tree, Listed, Index));
                     end loop;

                     if Values then
                        Note (Node, Types.Type_None);
                     end if;

                     return;
                  end if;

                  for Index in 1 .. S.Child_Count (Tree, Listed) loop
                     declare
                        Alternative : constant S.Node_Id :=
                          S.Child (Tree, Listed, Index);
                        Choices     : constant S.Node_Id :=
                          S.First (Tree, Alternative);
                        Given       : constant Natural :=
                          S.Child_Count (Tree, Choices);
                     begin
                        for Position in 1 .. Given loop
                           Examine
                             (S.Child (Tree, Choices, Position),
                              Last => Position = Given
                                        and then Index
                                                 = S.Child_Count
                                                     (Tree, Listed));
                        end loop;

                        Analyse_Arm (Alternative);
                     end;
                  end loop;

                  --  Ada requires every value to be accounted for, and so does
                  --  this: a case that silently did nothing for a value nobody
                  --  thought about is the bug the rule exists to prevent. For
                  --  an expression it is worse again -- there would be no
                  --  value to yield -- which is why Ada refuses an `others`
                  --  there for a subtype it does not cover either.
                  if not Catch and then Total < Whole then
                     Complain
                       (Adash.Errors.Error_Case_Incomplete, Node,
                        [1 => Adash.Messages.Named
                                ("found", Types.Name (Of_Type))]);
                  end if;

                  if Values then
                     Note (Node, Yields);
                  end if;
               end;

            when S.Node_While_Loop =>
               Require_Condition (S.First (Tree, Node));
               Loop_Depth := Loop_Depth + 1;
               Analyse_Sequence (S.Second (Tree, Node));
               Loop_Depth := Loop_Depth - 1;

            when S.Node_For_Loop | S.Node_For_Reverse_Loop =>
               declare
                  Variable : constant S.Node_Id := S.First (Tree, Node);

                  --  Three children is a range; two is a type name, which is
                  --  Ada's other way of writing what to count over.
                  Over_A_Type : constant Boolean :=
                    S.Child_Count (Tree, Node) = 3;

                  --  What the loop parameter is. An Integer for a range, and
                  --  the type itself when the type was named.
                  Counted : Types.Type_Kind := Types.Type_Integer;

                  Error : Adash.Errors.Error_Info;
               begin
                  if Over_A_Type then
                     Counted := Named_Type (S.Second (Tree, Node));

                     if Counted /= Types.Type_None
                       and then not Types.Is_Discrete (Counted)
                     then
                        --  Ada's rule. A Float has no next value and a String
                        --  has no first one, so neither can be counted over.
                        Complain
                          (Adash.Errors.Error_Case_Not_Discrete,
                           S.Second (Tree, Node),
                           [1 => Adash.Messages.Named
                                   ("found", Types.Name (Counted))]);
                        Counted := Types.Type_None;
                     end if;
                  else
                     declare
                        --  Which bound decides. The first, unless it is a name
                        --  several declarations could answer and the second is
                        --  not -- the same rule a comparison uses, and for the
                        --  same reason: they have each other's type.
                        Settle_From_High : constant Boolean :=
                          Is_Open_Call (S.Second (Tree, Node))
                            and then not Is_Open_Call (S.Third (Tree, Node));

                        High_First : constant Types.Type_Kind :=
                          (if Settle_From_High
                           then Analyse_Expression (S.Third (Tree, Node))
                           else Types.Type_None);

                        Low  : constant Types.Type_Kind :=
                          Analyse_Expression (S.Second (Tree, Node),
                                              High_First);
                        High : constant Types.Type_Kind :=
                          (if Settle_From_High then High_First
                           else Analyse_Expression (S.Third (Tree, Node),
                                                    Low));
                     begin
                        --  What the loop counts over is what its bounds are.
                        --  A range of an enumeration is Ada's own way of
                        --  walking part of one, and saying Integer here would
                        --  be this build inventing a rule.
                        if Low /= Types.Type_None then
                           if not Types.Is_Discrete (Low) then
                              --  Ada's rule. A Float has no next value, so a
                              --  range of them cannot be counted through.
                              Complain
                                (Adash.Errors.Error_Case_Not_Discrete,
                                 S.Second (Tree, Node),
                                 [1 => Adash.Messages.Named
                                         ("found", Types.Name (Low))]);
                           else
                              Counted := Low;
                           end if;
                        end if;

                        if High /= Types.Type_None
                          and then Low /= Types.Type_None
                          and then not Types.Is_Acceptable (High, Low)
                        then
                           Complain
                             (Adash.Errors.Error_Type_Mismatch,
                              S.Third (Tree, Node),
                              [Adash.Messages.Named
                                 ("found", Types.Name (High)),
                               Adash.Messages.Named
                                 ("expected", Types.Name (Low))]);
                        end if;
                     end;
                  end if;

                  --  The loop parameter is declared in a scope of its own and
                  --  is a constant, as Ada says: assigning to it is an error,
                  --  and it is gone after the loop.
                  Chain.Enter;

                  if not Chain.Declare_Symbol
                    (Symbols.Make
                       (S.Text (Tree, Variable), Symbols.Symbol_Constant,
                        Counted, Origin, S.Extent (Tree, Variable)),
                     Error)
                  then
                     Legal := False;
                  end if;

                  Note (Variable, Counted,
                        Chain.Lookup (S.Text (Tree, Variable)));

                  Loop_Depth := Loop_Depth + 1;
                  Analyse_Sequence
                    (S.Child (Tree, Node, (if Over_A_Type then 3 else 4)));
                  Loop_Depth := Loop_Depth - 1;
                  Chain.Leave;
               end;

            when S.Node_Loop =>
               Loop_Depth := Loop_Depth + 1;
               Analyse_Sequence (S.First (Tree, Node));
               Loop_Depth := Loop_Depth - 1;

            when S.Node_Exit =>
               --  Illegal Ada outside a loop, and illegal here. Caught by the
               --  analyser rather than by the lowering, because it is a fault
               --  in the program: the lowering would have to report it as
               --  something this build cannot run, which says Adash is
               --  incomplete when what is wrong is the exit.
               if Loop_Depth = 0 then
                  Complain (Adash.Errors.Error_Exit_Outside_Loop, Node,
                            Adash.Messages.No_Arguments);
               end if;

               if S.Child_Count (Tree, Node) = 1 then
                  Require_Condition (S.First (Tree, Node));
               end if;

            when S.Node_Subprogram_Declaration =>
               Analyse_Subprogram (Node);

            when S.Node_Return =>
               if S.Child_Count (Tree, Node) = 1 then
                  declare
                     Given : constant Types.Type_Kind :=
                       Analyse_Expression (S.First (Tree, Node), Returns);
                  begin
                     if Subprogram_Depth > 0 and then Returns = Types.Type_None
                     then
                        --  Inside a procedure. Outside any subprogram this is
                        --  how a submission ends early, which is meaningful and
                        --  stays legal -- the check is about the enclosing
                        --  subprogram, not about return in general.
                        Complain (Adash.Errors.Error_Return_With_Value, Node,
                                  Adash.Messages.No_Arguments);

                     elsif Returns /= Types.Type_None
                       and then Given /= Types.Type_None
                       and then not Types.Is_Acceptable (Given, Returns)
                     then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch,
                           S.First (Tree, Node),
                           [Adash.Messages.Named ("found", Types.Name (Given)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Returns))]);
                     end if;
                  end;

               elsif Returns /= Types.Type_None then
                  Complain (Adash.Errors.Error_Return_Without_Value, Node,
                            Adash.Messages.No_Arguments);
               end if;

            when S.Node_Block =>
               --  A block is a scope of its own, so what it declares is gone
               --  afterwards and may hide an outer name while it lasts -- and
               --  a master of its own, so a task declared in one depends on
               --  something other than the outermost region.
               Chain.Enter;
               Master_Depth := Master_Depth + 1;

               declare
                  Declared : constant S.Node_Id := S.First (Tree, Node);
               begin
                  --  A declaration is parsed as a statement here, so nothing
                  --  in the grammar stops a statement being written before
                  --  `begin`. Ada draws the line there and so does this: a
                  --  subset that accepted what Ada rejects would be teaching
                  --  the wrong language.
                  for Index in 1 .. S.Child_Count (Tree, Declared) loop
                     if S.Kind (Tree, S.Child (Tree, Declared, Index))
                       not in S.Node_Object_Declaration
                            | S.Node_Subprogram_Declaration
                            | S.Node_Type_Declaration
                            | S.Node_Subtype_Declaration
                            | S.Node_Record_Declaration
                            | S.Node_Array_Declaration
                            | S.Node_Task_Declaration
                            | S.Node_Task_Body
                            | S.Node_Protected_Declaration
                            | S.Node_Protected_Body
                     then
                        Complain
                          (Adash.Errors.Error_Statement_Among_Declarations,
                           S.Child (Tree, Declared, Index),
                           Adash.Messages.No_Arguments);
                     end if;
                  end loop;

                  Analyse_Sequence (Declared);
                  Analyse_Sequence (S.Second (Tree, Node));

                  Analyse_Handlers (S.Third (Tree, Node));
               end;

               Master_Depth := Master_Depth - 1;
               Chain.Leave;

            when S.Node_Sequence =>
               Analyse_Sequence (Node);

            when S.Node_Null_Statement =>
               null;

            when others =>
               null;
         end case;
      end Analyse_Statement;

      -----------------------------
      -- Report_Missing_Bodies --
      -----------------------------

      --  Every specification declared deeper than Below, complained about and
      --  forgotten. Called when a declarative region closes, so the diagnostic
      --  arrives where the body should have been rather than at the end of the
      --  submission.
      procedure Report_Missing_Bodies (Below : Natural) is
         Index : Natural := Natural (Awaiting.Length);
      begin
         while Index >= 1 loop
            if Awaiting.Element (Index).Depth > Below then
               Complain (Adash.Errors.Error_Body_Missing,
                         Awaiting.Element (Index).Where,
                         [1 => Adash.Messages.Named
                                 ("name",
                                  Symbols.Name (Awaiting.Element (Index).Named))]);
               Awaiting.Delete (Index);
            end if;

            Index := Index - 1;
         end loop;
      end Report_Missing_Bodies;

      ------------------------
      -- Analyse_Subprogram --
      ------------------------

      --  The handlers of a block or a body.
      --
      --  Only exceptions something raises may be named: a handler for what
      --  cannot happen is almost always a misremembered name, and one accepted
      --  silently would never run. Its statements are analysed in the scope
      --  around it, which is Ada's rule and the useful one -- a handler
      --  usually reports on what was being attempted.
      procedure Analyse_Handlers (Handlers : S.Node_Id) is
         Total : constant Natural :=
           (if S.Is_Present (Handlers) then S.Child_Count (Tree, Handlers)
            else 0);
      begin
         for Index in 1 .. Total loop
            declare
               One   : constant S.Node_Id := S.Child (Tree, Handlers, Index);
               Named : constant S.Node_Id := S.First (Tree, One);
               Count : constant Natural := S.Child_Count (Tree, Named);
            begin
               for Position in 1 .. Count loop
                  declare
                     Which : constant S.Node_Id :=
                       S.Child (Tree, Named, Position);
                  begin
                     if S.Kind (Tree, Which) = S.Node_Others then
                        --  `others` answers for what is left, so anything
                        --  after it answers for nothing.
                        if Position /= Count or else Index /= Total then
                           Complain
                             (Adash.Errors.Error_Case_Others_Not_Last,
                              Which, Adash.Messages.No_Arguments);
                        end if;

                     elsif not Adash.Predefined.Is_Exception
                                 (S.Text (Tree, Which))
                       and then Symbols."/=" (Symbols.Kind
                                                (Visible (S.Text (Tree,
                                                                  Which))),
                                              Symbols.Symbol_Exception)
                     then
                        Complain
                          (Adash.Errors.Error_Not_An_Exception, Which,
                           [1 => Adash.Messages.Named
                                   ("name", S.Text (Tree, Which))]);
                     end if;
                  end;
               end loop;

               Handler_Depth := Handler_Depth + 1;
               Analyse_Sequence (S.Second (Tree, One));
               Handler_Depth := Handler_Depth - 1;
            end;
         end loop;
      end Analyse_Handlers;

      procedure Read_Formals
        (Formals : S.Node_Id;
         Count   : Natural;
         Kinds   : in out Symbols.Parameter_Types;
         Names   : in out Symbols.Parameter_Names;
         Modes   : in out Symbols.Parameter_Modes;
         Given   : in out Symbols.Parameter_Defaults;
         Has     : in out Symbols.Parameter_Has_Default) is
      begin
         for Index in 1 .. Count loop
            declare
               Formal : constant S.Node_Id := S.Child (Tree, Formals, Index);
               Spelt  : constant String := S.Text (Tree, Formal);
            begin
               Kinds (Index) := Named_Type (S.Second (Tree, Formal));
               Names (Index) :=
                 Ada.Strings.Unbounded.To_Unbounded_String
                   (S.Text (Tree, S.First (Tree, Formal)));

               --  The parser wrote the mode as the node's text, so the three
               --  spellings are the three modes and there is no fourth.
               Modes (Index) :=
                 (if Spelt = "out" then Symbols.Mode_Out
                  elsif Spelt = "in out" then Symbols.Mode_In_Out
                  else Symbols.Mode_In);

               if S.Child_Count (Tree, Formal) = 3 then
                  declare
                     Default : constant S.Node_Id := S.Child (Tree, Formal, 3);
                     Spelling : Ada.Strings.Unbounded.Unbounded_String;

                     --  Analysed first, so that a name in it has resolved to a
                     --  symbol by the time Static_Default asks what it denotes
                     --  -- and so that a default of the wrong type is reported
                     --  as the mismatch it is rather than as not a literal.
                     Offered : constant Types.Type_Kind :=
                       Analyse_Expression (Default, Kinds (Index));
                  begin
                     if Offered /= Types.Type_None
                       and then Kinds (Index) /= Types.Type_None
                       and then not Types.Is_Acceptable
                                      (Offered, Kinds (Index))
                     then
                        Complain
                          (Adash.Errors.Error_Type_Mismatch, Default,
                           [Adash.Messages.Named
                              ("found", Types.Name (Offered)),
                            Adash.Messages.Named
                              ("expected", Types.Name (Kinds (Index)))]);
                     elsif Symbols."/=" (Modes (Index), Symbols.Mode_In) then
                        --  Ada's rule, and a sensible one: a default is a
                        --  value, and an `out` parameter is somewhere to put
                        --  one rather than something to be given.
                        Complain
                          (Adash.Errors.Error_Default_Not_In_Mode, Default,
                           [1 => Adash.Messages.Named
                                   ("name",
                                    S.Text (Tree, S.First (Tree, Formal)))]);

                     elsif not Static_Default
                                 (Into, Tree, Default, Kinds (Index), Spelling)
                     then
                        --  Restricted to a literal on purpose. An arbitrary
                        --  expression would have to be evaluated at each call
                        --  in the scope of the *declaration*, and a name
                        --  resolved at the call site is the one thing that
                        --  cannot be.
                        Complain
                          (Adash.Errors.Error_Default_Not_Literal, Default,
                           [1 => Adash.Messages.Named
                                   ("name",
                                    S.Text (Tree, S.First (Tree, Formal)))]);
                     else
                        Given (Index) := Spelling;
                        Has (Index)   := True;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end Read_Formals;

      procedure Analyse_Subprogram (Node : S.Node_Id) is
         Name_Node  : constant S.Node_Id := S.Child (Tree, Node, 1);
         Formals    : constant S.Node_Id := S.Child (Tree, Node, 2);
         Result     : constant S.Node_Id := S.Child (Tree, Node, 3);
         Declared   : constant S.Node_Id := S.Child (Tree, Node, 4);
         Statements : constant S.Node_Id := S.Child (Tree, Node, 5);

         Name  : constant String := S.Text (Tree, Name_Node);
         Count : constant Natural := S.Child_Count (Tree, Formals);

         Kinds  : Symbols.Parameter_Types := [others => Types.Type_None];
         Modes  : Symbols.Parameter_Modes := [others => Symbols.Mode_In];
         Names  : Symbols.Parameter_Names := [others => <>];
         Given  : Symbols.Parameter_Defaults := [others => <>];
         Has    : Symbols.Parameter_Has_Default := [others => False];
         Yields : Types.Type_Kind := Types.Type_None;
         Error  : Adash.Errors.Error_Info;

         --  A specification carries no declarative part and no statements.
         --  Their absence is what tells the two apart; a body always has both
         --  sequences, empty or not.
         Is_Spec : constant Boolean := not S.Is_Present (Statements);

         --  The specification this body completes, when there is one.
         Completes : Natural := 0;

         --  Saved across the body, because a subprogram is a scope for `exit`
         --  as well as for names: a loop outside it must not be exitable from
         --  within, and restoring rather than zeroing keeps that true for the
         --  statements that follow.
         Outer_Loops   : constant Natural := Loop_Depth;
         Outer_Returns : constant Types.Type_Kind := Returns;
      begin
         --  More parameters than a profile carries. Refused by name rather
         --  than kept as the first sixteen: a declaration silently shortened
         --  is one whose calls are then refused for a reason nothing said.
         if Count > Symbols.Max_Parameters then
            Complain
              (Adash.Errors.Error_Too_Many_Parameters, Name_Node,
               [Adash.Messages.Named ("name", Name),
                Adash.Messages.Named
                  ("limit", Natural'Image (Symbols.Max_Parameters))]);
            Note (Node, Types.Type_None);
            return;
         end if;

         --  A body whose name is a generic's completes that generic, which
         --  Ada writes as a unit of its own. It is *not* analysed here: what
         --  every name in it means depends on what an instantiation binds its
         --  formals to, and there is nothing to conclude until one does.
         if not Is_Spec then
            for Index in 1 .. Natural (Templates.Length) loop
               if Ada.Strings.Unbounded.To_String
                    (Templates.Element (Index).Key)
                  = Symbols.Fold (Full_Name (Name))
               then
                  declare
                     Held : Template := Templates.Element (Index);
                  begin
                     Held.Made_Of := Node;
                     Templates.Replace_Element (Index, Held);
                  end;

                  --  Marked as the generic's, so the lowering leaves it alone.
                  --  It is a template: its names have no meaning until an
                  --  instantiation binds the formals, and emitting it would
                  --  emit a body every annotation in which is absent.
                  Note (Name_Node, Types.Type_None,
                        Chain.Lookup (Full_Name (Name)));
                  Note (Node, Types.Type_None);
                  return;
               end if;
            end loop;
         end if;

         --  Refused here rather than left to run out of stack somewhere in
         --  the analyser or the lowering, both of which recurse once per
         --  level. See Adash.Language.Max_Nesting.
         if Subprogram_Depth + 2 > Adash.Language.Max_Nesting then
            Complain (Adash.Errors.Error_Nested_Subprogram, Node,
                      [1 => Adash.Messages.Named ("name", Name)]);
            return;
         end if;

         if Adash.Predefined.Profile_Of (Name).Known
           and then Is_Its_Own_Name
         then
            --  Ada would overload it. Here the shell's own subprograms accept
            --  any type, so a user's version would fit every call the original
            --  does and every one of them would be ambiguous.
            Complain (Adash.Errors.Error_Name_Is_Predefined, Name_Node,
                      [1 => Adash.Messages.Named ("name", Name)]);
            return;
         end if;

         if Count > Symbols.Max_Parameters then
            Complain (Adash.Errors.Error_Wrong_Argument_Count, Node,
                      [Adash.Messages.Named ("name", Name),
                       Adash.Messages.Named
                         ("expected", Natural'Image (Symbols.Max_Parameters)),
                       Adash.Messages.Named ("found", Natural'Image (Count))]);
            return;
         end if;

         if S.Is_Present (Result) then
            Yields := Named_Type (Result);

            if Types.Is_Composite (Yields) then
               --  A function's result is what it leaves on the stack, and a
               --  composite is a run of slots rather than a value: there is
               --  nowhere for one to be left. A procedure with an `out`
               --  parameter is how a program hands one back, and that is a
               --  run whose place the caller supplied.
               Complain
                 (Adash.Errors.Error_Result_Not_Simple, Result,
                  [Adash.Messages.Named ("name", Name),
                   Adash.Messages.Named ("found", Types.Name (Yields))]);
               Yields := Types.Type_None;
            end if;
         end if;

         Read_Formals (Formals, Count, Kinds, Names, Modes, Given, Has);

         declare
            Introduced : constant Symbols.Symbol :=
              Symbols.Make_Subprogram
                (Name       => Full_Name (Name),
                 Kind       => (if S.Is_Present (Result)
                                then Symbols.Symbol_Function
                                else Symbols.Symbol_Procedure),
                 Of_Type    => Yields,
                 Count      => Count,
                 Parameters => Kinds,
                 Modes      => Modes,
                 Names      => Names,
                 Defaults   => Given,
                 Defaulted  => Has,
                 Origin     => Origin,
                 Extent     => S.Extent (Tree, Name_Node));
         begin
            --  A body may be completing a specification given earlier in the
            --  same declarative region, in which case the name is already
            --  declared and declaring it again would be a redeclaration of
            --  itself. Searched backwards so the nearest one wins.
            if not Is_Spec then
               for Index in reverse 1 .. Natural (Awaiting.Length) loop
                  if Awaiting.Element (Index).Depth = Chain.Depth
                    and then Symbols.Same_Profile
                               (Awaiting.Element (Index).Named, Introduced)
                  then
                     Completes := Index;
                     exit;
                  end if;
               end loop;
            end if;

            --  A body in a package body completes a specification the package
            --  *declaration* made, and that declaration was a submission of
            --  its own -- so there is nothing in the queue to match against.
            --  What there is instead is the specification's own symbol, which
            --  the replayed declaration put back in scope.
            if Completes = 0
              and then not Is_Spec
              and then Ada.Strings.Unbounded.Length (Prefix) > 0
              and then Symbols.Same_Profile
                         (Chain.Lookup (Full_Name (Name)), Introduced)
            then
               Note (Name_Node, Yields, Chain.Lookup (Full_Name (Name)));

            elsif Completes /= 0 then
               --  The specification's symbol stays the one every call resolved
               --  to, so the body is annotated with it rather than with a
               --  second symbol of its own. That is also what lets the
               --  lowering find this body from a call written before it.
               Note (Name_Node, Yields, Awaiting.Element (Completes).Named);
               Awaiting.Delete (Completes);

            else
               --  Declared before its own body is analysed, so that a call to
               --  itself resolves. Without this a recursive subprogram is
               --  undeclared inside exactly the one place it is most often
               --  written.
               if Chain.Declare_Symbol (Introduced, Error) then
                  if Is_Spec then
                     --  Only a declaration that took. A refused one names a
                     --  subprogram that already exists, and queueing it would
                     --  ask twice for the one body that is missing.
                     --  A specification inside a package *declaration* is
                     --  completed in the package body, which is a submission
                     --  of its own -- exactly as Ada makes it a unit of its
                     --  own. Everything else has to be completed where it was
                     --  written, and is queued for that.
                     if not In_Package_Spec then
                        Awaiting.Append
                          (Pending_Body'(Named =>
                                           Chain.Lookup (Full_Name (Name)),
                                         Where => Name_Node,
                                         Depth => Chain.Depth));
                     end if;
                  end if;

               else
                  Legal := False;
                  Refuse_Declaration (Error, Name_Node);
               end if;

               Note (Name_Node, Yields, Chain.Lookup (Full_Name (Name)));
            end if;
         end;

         Note (Node, Types.Type_None);

         if Is_Spec then
            --  Nothing to analyse: a specification has no body, and entering a
            --  scope for it would declare parameters nothing reads.
            return;
         end if;

         Chain.Enter;
         Subprogram_Depth := Subprogram_Depth + 1;
         Master_Depth     := Master_Depth + 1;
         Returns          := Yields;
         Loop_Depth       := 0;

         for Index in 1 .. Count loop
            declare
               Formal : constant S.Node_Id := S.Child (Tree, Formals, Index);
               Ident  : constant S.Node_Id := S.First (Tree, Formal);
            begin
               if not Chain.Declare_Symbol
                        (Symbols.Make
                           (Name    => S.Text (Tree, Ident),
                            Kind    => Symbols.Symbol_Parameter,
                            Of_Type => Kinds (Index),
                            Origin  => Origin,
                            Extent  => S.Extent (Tree, Ident),
                            Mode    => Modes (Index)),
                         Error)
               then
                  Legal := False;
                  Refuse_Declaration (Error, Ident);
               end if;

               Note (Ident, Kinds (Index), Chain.Lookup (S.Text (Tree, Ident)));
            end;
         end loop;

         Analyse_Sequence (Declared);
         Analyse_Sequence (Statements);
         Analyse_Handlers (S.Child (Tree, Node, 6));

         --  Anything declared inside this body and never given a body here.
         Report_Missing_Bodies (Chain.Depth - 1);

         Subprogram_Depth := Subprogram_Depth - 1;
         Master_Depth     := Master_Depth - 1;
         Returns          := Outer_Returns;
         Loop_Depth       := Outer_Loops;
         Chain.Leave;
      end Analyse_Subprogram;

      ----------------------
      -- Analyse_Sequence --
      ----------------------

      procedure Analyse_Sequence (Node : S.Node_Id) is
      begin
         for Index in 1 .. S.Child_Count (Tree, Node) loop
            Analyse_Statement (S.Child (Tree, Node, Index));
         end loop;
      end Analyse_Sequence;

      --  The names that exist before any program declares anything come from
      --  Adash.Predefined, which owns them and their metadata. Semantics used
      --  to seed a few here; that list is gone rather than duplicated, so
      --  there is one answer to what is predefined.
      procedure Install_Predefined is
      begin
         if not Adash.Predefined.Install (Chain) then
            --  Two predefined entities share a name. A defect in the registry
            --  rather than in the program, and analysing on top of a broken
            --  environment would report nonsense about the source.
            Legal := False;
         end if;
      end Install_Predefined;

   begin
      Into.Notes.Clear;
      Into.Legal := False;
      Into.Analysed := False;

      --  One entry per node, allocated up front so an annotation never moves
      --  and a caller holding a Node_Id keeps getting the same answer.
      for Index in 1 .. Syntax.Node_Count (Tree) loop
         pragma Unreferenced (Index);
         Into.Notes.Append (Annotation'(others => <>));
      end loop;

      if Syntax.Has_Errors (Tree) then
         --  Analysing a tree that did not parse would report on the recovery
         --  rather than on the program. The parse diagnostics are what the
         --  user needs, and adding to them would bury them.
         return;
      end if;

      Install_Predefined;

      --  What the program forbids itself, before the first statement is looked
      --  at: a configuration pragma is about the whole program, and one read
      --  as it is met would hold only from where it was written.
      Read_Restrictions;

      Analyse_Sequence (Syntax.Root (Tree));

      --  Anything the submission itself declared and never gave a body to. The
      --  ones inside a body were reported as that body closed; these are what
      --  is left.
      Report_Missing_Bodies (0);

      Into.Legal := Legal;
      Into.Analysed := True;
   end Analyse;

   ----------------
   -- Is_Legal --
   ----------------

   function Is_Legal (Item : Analysis) return Boolean is
   begin
      --  A caller that forgot to call Analyse must not get permission by
      --  default, which is why this is two flags rather than one.
      return Item.Analysed and then Item.Legal;
   end Is_Legal;

   --------------
   -- Type_Of --
   --------------

   --------------------
   -- Static_Choice --
   --------------------

   function Static_Choice
     (Item  : Analysis;
      Tree  : Syntax.Tree;
      Node  : Syntax.Node_Id;
      Value : out Long_Long_Integer) return Boolean
   is
      package S renames Syntax;

      --  What a discrete type's ends are, when they are known without running
      --  anything. A subtype's are its own; a base type's are what the shape
      --  holds.
      --
      --  @param Of_Type The type asked about.
      --  @param Lowest Which end.
      --  @param Answer Where to put it.
      --  @return Whether there is an answer.
      function Ends_Of
        (Of_Type : Types.Type_Kind;
         Lowest  : Boolean;
         Answer  : out Long_Long_Integer) return Boolean
      is
      begin
         Answer := 0;

         if Types.Has_Bounds (Of_Type) then
            Answer :=
              (if Lowest then Types.Low_Bound (Of_Type)
               else Types.High_Bound (Of_Type));
            return True;
         end if;

         case Types.Shape (Of_Type) is
            when Types.Shape_Integer =>
               --  The machine's own range, which is what an Integer holds
               --  here -- and what the lowering pushes for the same question.
               Answer :=
                 (if Lowest then Long_Long_Integer'First
                  else Long_Long_Integer'Last);
               return True;

            when Types.Shape_Boolean | Types.Shape_Character
               | Types.Shape_Enumeration =>
               Answer :=
                 (if Lowest then 0 else Types.Value_Count (Of_Type) - 1);
               return True;

            when others =>
               return False;
         end case;
      end Ends_Of;

   begin
      Value := 0;

      if not S.Is_Present (Node) then
         return False;
      end if;

      case S.Kind (Tree, Node) is
         when S.Node_Parenthesized =>
            --  Parentheses group and change nothing, here as everywhere.
            return Static_Choice (Item, Tree, S.First (Tree, Node), Value);

         when S.Node_Attribute =>
            --  `Integer'Last`, `Verdict'First`, `Colour'Size`. Ada calls these
            --  static and so does this: what they answer is decided by the
            --  declaration, and nothing between here and running can change
            --  it. Without this a case choice, a subtype bound and an
            --  aggregate's index each had to be written as a literal, and a
            --  program that named the type it meant was refused.
            declare
               Asked : constant String :=
                 Symbols.Fold (S.Text (Tree, S.Second (Tree, Node)));
               Of_Prefix : constant Types.Type_Kind :=
                 (if Symbols."=" (Symbols.Kind
                                    (Symbol_Of (Item, S.First (Tree, Node))),
                                  Symbols.Symbol_Type)
                  then Symbols.Of_Type (Symbol_Of (Item, S.First (Tree, Node)))
                  else Type_Of (Item, S.First (Tree, Node)));
            begin
               --  An array's ends are its *index range*, which is where its
               --  values sit rather than what they are: `Samples'First` is
               --  one where `Samples (1)` is an Integer. A String's are not
               --  known before it runs, so they are not static.
               if Types.Shape (Of_Prefix) = Types.Shape_Array
                 and then Asked in "first" | "last" | "length"
               then
                  declare
                     How_Many : constant Long_Long_Integer :=
                       Long_Long_Integer (Part_Count (Item, Of_Prefix));
                  begin
                     --  A type whose values carry their own length knows one
                     --  of the three: every value of one begins at one, and
                     --  what it ends at is the caller's business. Part_Count
                     --  answers zero for such a type, which is what says so.
                     if Types.Is_Open (Of_Prefix) then
                        if Asked /= "first" then
                           return False;
                        end if;

                        Value := 1;
                        return True;
                     end if;

                     if How_Many = 0 then
                        return False;
                     end if;

                     Value :=
                       (if Asked = "length" then How_Many
                        elsif Asked = "first" then First_Index (Item, Of_Prefix)
                        else First_Index (Item, Of_Prefix) + How_Many - 1);
                     return True;
                  end;

               elsif Asked in "first" | "last" then
                  return Ends_Of (Type_Of (Item, Node), Asked = "first",
                                  Value);

               elsif Asked = "size" then
                  if Of_Prefix = Types.Type_None then
                     return False;
                  end if;

                  Value := Long_Long_Integer (Types.Width (Of_Prefix));
                  return True;
               end if;

               return False;
            end;

         when S.Node_Call =>
            --  `Integer'Pos (7)`, `Colour'Val (1)`, `Colour'Succ (Red)`. An
            --  attribute that takes an argument is a call to the parser, and
            --  is static when what it is given is.
            declare
               Head : constant S.Node_Id := S.First (Tree, Node);
               Args : constant S.Node_Id := S.Second (Tree, Node);
            begin
               if S.Kind (Tree, Head) /= S.Node_Attribute
                 or else not S.Is_Present (Args)
                 or else S.Child_Count (Tree, Args) /= 1
               then
                  return False;
               end if;

               declare
                  Asked : constant String :=
                    Symbols.Fold (S.Text (Tree, S.Second (Tree, Head)));
                  Given : Long_Long_Integer;
               begin
                  if Asked not in "pos" | "val" | "succ" | "pred"
                    or else not Static_Choice
                                  (Item, Tree, S.Child (Tree, Args, 1), Given)
                  then
                     return False;
                  end if;

                  --  A value *is* its position here, so `'Pos` and `'Val` are
                  --  the number they were given and the two neighbours are
                  --  one either side of it.
                  Value :=
                    (case Asked (Asked'First) is
                        when 's' => Given + 1,
                        when 'p' =>
                          (if Asked = "pred" then Given - 1 else Given),
                        when others => Given);
                  return True;
               end;
            end;

         when S.Node_Integer_Literal =>
            Value := Long_Long_Integer'Value (S.Text (Tree, Node));
            return True;

         when S.Node_Character_Literal =>
            declare
               Text : constant String := S.Text (Tree, Node);
            begin
               if Text'Length = 0 then
                  return False;
               end if;

               Value := Long_Long_Integer (Character'Pos (Text (Text'First)));
               return True;
            end;

         when S.Node_Name =>
            --  True and False, and only those: a name that resolves to
            --  something the shell provides is a literal of the language, and
            --  one that resolves to a variable is not static however it is
            --  spelled. A parameter named True inside a body is a variable,
            --  and asking the symbol rather than the text is what tells them
            --  apart.
            declare
               Found : constant Symbols.Symbol := Symbol_Of (Item, Node);
            begin
               if Symbols.Is_Nothing (Found)
                 or else Symbols.Kind (Found)
                         not in Symbols.Symbol_Constant
                              | Symbols.Symbol_Literal
               then
                  return False;
               end if;

               --  An enumeration literal, which is static for the same reason
               --  True is: the declaration fixed its position and nothing can
               --  change it. A loop parameter over the same type is a
               --  *constant* of it and is not static, which is why the kind
               --  answers this rather than the type.
               if Symbols.Kind (Found) = Symbols.Symbol_Literal then
                  Value := Long_Long_Integer (Symbols.Position (Found));
                  return True;
               end if;

               if not Symbols.Is_Provided (Found) then
                  return False;
               end if;

               if Symbols.Key (Found) = "true" then
                  Value := 1;
                  return True;
               elsif Symbols.Key (Found) = "false" then
                  Value := 0;
                  return True;
               end if;

               return False;
            end;

         when S.Node_Unary_Operation =>
            --  `-1` is a literal as anybody writing a case would use the word,
            --  and is an operation as the grammar sees it.
            declare
               Inner : Long_Long_Integer := 0;
            begin
               if S.Operator (Tree, Node) not in S.Op_Plus | S.Op_Minus
                 or else not Static_Choice
                               (Item, Tree, S.First (Tree, Node), Inner)
               then
                  return False;
               end if;

               Value :=
                 (if S.Operator (Tree, Node) = S.Op_Minus then -Inner
                  else Inner);
               return True;
            end;

         when others =>
            return False;
      end case;

   exception
      when Constraint_Error =>
         --  A literal too large for the machine. Not static in any useful
         --  sense: refusing it here reports it as a choice rather than letting
         --  the emitter raise while building the program.
         return False;
   end Static_Choice;

   -------------
   -- Type_Of --
   -------------

   function Type_Of
     (Item : Analysis;
      Node : Syntax.Node_Id) return Types.Type_Kind
   is
      Index : constant Natural := Syntax.Index (Node);
   begin
      if Index = 0 or else Index > Natural (Item.Notes.Length) then
         return Types.Type_None;
      end if;

      return Item.Notes.Element (Index).Resolved_Type;
   end Type_Of;

   ----------------
   -- Symbol_Of --
   ----------------

   function Symbol_Of
     (Item : Analysis;
      Node : Syntax.Node_Id) return Symbols.Symbol
   is
      Index : constant Natural := Syntax.Index (Node);
   begin
      if Index = 0 or else Index > Natural (Item.Notes.Length) then
         return Symbols.Nothing;
      end if;

      return Item.Notes.Element (Index).Resolved;
   end Symbol_Of;

   ----------------------
   -- Annotated_Count --
   ----------------------

   function Queue_Bound (Item : Analysis; Most : out Natural) return Boolean is
   begin
      Most := Item.Queue_Limit;
      return Item.Queue_Given;
   end Queue_Bound;

   function Forbids_Termination (Item : Analysis) return Boolean is
   begin
      return Item.Endless;
   end Forbids_Termination;

   function Task_Bound (Item : Analysis; Most : out Natural) return Boolean is
   begin
      Most := Item.Task_Limit;
      return Item.Bounded;
   end Task_Bound;

   function Slots_Asked_About
     (Item : Analysis; Node : Syntax.Node_Id) return Natural is
   begin
      for One of Item.Sizes loop
         if Syntax."=" (One.At_Node, Node) then
            return One.Slots;
         end if;
      end loop;

      return 0;
   end Slots_Asked_About;

   function Annotated_Count (Item : Analysis) return Natural is
      Result : Natural := 0;
   begin
      for Current of Item.Notes loop
         if Current.Visited then
            Result := Result + 1;
         end if;
      end loop;

      return Result;
   end Annotated_Count;

end Adash.Language.Semantics;

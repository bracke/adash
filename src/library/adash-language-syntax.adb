package body Adash.Language.Syntax is

   use Ada.Strings.Unbounded;

   ---------------
   -- Spelling --
   ---------------

   function Spelling (Item : Operation) return String is
   begin
      case Item is
         when Op_None          => return "";
         when Op_Plus          => return "+";
         when Op_Minus         => return "-";
         when Op_Not           => return "not";
         when Op_Abs           => return "abs";
         when Op_Multiply      => return "*";
         when Op_Divide        => return "/";
         when Op_Mod           => return "mod";
         when Op_Rem           => return "rem";
         when Op_Add           => return "+";
         when Op_Subtract      => return "-";
         when Op_Concat        => return "&";
         when Op_Power         => return "**";
         when Op_Equal         => return "=";
         when Op_Not_Equal     => return "/=";
         when Op_Less          => return "<";
         when Op_Less_Equal    => return "<=";
         when Op_Greater       => return ">";
         when Op_Greater_Equal => return ">=";
         when Op_In            => return "in";
         when Op_Not_In        => return "not in";
         when Op_And           => return "and";
         when Op_Or            => return "or";
         when Op_Xor           => return "xor";
         when Op_And_Then      => return "and then";
         when Op_Or_Else       => return "or else";
      end case;
   end Spelling;

   -----------------
   -- Is_Present --
   -----------------

   function Is_Present (Item : Node_Id) return Boolean is
   begin
      return Item /= No_Node;
   end Is_Present;

   -----------
   -- Index --
   -----------

   function Index (Item : Node_Id) return Natural is
   begin
      return Natural (Item);
   end Index;

   ----------
   -- Root --
   ----------

   function Root (Item : Tree) return Node_Id is
   begin
      return Item.Root;
   end Root;

   -----------------
   -- Node_Count --
   -----------------

   function Node_Count (Item : Tree) return Natural is
   begin
      return Natural (Item.Nodes.Length);
   end Node_Count;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Tree; Node : Node_Id) return Node_Kind is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return Node_None;
      end if;

      return Item.Nodes.Element (Positive (Node)).Kind;
   end Kind;

   ------------
   -- Extent --
   ------------

   function Extent (Item : Tree; Node : Node_Id) return Adash.Source.Span is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return Adash.Source.Nowhere;
      end if;

      return Item.Nodes.Element (Positive (Node)).Extent;
   end Extent;

   --------------
   -- Operator --
   --------------

   function Operator (Item : Tree; Node : Node_Id) return Operation is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return Op_None;
      end if;

      return Item.Nodes.Element (Positive (Node)).Operator;
   end Operator;

   ----------
   -- Text --
   ----------

   function Text (Item : Tree; Node : Node_Id) return String is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return "";
      end if;

      return To_String (Item.Nodes.Element (Positive (Node)).Text);
   end Text;

   --------------
   -- Set_Text --
   --------------

   procedure Set_Text (Item : in out Tree; Node : Node_Id; Text : String) is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return;
      end if;

      declare
         Changed : Node_Record := Item.Nodes.Element (Positive (Node));
      begin
         Changed.Text := To_Unbounded_String (Text);
         Item.Nodes.Replace_Element (Positive (Node), Changed);
      end;
   end Set_Text;

   ------------------
   -- Child_Count --
   ------------------

   function Child_Count (Item : Tree; Node : Node_Id) return Natural is
   begin
      if Node = No_Node or else Natural (Node) > Natural (Item.Nodes.Length) then
         return 0;
      end if;

      return Item.Nodes.Element (Positive (Node)).Child_Count;
   end Child_Count;

   -----------
   -- Child --
   -----------

   function Child (Item : Tree; Node : Node_Id; Index : Positive) return Node_Id is
   begin
      if Index > Child_Count (Item, Node) then
         return No_Node;
      end if;

      declare
         Record_Of : constant Node_Record := Item.Nodes.Element (Positive (Node));
      begin
         return Item.Children.Element (Record_Of.First_Child + Index - 1);
      end;
   end Child;

   -----------
   -- First --
   -----------

   function First (Item : Tree; Node : Node_Id) return Node_Id is
   begin
      return Child (Item, Node, 1);
   end First;

   ------------
   -- Second --
   ------------

   function Second (Item : Tree; Node : Node_Id) return Node_Id is
   begin
      return Child (Item, Node, 2);
   end Second;

   -----------
   -- Third --
   -----------

   function Third (Item : Tree; Node : Node_Id) return Node_Id is
   begin
      return Child (Item, Node, 3);
   end Third;

   ------------------
   -- Has_Errors --
   ------------------

   function Has_Errors (Item : Tree) return Boolean is
   begin
      --  Every node, not only the root's descendants: a node built and then
      --  abandoned by recovery is still evidence the parse went wrong.
      for Current of Item.Nodes loop
         if Current.Kind = Node_Error then
            return True;
         end if;
      end loop;

      return False;
   end Has_Errors;

   ---------------
   -- Add_Leaf --
   ---------------

   function Add_Leaf
     (Item     : in out Tree;
      Kind     : Node_Kind;
      Extent   : Adash.Source.Span;
      Text     : String := "";
      Operator : Operation := Op_None) return Node_Id
   is
   begin
      return Add_Node (Item, Kind, Extent, No_Children, Text, Operator);
   end Add_Leaf;

   ---------------
   -- Add_Node --
   ---------------

   function Add_Node
     (Item     : in out Tree;
      Kind     : Node_Kind;
      Extent   : Adash.Source.Span;
      Children : Node_List;
      Text     : String := "";
      Operator : Operation := Op_None) return Node_Id
   is
      Created : Node_Record;
   begin
      Created.Kind     := Kind;
      Created.Extent   := Extent;
      Created.Operator := Operator;
      Created.Text     := To_Unbounded_String (Text);

      if Children'Length > 0 then
         Created.First_Child := Natural (Item.Children.Length) + 1;
         Created.Child_Count := Children'Length;

         for Current of Children loop
            Item.Children.Append (Current);
         end loop;
      end if;

      Item.Nodes.Append (Created);

      --  The identity is the index, which is why nodes are never removed: a
      --  Node_Id handed out earlier has to keep meaning the same node.
      return Node_Id (Item.Nodes.Length);
   end Add_Node;

   ---------------
   -- Set_Root --
   ---------------

   -----------
   -- Graft --
   -----------

   function Graft
     (Item    : in out Tree;
      Node    : Node_Id;
      Bindings : Renamings := No_Renamings) return Node_Id
   is
      --  The text this node gets in the copy. Only a name is ever replaced:
      --  a literal's text is a value and a mode's text is a keyword, and
      --  neither is a name a binding could be about.
      function Spelt return String is
      begin
         if Kind (Item, Node) /= Node_Name then
            return Text (Item, Node);
         end if;

         for One of Bindings loop
            if Ada.Strings.Unbounded.To_String (One.From)
               = Text (Item, Node)
            then
               return Ada.Strings.Unbounded.To_String (One.To);
            end if;
         end loop;

         return Text (Item, Node);
      end Spelt;
   begin
      if not Is_Present (Node) then
         return No_Node;
      end if;

      declare
         --  Children first, so that every child exists before the parent that
         --  names them. Depth first is also what keeps this from having to
         --  patch anything afterwards.
         Count  : constant Natural := Child_Count (Item, Node);
         Copies : Node_List (1 .. Natural'Max (Count, 1));

         --  Read before the children are made, because making them appends to
         --  the same store and a reference into it would not survive that.
         Written : constant String := Spelt;
         Shape   : constant Node_Kind := Kind (Item, Node);
         Where   : constant Adash.Source.Span := Extent (Item, Node);
         How     : constant Operation := Operator (Item, Node);
      begin
         for Index in 1 .. Count loop
            Copies (Index) := Graft (Item, Child (Item, Node, Index), Bindings);
         end loop;

         if Count = 0 then
            return Add_Leaf (Item, Shape, Where, Written, How);
         end if;

         return Add_Node
           (Item, Shape, Where, Copies (1 .. Count), Written, How);
      end;
   end Graft;

   procedure Set_Root (Item : in out Tree; Node : Node_Id) is
   begin
      Item.Root := Node;
   end Set_Root;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Tree) is
   begin
      Item.Nodes.Clear;
      Item.Children.Clear;
      Item.Root := No_Node;
   end Clear;

end Adash.Language.Syntax;

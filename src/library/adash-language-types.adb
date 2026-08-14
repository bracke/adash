package body Adash.Language.Types is

   ---------
   -- "=" --
   ---------

   overriding function "=" (Left, Right : Type_Kind) return Boolean is
   begin
      return Left.Form = Right.Form and then Left.Id = Right.Id;
   end "=";

   -----------
   -- Shape --
   -----------

   function Shape (Item : Type_Kind) return Type_Shape is
   begin
      return Item.Form;
   end Shape;

   --------------
   -- Identity --
   --------------

   function Identity (Item : Type_Kind) return Natural is
   begin
      return Item.Id;
   end Identity;

   ------------------
   -- Enumeration --
   ------------------

   function Enumeration
     (Id       : Positive;
      Called   : String;
      Literals : Natural) return Type_Kind
   is
      Result : Type_Kind;

      --  Quoted short rather than refused. The name is for a diagnostic to
      --  show; identity is the number beside it, so a truncated name can be
      --  awkward to read and cannot be mistaken for another type.
      Kept : constant Natural := Natural'Min (Called'Length, Max_Name);
   begin
      Result.Form     := Shape_Enumeration;
      Result.Id       := Id;
      Result.Length   := Kept;
      Result.Literals := Literals;
      Result.Called (1 .. Kept) :=
        Called (Called'First .. Called'First + Kept - 1);

      return Result;
   end Enumeration;

   -------------------
   -- Constrained --
   -------------------

   function Constrained
     (Base   : Type_Kind;
      Called : String;
      Low    : Long_Long_Integer;
      High   : Long_Long_Integer) return Type_Kind
   is
      Result : Type_Kind := Base;
      Kept   : constant Natural := Natural'Min (Called'Length, Max_Name);
   begin
      --  The identity is the base's, untouched. A subtype is the same type,
      --  and everything that compares types has to keep saying so.
      Result.Narrowed := True;
      Result.Low      := Low;
      Result.High     := High;
      Result.Length   := Kept;
      Result.Called   := [others => ' '];
      Result.Called (1 .. Kept) :=
        Called (Called'First .. Called'First + Kept - 1);

      return Result;
   end Constrained;

   ------------------
   -- Has_Bounds --
   ------------------

   function Has_Bounds (Item : Type_Kind) return Boolean is
   begin
      return Item.Narrowed;
   end Has_Bounds;

   -----------------
   -- Low_Bound --
   -----------------

   function Low_Bound (Item : Type_Kind) return Long_Long_Integer is
   begin
      return Item.Low;
   end Low_Bound;

   ------------------
   -- High_Bound --
   ------------------

   function High_Bound (Item : Type_Kind) return Long_Long_Integer is
   begin
      return Item.High;
   end High_Bound;

   -----------
   -- Width --
   -----------

   function Width (Item : Type_Kind) return Positive is
   begin
      return Item.Slots;
   end Width;

   -----------------
   -- Task_Type --
   -----------------

   function Task_Type (Id : Positive; Called : String) return Type_Kind is
      Result : Type_Kind := Enumeration (Id, Called, 0);
   begin
      Result.Form := Shape_Task;
      return Result;
   end Task_Type;

   ---------------
   -- Is_Task --
   ---------------

   function Is_Task (Item : Type_Kind) return Boolean is
   begin
      return Item.Form = Shape_Task;
   end Is_Task;

   ----------------------
   -- Protected_Type --
   ----------------------

   function Protected_Type (Id : Positive; Called : String) return Type_Kind is
      Result : Type_Kind := Enumeration (Id, Called, 0);
   begin
      Result.Form := Shape_Protected;
      return Result;
   end Protected_Type;

   --------------------
   -- Is_Protected --
   --------------------

   function Is_Protected (Item : Type_Kind) return Boolean is
   begin
      return Item.Form = Shape_Protected;
   end Is_Protected;

   -----------------------
   -- Composite_Record --
   -----------------------

   function Composite_Record
     (Id     : Positive;
      Called : String;
      Slots  : Positive) return Type_Kind
   is
      Result : Type_Kind := Enumeration (Id, Called, 0);
   begin
      Result.Form  := Shape_Record;
      Result.Slots := Slots;
      return Result;
   end Composite_Record;

   ----------------------
   -- Composite_Array --
   ----------------------

   function Composite_Array
     (Id     : Positive;
      Called : String;
      Slots  : Positive) return Type_Kind
   is
      Result : Type_Kind := Enumeration (Id, Called, 0);
   begin
      Result.Form  := Shape_Array;
      Result.Slots := Slots;
      return Result;
   end Composite_Array;

   -------------------
   -- Is_Composite --
   -------------------

   function Is_Composite (Item : Type_Kind) return Boolean is
   begin
      return Item.Form in Shape_Record | Shape_Array;
   end Is_Composite;

   ----------
   -- Name --
   ----------

   function Name (Item : Type_Kind) return String is
   begin
      --  No `others`. A shape added without a name is a compile error, which
      --  is the only moment anyone is still thinking about what to call it.
      --  A subtype answers with its own name, which is what a user wrote and
      --  what a diagnostic should quote back.
      if Item.Length > 0 then
         return Item.Called (1 .. Item.Length);
      end if;

      case Item.Form is
         when Shape_None      => return "";
         when Shape_Boolean   => return "Boolean";
         when Shape_Integer   => return "Integer";
         when Shape_Float     => return "Float";
         when Shape_Character => return "Character";
         when Shape_Task_Id   => return "Task_Id";
         when Shape_String    => return "String";

         when Shape_Enumeration | Shape_Record | Shape_Array | Shape_Task
            | Shape_Protected =>
            --  A declared type always has a name, which the branch above
            --  returns. Reaching here means one was built without one.
            return "";
      end case;
   end Name;

   -----------------
   -- Is_Ordered --
   -----------------

   function Is_Ordered (Item : Type_Kind) return Boolean is
   begin
      case Item.Form is
         when Shape_None =>
            return False;

         when Shape_Boolean | Shape_Integer | Shape_Float | Shape_Character
            | Shape_String | Shape_Enumeration =>
            --  Every scalar Adash has is ordered, including Boolean, which Ada
            --  orders False < True, and an enumeration, which Ada orders by
            --  the order its literals were written in.
            return True;

         when Shape_Record | Shape_Array | Shape_Task
            | Shape_Protected | Shape_Task_Id =>
            --  Ada orders an array of a discrete type and does not order a
            --  record. Neither is ordered here: an ordering over a run of
            --  slots needs a rule per shape, and a shell script compares
            --  values rather than sorting structures. A task is not a value
            --  to compare at all -- it is something that runs.
            return False;
      end case;
   end Is_Ordered;

   ------------------
   -- Is_Discrete --
   ------------------

   function Is_Discrete (Item : Type_Kind) return Boolean is
   begin
      return Item.Form in Shape_Boolean | Shape_Integer | Shape_Character
                        | Shape_Enumeration;
   end Is_Discrete;

   -----------------------
   -- Admitted_Count --
   -----------------------

   function Admitted_Count (Item : Type_Kind) return Long_Long_Integer is
   begin
      if not Is_Discrete (Item) then
         return 0;
      end if;

      if Has_Bounds (Item) then
         return High_Bound (Item) - Low_Bound (Item) + 1;
      end if;

      return Value_Count (Item);
   end Admitted_Count;

   -------------------
   -- Value_Count --
   -------------------

   function Value_Count (Item : Type_Kind) return Long_Long_Integer is
   begin
      case Item.Form is
         when Shape_Boolean =>
            return 2;

         when Shape_Character =>
            return 256;

         when Shape_Enumeration =>
            return Long_Long_Integer (Item.Literals);

         when Shape_Integer =>
            return Long_Long_Integer (Integer'Last)
                   - Long_Long_Integer (Integer'First) + 1;

         when others =>
            return 0;
      end case;
   end Value_Count;

   ------------------
   -- Is_Numeric --
   ------------------

   function Is_Numeric (Item : Type_Kind) return Boolean is
   begin
      case Item.Form is
         when Shape_Integer | Shape_Float =>
            return True;

         when Shape_None | Shape_Boolean | Shape_Character | Shape_String
            | Shape_Enumeration | Shape_Record | Shape_Array | Shape_Task
            | Shape_Protected | Shape_Task_Id =>
            return False;
      end case;
   end Is_Numeric;

   --------------------
   -- Has_Literals --
   --------------------

   function Has_Literals (Item : Type_Kind) return Boolean is
   begin
      case Item.Form is
         when Shape_Boolean | Shape_Integer | Shape_Float | Shape_Character
            | Shape_String =>
            return True;

         when Shape_Enumeration =>
            --  Its values are written as the names the declaration gave them,
            --  which resolve through the scope chain like any other name. A
            --  body may hide one, which no literal can be.
            return False;

         when Shape_Record | Shape_Array | Shape_Task
            | Shape_Protected | Shape_Task_Id =>
            --  An aggregate is not a literal: what it holds is expressions,
            --  and two aggregates with the same text can mean different values
            --  at different points of a program. A task has no literal at all:
            --  what makes one is a declaration, not a value written down.
            return False;

         when Shape_None =>
            --  Type_None cannot be written down. That is what makes it safe as
            --  "no value": no source can produce one by accident.
            return False;
      end case;
   end Has_Literals;

   ---------------------
   -- Is_Acceptable --
   ---------------------

   function Is_Acceptable (Found : Type_Kind; Expected : Type_Kind) return Boolean is
   begin
      --  Identity, and nothing else. Not even Integer where Float is expected:
      --  a language that converts quietly has a rounding rule nobody wrote
      --  down, and the first time it matters is in someone's arithmetic.
      if Found.Form = Shape_None or else Expected.Form = Shape_None then
         return False;
      end if;

      --  A composite carries how many slots it is, and two runs of different
      --  lengths are not each other's value. A slice of two elements where
      --  three are wanted would copy a slot belonging to something else, and
      --  the lengths here are known before the program runs -- so this is
      --  refused where it is written rather than raised where it runs, which
      --  is what Ada does with the same case.
      if Is_Composite (Found)
        and then Is_Composite (Expected)
        and then Found.Slots /= Expected.Slots
      then
         return False;
      end if;

      --  Shape *and* identity, which is what "=" compares. Two enumerations
      --  with the same literals spelled the same way are two types, which is
      --  Ada's rule and the reason a declaration carries an identity at all.
      return Found = Expected;
   end Is_Acceptable;

   ----------------------
   -- Is_Convertible --
   ----------------------

   function Is_Convertible (From : Type_Kind; To : Type_Kind) return Boolean is
   begin
      --  Nothing converts to or from "no value".
      if From.Form = Shape_None or else To.Form = Shape_None then
         return False;
      end if;

      --  A type converts to itself, which makes an explicit conversion legal
      --  even when it is redundant -- generated code and macros rely on that.
      if Is_Acceptable (From, To) then
         return True;
      end if;

      --  Every type has a text form, so every type converts to String.
      if To.Form = Shape_String then
         return True;
      end if;

      case From.Form is
         when Shape_Integer | Shape_Float =>
            --  Between the numeric types, and from text.
            return Is_Numeric (To);

         when Shape_Character =>
            return False;

         when Shape_String =>
            --  Parsing text into a value is a conversion that can fail, which
            --  is why it must be written rather than implied. Values.Convert
            --  reports the failure.
            return To.Form = Shape_Character or else Is_Numeric (To)
              or else To.Form = Shape_Boolean;

         when Shape_Boolean =>
            return False;

         when Shape_Enumeration =>
            --  Only to String, which is handled above. An enumeration is not a
            --  number here: `Colour'Pos` is how a program asks for its
            --  position, and that is written down where a conversion would be
            --  silent.
            return False;

         when Shape_Record | Shape_Array | Shape_Task
            | Shape_Protected | Shape_Task_Id =>
            return False;

         when Shape_None =>
            return False;
      end case;
   end Is_Convertible;

end Adash.Language.Types;

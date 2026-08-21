with Ada.Characters.Handling;

package body Adash.Language.Symbols is

   use Ada.Strings.Unbounded;

   ----------
   -- Fold --
   ----------

   function Fold (Name : String) return String is
      Result : String := Name;
   begin
      --  ASCII folding only, deliberately. Ada 2022 identifiers may contain
      --  characters beyond ASCII, and folding those correctly is a Unicode
      --  case-mapping problem with locale-sensitive corners -- the Turkish
      --  dotless i being the famous one. Getting it half right here would make
      --  two names equal on one machine and not another, which is worse than
      --  the current limitation of treating non-ASCII letters case-sensitively.
      --  When the lexer settles what an identifier is, this is where the rule
      --  goes, once.
      for Index in Result'Range loop
         Result (Index) := Ada.Characters.Handling.To_Lower (Result (Index));
      end loop;

      return Result;
   end Fold;

   ----------
   -- Make --
   ----------

   function Make
     (Name     : String;
      Kind     : Symbol_Kind;
      Of_Type  : Types.Type_Kind;
      Origin   : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent   : Adash.Source.Span := Adash.Source.Nowhere;
      Mode     : Parameter_Mode := Mode_In;
      Provided : Boolean := False;
      Position : Natural := 0) return Symbol
   is
   begin
      return (Name    => To_Unbounded_String (Name),
              Within  => <>,
              Kept    => <>,
              Key     => To_Unbounded_String (Fold (Name)),
              Kind    => Kind,
              Of_Type => Of_Type,
              Origin  => Origin,
              Extent  => Extent,
              Present => True,
              Provided => Provided,

              --  Nothing that Make builds can be called, so it has no
              --  parameters. Make_Subprogram is where a profile comes from.
              Profiled   => False,
              Count      => 0,
              Parameters => [others => Types.Type_None],
              Modes      => [others => Mode_In],
              Names      => [others => <>],
              Defaults   => [others => <>],
              Defaulted  => [others => False],
              Passed_As  => Mode,
              Sits_At    => Position);
   end Make;

   -------------------
   -- Is_Provided --
   -------------------

   function Is_Provided (Item : Symbol) return Boolean is
   begin
      return Item.Provided;
   end Is_Provided;

   ---------------
   -- Kept_By --
   ---------------

   function Kept_By (Item : Symbol) return String is
   begin
      return To_String (Item.Kept);
   end Kept_By;

   ----------------
   -- Keep_For --
   ----------------

   procedure Keep_For (Item : in out Symbol; Owner : String) is
   begin
      Item.Kept := To_Unbounded_String (Owner);
   end Keep_For;

   ----------------------
   -- Declared_Within --
   ----------------------

   function Declared_Within (Item : Symbol) return String is
   begin
      return To_String (Item.Within);
   end Declared_Within;

   ---------------------
   -- Declare_Within --
   ---------------------

   procedure Declare_Within (Item : in out Symbol; Unit : String) is
   begin
      Item.Within := To_Unbounded_String (Unit);
   end Declare_Within;

   -----------------
   -- Is_Nothing --
   -----------------

   ---------------------
   -- Make_Subprogram --
   ---------------------

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
      Extent     : Adash.Source.Span := Adash.Source.Nowhere) return Symbol is
   begin
      return
        (Name       => To_Unbounded_String (Name),
         Within     => <>,
         Kept       => <>,
         Key        => To_Unbounded_String (Fold (Name)),
         Kind       => Kind,
         Of_Type    => Of_Type,
         Origin     => Origin,
         Extent     => Extent,
         Present    => True,
         Provided   => False,
         Profiled   => True,
         Count      => Count,
         Parameters => Parameters,
         Modes      => Modes,
         Names      => Names,
         Defaults   => Defaults,
         Defaulted  => Defaulted,
         Passed_As  => Mode_In,
         Sits_At    => 0);
   end Make_Subprogram;

   ---------------
   -- Position --
   ---------------

   function Position (Item : Symbol) return Natural is
   begin
      return Item.Sits_At;
   end Position;

   ---------------------
   -- Parameter_Name --
   ---------------------

   function Parameter_Name (Item : Symbol; Index : Positive) return String is
   begin
      return To_String (Item.Names (Index));
   end Parameter_Name;

   -------------------
   -- Parameter_At --
   -------------------

   function Parameter_At (Item : Symbol; Name : String) return Natural is
      Wanted : constant String := Fold (Name);
   begin
      for Index in 1 .. Item.Count loop
         if Fold (To_String (Item.Names (Index))) = Wanted then
            return Index;
         end if;
      end loop;

      return 0;
   end Parameter_At;

   ------------------
   -- Has_Default --
   ------------------

   function Has_Default (Item : Symbol; Index : Positive) return Boolean is
   begin
      return Item.Defaulted (Index);
   end Has_Default;

   -------------------
   -- Default_Text --
   -------------------

   function Default_Text (Item : Symbol; Index : Positive) return String is
   begin
      return To_String (Item.Defaults (Index));
   end Default_Text;

   -------------------
   -- Same_Profile --
   -------------------

   function Same_Profile (Left, Right : Symbol) return Boolean is
      use type Types.Type_Kind;
   begin
      if Left.Key /= Right.Key
        or else Left.Count /= Right.Count
        or else Left.Of_Type /= Right.Of_Type
      then
         return False;
      end if;

      for Index in 1 .. Left.Count loop
         if Left.Parameters (Index) /= Right.Parameters (Index) then
            return False;
         end if;
      end loop;

      return True;
   end Same_Profile;

   -----------------
   -- Has_Profile --
   -----------------

   function Has_Profile (Item : Symbol) return Boolean is
   begin
      return Item.Profiled;
   end Has_Profile;

   ---------------------
   -- Parameter_Count --
   ---------------------

   function Parameter_Count (Item : Symbol) return Natural is
   begin
      return Item.Count;
   end Parameter_Count;

   ------------------------
   -- Parameter_Passing --
   ------------------------

   function Parameter_Passing
     (Item : Symbol; Index : Positive) return Parameter_Mode is
   begin
      return Item.Modes (Index);
   end Parameter_Passing;

   -------------
   -- Passing --
   -------------

   function Passing (Item : Symbol) return Parameter_Mode is
   begin
      return Item.Passed_As;
   end Passing;

   --------------------
   -- Parameter_Type --
   --------------------

   function Parameter_Type
     (Item : Symbol; Index : Positive) return Types.Type_Kind is
   begin
      return Item.Parameters (Index);
   end Parameter_Type;

   function Is_Nothing (Item : Symbol) return Boolean is
   begin
      return not Item.Present;
   end Is_Nothing;

   ----------
   -- Name --
   ----------

   function Name (Item : Symbol) return String is
   begin
      return To_String (Item.Name);
   end Name;

   ---------
   -- Key --
   ---------

   function Key (Item : Symbol) return String is
   begin
      return To_String (Item.Key);
   end Key;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Symbol) return Symbol_Kind is
   begin
      return Item.Kind;
   end Kind;

   -------------
   -- Of_Type --
   -------------

   function Of_Type (Item : Symbol) return Types.Type_Kind is
   begin
      return Item.Of_Type;
   end Of_Type;

   ------------
   -- Origin --
   ------------

   function Origin (Item : Symbol) return Adash.Source.Origin is
   begin
      return Item.Origin;
   end Origin;

   ------------
   -- Extent --
   ------------

   function Extent (Item : Symbol) return Adash.Source.Span is
   begin
      return Item.Extent;
   end Extent;

   ---------------------
   -- Is_Assignable --
   ---------------------

   function Is_Assignable (Item : Symbol) return Boolean is
   begin
      if not Item.Present then
         return False;
      end if;

      case Item.Kind is
         when Symbol_Variable =>
            return True;

         when Symbol_Parameter =>
            --  An `in` parameter is a value the body was given, not a place it
            --  may write to. Ada says so; before modes existed this package
            --  could not, and said every parameter was assignable.
            return Item.Passed_As /= Mode_In;

         when Symbol_Constant | Symbol_Literal | Symbol_Function
            | Symbol_Procedure | Symbol_Entry | Symbol_Type | Symbol_Package
            | Symbol_Generic | Symbol_Exception =>
            return False;
      end case;
   end Is_Assignable;

   -------------------
   -- Is_Callable --
   -------------------

   function Is_Callable (Item : Symbol) return Boolean is
   begin
      if not Item.Present then
         return False;
      end if;

      case Item.Kind is
         when Symbol_Function | Symbol_Procedure | Symbol_Entry =>
            return True;

         when Symbol_Variable | Symbol_Constant | Symbol_Literal
            | Symbol_Parameter | Symbol_Type | Symbol_Package
            | Symbol_Generic | Symbol_Exception =>
            --  A generic is not callable. What is callable is what an
            --  instantiation of it declared, which is an ordinary subprogram.
            return False;
      end case;
   end Is_Callable;

end Adash.Language.Symbols;

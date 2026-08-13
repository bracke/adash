with AUnit.Assertions;

with Adash.Errors;
with Adash.Language.Scopes;
with Adash.Language.Symbols;
with Adash.Language.Types;
with Adash.Language.Values;

package body Adash_Tests.Language_Cases is

   use AUnit.Assertions;

   package T renames Adash.Language.Types;
   package V renames Adash.Language.Values;
   package Sym renames Adash.Language.Symbols;
   package Sc renames Adash.Language.Scopes;

   use type Adash.Errors.Error_Code;
   use type T.Type_Kind;
   use type V.Ordering;
   use type Sym.Symbol_Kind;
   use type T.Type_Shape;

   ------------------------------------------------------------------
   --  Types
   ------------------------------------------------------------------

   procedure Types_Are_Adas_Types_Under_Adas_Names
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Assert (T.Name (T.Type_Integer) = "Integer", "Integer is not called Integer");
      Assert (T.Name (T.Type_Boolean) = "Boolean", "Boolean is not called Boolean");
      Assert (T.Name (T.Type_String) = "String", "String is not called String");

      --  Type_None cannot be written down. That is what makes it safe as "no
      --  value": no source can produce one by accident.
      Assert (T.Name (T.Type_None) = "", "Type_None has a spelling");
      Assert (not T.Has_Literals (T.Type_None), "Type_None has literals");

      --  Ada orders Boolean, False < True. Saying so in one place keeps the
      --  evaluator from deciding differently.
      Assert (T.Is_Ordered (T.Type_Boolean), "Boolean is not ordered");
      Assert (not T.Is_Ordered (T.Type_None), "Type_None is ordered");

      Assert (T.Is_Numeric (T.Type_Integer) and then T.Is_Numeric (T.Type_Float),
              "a numeric type is not numeric");
      Assert (not T.Is_Numeric (T.Type_Character),
              "Character is numeric; it is not a small integer here");
   end Types_Are_Adas_Types_Under_Adas_Names;

   procedure A_Declared_Type_Is_Its_Own_Type
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  Two enumerations that look alike. The identity is what a declaration
      --  gives them, and it is the whole of what tells them apart.
      Colour : constant T.Type_Kind := T.Enumeration (11, "Colour", 3);
      Mood   : constant T.Type_Kind := T.Enumeration (42, "Mood", 3);
      Again  : constant T.Type_Kind := T.Enumeration (11, "Colour", 3);
   begin
      Assert (T.Name (Colour) = "Colour", "a declared type lost its name");
      Assert (T.Shape (Colour) = T.Shape_Enumeration,
              "an enumeration is not shaped like one");
      Assert (T.Is_Discrete (Colour), "an enumeration is not discrete");
      Assert (T.Is_Ordered (Colour), "an enumeration is not ordered");
      Assert (T.Value_Count (Colour) = 3, "an enumeration lost its count");
      Assert (not T.Has_Literals (Colour),
              "an enumeration has literals; its values are names");

      --  Ada's rule, and the reason a declaration carries an identity rather
      --  than being compared by its literals.
      Assert (not T.Is_Acceptable (Mood, Colour),
              "two enumerations with the same shape were called one type");
      Assert (T.Is_Acceptable (Again, Colour),
              "one declaration was called two types");

      --  Nothing converts into one. `Colour'Value` is how a program reads one
      --  back, and that is written down where a conversion would be silent.
      Assert (T.Is_Convertible (Colour, T.Type_String),
              "an enumeration does not convert to text");
      Assert (not T.Is_Convertible (T.Type_String, Colour),
              "text converts silently into an enumeration");
      Assert (not T.Is_Convertible (Colour, T.Type_Integer),
              "an enumeration converts silently into a number");
   end A_Declared_Type_Is_Its_Own_Type;

   procedure A_Composite_Is_Its_Parts_End_To_End
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Line : constant T.Type_Kind := T.Composite_Record (7, "Line", 2);
      Grid : constant T.Type_Kind := T.Composite_Array (9, "Grid", 4);
   begin
      Assert (T.Shape (Line) = T.Shape_Record, "a record is not one");
      Assert (T.Shape (Grid) = T.Shape_Array, "an array is not one");
      Assert (T.Is_Composite (Line) and then T.Is_Composite (Grid),
              "a composite is not composite");
      Assert (not T.Is_Composite (T.Type_Integer),
              "a built-in type is composite");

      --  The width is the whole of what the type carries about its shape.
      --  What it is made of lives beside the identity, in the analysis, and
      --  the reason is that a type is copied on every scope lookup.
      Assert (T.Width (Line) = 2, "a record lost its width");
      Assert (T.Width (Grid) = 4, "an array lost its width");
      Assert (T.Width (T.Type_Integer) = 1,
              "a value that fits in a cell takes more than one slot");

      Assert (T.Name (Line) = "Line", "a record lost its name");
      Assert (not (Line = Grid), "two declarations were called one type");
      Assert (Line = T.Composite_Record (7, "Line", 2),
              "one declaration was called two types");

      --  Neither is ordered. Ada orders an array of a discrete type and does
      --  not order a record; an ordering over a run of slots needs a rule per
      --  shape, and a shell script compares values rather than sorting
      --  structures.
      Assert (not T.Is_Ordered (Line) and then not T.Is_Ordered (Grid),
              "a composite claims an ordering");
      Assert (not T.Is_Discrete (Line), "a record is discrete");
      Assert (not T.Has_Literals (Grid),
              "an aggregate was called a literal; it holds expressions");
      Assert (not T.Is_Convertible (Line, T.Type_Integer),
              "a record converts to a number");
   end A_Composite_Is_Its_Parts_End_To_End;

   procedure A_Subtype_Is_The_Type_It_Names
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Percent : constant T.Type_Kind :=
        T.Constrained (T.Type_Integer, "Percent", 0, 100);

      Colour : constant T.Type_Kind := T.Enumeration (11, "Colour", 4);
      Warm   : constant T.Type_Kind := T.Constrained (Colour, "Warm", 0, 1);
   begin
      --  A subtype is the same type as what it names. Every question of the
      --  form "is this an Integer?" means that one, and there are dozens of
      --  them: a `=` comparing bounds would answer no to all of them and a
      --  subtype would stop being usable anywhere its base is.
      Assert (Percent = T.Type_Integer, "a subtype is not its base type");
      Assert (T.Is_Acceptable (Percent, T.Type_Integer),
              "a subtype is not acceptable where its base is wanted");
      Assert (T.Is_Acceptable (T.Type_Integer, Percent),
              "a base type is not acceptable where its subtype is wanted");
      Assert (Warm = Colour, "a subtype of an enumeration is not that type");
      Assert (not (Warm = Percent), "two unrelated subtypes are one type");

      --  What it does carry is a name of its own and what it admits, which is
      --  what the check the lowering emits is made from.
      Assert (T.Name (Percent) = "Percent", "a subtype lost its name");
      Assert (T.Has_Bounds (Percent), "a subtype has no bounds");
      Assert (T.Low_Bound (Percent) = 0 and then T.High_Bound (Percent) = 100,
              "a subtype lost its bounds");
      Assert (not T.Has_Bounds (T.Type_Integer),
              "a built-in type came with bounds");
      Assert (T.Value_Count (Warm) = 4,
              "a subtype forgot how many values its type has");
   end A_Subtype_Is_The_Type_It_Names;

   procedure There_Is_No_Implicit_Conversion
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Assert (T.Is_Acceptable (T.Type_Integer, T.Type_Integer),
              "a type is not acceptable as itself");

      --  The decision this test exists to lock. A language that quietly turns
      --  an Integer into a Float has a rounding rule nobody wrote down, and the
      --  first time it matters is in someone's arithmetic.
      Assert (not T.Is_Acceptable (T.Type_Integer, T.Type_Float),
              "an Integer was accepted where a Float was expected");
      Assert (not T.Is_Acceptable (T.Type_Float, T.Type_Integer),
              "a Float was accepted where an Integer was expected");
      Assert (not T.Is_Acceptable (T.Type_Character, T.Type_String),
              "a Character was accepted where a String was expected");
      Assert (not T.Is_Acceptable (T.Type_Boolean, T.Type_Integer),
              "a Boolean was accepted where an Integer was expected");

      --  Nothing is acceptable where no value belongs, including no value.
      Assert (not T.Is_Acceptable (T.Type_None, T.Type_None),
              "Type_None is acceptable as itself");

      --  Explicit conversion is a different question, and does exist.
      Assert (T.Is_Convertible (T.Type_Integer, T.Type_Float),
              "Integer does not convert to Float");
      Assert (T.Is_Convertible (T.Type_Integer, T.Type_String),
              "Integer does not convert to String");
      Assert (not T.Is_Convertible (T.Type_None, T.Type_String),
              "Type_None converts to String");
   end There_Is_No_Implicit_Conversion;

   ------------------------------------------------------------------
   --  Values
   ------------------------------------------------------------------

   procedure Values_Know_Their_Own_Type
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Number : constant V.Value := V.To_Value (42);
      Text   : constant V.Value := V.To_Value ("42");
      Got_I  : Integer;
      Got_B  : Boolean;
   begin
      Assert (V.Kind (Number) = T.Type_Integer, "an Integer value is not one");
      Assert (V.Kind (Text) = T.Type_String, "a String value is not one");
      Assert (V.Is_None (V.None), "None is not none");
      Assert (not V.Is_None (Number), "a real value reports itself as none");

      Assert (V.Get (Number, Got_I) and then Got_I = 42,
              "an Integer did not round-trip");

      --  A typed read refuses the wrong type rather than converting. This is
      --  what stops an Integer being read out of a String by accident.
      Assert (not V.Get (Text, Got_I),
              "an Integer was read out of a String; got"
              & Integer'Image (Got_I));
      declare
         Read_A_Boolean : constant Boolean := V.Get (Number, Got_B);
         Detail         : constant String := Boolean'Image (Got_B);
      begin
         Assert (not Read_A_Boolean,
                 "a Boolean was read out of an Integer; got " & Detail);
      end;

      --  Text refuses every non-String, because Text and Image are different
      --  questions and answering one with the other is how an Integer ends up
      --  compared against the text of another Integer.
      Assert (V.Text (Text) = "42", "a String did not round-trip");
      Assert (V.Text (Number) = "", "Text answered for a non-String");
   end Values_Know_Their_Own_Type;

   procedure Equality_Across_Types_Is_False_Not_An_Error
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Number : constant V.Value := V.To_Value (1);
      Text   : constant V.Value := V.To_Value ("1");
      Result : V.Ordering;
      Error  : Adash.Errors.Error_Info;
   begin
      Assert (V.Equal (Number, V.To_Value (1)), "equal Integers are not equal");
      Assert (not V.Equal (Number, V.To_Value (2)),
              "different Integers are equal");

      --  `1 = "1"` is False rather than a refusal: a user asking the question
      --  deserves an answer, and Ada's rule for distinct types is that they
      --  are simply not equal.
      Assert (not V.Equal (Number, Text),
              "an Integer compared equal to a String");

      --  Ordering across types is different: there is no reason an Integer
      --  should sort before or after a String, and inventing one would produce
      --  a total order every sort would silently depend on.
      Assert (not V.Compare (Number, Text, Result, Error),
              "an Integer was ordered against a String");
      Assert (Error.Code = Adash.Errors.Error_Type_Mismatch,
              "ordering across types was refused for the wrong reason");

      Assert (V.Compare (V.To_Value (1), V.To_Value (2), Result, Error)
              and then Result = V.Before,
              "1 did not order before 2");

      --  Ada orders Boolean.
      Assert (V.Compare (V.To_Value (False), V.To_Value (True), Result, Error)
              and then Result = V.Before,
              "False did not order before True");

      --  Strings order by bytes, not by a locale collation: a script that sorts
      --  must produce the same order on every machine.
      Assert (V.Compare (V.To_Value ("Z"), V.To_Value ("a"), Result, Error)
              and then Result = V.Before,
              "string ordering is not by code point");
   end Equality_Across_Types_Is_False_Not_An_Error;

   procedure Images_Are_The_Languages_Own_Lexical_Form
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Ada's 'Image leads with a blank for the sign. Leaving it in makes
      --  every concatenation wrong, and this is the test that would catch it
      --  coming back.
      Assert (V.Image (V.To_Value (42)) = "42",
              "an Integer image carries Ada's leading blank: '"
              & V.Image (V.To_Value (42)) & "'");
      Assert (V.Image (V.To_Value (-7)) = "-7", "a negative Integer imaged wrongly");

      --  The language's own literals, not Ada's shouting 'Image. A script that
      --  prints a Boolean and tests for "True" must not depend on the locale,
      --  which is why this is not a catalog message.
      Assert (V.Image (V.To_Value (True)) = "True", "True did not image as True");
      Assert (V.Image (V.To_Value (False)) = "False", "False did not image as False");

      --  Unquoted: quoting is a decision for whoever displays it, and a value
      --  that quoted itself could not be concatenated.
      Assert (V.Image (V.To_Value ("hello")) = "hello", "a String imaged with quotes");
      Assert (V.Image (V.To_Value ('x')) = "x", "a Character imaged wrongly");
      Assert (V.Image (V.None) = "", "None imaged as something");
   end Images_Are_The_Languages_Own_Lexical_Form;

   procedure Conversions_Are_Explicit_And_Can_Fail
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Result : V.Value;
      Error  : Adash.Errors.Error_Info;
      Got_I  : Integer;
      Got_F  : Float;
   begin
      Assert (V.Convert (V.To_Value (42), T.Type_String, Result, Error)
              and then V.Text (Result) = "42",
              "Integer did not convert to String");

      Assert (V.Convert (V.To_Value ("42"), T.Type_Integer, Result, Error)
              and then V.Get (Result, Got_I) and then Got_I = 42,
              "String did not convert to Integer");

      Assert (V.Convert (V.To_Value (3), T.Type_Float, Result, Error)
              and then V.Get (Result, Got_F) and then Got_F = 3.0,
              "Integer did not convert to Float");

      --  A conversion from text can fail on the text itself. That is something
      --  a user wrote, so it is reported rather than raised.
      Assert (not V.Convert (V.To_Value ("abc"), T.Type_Integer, Result, Error),
              "'abc' converted to an Integer");
      Assert (Error.Code = Adash.Errors.Error_Type_Mismatch,
              "a failed conversion was reported as something else");

      --  Only the language's own two Boolean literals, case-insensitively.
      --  Accepting "1" or "yes" would force a decision about what "2" means.
      Assert (V.Convert (V.To_Value ("TRUE"), T.Type_Boolean, Result, Error),
              "'TRUE' did not convert to a Boolean");
      Assert (not V.Convert (V.To_Value ("1"), T.Type_Boolean, Result, Error),
              "'1' converted to a Boolean");
      Assert (not V.Convert (V.To_Value ("yes"), T.Type_Boolean, Result, Error),
              "'yes' converted to a Boolean");

      --  A Character is one character; taking the first of several would
      --  silently discard the rest.
      Assert (not V.Convert (V.To_Value ("ab"), T.Type_Character, Result, Error),
              "a two-character String converted to a Character");

      --  A conversion that does not exist is refused before it is attempted.
      Assert (not V.Convert (V.To_Value (True), T.Type_Integer, Result, Error),
              "a Boolean converted to an Integer");
   end Conversions_Are_Explicit_And_Can_Fail;

   ------------------------------------------------------------------
   --  Symbols
   ------------------------------------------------------------------

   procedure Names_Are_Case_Insensitive_But_Keep_Their_Spelling
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Item : constant Sym.Symbol := Sym.Make
        ("Count", Sym.Symbol_Variable, T.Type_Integer);
   begin
      --  Ada's identifiers are case-insensitive, so Adash's are. A subset of
      --  Ada that treated Count and COUNT as two names would surprise every
      --  user it had.
      Assert (Sym.Key (Item) = "count", "a name did not fold for comparison");
      Assert (Sym.Fold ("COUNT") = Sym.Key (Item), "folding is not consistent");

      --  The original spelling is kept, because that is what a diagnostic
      --  quotes back. Showing the folded form would display a name the user
      --  did not write.
      Assert (Sym.Name (Item) = "Count", "a symbol lost the user's spelling");

      Assert (Sym.Is_Assignable (Item), "a variable is not assignable");
      Assert (not Sym.Is_Callable (Item), "a variable is callable");

      declare
         Fixed : constant Sym.Symbol :=
           Sym.Make ("Limit", Sym.Symbol_Constant, T.Type_Integer);
         Call  : constant Sym.Symbol :=
           Sym.Make ("Run", Sym.Symbol_Procedure, T.Type_None);
      begin
         Assert (not Sym.Is_Assignable (Fixed), "a constant is assignable");
         Assert (Sym.Is_Callable (Call), "a procedure is not callable");
         Assert (not Sym.Is_Assignable (Call), "a procedure is assignable");
         Assert (Sym.Of_Type (Call) = T.Type_None, "a procedure has a type");
      end;

      Assert (Sym.Is_Nothing (Sym.Nothing), "Nothing denotes something");
      Assert (not Sym.Is_Assignable (Sym.Nothing), "Nothing is assignable");
   end Names_Are_Case_Insensitive_But_Keep_Their_Spelling;

   ------------------------------------------------------------------
   --  Scopes
   ------------------------------------------------------------------

   procedure A_Duplicate_In_One_Scope_Is_Refused
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chain : Sc.Chain;
      Error : Adash.Errors.Error_Info;
   begin
      Assert (Chain.Declare_Symbol
                (Sym.Make ("Total", Sym.Symbol_Variable, T.Type_Integer,
                           Extent => (First => 11, Last => 15)),
                 Error),
              "the first declaration was refused");
      Assert (Chain.Local_Count = 1, "the declaration was not recorded");

      --  Refused, not replaced. A second declaration of one name in one scope
      --  is almost always a typo, and replacing the first silently makes the
      --  program mean something nobody wrote.
      Assert (not Chain.Declare_Symbol
                (Sym.Make ("total", Sym.Symbol_Variable, T.Type_String), Error),
              "a duplicate declaration was accepted");
      Assert (Error.Code = Adash.Errors.Error_Name_Already_Declared,
              "a duplicate was refused for the wrong reason");

      --  Case-insensitively: `total` collided with `Total`.
      Assert (Chain.Local_Count = 1, "the refused declaration was recorded anyway");

      --  And the failure carries where the first one was, because "already
      --  declared" is only actionable if the user is told where.
      Assert (Adash.Errors.Arguments (Error)'Length = 2,
              "the duplicate failure did not carry the first declaration");

      --  A name the shell provides is a different refusal. Nothing declared it,
      --  so there is no line to send the reader to: reporting one meant naming
      --  a line that had nothing to do with the collision and, in a one-line
      --  submission, was the line being complained about.
      Assert (Chain.Declare_Symbol
                (Sym.Make ("Status", Sym.Symbol_Function, T.Type_Integer,
                           Provided => True),
                 Error),
              "a provided name could not be installed");

      Assert (not Chain.Declare_Symbol
                (Sym.Make ("status", Sym.Symbol_Variable, T.Type_Integer,
                           Extent => (First => 1, Last => 6)),
                 Error),
              "a name the shell provides was redeclared");
      Assert (Error.Code = Adash.Errors.Error_Name_Is_Predefined,
              "colliding with a provided name was refused for the wrong reason");
      Assert (Adash.Errors.Arguments (Error)'Length = 1,
              "the refusal carried a position for a name that has none");
   end A_Duplicate_In_One_Scope_Is_Refused;

   procedure An_Inner_Declaration_Hides_And_Then_Restores
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chain : Sc.Chain;
      Error : Adash.Errors.Error_Info;
   begin
      Assert (Chain.Declare_Symbol
                (Sym.Make ("X", Sym.Symbol_Variable, T.Type_Integer), Error),
              "the outer declaration was refused");
      Assert (Chain.Depth = 1, "a fresh chain is not one deep");

      Chain.Enter;
      Assert (Chain.Depth = 2, "entering did not deepen the chain");
      Assert (Chain.Local_Count = 0, "a new scope is not empty");

      --  The outer declaration is still visible from inside.
      Assert (Chain.Is_Visible ("x"), "an outer name is not visible inside");
      Assert (Sym.Of_Type (Chain.Lookup ("X")) = T.Type_Integer,
              "the outer symbol changed");

      --  Redeclaring in an inner scope is legal and hides the outer one -- and
      --  a table that treated this like a duplicate would reject legal Ada.
      Assert (Chain.Would_Hide ("X"), "hiding was not reported before the fact");
      Assert (Chain.Declare_Symbol
                (Sym.Make ("X", Sym.Symbol_Variable, T.Type_String), Error),
              "an inner redeclaration was refused");
      Assert (Sym.Of_Type (Chain.Lookup ("X")) = T.Type_String,
              "the inner declaration did not win");

      --  Local and chained lookup are different questions.
      Assert (not Sym.Is_Nothing (Chain.Lookup_Local ("X")),
              "the inner declaration is not local");

      Chain.Leave;

      --  The outer one is untouched and visible again.
      Assert (Chain.Depth = 1, "leaving did not shallow the chain");
      Assert (Sym.Of_Type (Chain.Lookup ("X")) = T.Type_Integer,
              "the outer declaration did not come back");
      Assert (Chain.Local_Count = 1, "leaving lost the outer declaration");
   end An_Inner_Declaration_Hides_And_Then_Restores;

   procedure An_Undeclared_Name_Is_Simply_Absent
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Chain : Sc.Chain;
   begin
      --  A fresh chain has an outermost scope, so a lookup never has to ask
      --  whether there is anywhere to look.
      Assert (not Chain.Is_Visible ("nothing_here"),
              "an empty chain found a name");
      Assert (Sym.Is_Nothing (Chain.Lookup ("nothing_here")),
              "an empty chain returned a symbol");
      Assert (Sym.Is_Nothing (Chain.Lookup_Local ("nothing_here")),
              "an empty chain returned a local symbol");
      Assert (not Chain.Would_Hide ("nothing_here"),
              "an empty chain reported hiding");

      --  Leaving the outermost scope does nothing rather than emptying the
      --  chain, so an unbalanced Leave cannot make later lookups impossible.
      Chain.Leave;
      Assert (Chain.Depth = 1, "leaving the outermost scope closed it");
   end An_Undeclared_Name_Is_Simply_Absent;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Language core");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Types_Are_Adas_Types_Under_Adas_Names'Access,
         "language : the types are Ada's types under Ada's names");
      Register_Routine
        (T, A_Declared_Type_Is_Its_Own_Type'Access,
         "language : a declared type is its own type");
      Register_Routine
        (T, A_Composite_Is_Its_Parts_End_To_End'Access,
         "language : a composite is its parts end to end");
      Register_Routine
        (T, A_Subtype_Is_The_Type_It_Names'Access,
         "language : a subtype is the type it names");
      Register_Routine
        (T, There_Is_No_Implicit_Conversion'Access,
         "language : there is no implicit conversion between types");
      Register_Routine
        (T, Values_Know_Their_Own_Type'Access,
         "language : values know their own type and refuse the wrong read");
      Register_Routine
        (T, Equality_Across_Types_Is_False_Not_An_Error'Access,
         "language : equality across types is False, ordering is refused");
      Register_Routine
        (T, Images_Are_The_Languages_Own_Lexical_Form'Access,
         "language : images are the language's own lexical form");
      Register_Routine
        (T, Conversions_Are_Explicit_And_Can_Fail'Access,
         "language : conversions are explicit and report their failures");
      Register_Routine
        (T, Names_Are_Case_Insensitive_But_Keep_Their_Spelling'Access,
         "language : names fold for comparison and keep their spelling");
      Register_Routine
        (T, A_Duplicate_In_One_Scope_Is_Refused'Access,
         "language : a duplicate in one scope is refused, with where");
      Register_Routine
        (T, An_Inner_Declaration_Hides_And_Then_Restores'Access,
         "language : an inner declaration hides an outer one, then restores it");
      Register_Routine
        (T, An_Undeclared_Name_Is_Simply_Absent'Access,
         "language : an undeclared name is absent, not an error");
   end Register_Tests;

end Adash_Tests.Language_Cases;

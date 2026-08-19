with Ada.Strings.Fixed;
with Ada.Strings.Maps.Constants;

with Adash.Messages;

package body Adash.Language.Values is

   use Ada.Strings.Unbounded;
   use type Types.Type_Kind;
   use type Types.Type_Shape;

   function Mismatch
     (Found, Expected : Types.Type_Kind) return Adash.Errors.Error_Info;
   --  The failure for an operation given the wrong type.

   function Trimmed (Item : String) return String
   is (Ada.Strings.Fixed.Trim (Item, Ada.Strings.Both));

   --------------
   -- Mismatch --
   --------------

   function Mismatch
     (Found, Expected : Types.Type_Kind) return Adash.Errors.Error_Info
   is
   begin
      return Adash.Errors.Failure
        (Adash.Errors.Error_Type_Mismatch,
         [Adash.Messages.Named ("found", Types.Name (Found)),
          Adash.Messages.Named ("expected", Types.Name (Expected))]);
   end Mismatch;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Value) return Types.Type_Kind is
   begin
      return Item.Kind;
   end Kind;

   --------------
   -- Is_None --
   --------------

   function Is_None (Item : Value) return Boolean is
   begin
      return Item.Kind = Types.Type_None;
   end Is_None;

   ----------------
   -- To_Value --
   ----------------

   function To_Value (Item : Boolean) return Value is
   begin
      return (Kind => Types.Type_Boolean, Boolean_V => Item, others => <>);
   end To_Value;

   function To_Value (Item : Integer) return Value is
   begin
      return (Kind => Types.Type_Integer, Integer_V => Item, others => <>);
   end To_Value;

   function To_Value (Item : Float) return Value is
   begin
      return (Kind => Types.Type_Float, Float_V => Item, others => <>);
   end To_Value;

   function To_Value (Item : Character) return Value is
   begin
      return (Kind => Types.Type_Character, Char_V => Item, others => <>);
   end To_Value;

   function To_Value (Item : String) return Value is
   begin
      return (Kind   => Types.Type_String,
              Text_V => To_Unbounded_String (Item),
              others => <>);
   end To_Value;

   ---------
   -- Get --
   ---------

   function Get (Item : Value; Into : out Boolean) return Boolean is
   begin
      Into := False;

      if Item.Kind /= Types.Type_Boolean then
         return False;
      end if;

      Into := Item.Boolean_V;
      return True;
   end Get;

   function Get (Item : Value; Into : out Integer) return Boolean is
   begin
      Into := 0;

      if Item.Kind /= Types.Type_Integer then
         return False;
      end if;

      Into := Item.Integer_V;
      return True;
   end Get;

   function Get (Item : Value; Into : out Float) return Boolean is
   begin
      Into := 0.0;

      if Item.Kind /= Types.Type_Float then
         return False;
      end if;

      Into := Item.Float_V;
      return True;
   end Get;

   function Get (Item : Value; Into : out Character) return Boolean is
   begin
      Into := Character'Val (0);

      if Item.Kind /= Types.Type_Character then
         return False;
      end if;

      Into := Item.Char_V;
      return True;
   end Get;

   ----------
   -- Text --
   ----------

   function Text (Item : Value) return String is
   begin
      if Item.Kind /= Types.Type_String then
         --  Refused rather than imaged. Text and Image are different questions,
         --  and answering this one with the other is how an Integer ends up
         --  compared against the text of another Integer.
         return "";
      end if;

      return To_String (Item.Text_V);
   end Text;

   -----------
   -- Equal --
   -----------

   function Equal (Left, Right : Value) return Boolean is
   begin
      --  Different types are never equal, and asking is not an error: `1 = "1"`
      --  is False rather than a refusal, because a user asking the question
      --  deserves an answer.
      if Left.Kind /= Right.Kind then
         return False;
      end if;

      case Types.Shape (Left.Kind) is
         when Types.Shape_None      => return True;
         when Types.Shape_Boolean   => return Left.Boolean_V = Right.Boolean_V;
         when Types.Shape_Integer   => return Left.Integer_V = Right.Integer_V;
         when Types.Shape_Float     => return Left.Float_V = Right.Float_V;
         when Types.Shape_Character => return Left.Char_V = Right.Char_V;
         when Types.Shape_String    => return Left.Text_V = Right.Text_V;

         when Types.Shape_Enumeration | Types.Shape_Record
            | Types.Shape_Array | Types.Shape_Task
            | Types.Shape_Protected | Types.Shape_Task_Id =>
            --  Unreachable, and unreachable by construction rather than by
            --  luck: nothing builds a Value of a declared type. This model is
            --  what the *shell* exchanges with a program -- a command's
            --  arguments and a predefined function's answer -- and every one
            --  of those is one of the five built-in types. An enumeration
            --  lives in the machine, where it is its position.
            return False;
      end case;
   end Equal;

   -------------
   -- Compare --
   -------------

   function Compare
     (Left, Right : Value;
      Result      : out Ordering;
      Error       : out Adash.Errors.Error_Info) return Boolean
   is
      function Order (Less, Equal_To : Boolean) return Ordering
      is (if Equal_To then Same elsif Less then Before else After);
   begin
      Result := Same;
      Error  := Adash.Errors.Success;

      --  Ordering across types has no answer, unlike equality. There is no
      --  reason an Integer should sort before or after a String, and inventing
      --  one -- by type name, say -- would produce a total order nobody asked
      --  for and every sort would silently depend on.
      if Left.Kind /= Right.Kind then
         Error := Mismatch (Right.Kind, Left.Kind);
         return False;
      end if;

      if not Types.Is_Ordered (Left.Kind) then
         Error := Mismatch (Left.Kind, Left.Kind);
         return False;
      end if;

      case Types.Shape (Left.Kind) is
         when Types.Shape_None | Types.Shape_Enumeration
            | Types.Shape_Record | Types.Shape_Array | Types.Shape_Task
            | Types.Shape_Protected | Types.Shape_Task_Id =>
            --  A declared type for the reason given in Equal: nothing builds
            --  one of these, so reaching here would be a defect rather than a
            --  comparison.
            Error := Mismatch (Left.Kind, Left.Kind);
            return False;

         when Types.Shape_Boolean =>
            --  Ada orders Boolean: False < True.
            Result := Order (not Left.Boolean_V and then Right.Boolean_V,
                             Left.Boolean_V = Right.Boolean_V);

         when Types.Shape_Integer =>
            Result := Order (Left.Integer_V < Right.Integer_V,
                             Left.Integer_V = Right.Integer_V);

         when Types.Shape_Float =>
            Result := Order (Left.Float_V < Right.Float_V,
                             Left.Float_V = Right.Float_V);

         when Types.Shape_Character =>
            Result := Order (Left.Char_V < Right.Char_V,
                             Left.Char_V = Right.Char_V);

         when Types.Shape_String =>
            --  Byte order, not a locale collation. A script that sorts must
            --  produce the same order on every machine, and a locale-aware
            --  comparison is exactly the thing that would not.
            Result := Order (Left.Text_V < Right.Text_V,
                             Left.Text_V = Right.Text_V);
      end case;

      return True;
   end Compare;

   -----------
   -- Image --
   -----------

   -------------
   -- Literal --
   -------------

   function Literal (Item : Value) return String is
      Rendered : constant String := Image (Item);
   begin
      case Types.Shape (Kind (Item)) is
         when Types.Shape_String =>
            declare
               Written : Ada.Strings.Unbounded.Unbounded_String;
               Quoted  : Ada.Strings.Unbounded.Unbounded_String;
               Open    : Boolean := False;

               --  Close the quoted run being built, if there is one.
               procedure Finish_Run;

               procedure Finish_Run is
               begin
                  if not Open then
                     return;
                  end if;

                  Ada.Strings.Unbounded.Append (Quoted, '"');

                  if Ada.Strings.Unbounded.Length (Written) > 0 then
                     Ada.Strings.Unbounded.Append (Written, " & ");
                  end if;

                  Ada.Strings.Unbounded.Append (Written, Quoted);
                  Quoted := Ada.Strings.Unbounded.Null_Unbounded_String;
                  Open := False;
               end Finish_Run;

            begin
               for Letter of Rendered loop
                  --  A literal cannot carry a control character: a newline
                  --  inside one ends the line, and what comes back is a
                  --  literal that was never closed. So a run of ordinary
                  --  characters is quoted and anything else is written as the
                  --  character it is -- which is how somebody writing a
                  --  newline in this language writes one.
                  --
                  --  This is not decoration. A value carried from one
                  --  submission to the next is carried as the text that
                  --  declares it, so a variable holding a line of a file used
                  --  to break every submission after it: the session went on
                  --  answering "this string literal is not closed" to
                  --  everything that followed.
                  if Character'Pos (Letter) < 32
                    or else Character'Pos (Letter) = 127
                  then
                     Finish_Run;

                     if Ada.Strings.Unbounded.Length (Written) > 0 then
                        Ada.Strings.Unbounded.Append (Written, " & ");
                     end if;

                     Ada.Strings.Unbounded.Append
                       (Written,
                        "Character'Val ("
                        & Ada.Strings.Fixed.Trim
                            (Integer'Image (Character'Pos (Letter)),
                             Ada.Strings.Both)
                        & ")");
                  else
                     if not Open then
                        Ada.Strings.Unbounded.Append (Quoted, '"');
                        Open := True;
                     end if;

                     --  Doubled, which is how every Ada string literal
                     --  carries a quotation mark.
                     if Letter = '"' then
                        Ada.Strings.Unbounded.Append (Quoted, '"');
                     end if;

                     Ada.Strings.Unbounded.Append (Quoted, Letter);
                  end if;
               end loop;

               Finish_Run;

               --  Nothing at all is the empty literal rather than nothing,
               --  which would not be an expression.
               if Ada.Strings.Unbounded.Length (Written) = 0 then
                  return """""";
               end if;

               return Ada.Strings.Unbounded.To_String (Written);
            end;

         when Types.Shape_Character =>
            return "'" & Rendered & "'";

         when others =>
            --  A number or a Boolean reads back as it writes. Integer'Image
            --  leads with a space for a non-negative value, which is not part
            --  of the literal.
            return Ada.Strings.Fixed.Trim (Rendered, Ada.Strings.Both);
      end case;
   end Literal;

   function Image (Item : Value) return String is
   begin
      case Types.Shape (Item.Kind) is
         when Types.Shape_None | Types.Shape_Enumeration
            | Types.Shape_Record | Types.Shape_Array | Types.Shape_Task
            | Types.Shape_Protected | Types.Shape_Task_Id =>
            --  A declared type for the reason given in Equal: nothing builds
            --  one of these. An enumeration's image is the machine's business,
            --  where the literal names are, and a composite has no one text.
            return "";

         when Types.Shape_Boolean =>
            --  The language's own spelling, matching Ada's literals rather than
            --  Ada's 'Image, which shouts.
            return (if Item.Boolean_V then "True" else "False");

         when Types.Shape_Integer =>
            --  Ada's 'Image leads with a blank for the sign. That blank is an
            --  artefact of the attribute, not part of the number, and leaving
            --  it in makes every concatenation wrong.
            return Trimmed (Integer'Image (Item.Integer_V));

         when Types.Shape_Float =>
            return Trimmed (Float'Image (Item.Float_V));

         when Types.Shape_Character =>
            return [1 => Item.Char_V];

         when Types.Shape_String =>
            --  Unquoted. Quoting is a decision for whoever is displaying it,
            --  and a value that quoted itself could not be concatenated.
            return To_String (Item.Text_V);
      end case;
   end Image;

   -------------
   -- Convert --
   -------------

   function Convert
     (Item   : Value;
      Into   : Types.Type_Kind;
      Result : out Value;
      Error  : out Adash.Errors.Error_Info) return Boolean
   is
      Source_Text : constant String := Trimmed (Image (Item));
   begin
      Result := None;
      Error  := Adash.Errors.Success;

      if not Types.Is_Convertible (Item.Kind, Into) then
         Error := Mismatch (Item.Kind, Into);
         return False;
      end if;

      if Item.Kind = Into then
         Result := Item;
         return True;
      end if;

      --  Every type has a text form, so this one never fails.
      if Into = Types.Type_String then
         Result := To_Value (Image (Item));
         return True;
      end if;

      case Types.Shape (Into) is
         when Types.Shape_Integer =>
            if Types.Shape (Item.Kind) = Types.Shape_Float then
               --  Ada's rounding, which is to nearest with ties away from zero.
               --  Truncation would be a second rule to remember.
               Result := To_Value (Integer (Item.Float_V));
               return True;
            end if;

            begin
               Result := To_Value (Integer'Value (Source_Text));
               return True;
            exception
               when Constraint_Error =>
                  --  Text that is not a number is something a user wrote, so it
                  --  is reported rather than raised out of here.
                  Error := Mismatch (Item.Kind, Into);
                  return False;
            end;

         when Types.Shape_Float =>
            if Types.Shape (Item.Kind) = Types.Shape_Integer then
               Result := To_Value (Float (Item.Integer_V));
               return True;
            end if;

            begin
               Result := To_Value (Float'Value (Source_Text));
               return True;
            exception
               when Constraint_Error =>
                  Error := Mismatch (Item.Kind, Into);
                  return False;
            end;

         when Types.Shape_Character =>
            if Source_Text'Length /= 1 then
               --  A Character is one character. Taking the first of several
               --  would silently discard the rest.
               Error := Mismatch (Item.Kind, Into);
               return False;
            end if;

            Result := To_Value (Source_Text (Source_Text'First));
            return True;

         when Types.Shape_Boolean =>
            --  Only the language's own two literals, and case-insensitively
            --  because Ada identifiers are. Not "1", not "yes", not "on": a
            --  shell that accepts those has to decide what "2" means.
            declare
               Folded : constant String :=
                 Ada.Strings.Fixed.Translate
                   (Source_Text, Ada.Strings.Maps.Constants.Lower_Case_Map);
            begin
               if Folded = "true" then
                  Result := To_Value (True);
                  return True;
               elsif Folded = "false" then
                  Result := To_Value (False);
                  return True;
               end if;

               Error := Mismatch (Item.Kind, Into);
               return False;
            end;

         when Types.Shape_None | Types.Shape_String
            | Types.Shape_Enumeration | Types.Shape_Record
            | Types.Shape_Array | Types.Shape_Task
            | Types.Shape_Protected | Types.Shape_Task_Id =>
            --  String is handled above, where every type's text form is. An
            --  enumeration converts to nothing here for the reason given in
            --  Equal: nothing builds one of these, and there is no conversion
            --  into one either -- `Colour'Value` is how a program reads one
            --  back, and that is written down where a conversion would be
            --  silent.
            Error := Mismatch (Item.Kind, Into);
            return False;
      end case;
   end Convert;

end Adash.Language.Values;

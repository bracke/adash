private with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Language.Types;

--  A value in the Adash language.
--
--  Every value knows its own type. There is no untyped representation, and in
--  particular nothing here is a string that other code parses back into
--  meaning: a value that is stringly typed is one whose type errors are
--  discovered by the user, at a distance, as wrong behaviour rather than as a
--  refusal.
--
--  Values are immutable. An operation produces a new value rather than changing
--  one, so a value stored in a scope, captured in a diagnostic, or held by a
--  caller cannot change underneath any of them. Assignment in the language
--  replaces what a name denotes; it does not mutate what the old value was.
--
--  Operations refuse rather than guess. Adding an Integer to a String is not an
--  error to be recovered from by converting one of them -- it is a question
--  with no answer, and the reply is a structured failure carrying both types.
--  Every operation that can fail says so in its signature; none of them raises
--  for a type mismatch, because a mismatch is something a user wrote and not a
--  defect in Adash.
--
--  Copying is by value and cheap for everything but String, which carries its
--  own storage. There is no sharing, no reference counting and no aliasing: two
--  copies of a value are independent, which is what makes them safe to hold
--  across a scope's lifetime without an ownership rule to get wrong.
package Adash.Language.Values is

   package Types renames Adash.Language.Types;

   --  A value of one of the language's types.
   type Value is private;

   --  The absence of a value: what a procedure yields, and what a failed
   --  evaluation carries.
   None : constant Value;

   --  @param Item Value to inspect.
   --  @return Its type.
   function Kind (Item : Value) return Types.Type_Kind;

   --  @param Item Value to test.
   --  @return True when Item is None.
   function Is_None (Item : Value) return Boolean;

   ---------------------------------------------------------------------------
   --  Construction. Total: every Ada value of the corresponding type maps to
   --  an Adash value, so none of these can fail.
   ---------------------------------------------------------------------------

   --  @param Item The Boolean.
   --  @return The value.
   function To_Value (Item : Boolean) return Value;

   --  @param Item The Integer.
   --  @return The value.
   function To_Value (Item : Integer) return Value;

   --  @param Item The Float.
   --  @return The value.
   function To_Value (Item : Float) return Value;

   --  @param Item The Character.
   --  @return The value.
   function To_Value (Item : Character) return Value;

   --  @param Item The String.
   --  @return The value.
   function To_Value (Item : String) return Value;

   ---------------------------------------------------------------------------
   --  Reading. Each refuses a value of the wrong type rather than converting
   --  one, so a caller cannot read an Integer out of a String by accident.
   ---------------------------------------------------------------------------

   --  @param Item Value to read.
   --  @param Into The Boolean, when this returns True.
   --  @return True when Item is a Boolean.
   function Get (Item : Value; Into : out Boolean) return Boolean;

   --  @param Item Value to read.
   --  @param Into The Integer, when this returns True.
   --  @return True when Item is an Integer.
   function Get (Item : Value; Into : out Integer) return Boolean;

   --  @param Item Value to read.
   --  @param Into The Float, when this returns True.
   --  @return True when Item is a Float.
   function Get (Item : Value; Into : out Float) return Boolean;

   --  @param Item Value to read.
   --  @param Into The Character, when this returns True.
   --  @return True when Item is a Character.
   function Get (Item : Value; Into : out Character) return Boolean;

   --  The text of a String value.
   --
   --  Refuses every other type: use Image for the canonical text of any value.
   --  The two are different questions, and conflating them is how an Integer
   --  ends up compared against the text of another Integer.
   --
   --  @param Item Value to read.
   --  @return Its text, or "" when Item is not a String.
   function Text (Item : Value) return String;

   ---------------------------------------------------------------------------
   --  Comparison
   ---------------------------------------------------------------------------

   --  Whether two values are equal.
   --
   --  Values of different types are never equal, and comparing them is not an
   --  error -- the answer is simply False. That is Ada's rule for distinct
   --  types and it is the one that does not surprise: `1 = "1"` is False rather
   --  than a refusal, because a user asking the question deserves an answer.
   --
   --  @param Left One value.
   --  @param Right The other.
   --  @return True when they are the same type and the same value.
   function Equal (Left, Right : Value) return Boolean;

   --  How two values order.
   type Ordering is (Before, Same, After);

   --  Order two values of the same type.
   --
   --  @param Left One value.
   --  @param Right The other.
   --  @param Result How they order, when this returns True.
   --  @param Error Why they cannot be ordered, when this returns False.
   --  @return True when both are the same ordered type.
   function Compare
     (Left, Right : Value;
      Result      : out Ordering;
      Error       : out Adash.Errors.Error_Info) return Boolean;

   ---------------------------------------------------------------------------
   --  Text
   ---------------------------------------------------------------------------

   --  The canonical text of any value.
   --
   --  This is the language's own lexical form, not prose for a user, which is
   --  why it does not come from a message catalog: a script that prints a
   --  Boolean and tests for "True" must not break because the shell was started
   --  in another locale. An Integer images without Ada's leading blank, because
   --  that blank is an artefact of Ada's attribute and not part of the number.
   --
   --  @param Item Value to render.
   --  @return Its canonical text. A String images as its own text, without
   --          quotes: quoting is a decision for whoever is displaying it.
   function Image (Item : Value) return String;

   --  The value written as source this language would read back.
   --
   --  Different from Image, and the difference is the point: a String images as
   --  its contents and reads back as a quoted literal with its quotes doubled,
   --  and a Character images as itself and reads back inside apostrophes.
   --  Anything that carries a value from one submission to the next has to
   --  write it as something the next one can parse.
   --
   --  @param Item Value to render.
   --  @return Source text denoting it.
   function Literal (Item : Value) return String;

   --  Convert a value to another type.
   --
   --  Explicit only: see Adash.Language.Types.Is_Convertible for which pairs
   --  exist. A conversion from String can fail on the text itself -- "abc" is
   --  not an Integer -- and that failure is reported rather than raised,
   --  because it is something a user wrote.
   --
   --  @param Item Value to convert.
   --  @param Into The target type.
   --  @param Result The converted value, when this returns True.
   --  @param Error Why it could not be converted, when this returns False.
   --  @return True when the conversion succeeded.
   function Convert
     (Item   : Value;
      Into   : Types.Type_Kind;
      Result : out Value;
      Error  : out Adash.Errors.Error_Info) return Boolean;

private

   --  One variant per type rather than a discriminated record with a String
   --  component, which would make every Value carry the maximum length. The
   --  text is unbounded and only occupied for a String.
   type Value is record
      Kind      : Types.Type_Kind := Types.Type_None;
      Boolean_V : Boolean := False;
      Integer_V : Integer := 0;
      Float_V   : Float := 0.0;
      Char_V    : Character := Character'Val (0);
      Text_V    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   None : constant Value := (others => <>);

end Adash.Language.Values;

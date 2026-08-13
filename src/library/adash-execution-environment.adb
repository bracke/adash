with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

package body Adash.Execution.Environment is

   use Ada.Strings.Unbounded;

   function Split_Name (Entry_Text : String) return String;
   --  The part of "NAME=VALUE" before the first '='.

   procedure Insert_Sorted (Item : in out Block; Name : String; Value : String);
   --  Place NAME=VALUE, replacing any existing entry of that name, keeping the
   --  vector ordered by name.

   ----------------
   -- Split_Name --
   ----------------

   function Split_Name (Entry_Text : String) return String is
   begin
      for Index in Entry_Text'Range loop
         if Entry_Text (Index) = '=' then
            return Entry_Text (Entry_Text'First .. Index - 1);
         end if;
      end loop;

      --  No '=' at all. Not a well-formed entry, but the whole string is the
      --  best available answer for what it is named, and treating it as
      --  nameless would make it impossible to Unset.
      return Entry_Text;
   end Split_Name;

   -------------------
   -- Insert_Sorted --
   -------------------

   procedure Insert_Sorted (Item : in out Block; Name : String; Value : String) is
      Composed : constant Unbounded_String :=
        To_Unbounded_String (Name & "=" & Value);
   begin
      for Index in 1 .. Natural (Item.Entries.Length) loop
         declare
            Existing : constant String := To_String (Item.Entries.Element (Index));
            Existing_Name : constant String := Split_Name (Existing);
         begin
            if Existing_Name = Name then
               Item.Entries.Replace_Element (Index, Composed);
               return;
            elsif Existing_Name > Name then
               Item.Entries.Insert (Index, Composed);
               return;
            end if;
         end;
      end loop;

      Item.Entries.Append (Composed);
   end Insert_Sorted;

   ---------------
   -- Inherited --
   ---------------

   function Inherited return Block is
      Result : Block;

      procedure Take (Name, Value : String);

      procedure Take (Name, Value : String) is
      begin
         Insert_Sorted (Result, Name, Value);
      end Take;

   begin
      --  Ada.Environment_Variables rather than hostkit. Reading this process's
      --  environment does not differ because the host differs, which is
      --  hostkit's own test for what belongs to it; what does differ -- handing
      --  an environment to a child -- is hostkit's, and is where this goes.
      Ada.Environment_Variables.Iterate (Take'Access);
      return Result;
   end Inherited;

   -----------
   -- Empty --
   -----------

   function Empty return Block is
      Result : Block;
   begin
      return Result;
   end Empty;

   ---------
   -- Set --
   ---------

   procedure Set (Item : in out Block; Name : String; Value : String) is
   begin
      if Name'Length = 0 then
         --  There is no variable with no name. An entry of "=value" is
         --  something no host can parse back, so this refuses rather than
         --  producing one.
         return;
      end if;

      Insert_Sorted (Item, Name, Value);
   end Set;

   -----------
   -- Unset --
   -----------

   procedure Unset (Item : in out Block; Name : String) is
   begin
      for Index in 1 .. Natural (Item.Entries.Length) loop
         if Split_Name (To_String (Item.Entries.Element (Index))) = Name then
            Item.Entries.Delete (Index);
            return;
         end if;
      end loop;
   end Unset;

   --------------
   -- Contains --
   --------------

   function Contains (Item : Block; Name : String) return Boolean is
   begin
      for Entry_Text of Item.Entries loop
         if Split_Name (To_String (Entry_Text)) = Name then
            return True;
         end if;
      end loop;

      return False;
   end Contains;

   -----------
   -- Value --
   -----------

   function Value (Item : Block; Name : String) return String is
   begin
      for Entry_Text of Item.Entries loop
         declare
            Text : constant String := To_String (Entry_Text);
         begin
            if Split_Name (Text) = Name then
               if Text'Length > Name'Length then
                  return Text (Text'First + Name'Length + 1 .. Text'Last);
               end if;

               return "";
            end if;
         end;
      end loop;

      return "";
   end Value;

   ------------
   -- Length --
   ------------

   function Length (Item : Block) return Natural is
   begin
      return Natural (Item.Entries.Length);
   end Length;

   ---------------
   -- To_Vector --
   ---------------

   function To_Vector (Item : Block) return Hostkit.String_Vectors.Vector is
   begin
      --  Already sorted by name: Insert_Sorted keeps it that way, so there is
      --  nothing to do here and the order a caller sees is the order a test
      --  can assert on.
      return Item.Entries;
   end To_Vector;

end Adash.Execution.Environment;

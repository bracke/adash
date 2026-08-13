package body Adash.Configuration.Migration is

   use type Tomllib.Documents.Node;
   use type Tomllib.Documents.Value_Kind;

   --  One setting that moved. Kept as data rather than as code so that adding
   --  a rename is one line in one table, and so that Rename_Count can be
   --  asserted against the schema number.
   type Rename is record
      --  The schema in which the key changed. A file older than this needs the
      --  rename applied; one at or after it already has the new spelling.
      Introduced_In : Positive;

      --  What the key used to be, and what it is now. Both dotted, as TOML
      --  writes them.
      Was : access constant String;
      Now : access constant String;
   end record;

   type Rename_Table is array (Positive range <>) of Rename;

   --  Empty, because there has been one schema. When the first setting is
   --  renamed, this gets an entry and Current_Schema goes to 2 in the same
   --  change; the test that compares the two is what makes doing only half of
   --  it fail rather than pass quietly.
   Rename_Rules : constant Rename_Table (1 .. 0) := [];

   ------------------
   -- Rename_Count --
   ------------------

   function Rename_Count return Natural is
   begin
      return Rename_Rules'Length;
   end Rename_Count;

   ----------------
   -- Schema_Of --
   ----------------

   function Schema_Of (From : in out Tomllib.Documents.Document) return Natural
   is
      Value : constant Tomllib.Documents.Node :=
        Tomllib.Documents.Value
          (From, Tomllib.Documents.Root (From), "schema");
   begin
      --  No key at all: a hand-written file, which is the common case. Treated
      --  as current, because there is nothing to bring it forward from.
      if Value = Tomllib.Documents.No_Node then
         return Current_Schema;
      end if;

      --  A schema key that is not a whole number is a mistake in a file
      --  somebody wrote by hand. Treated as current for the same reason:
      --  guessing low would migrate settings that never needed it.
      if Tomllib.Documents.Kind (From, Value)
         /= Tomllib.Documents.Integer_Value
      then
         return Current_Schema;
      end if;

      declare
         Written : constant Long_Long_Integer :=
           Tomllib.Documents.As_Integer (From, Value);
      begin
         if Written < 0 then
            return Current_Schema;
         end if;

         if Written > Long_Long_Integer (Natural'Last) then
            --  Far enough in the future that the number itself is nonsense.
            --  Reported as newer, which is the honest answer and the one that
            --  makes the caller warn rather than migrate.
            return Natural'Last;
         end if;

         return Natural (Written);
      end;
   end Schema_Of;

   -----------
   -- Apply --
   -----------

   function Apply
     (Item : in out Tomllib.Documents.Document;
      From : Natural) return Natural
   is
      Moved : Natural := 0;
   begin
      --  The table is empty in this release, so the compiler can see that this
      --  loop does not run and says so. That is a fact about there having been
      --  one schema, not a defect, and the alternative -- leaving the loop out
      --  until it is needed -- means writing it for the first time on the day
      --  a rename is already overdue.
      pragma Warnings (Off, "loop range is null*");

      for Entry_Index in Rename_Rules'Range loop
         declare
            Rule : constant Rename := Rename_Rules (Entry_Index);
         begin
            --  Only the renames the file predates. Applying one the file
            --  already has would look for a key that is no longer there, which
            --  is harmless, and would count a move that did not happen, which
            --  is not: the count decides whether the file gets rewritten.
            if From < Rule.Introduced_In then
               declare
                  Old_Value : constant Tomllib.Documents.Node :=
                    Tomllib.Documents.Find (Item, Rule.Was.all);
               begin
                  if Old_Value /= Tomllib.Documents.No_Node then
                     --  The new spelling wins if both are present. A file that
                     --  has been half-edited by hand should end up with what
                     --  its author most recently meant, and that is the
                     --  current name.
                     if Tomllib.Documents.Find (Item, Rule.Now.all)
                        = Tomllib.Documents.No_Node
                     then
                        Tomllib.Documents.Set
                          (Item, Tomllib.Documents.Root (Item),
                           Rule.Now.all, Old_Value);
                     end if;

                     if Tomllib.Documents.Remove
                          (Item, Tomllib.Documents.Root (Item), Rule.Was.all)
                     then
                        Moved := Moved + 1;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;

      pragma Warnings (On, "loop range is null*");

      return Moved;
   end Apply;

end Adash.Configuration.Migration;

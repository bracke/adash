package body Adash.Interactive.History is

   use Ada.Strings.Unbounded;

   ----------------
   -- Set_Limit --
   ----------------

   procedure Set_Limit (Item : in out Log; Limit : Positive) is
   begin
      Item.Limit := Limit;

      while Natural (Item.Lines.Length) > Item.Limit loop
         Item.Lines.Delete_First;
      end loop;
   end Set_Limit;

   -------------------
   -- Record_Line --
   -------------------

   procedure Record_Line
     (Item      : in out Log;
      Line      : String;
      Sensitive : Boolean := False)
   is
   begin
      --  Nothing at all, not even a placeholder. An entry saying a secret was
      --  here is still a record of when one was typed.
      if Sensitive then
         return;
      end if;

      --  A blank line is not an entry: recalling one gives the user nothing
      --  and pushes a real entry out of a bounded log.
      if Line'Length = 0 then
         return;
      end if;

      --  Consecutive duplicates collapse; a non-consecutive repeat is kept,
      --  because returning to something after other work is a real place in
      --  the session.
      if not Item.Lines.Is_Empty
        and then To_String (Item.Lines.Last_Element) = Line
      then
         return;
      end if;

      Item.Lines.Append (To_Unbounded_String (Line));

      while Natural (Item.Lines.Length) > Item.Limit loop
         Item.Lines.Delete_First;
      end loop;
   end Record_Line;

   ----------------------
   -- Marked_Sensitive --
   ----------------------

   function Marked_Sensitive (Line : String) return Boolean is
   begin
      --  The first character of the whole submission, not of each line in it:
      --  a submission is one entry, so it is marked or it is not, and a
      --  continuation line that happened to be indented does not decide for
      --  the construct it belongs to.
      return Line'Length > 0 and then Line (Line'First) = ' ';
   end Marked_Sensitive;

   -----------
   -- Count --
   -----------

   function Count (Item : Log) return Natural is
   begin
      return Natural (Item.Lines.Length);
   end Count;

   --------------
   -- Entry_At --
   --------------

   function Entry_At (Item : Log; Index : Positive) return String is
   begin
      if Index > Natural (Item.Lines.Length) then
         return "";
      end if;

      return To_String (Item.Lines.Element (Index));
   end Entry_At;

   -------------------
   -- Most_Recent --
   -------------------

   function Most_Recent (Item : Log) return String is
   begin
      if Item.Lines.Is_Empty then
         return "";
      end if;

      return To_String (Item.Lines.Last_Element);
   end Most_Recent;

   ------------------------
   -- Search_Backwards --
   ------------------------

   function Search_Backwards
     (Item   : Log;
      Prefix : String;
      Found  : out Entry_Text) return Boolean
   is
   begin
      Found := Null_Unbounded_String;

      --  From the newest end, which is what a user means by "the last time I
      --  did this".
      for Index in reverse 1 .. Natural (Item.Lines.Length) loop
         declare
            Line : constant String := To_String (Item.Lines.Element (Index));
         begin
            if Prefix'Length = 0
              or else (Line'Length >= Prefix'Length
                       and then Line (Line'First .. Line'First + Prefix'Length - 1)
                                = Prefix)
            then
               Found := Item.Lines.Element (Index);
               return True;
            end if;
         end;
      end loop;

      return False;
   end Search_Backwards;

   -----------------
   -- Forget_Last --
   -----------------

   procedure Forget_Last
     (Item    : in out Log;
      Count   : Natural;
      Removed : out Natural)
   is
   begin
      Removed := Natural'Min (Count, Natural (Item.Lines.Length));

      for Ignored in 1 .. Removed loop
         Item.Lines.Delete_Last;
      end loop;
   end Forget_Last;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Log) is
   begin
      Item.Lines.Clear;
   end Clear;

end Adash.Interactive.History;

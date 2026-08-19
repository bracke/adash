package body Adash.Patterns is

   function Matches (Whole : String; Pattern : String) return Boolean is
      Text_At    : Natural := Whole'First;
      Pattern_At : Natural := Pattern'First;

      --  Where to resume if what followed the star does not work out.
      Star_At    : Natural := 0;
      Resume_At  : Natural := Whole'First;

      --  Whether one character answers one class, and where the class ends.
      function Class_Holds
        (Item : Character; From : Positive; Ends : out Natural) return Boolean;

      function Class_Holds
        (Item : Character; From : Positive; Ends : out Natural) return Boolean
      is
         Cursor  : Positive := From + 1;
         Negated : Boolean := False;
         Held    : Boolean := False;
      begin
         Ends := 0;

         if Cursor <= Pattern'Last
           and then (Pattern (Cursor) = '!' or else Pattern (Cursor) = '^')
         then
            Negated := True;
            Cursor := Cursor + 1;
         end if;

         while Cursor <= Pattern'Last and then Pattern (Cursor) /= ']' loop
            if Cursor + 2 <= Pattern'Last
              and then Pattern (Cursor + 1) = '-'
              and then Pattern (Cursor + 2) /= ']'
            then
               if Item >= Pattern (Cursor) and then Item <= Pattern (Cursor + 2)
               then
                  Held := True;
               end if;

               Cursor := Cursor + 3;
            else
               if Item = Pattern (Cursor) then
                  Held := True;
               end if;

               Cursor := Cursor + 1;
            end if;
         end loop;

         --  An unclosed class is not a class. The `[` is then an ordinary
         --  character, which is what a user who typed one and meant one gets,
         --  rather than a pattern that silently matches nothing.
         if Cursor > Pattern'Last then
            return False;
         end if;

         Ends := Cursor;
         return (if Negated then not Held else Held);
      end Class_Holds;

   begin
      while Text_At <= Whole'Last loop
         if Pattern_At <= Pattern'Last and then Pattern (Pattern_At) = '*' then
            Star_At := Pattern_At;
            Pattern_At := Pattern_At + 1;
            Resume_At := Text_At;

         elsif Pattern_At <= Pattern'Last
           and then Pattern (Pattern_At) = '['
         then
            declare
               Ends : Natural;
            begin
               if Class_Holds (Whole (Text_At), Pattern_At, Ends) then
                  Pattern_At := Ends + 1;
                  Text_At := Text_At + 1;

               elsif Ends > 0 or else Pattern (Pattern_At) /= Whole (Text_At)
               then
                  --  A class that was closed and did not hold, or a `[` that
                  --  is not this character: back to the star, or no match.
                  if Star_At = 0 then
                     return False;
                  end if;

                  Pattern_At := Star_At + 1;
                  Resume_At := Resume_At + 1;
                  Text_At := Resume_At;

               else
                  --  An unclosed `[` standing for itself.
                  Pattern_At := Pattern_At + 1;
                  Text_At := Text_At + 1;
               end if;
            end;

         elsif Pattern_At <= Pattern'Last
           and then (Pattern (Pattern_At) = '?'
                     or else Pattern (Pattern_At) = Whole (Text_At))
         then
            Pattern_At := Pattern_At + 1;
            Text_At := Text_At + 1;

         elsif Star_At > 0 then
            Pattern_At := Star_At + 1;
            Resume_At := Resume_At + 1;
            Text_At := Resume_At;

         else
            return False;
         end if;
      end loop;

      --  Text exhausted: what is left of the pattern must be stars.
      while Pattern_At <= Pattern'Last
        and then Pattern (Pattern_At) = '*'
      loop
         Pattern_At := Pattern_At + 1;
      end loop;

      return Pattern_At > Pattern'Last;
   end Matches;

   function Holds_A_Pattern (Text : String) return Boolean is
   begin
      for Index in Text'Range loop
         if Text (Index) in '*' | '?' | '[' then
            return True;
         end if;
      end loop;

      return False;
   end Holds_A_Pattern;


   --------------------------
   -- Holds_A_Brace_Group --
   --------------------------

   --  Where the group that starts at From ends, or zero when it does not.
   --
   --  Counting depth, because groups nest: the closing brace of `{a,{b,c}}` is
   --  the last one, not the first one after the comma.
   function Group_Ends (Text : String; From : Positive) return Natural;

   function Group_Ends (Text : String; From : Positive) return Natural is
      Depth : Natural := 0;
   begin
      for Index in From .. Text'Last loop
         if Text (Index) = '{' then
            Depth := Depth + 1;
         elsif Text (Index) = '}' then
            Depth := Depth - 1;

            if Depth = 0 then
               return Index;
            end if;
         end if;
      end loop;

      return 0;
   end Group_Ends;

   --  Whether the body of a group says anything: a comma at its own depth, or
   --  a range. `{a}` says nothing, and stays as it was written.
   function Group_Speaks (Body_Text : String) return Boolean;

   function Group_Speaks (Body_Text : String) return Boolean is
      Depth : Natural := 0;
   begin
      for Index in Body_Text'Range loop
         if Body_Text (Index) = '{' then
            Depth := Depth + 1;
         elsif Body_Text (Index) = '}' then
            Depth := (if Depth > 0 then Depth - 1 else 0);
         elsif Body_Text (Index) = ',' and then Depth = 0 then
            return True;
         elsif Body_Text (Index) = '.' and then Depth = 0
           and then Index < Body_Text'Last
           and then Body_Text (Index + 1) = '.'
         then
            return True;
         end if;
      end loop;

      return False;
   end Group_Speaks;

   function Holds_A_Brace_Group (Text : String) return Boolean is
   begin
      for Index in Text'Range loop
         if Text (Index) = '{' then
            declare
               Ends : constant Natural := Group_Ends (Text, Index);
            begin
               if Ends > Index
                 and then Group_Speaks (Text (Index + 1 .. Ends - 1))
               then
                  return True;
               end if;
            end;
         end if;
      end loop;

      return False;
   end Holds_A_Brace_Group;

   -------------
   -- Expand --
   -------------

   --  A range, if this is one: `1..4` or `a..d`.
   --
   --  Both ends the same shape, because `{1..d}` is not a range anybody meant
   --  -- it stays text, and text is what a doubtful group is.
   function Is_A_Range
     (Body_Text : String;
      Numeric   : out Boolean;
      From      : out Integer;
      To        : out Integer) return Boolean;

   function Is_A_Range
     (Body_Text : String;
      Numeric   : out Boolean;
      From      : out Integer;
      To        : out Integer) return Boolean
   is
      Dots : Natural := 0;
   begin
      Numeric := False;
      From := 0;
      To := 0;

      for Index in Body_Text'First .. Body_Text'Last - 1 loop
         if Body_Text (Index) = '.' and then Body_Text (Index + 1) = '.' then
            Dots := Index;
            exit;
         end if;
      end loop;

      if Dots = 0 then
         return False;
      end if;

      declare
         Left  : constant String := Body_Text (Body_Text'First .. Dots - 1);
         Right : constant String := Body_Text (Dots + 2 .. Body_Text'Last);
      begin
         if Left'Length = 0 or else Right'Length = 0 then
            return False;
         end if;

         --  One letter each side counts through the alphabet.
         if Left'Length = 1 and then Right'Length = 1
           and then Left (Left'First) in 'a' .. 'z' | 'A' .. 'Z'
           and then Right (Right'First) in 'a' .. 'z' | 'A' .. 'Z'
         then
            From := Character'Pos (Left (Left'First));
            To := Character'Pos (Right (Right'First));
            return True;
         end if;

         --  Digits each side count as numbers. A sign is allowed on either,
         --  because `{-2..2}` is a range somebody writes.
         declare
            function Whole (Item : String; Value : out Integer) return Boolean;

            function Whole (Item : String; Value : out Integer) return Boolean
            is
               First  : Positive := Item'First;
               Signed : Boolean := False;
            begin
               Value := 0;

               if Item (First) in '-' | '+' then
                  Signed := Item (First) = '-';
                  First := First + 1;
               end if;

               if First > Item'Last then
                  return False;
               end if;

               for Index in First .. Item'Last loop
                  if Item (Index) not in '0' .. '9' then
                     return False;
                  end if;

                  --  Bounded well below Integer'Last: a range this library
                  --  would refuse to expand anyway does not need to be
                  --  represented exactly.
                  if Value > 100_000_000 then
                     return False;
                  end if;

                  Value := Value * 10
                    + (Character'Pos (Item (Index)) - Character'Pos ('0'));
               end loop;

               if Signed then
                  Value := -Value;
               end if;

               return True;
            end Whole;
         begin
            if Whole (Left, From) and then Whole (Right, To) then
               Numeric := True;
               return True;
            end if;
         end;
      end;

      return False;
   end Is_A_Range;

   --  The alternatives of a group body, split at the commas at its own depth.
   procedure Alternatives
     (Body_Text : String; Into : out Text_Lists.Vector);

   procedure Alternatives
     (Body_Text : String; Into : out Text_Lists.Vector)
   is
      Depth : Natural := 0;
      From  : Positive := Body_Text'First;
   begin
      Into.Clear;

      for Index in Body_Text'Range loop
         if Body_Text (Index) = '{' then
            Depth := Depth + 1;
         elsif Body_Text (Index) = '}' then
            Depth := (if Depth > 0 then Depth - 1 else 0);
         elsif Body_Text (Index) = ',' and then Depth = 0 then
            Into.Append (Body_Text (From .. Index - 1));
            From := Index + 1;
         end if;
      end loop;

      Into.Append (Body_Text (From .. Body_Text'Last));
   end Alternatives;

   procedure Expand
     (Text    : String;
      Into    : out Text_Lists.Vector;
      Refused : out Boolean)
   is
      --  Where the first group that says something starts, and where it ends.
      Opens : Natural := 0;
      Ends  : Natural := 0;
   begin
      Into.Clear;
      Refused := False;

      for Index in Text'Range loop
         if Text (Index) = '{' then
            declare
               Closes : constant Natural := Group_Ends (Text, Index);
            begin
               if Closes > Index
                 and then Group_Speaks (Text (Index + 1 .. Closes - 1))
               then
                  Opens := Index;
                  Ends := Closes;
                  exit;
               end if;
            end;
         end if;
      end loop;

      --  Nothing to do: the text stands for itself, so a caller never has to
      --  ask whether there was a group before using what comes back.
      if Opens = 0 then
         Into.Append (Text);
         return;
      end if;

      declare
         Before : constant String := Text (Text'First .. Opens - 1);
         Middle : constant String := Text (Opens + 1 .. Ends - 1);
         After  : constant String := Text (Ends + 1 .. Text'Last);

         Numeric : Boolean;
         From    : Integer;
         To      : Integer;

         Pieces : Text_Lists.Vector;

         --  Expand one alternative with what follows it, and keep the result.
         procedure Take (Alternative : String);

         procedure Take (Alternative : String) is
            Rest : Text_Lists.Vector;
            Gave : Boolean;
         begin
            if Refused then
               return;
            end if;

            --  The rest of the text is expanded with this alternative in
            --  place, which is what makes two groups multiply and a nested
            --  group work: everything after the first group is text again.
            Expand (Before & Alternative & After, Rest, Gave);

            if Gave then
               Refused := True;
               Into.Clear;
               return;
            end if;

            for Item of Rest loop
               if Natural (Into.Length) >= Maximum_Expansions then
                  Refused := True;
                  Into.Clear;
                  return;
               end if;

               Into.Append (Item);
            end loop;
         end Take;

      begin
         if Is_A_Range (Middle, Numeric, From, To) then
            --  Counting, up or down: `{4..1}` counts back, which is what every
            --  other shell does and what somebody writing it means.
            declare
               Step : constant Integer := (if To >= From then 1 else -1);
               Item : Integer := From;
            begin
               loop
                  if Numeric then
                     declare
                        Written : constant String := Integer'Image (Item);
                        Trimmed : constant String :=
                          (if Written (Written'First) = ' '
                           then Written (Written'First + 1 .. Written'Last)
                           else Written);
                     begin
                        Take (Trimmed);
                     end;
                  else
                     Take ([1 => Character'Val (Item)]);
                  end if;

                  exit when Item = To or else Refused;
                  Item := Item + Step;
               end loop;
            end;

            return;
         end if;

         Alternatives (Middle, Pieces);

         for Alternative of Pieces loop
            Take (Alternative);
            exit when Refused;
         end loop;
      end;
   end Expand;

end Adash.Patterns;

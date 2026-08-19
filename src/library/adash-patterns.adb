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

end Adash.Patterns;

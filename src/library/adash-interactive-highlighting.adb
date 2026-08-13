with Adash.Commands;
with Adash.Predefined;

package body Adash.Interactive.Highlighting is

   use type Tokens.Token_Kind;

   --------------
   -- Role_For --
   --------------

   function Role_For (Item : Tokens.Token) return Adash.Terminal.Style_Role is
   begin
      case Tokens.Kind (Item) is
         when Tokens.Token_Reserved_Word =>
            return Adash.Terminal.Role_Keyword;

         when Tokens.Token_Integer_Literal | Tokens.Token_Real_Literal
            | Tokens.Token_Character_Literal | Tokens.Token_String_Literal
            | Tokens.Token_Interpolation_Start
            | Tokens.Token_Interpolation_Chunk
            | Tokens.Token_Interpolation_End =>
            --  The literal parts of an interpolated string are literal; the
            --  expressions between them arrived as their own tokens and are
            --  coloured as whatever they are.
            return Adash.Terminal.Role_Literal;

         when Tokens.Token_Comment =>
            return Adash.Terminal.Role_Comment;

         when Tokens.Token_Error =>
            --  Bytes that are not a lexical element at all. Marked, because a
            --  user who typed one wants to see where.
            return Adash.Terminal.Role_Error;

         when Tokens.Token_Delimiter =>
            return Adash.Terminal.Role_Operator;

         when Tokens.Token_Identifier =>
            declare
               Name      : constant String := Tokens.Text (Item);
               Command   : Adash.Commands.Command_Id;
               Entity    : Adash.Predefined.Entity_Id;
            begin
               --  A name the shell knows is shown differently from one it does
               --  not. This is the one place highlighting consults something
               --  beyond the token, and it is deliberately limited to what can
               --  be answered without analysing the line: a registry lookup,
               --  not name resolution. Resolving would need a tree, and there
               --  is usually no tree while a line is being typed.
               if Adash.Commands.Find (Name, Command)
                 or else Adash.Predefined.Find (Name, Entity)
               then
                  return Adash.Terminal.Role_Known_Name;
               end if;

               return Adash.Terminal.Role_Plain;
            end;

         when Tokens.Token_End_Of_Input =>
            return Adash.Terminal.Role_Plain;
      end case;
   end Role_For;

   ------------
   -- Colour --
   ------------

   function Colour (From : Tokens.Token_Stream) return Highlight is
      Result : Highlight;
   begin
      for Index in 1 .. From.Length loop
         exit when Result.Count = Max_Spans;

         declare
            Item : constant Tokens.Token := From.Element (Index);
         begin
            --  End-of-input covers nothing, so it would be an empty span a
            --  renderer has to skip.
            if Tokens.Kind (Item) /= Tokens.Token_End_Of_Input then
               Result.Count := Result.Count + 1;
               Result.Spans (Result.Count) :=
                 (Extent => Tokens.Extent (Item), Role => Role_For (Item));
            end if;
         end;
      end loop;

      return Result;
   end Colour;

end Adash.Interactive.Highlighting;

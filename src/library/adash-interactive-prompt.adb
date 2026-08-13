with Ada.Directories;

with Adash.Configuration;

package body Adash.Interactive.Prompt is

   -----------
   -- Build --
   -----------

   function Build
     (Session     : Adash.Engine.Session;
      Kind        : Prompt_Kind := Primary;
      Last_Failed : Boolean := False) return Model
   is
      Chosen : constant Adash.Configuration.Settings :=
        Adash.Engine.Settings (Session);

      Result : Model;

      procedure Add
        (Of_Kind : Element_Kind;
         Message : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
         Role    : Adash.Terminal.Style_Role := Adash.Terminal.Role_Plain)
      is
      begin
         if Result.Count = Max_Elements then
            return;
         end if;

         Result.Count := Result.Count + 1;
         Result.Elements (Result.Count) := (Of_Kind, Message, Role);
      end Add;

   begin
      case Kind is
         when Primary =>
            --  The failure marker comes first so it is visible even on a
            --  narrow terminal where the directory is what gets truncated.
            if Last_Failed
              and then Adash.Configuration.Boolean_Value
                         (Chosen, Adash.Configuration.Prompt_Failure_Setting)
            then
               Add (Element_Status, Adash.Messages.Msg_Prompt_Failed,
                    Adash.Terminal.Role_Error);
            end if;

            if Adash.Configuration.Boolean_Value
                 (Chosen, Adash.Configuration.Prompt_Directory_Setting)
            then
               Add (Element_Directory, Role => Adash.Terminal.Role_Muted);
            end if;
            Add (Element_Message, Adash.Messages.Msg_Prompt_Primary,
                 Adash.Terminal.Role_Plain);

         when Continuation =>
            --  No directory: the line is a continuation of one already shown,
            --  and repeating the context would make the two look unrelated.
            Add (Element_Message, Adash.Messages.Msg_Prompt_Continuation,
                 Adash.Terminal.Role_Muted);
      end case;

      return Result;
   end Build;

   --------------
   -- Text_Of --
   --------------

   function Text_Of (Item : Element) return String is
   begin
      case Item.Kind is
         when Element_Message | Element_Status =>
            --  The caller's catalog renders these; the identifier is on the
            --  element.
            return "";

         when Element_Directory =>
            --  The last component only. A full path pushes the place a user
            --  types off the edge of a narrow terminal, which is the one thing
            --  a prompt must not do.
            declare
               Here : constant String := Ada.Directories.Current_Directory;
            begin
               return Ada.Directories.Simple_Name (Here);
            exception
               when others =>
                  --  A working directory that has been deleted under the
                  --  shell. Not a reason to have no prompt.
                  return "";
            end;
      end case;
   end Text_Of;

end Adash.Interactive.Prompt;

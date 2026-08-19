with Ada.Directories;
with Ada.Strings;
with Ada.Strings.Fixed;

with Adash.Configuration;
with Adash.Execution;
with Hostkit.Fs;

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
         Role    : Adash.Terminal.Style_Role := Adash.Terminal.Role_Plain;
         Text    : String := "")
      is
      begin
         if Result.Count = Max_Elements then
            return;
         end if;

         Result.Count := Result.Count + 1;
         Result.Elements (Result.Count) :=
           (Of_Kind, Message, Role, Adash.Messages.Named ("text", Text));
      end Add;

      --  What the user asked a prompt to look like, or "" for the built-in
      --  one. Read once: it is a setting, and reading it twice in one prompt
      --  would let it change halfway through.
      Format : constant String :=
        Adash.Configuration.Text_Value
          (Chosen, Adash.Configuration.Prompt_Format_Setting);

      --  Take one placeholder if it starts here, and say which.
      function Placeholder_At
        (Text : String; From : Positive; Ends : out Natural) return Element_Kind;

      function Placeholder_At
        (Text : String; From : Positive; Ends : out Natural) return Element_Kind
      is
         type Known is record
            Name : access constant String;
            Kind : Element_Kind;
         end record;

         Directory : aliased constant String := Directory_Placeholder;
         Whole     : aliased constant String := Path_Placeholder;
         Number    : aliased constant String := Status_Placeholder;
         Failed    : aliased constant String := Failed_Placeholder;

         Table : constant array (1 .. 4) of Known :=
           [(Directory'Access, Element_Directory),
            (Whole'Access, Element_Path),
            (Number'Access, Element_Status_Number),
            (Failed'Access, Element_Status)];
      begin
         Ends := 0;

         for Item of Table loop
            declare
               Name : constant String := Item.Name.all;
            begin
               if From + Name'Length - 1 <= Text'Last
                 and then Text (From .. From + Name'Length - 1) = Name
               then
                  Ends := From + Name'Length - 1;
                  return Item.Kind;
               end if;
            end;
         end loop;

         return Element_Literal;
      end Placeholder_At;

      --  Build from a user's format.
      procedure Add_The_Format;

      procedure Add_The_Format is
         Cursor : Positive := Format'First;
         Run    : Natural := Format'First;

         procedure Flush (Upto : Natural);

         procedure Flush (Upto : Natural) is
         begin
            if Upto >= Run then
               Add (Element_Literal, Text => Format (Run .. Upto));
            end if;
         end Flush;

      begin
         while Cursor <= Format'Last loop
            declare
               Ends : Natural;
               Kind : constant Element_Kind :=
                 (if Format (Cursor) = '{'
                  then Placeholder_At (Format, Cursor, Ends)
                  else Element_Literal);
            begin
               if Format (Cursor) = '{' and then Ends > 0 then
                  Flush (Cursor - 1);

                  --  A failure marker appears only when there was a failure,
                  --  so a format can carry one and stay quiet on a good day.
                  if Kind /= Element_Status or else Last_Failed then
                     Add (Kind,
                          Message =>
                            (if Kind = Element_Status
                             then Adash.Messages.Msg_Prompt_Failed
                             else Adash.Messages.Msg_Error_None),
                          Role =>
                            (case Kind is
                                when Element_Status => Adash.Terminal.Role_Error,
                                when Element_Status_Number =>
                                  (if Last_Failed then Adash.Terminal.Role_Error
                                   else Adash.Terminal.Role_Muted),
                                when others => Adash.Terminal.Role_Muted),
                          Text =>
                            (if Kind = Element_Status_Number
                             then Ada.Strings.Fixed.Trim
                                    (Integer'Image
                                       (Integer
                                          (Adash.Execution.Numeric
                                             (Adash.Engine.Last_Status
                                                (Session)))),
                                     Ada.Strings.Both)
                             else ""));
                  end if;

                  Cursor := Ends + 1;
                  Run := Cursor;
               else
                  Cursor := Cursor + 1;
               end if;
            end;
         end loop;

         Flush (Format'Last);
         Result.Joined := True;
      end Add_The_Format;

   begin
      --  A format the user wrote replaces the built-in prompt whole. Mixing
      --  the two would mean a directory that appears twice for anybody who
      --  wrote `{directory}` while the switch was still on.
      if Kind = Primary and then Format /= "" then
         Add_The_Format;
         return Result;
      end if;

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
         when Element_Literal | Element_Status_Number =>
            --  Carried on the element: a literal is what somebody typed, and
            --  a status is a number this package worked out when it built the
            --  model rather than one it can recompute here.
            return Adash.Messages.Value (Item.Text);

         when Element_Path =>
            declare
               Here : constant String := Ada.Directories.Current_Directory;
               Home : constant String := Hostkit.Fs.Home_Directory;
            begin
               --  Written the way a user would type it, now that typing it
               --  works: `~/src/adash` rather than the whole path, which on a
               --  narrow terminal is the difference between a prompt and a
               --  line that wraps before anything is typed.
               if Home /= "" and then Here'Length >= Home'Length
                 and then Here (Here'First .. Here'First + Home'Length - 1)
                          = Home
               then
                  return "~"
                    & Here (Here'First + Home'Length .. Here'Last);
               end if;

               return Here;
            exception
               when others =>
                  return "";
            end;

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

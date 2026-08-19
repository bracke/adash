with Ada.Strings.Unbounded;

with Tomllib.Documents;
with Tomllib.Errors;
with Tomllib.Parsers;
with Tomllib.Serializers;

with Adash.Configuration.Migration;
with Adash.Messages;
with Adash.Source;

package body Adash.Configuration.Files is

   use Ada.Strings.Unbounded;

   package Doc renames Tomllib.Documents;
   package Msg renames Adash.Messages;

   use type Doc.Node;
   use type Doc.Value_Kind;

   ----------
   -- Path --
   ----------

   function Path return String is
   begin
      return Adash.Persistence.Path_For
               (Adash.Persistence.Configuration_Store, File_Name);
   end Path;

   --  A number without Ada's leading blank, for a diagnostic argument.
   function Image (Value : Long_Long_Integer) return String;

   function Image (Value : Long_Long_Integer) return String is
      Text : constant String := Long_Long_Integer'Image (Value);
   begin
      return (if Text (Text'First) = ' '
              then Text (Text'First + 1 .. Text'Last) else Text);
   end Image;

   --  The words a choice setting offers, as one string for a diagnostic. Built
   --  from the same table the validation uses, so the message can never list
   --  something the setting would refuse.
   function Choice_List (Which : Setting_Id) return String;

   function Choice_List (Which : Setting_Id) return String is
      Result : Unbounded_String;
   begin
      for Index in 1 .. Choice_Count (Which) loop
         if Index > 1 then
            Append (Result, ", ");
         end if;

         Append (Result, Choice_At (Which, Index));
      end loop;

      return To_String (Result);
   end Choice_List;

   --  What a setting expects, as the message that says so.
   --
   --  A message rather than a string: `true or false` is a sentence a user
   --  reads, and this package is not the boundary that writes sentences. The
   --  values that fill it -- a range, a list of choices -- are data and travel
   --  as arguments.
   function Expected (Which : Setting_Id) return Msg.Message_Id;
   function Expected_Given (Which : Setting_Id) return Msg.Argument_List;

   function Expected (Which : Setting_Id) return Msg.Message_Id is
   begin
      case Kind (Which) is
         when Boolean_Setting => return Msg.Msg_Config_Wants_Truth;
         when Integer_Setting => return Msg.Msg_Config_Wants_Range;
         when Choice_Setting  => return Msg.Msg_Config_Wants_Choice;
         when Text_Setting    => return Msg.Msg_Config_Wants_Text;
      end case;
   end Expected;

   function Expected_Given (Which : Setting_Id) return Msg.Argument_List is
   begin
      case Kind (Which) is
         when Boolean_Setting =>
            return Msg.No_Arguments;

         when Integer_Setting =>
            return [Msg.Named ("low", Image (Minimum (Which))),
                    Msg.Named ("high", Image (Maximum (Which)))];

         when Choice_Setting =>
            return [1 => Msg.Named ("choices", Choice_List (Which))];

         when Text_Setting =>
            return [1 => Msg.Named ("limit", Image (Maximum_Text))];
      end case;
   end Expected_Given;

   ----------------
   -- Read_From --
   ----------------

   procedure Read_From
     (Text        : String;
      Origin_Name : String;
      Into        : out Settings;
      Report      : in out Adash.Diagnostics.List)
   is
      Document : Doc.Document;
      Error    : Tomllib.Errors.Error_Info;

      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_File, Origin_Name);

      procedure Complain
        (Message   : Msg.Message_Id;
         Level     : Adash.Diagnostics.Severity;
         Arguments : Msg.Argument_List;
         Quoted    : Msg.Message_Id := Msg.Msg_Error_None;
         Given     : Msg.Argument_List := Msg.No_Arguments);

      procedure Complain
        (Message   : Msg.Message_Id;
         Level     : Adash.Diagnostics.Severity;
         Arguments : Msg.Argument_List;
         Quoted    : Msg.Message_Id := Msg.Msg_Error_None;
         Given     : Msg.Argument_List := Msg.No_Arguments)
      is
      begin
         Report.Emit
           (Adash.Diagnostics.Make
              (Message   => Message,
               Level     => Level,
               Of_Kind   => Adash.Diagnostics.Category_Configuration,
               Raised_By => Adash.Diagnostics.Owner_Configuration,
               Origin    => Origin,
               Arguments => Arguments,
               Quoted    => Quoted,
               Fills     => "detail",
               Quoted_Arguments => Given));
      end Complain;

   begin
      --  Starting from the defaults rather than from nothing. Every path out of
      --  here leaves a usable set of settings, including the ones that report a
      --  problem: a shell that would not start because one line of its
      --  configuration was wrong would leave the user with no shell to fix it
      --  with.
      Into := Defaults;

      Tomllib.Parsers.Parse (Text, Document, Error);

      if Tomllib.Errors.Failed (Error) then
         Complain
           (Msg.Msg_Config_Syntax,
            Adash.Diagnostics.Severity_Error,
            [Msg.Named ("path", Origin_Name),
             Msg.Named ("line", Positive'Image (Error.At_Position.Line)),
             Msg.Named ("column", Positive'Image (Error.At_Position.Column)),
             Msg.Named ("detail", Tomllib.Errors.Identifier (Error.Code))]);
         return;
      end if;

      declare
         Schema : constant Natural := Migration.Schema_Of (Document);
      begin
         if Migration.Is_Newer (Schema) then
            --  Read as far as it can be, and say so. Refusing outright would
            --  mean a user with two versions of Adash on two machines cannot
            --  share one file, which is exactly what they will try to do.
            Complain
              (Msg.Msg_Config_Newer_Schema,
               Adash.Diagnostics.Severity_Warning,
               [Msg.Named ("path", Origin_Name),
                Msg.Named ("detail", Image (Long_Long_Integer (Schema)))]);

         elsif Migration.Needs_Migration (Schema) then
            declare
               Moved : constant Natural := Migration.Apply (Document, Schema);
            begin
               if Moved > 0 then
                  Complain
                    (Msg.Msg_Config_Migrated,
                     Adash.Diagnostics.Severity_Note,
                     [Msg.Named ("path", Origin_Name),
                      Msg.Named ("detail",
                                 Image (Long_Long_Integer (Schema)))]);
               end if;
            end;
         end if;
      end;

      --  Every key in the file, rather than every setting Adash knows. Walking
      --  the file is what makes an unknown key visible; walking the schema
      --  would silently ignore anything that is not in it.
      declare
         procedure Walk (Table : Doc.Node; Prefix : String);

         procedure Walk (Table : Doc.Node; Prefix : String) is
         begin
            for Index in 1 .. Doc.Length (Document, Table) loop
               declare
                  Name : constant String := Doc.Name (Document, Table, Index);
                  Full : constant String :=
                    (if Prefix = "" then Name else Prefix & "." & Name);
                  Item : constant Doc.Node :=
                    Doc.Element (Document, Table, Index);
                  Which : Setting_Id;
               begin
                  --  The schema key is the file's own bookkeeping, not a
                  --  setting, and reporting it as unknown would make every
                  --  migrated file complain about itself.
                  if Full = "schema" then
                     null;

                  elsif Find (Full, Which) then
                     case Kind (Which) is
                        when Boolean_Setting =>
                           if Doc.Kind (Document, Item) /= Doc.Boolean_Value
                           then
                              Complain
                                (Msg.Msg_Config_Wrong_Type,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));
                           else
                              Set_Boolean
                                (Into, Which,
                                 Doc.As_Boolean (Document, Item));
                           end if;

                        when Integer_Setting =>
                           if Doc.Kind (Document, Item) /= Doc.Integer_Value
                           then
                              Complain
                                (Msg.Msg_Config_Wrong_Type,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));

                           elsif not Set_Integer
                                       (Into, Which,
                                        Doc.As_Integer (Document, Item))
                           then
                              --  Out of range keeps the default rather than
                              --  clamping: a limit silently reduced is a
                              --  surprise the user gets much later.
                              Complain
                                (Msg.Msg_Config_Out_Of_Range,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));
                           end if;

                        when Choice_Setting =>
                           if Doc.Kind (Document, Item) /= Doc.String_Value
                           then
                              Complain
                                (Msg.Msg_Config_Wrong_Type,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));

                           elsif not Set_Choice
                                       (Into, Which,
                                        Doc.As_String (Document, Item))
                           then
                              Complain
                                (Msg.Msg_Config_Bad_Choice,
                                 Adash.Diagnostics.Severity_Error,
                                 [Msg.Named ("key", Full),
                                  Msg.Named ("detail", Choice_List (Which))]);
                           end if;

                        when Text_Setting =>
                           if Doc.Kind (Document, Item) /= Doc.String_Value
                           then
                              Complain
                                (Msg.Msg_Config_Wrong_Type,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));

                           elsif not Set_Text
                                       (Into, Which,
                                        Doc.As_String (Document, Item))
                           then
                              --  Too long, or holding something a terminal
                              --  would read as an instruction. The default
                              --  stands rather than a truncation nobody asked
                              --  for.
                              Complain
                                (Msg.Msg_Config_Out_Of_Range,
                                 Adash.Diagnostics.Severity_Error,
                                 [1 => Msg.Named ("key", Full)],
                                 Expected (Which), Expected_Given (Which));
                           end if;
                     end case;

                  elsif Doc.Kind (Document, Item) = Doc.Table_Value then
                     --  A table whose own name is not a setting is a group of
                     --  them -- [history] holding enabled and limit -- so it is
                     --  walked rather than reported. A group with nothing
                     --  recognisable in it produces one complaint per key,
                     --  which is what the author needs to see.
                     Walk (Item, Full);

                  else
                     --  A warning, not an error. See the note in the spec: a
                     --  user with two versions of Adash will share one file.
                     Complain
                       (Msg.Msg_Config_Unknown_Key,
                        Adash.Diagnostics.Severity_Warning,
                        [Msg.Named ("path", Origin_Name),
                         Msg.Named ("key", Full)]);
                  end if;
               end;
            end loop;
         end Walk;

      begin
         Walk (Doc.Root (Document), "");
      end;
   end Read_From;

   ----------
   -- Load --
   ----------

   procedure Load
     (Into   : out Settings;
      Result : out Adash.Persistence.Outcome;
      Report : in out Adash.Diagnostics.List)
   is
      Text     : Adash.Persistence.Contents;
      Location : constant String := Path;

      procedure Note (Message : Msg.Message_Id);

      procedure Note (Message : Msg.Message_Id) is
      begin
         Report.Emit
           (Adash.Diagnostics.Make
              (Message   => Message,
               Level     => Adash.Diagnostics.Severity_Warning,
               Of_Kind   => Adash.Diagnostics.Category_Configuration,
               Raised_By => Adash.Diagnostics.Owner_Configuration,
               Arguments => [1 => Msg.Named ("path", Location)]));
      end Note;

   begin
      Into := Defaults;

      Adash.Persistence.Read (Location, Text, Result);

      case Result is
         when Adash.Persistence.Store_Ok =>
            Read_From (To_String (Text), Location, Into, Report);

         when Adash.Persistence.Store_Absent
            | Adash.Persistence.Store_Unavailable =>
            --  No file, or nowhere for one to be. The ordinary case for a
            --  first run, and saying anything about it would mean every new
            --  user's first session begins with a complaint.
            null;

         when Adash.Persistence.Store_Not_Text =>
            Note (Msg.Msg_Config_Not_Text);

         when Adash.Persistence.Store_Too_Large =>
            Note (Msg.Msg_Config_Too_Large);

         when others =>
            Note (Msg.Msg_Config_Unreadable);
      end case;
   end Load;

   --------------
   -- To_Text --
   --------------

   function To_Text (Item : Settings) return String is
      Document : Doc.Document;
      Root     : constant Doc.Node := Doc.Root (Document);
   begin
      --  The schema first, so a file opened in an editor says what it is
      --  before it says anything else.
      Doc.Set (Document, Root, "schema",
               Doc.New_Integer (Document,
                                Long_Long_Integer (Migration.Current_Schema)));

      for Which in Setting_Id loop
         --  Only what the user actually changed. A file listing every default
         --  would be four times the size, would need rewriting whenever a
         --  default changed, and would bury the two lines they chose.
         if not Is_Default (Item, Which) then
            declare
               Full  : constant String := Key (Which);
               Value : Doc.Node;
            begin
               case Kind (Which) is
                  when Boolean_Setting =>
                     Value := Doc.New_Boolean
                       (Document, Boolean_Value (Item, Which));
                  when Integer_Setting =>
                     Value := Doc.New_Integer
                       (Document, Integer_Value (Item, Which));
                  when Choice_Setting =>
                     Value := Doc.New_String
                       (Document, Choice_Value (Item, Which));
                  when Text_Setting =>
                     Value := Doc.New_String
                       (Document, Text_Value (Item, Which));
               end case;

               --  Walk the dotted key, creating the tables it names. tomllib
               --  writes them back as headers, so `history.limit` comes out
               --  under a `[history]` heading rather than as a dotted line --
               --  which is what a person editing the file expects to see.
               declare
                  Walk  : Doc.Node := Root;
                  First : Natural := Full'First;
               begin
                  loop
                     declare
                        Stop : Natural := First;
                     begin
                        while Stop <= Full'Last and then Full (Stop) /= '.' loop
                           Stop := Stop + 1;
                        end loop;

                        if Stop > Full'Last then
                           Doc.Set (Document, Walk,
                                    Full (First .. Stop - 1), Value);
                           exit;
                        end if;

                        declare
                           Step : constant String := Full (First .. Stop - 1);
                           Next : Doc.Node :=
                             Doc.Value (Document, Walk, Step);
                        begin
                           if Next = Doc.No_Node then
                              Next := Doc.New_Table (Document);
                              Doc.Set (Document, Walk, Step, Next);
                           end if;

                           Walk := Next;
                        end;

                        First := Stop + 1;
                     end;
                  end loop;
               end;
            end;
         end if;
      end loop;

      return Tomllib.Serializers.To_String (Document);
   end To_Text;

   ----------
   -- Save --
   ----------

   procedure Save
     (Item   : Settings;
      Result : out Adash.Persistence.Outcome)
   is
   begin
      Adash.Persistence.Write (Path, To_Text (Item), Result);
   end Save;

end Adash.Configuration.Files;

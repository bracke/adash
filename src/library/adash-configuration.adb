with Ada.Characters.Handling;

package body Adash.Configuration is

   use Ada.Strings.Unbounded;

   ---------
   -- Key --
   ---------

   function Key (Item : Setting_Id) return String is
   begin
      --  Written out rather than derived from 'Image. A derived key would
      --  change whenever an enumeration literal was renamed, and these are in
      --  users' files: renaming one would silently ignore the setting they had
      --  chosen, with no error anywhere.
      case Item is
         when Color_Setting            => return "color";
         when History_Enabled_Setting  => return "history.enabled";
         when History_Limit_Setting    => return "history.limit";
         when Read_Limit_Setting       => return "read.limit";
         when Prompt_Directory_Setting => return "prompt.directory";
         when Prompt_Failure_Setting   => return "prompt.failure";
         when Editing_Setting          => return "editing.enabled";
         when Session_File_Setting     => return "startup.session";
         when History_Per_Session_Setting => return "history.per-session";
         when History_Ignore_Space_Setting => return "history.ignore-space";
      end case;
   end Key;

   ----------
   -- Kind --
   ----------

   function Kind (Item : Setting_Id) return Setting_Kind is
   begin
      case Item is
         when Color_Setting         => return Choice_Setting;
         when History_Limit_Setting => return Integer_Setting;
         when Read_Limit_Setting    => return Integer_Setting;
         when others                => return Boolean_Setting;
      end case;
   end Kind;

   -----------------
   -- Description --
   -----------------

   function Description (Item : Setting_Id) return Adash.Messages.Message_Id is
   begin
      case Item is
         when Color_Setting =>
            return Adash.Messages.Msg_Setting_Color;
         when History_Enabled_Setting =>
            return Adash.Messages.Msg_Setting_History_Enabled;
         when History_Limit_Setting =>
            return Adash.Messages.Msg_Setting_History_Limit;
         when Read_Limit_Setting =>
            return Adash.Messages.Msg_Setting_Read_Limit;
         when Prompt_Directory_Setting =>
            return Adash.Messages.Msg_Setting_Prompt_Directory;
         when Prompt_Failure_Setting =>
            return Adash.Messages.Msg_Setting_Prompt_Failure;
         when Editing_Setting =>
            return Adash.Messages.Msg_Setting_Editing;
         when Session_File_Setting =>
            return Adash.Messages.Msg_Setting_Session_File;
         when History_Per_Session_Setting =>
            return Adash.Messages.Msg_Setting_History_Per_Session;
         when History_Ignore_Space_Setting =>
            return Adash.Messages.Msg_Setting_History_Ignore_Space;
      end case;
   end Description;

   --  The words a choice setting offers. One table, so that validating a value
   --  and listing the possibilities cannot disagree about what they are.
   type Choice_Table is array (1 .. Max_Choices) of Unbounded_String;

   function Choices (Item : Setting_Id) return Choice_Table;

   -------------
   -- Choices --
   -------------

   function Choices (Item : Setting_Id) return Choice_Table is
   begin
      case Item is
         when Color_Setting =>
            return [To_Unbounded_String ("auto"),
                    To_Unbounded_String ("always"),
                    To_Unbounded_String ("never"),
                    Null_Unbounded_String];

         when others =>
            return [others => Null_Unbounded_String];
      end case;
   end Choices;

   ------------------
   -- Choice_Count --
   ------------------

   function Choice_Count (Item : Setting_Id) return Natural is
      Table : constant Choice_Table := Choices (Item);
      Total : Natural := 0;
   begin
      for Word of Table loop
         exit when Length (Word) = 0;
         Total := Total + 1;
      end loop;

      return Total;
   end Choice_Count;

   ---------------
   -- Choice_At --
   ---------------

   function Choice_At (Item : Setting_Id; Index : Positive) return String is
      Table : constant Choice_Table := Choices (Item);
   begin
      if Index > Max_Choices then
         return "";
      end if;

      return To_String (Table (Index));
   end Choice_At;

   -------------
   -- Minimum --
   -------------

   function Minimum (Item : Setting_Id) return Long_Long_Integer is
   begin
      case Item is
         --  Zero would mean a history that remembers nothing, which is what
         --  history.enabled is for; one is the smallest limit that means
         --  anything.
         when History_Limit_Setting => return 1;

         --  One mebibyte is already more than a configuration file or a list
         --  of names, and zero would mean a shell that cannot read at all.
         when Read_Limit_Setting    => return 1;
         when others                => return Long_Long_Integer'First;
      end case;
   end Minimum;

   -------------
   -- Maximum --
   -------------

   function Maximum (Item : Setting_Id) return Long_Long_Integer is
   begin
      case Item is
         --  A bound rather than none, because the history is held in memory
         --  for the session and a limit read out of a file should not be able
         --  to exhaust it. High enough that nobody typing at a keyboard will
         --  reach it.
         when History_Limit_Setting => return 1_000_000;

         --  Four gibibytes, which is past what a String on a 32-bit host can
         --  hold: the limit above this one is the machine's, and this stops
         --  the setting from being the thing that promises what it cannot.
         when Read_Limit_Setting    => return 4_096;
         when others                => return Long_Long_Integer'Last;
      end case;
   end Maximum;

   --------------
   -- Defaults --
   --------------

   function Defaults return Settings is
      Result : Settings;
   begin
      --  What the shell does with no configuration file at all. Every one of
      --  these is the behaviour a first-time user gets, so each is chosen to
      --  be the least surprising rather than the most featureful.
      Result.Values (Color_Setting).Text := To_Unbounded_String ("auto");
      Result.Values (History_Enabled_Setting).Flag := True;
      Result.Values (History_Limit_Setting).Whole := 1_000;

      --  Sixteen mebibytes: a hundred times the largest file a script actually
      --  reads, and small enough that a mistake is refused rather than fatal.
      Result.Values (Read_Limit_Setting).Whole := 16;
      Result.Values (Prompt_Directory_Setting).Flag := True;
      Result.Values (Prompt_Failure_Setting).Flag := True;
      Result.Values (Editing_Setting).Flag := True;
      Result.Values (Session_File_Setting).Flag := True;

      --  Off by default. One shell writing one file is what a user expects,
      --  and the merge only earns its keep when two are running at once.
      Result.Values (History_Per_Session_Setting).Flag := False;

      --  On by default. A user who types a space before a password is asking
      --  for it to be forgotten, and a protection that has to be switched on
      --  first is one that is off in the session where it was needed.
      Result.Values (History_Ignore_Space_Setting).Flag := True;

      return Result;
   end Defaults;

   -------------------
   -- Boolean_Value --
   -------------------

   function Boolean_Value (Item : Settings; Which : Setting_Id) return Boolean
   is
   begin
      return Item.Values (Which).Flag;
   end Boolean_Value;

   -------------------
   -- Integer_Value --
   -------------------

   function Integer_Value (Item : Settings; Which : Setting_Id)
                           return Long_Long_Integer
   is
   begin
      return Item.Values (Which).Whole;
   end Integer_Value;

   ------------------
   -- Choice_Value --
   ------------------

   function Choice_Value (Item : Settings; Which : Setting_Id) return String is
   begin
      return To_String (Item.Values (Which).Text);
   end Choice_Value;

   -----------------
   -- Set_Boolean --
   -----------------

   procedure Set_Boolean
     (Item : in out Settings; Which : Setting_Id; To : Boolean)
   is
   begin
      Item.Values (Which).Flag := To;
   end Set_Boolean;

   -----------------
   -- Set_Integer --
   -----------------

   function Set_Integer
     (Item : in out Settings; Which : Setting_Id; To : Long_Long_Integer)
      return Boolean
   is
   begin
      --  Refused rather than clamped. A history limit silently reduced from a
      --  million to a thousand is a surprise the user gets much later, when
      --  entries they expected are missing and nothing ever said why.
      if To < Minimum (Which) or else To > Maximum (Which) then
         return False;
      end if;

      Item.Values (Which).Whole := To;
      return True;
   end Set_Integer;

   ----------------
   -- Set_Choice --
   ----------------

   function Set_Choice
     (Item : in out Settings; Which : Setting_Id; To : String) return Boolean
   is
      Folded : constant String := Ada.Characters.Handling.To_Lower (To);
   begin
      for Index in 1 .. Choice_Count (Which) loop
         if Choice_At (Which, Index) = Folded then
            Item.Values (Which).Text := To_Unbounded_String (Folded);
            return True;
         end if;
      end loop;

      return False;
   end Set_Choice;

   ----------------
   -- Is_Default --
   ----------------

   function Is_Default (Item : Settings; Which : Setting_Id) return Boolean is
      Original : constant Settings := Defaults;
   begin
      case Kind (Which) is
         when Boolean_Setting =>
            return Item.Values (Which).Flag = Original.Values (Which).Flag;

         when Integer_Setting =>
            return Item.Values (Which).Whole = Original.Values (Which).Whole;

         when Choice_Setting =>
            return Item.Values (Which).Text = Original.Values (Which).Text;
      end case;
   end Is_Default;

   ----------
   -- Find --
   ----------

   function Find (Name : String; Which : out Setting_Id) return Boolean is
   begin
      --  Case-sensitively, because TOML keys are. A file written with History
      --  rather than history is not a file with a setting spelled oddly; it is
      --  a file with an unknown key, and saying so is what tells the author
      --  their setting is not taking effect.
      for Candidate in Setting_Id loop
         if Key (Candidate) = Name then
            Which := Candidate;
            return True;
         end if;
      end loop;

      Which := Setting_Id'First;
      return False;
   end Find;

end Adash.Configuration;

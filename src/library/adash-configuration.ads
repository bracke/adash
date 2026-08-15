private with Ada.Strings.Unbounded;

with Adash.Messages;

--  What can be configured, and what it currently is.
--
--  The schema is a closed list. Every setting is declared here with its key,
--  its type, its default and its bounds, and there is no way to hold a value
--  for a key that is not in it. That is the whole design, and it buys three
--  things:
--
--    * a configuration file can be **checked**. An unknown key is reported
--      rather than kept, so a typo is something the user is told about at
--      start-up rather than something they discover when the setting they
--      thought they had turns out never to have existed;
--    * the defaults are **in one place**, and they are what the shell does
--      when there is no file at all. A default written into the reader as well
--      as into the file is two defaults that will disagree;
--    * the settings can be **listed**, with their descriptions, because the
--      descriptions are message identifiers like every other user-visible text
--      in this project.
--
--  Every setting here is read by something. A setting nobody reads is a
--  promise to the user that nothing keeps, and this list is deliberately short
--  for that reason rather than because there is nothing more one could imagine
--  configuring.
package Adash.Configuration is

   --  Everything Adash can be told.
   type Setting_Id is
     (
      --  When ANSI styling is emitted. Read by Adash.Terminal.
      Color_Setting,

      --  Whether anything is written to the history file at all. A user who
      --  turns this off gets a session with recall and no record of it
      --  afterwards, which is what somebody working on a shared machine wants.
      History_Enabled_Setting,

      --  How many entries are kept. Read by Adash.Interactive.History.
      History_Limit_Setting,

      --  Whether the prompt names the working directory.
      Prompt_Directory_Setting,

      --  Whether the prompt marks that the last submission failed. As text,
      --  never as colour alone.
      Prompt_Failure_Setting,

      --  Whether the interactive frontend takes the terminal into raw mode and
      --  edits in place. Turning it off gives whole-line input, which is what
      --  a terminal that misbehaves, or a screen reader that prefers to see
      --  the line once, needs.
      Editing_Setting,

      --  Whether the per-session startup file runs. Read by
      --  Adash.Scripting.Startup.
      Session_File_Setting,

      --  Whether a session keeps its history in a file of its own until it
      --  ends. Two shells writing the common file a line at a time interleave
      --  their commands there; with this on, each writes its own and merges in
      --  one block when it finishes, so the shared history reads as runs rather
      --  than as fragments.
      History_Per_Session_Setting,

      --  Whether a line that begins with a space is left out of the history
      --  entirely, in memory and on disk. On by default: a user reaching for
      --  the convention the other shells have needs it to work the first time
      --  they reach for it, and the cost of the default being wrong is a
      --  recalled line missing rather than a secret kept.
      History_Ignore_Space_Setting);

   --  What sort of value a setting holds.
   type Setting_Kind is
     (
      --  True or false.
      Boolean_Setting,

      --  A whole number, between a minimum and a maximum.
      Integer_Setting,

      --  One of a fixed list of words. Not a free string: a setting whose
      --  wrong values are only discovered at the point of use is one the user
      --  finds out about later and elsewhere.
      Choice_Setting);

   --  The key a setting has in the file, dotted as TOML writes it.
   --
   --  @param Item Which setting.
   --  @return Its key, for example "history.limit".
   function Key (Item : Setting_Id) return String;

   --  @param Item Which setting.
   --  @return What sort of value it holds.
   function Kind (Item : Setting_Id) return Setting_Kind;

   --  What the setting is for, as a message identifier.
   --
   --  A message rather than a string, because it is user-visible text and no
   --  user-visible text is written into Ada source in this project.
   --
   --  @param Item Which setting.
   --  @return The identifier.
   function Description (Item : Setting_Id) return Adash.Messages.Message_Id;

   --  Largest number of words a Choice_Setting offers.
   Max_Choices : constant := 4;

   --  @param Item A Choice_Setting.
   --  @return How many words it accepts.
   function Choice_Count (Item : Setting_Id) return Natural;

   --  @param Item A Choice_Setting.
   --  @param Index Which word, from one.
   --  @return That word, or "" when Index is out of range.
   function Choice_At (Item : Setting_Id; Index : Positive) return String;

   --  @param Item An Integer_Setting.
   --  @return The smallest value it accepts.
   function Minimum (Item : Setting_Id) return Long_Long_Integer;

   --  @param Item An Integer_Setting.
   --  @return The largest value it accepts.
   function Maximum (Item : Setting_Id) return Long_Long_Integer;

   --  A complete set of values.
   --
   --  Copyable on purpose. A session holds one, a test builds one, and a
   --  caller that wants to try a change without committing to it copies. A
   --  process-wide singleton would make all three awkward and would make the
   --  tests depend on each other's order.
   type Settings is tagged private;

   --  What the shell does with no configuration file at all.
   --
   --  @return The defaults.
   function Defaults return Settings;

   --  @param Item The settings.
   --  @param Which A Boolean_Setting.
   --  @return Its value.
   function Boolean_Value (Item : Settings; Which : Setting_Id) return Boolean;

   --  @param Item The settings.
   --  @param Which An Integer_Setting.
   --  @return Its value.
   function Integer_Value (Item : Settings; Which : Setting_Id)
                           return Long_Long_Integer;

   --  @param Item The settings.
   --  @param Which A Choice_Setting.
   --  @return Its value, one of the setting's words.
   function Choice_Value (Item : Settings; Which : Setting_Id) return String;

   --  @param Item The settings.
   --  @param Which A Boolean_Setting.
   --  @param To The new value.
   procedure Set_Boolean
     (Item : in out Settings; Which : Setting_Id; To : Boolean);

   --  Set a whole number, refusing one outside the setting's bounds.
   --
   --  @param Item The settings.
   --  @param Which An Integer_Setting.
   --  @param To The new value.
   --  @return False when To is out of range, in which case nothing changed.
   --          A refusal rather than a clamp: a history limit silently reduced
   --          from a million to a thousand is a surprise the user gets much
   --          later, when entries they expected are missing.
   function Set_Integer
     (Item : in out Settings; Which : Setting_Id; To : Long_Long_Integer)
      return Boolean;

   --  Set a word, refusing one the setting does not offer.
   --
   --  @param Item The settings.
   --  @param Which A Choice_Setting.
   --  @param To The new value, compared without regard to case.
   --  @return False when To is not one of the words, in which case nothing
   --          changed.
   function Set_Choice
     (Item : in out Settings; Which : Setting_Id; To : String) return Boolean;

   --  Whether a setting still holds what it was born with.
   --
   --  What lets a file be written containing only what the user actually
   --  changed, which is the difference between a configuration file somebody
   --  can read and a dump of every default.
   --
   --  @param Item The settings.
   --  @param Which Which setting.
   --  @return True when the value equals the default.
   function Is_Default (Item : Settings; Which : Setting_Id) return Boolean;

   --  Look a setting up by its key.
   --
   --  @param Name A dotted key.
   --  @param Which The setting, when this returns True.
   --  @return False when no setting has that key.
   function Find (Name : String; Which : out Setting_Id) return Boolean;

private

   --  One value. All three fields exist in every entry and only the one
   --  matching the setting's kind means anything, which keeps Settings a
   --  definite type that can be copied and compared without a discriminant to
   --  keep in step.
   type Held is record
      Flag  : Boolean := False;
      Whole : Long_Long_Integer := 0;
      Text  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Value_Array is array (Setting_Id) of Held;

   type Settings is tagged record
      Values : Value_Array;
   end record;

end Adash.Configuration;

with Ada.Environment_Variables;

with Hostkit.Fs;
with Hostkit.Host;

with Messages.Arguments;
with Messages.Result;

package body Adash.Messages.Rendering is

   package US renames Ada.Strings.Unbounded;

   --  Named for the same reason as Catalog_Runtime in the spec: `Messages`
   --  alone means the parent package here.
   package Catalog_Arguments renames Standard.Messages.Arguments;
   package Catalog_Result renames Standard.Messages.Result;

   use type Catalog_Result.Render_Status;

   --  The locale used when nothing else answers. The catalog declares its own
   --  default too; this is the step after that one, for a catalog that failed
   --  to load and so cannot declare anything.
   Invariant_Locale : constant String := "en";

   --  Environment variables this package reads. Reading an environment
   --  variable is portable Ada and does not differ because the host differs,
   --  so it does not belong to hostkit -- unlike the locale and the
   --  executable's directory below, which do and are asked of it.
   Locale_Variable  : constant String := "ADASH_LOCALE";
   Catalog_Variable : constant String := "ADASH_MESSAGE_CATALOG";

   function Environment_Value (Name : String) return String;
   --  The value of Name, or "" when it is unset or empty.

   function Chosen_Locale (Requested : String) return String;
   --  Apply the locale precedence documented in the spec, except for the
   --  catalog's own declared default, which only the loaded catalog knows.

   -------------------------
   -- Environment_Value --
   -------------------------

   function Environment_Value (Name : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return "";
   end Environment_Value;

   -------------------
   -- Chosen_Locale --
   -------------------

   function Chosen_Locale (Requested : String) return String is
   begin
      if Requested /= "" then
         return Requested;
      end if;

      declare
         From_Environment : constant String := Environment_Value (Locale_Variable);
      begin
         if From_Environment /= "" then
            return From_Environment;
         end if;
      end;

      declare
         --  Hostkit answers from a body per operating system. The alternative
         --  -- reading LANG, or worse OSTYPE -- is the confident wrong answer
         --  hostkit exists to prevent.
         From_Host : constant String := Hostkit.Host.Native_Locale;
      begin
         if From_Host /= "" then
            return From_Host;
         end if;
      end;

      return Invariant_Locale;
   end Chosen_Locale;

   --------------------------
   -- Default_Catalog_Path --
   --------------------------

   function Default_Catalog_Path return String is
      Override : constant String := Environment_Value (Catalog_Variable);
   begin
      if Override /= "" then
         return Override;
      end if;

      declare
         --  Not argv (0): a caller chooses that, and it is empty more often
         --  than is comfortable. Hostkit asks the operating system.
         Binary_Directory : constant String := Hostkit.Fs.Own_Executable_Directory;

         --  Installed layout, as adash.gpr's Install package lays it down.
         Installed : constant String :=
           Hostkit.Fs.Join
             (Hostkit.Fs.Join
                (Hostkit.Fs.Join (Binary_Directory, ".."), "share"),
              Hostkit.Fs.Join ("adash", Hostkit.Fs.Join ("messages", "catalog.txt")));

         --  Build tree: the executable sits in bin/, resources beside it.
         In_Build_Tree : constant String :=
           Hostkit.Fs.Join
             (Hostkit.Fs.Join (Binary_Directory, ".."),
              Hostkit.Fs.Join ("resources", Hostkit.Fs.Join ("messages", "catalog.txt")));
      begin
         if Hostkit.Fs.Real_Path (Installed) /= "" then
            return Installed;
         elsif Hostkit.Fs.Real_Path (In_Build_Tree) /= "" then
            return In_Build_Tree;
         end if;

         --  Neither exists. Return the installed candidate anyway, so that the
         --  failure Open reports names a path someone can act on rather than
         --  the empty string.
         return Installed;
      end;
   end Default_Catalog_Path;

   ----------
   -- Open --
   ----------

   procedure Open
     (Item             : in out Catalog;
      Catalog_Path     : String := "";
      Requested_Locale : String := "")
   is
      Selected_Path : constant String :=
        (if Catalog_Path = "" then Default_Catalog_Path else Catalog_Path);
      Wanted : constant String := Chosen_Locale (Requested_Locale);
   begin
      Item.Path := US.To_Unbounded_String (Selected_Path);

      Catalog_Runtime.Initialize (Item.Runtime, Selected_Path);

      if not Catalog_Runtime.Is_Valid (Item.Runtime) then
         Item.Ready  := False;
         Item.Locale := US.Null_Unbounded_String;
         return;
      end if;

      Item.Ready := True;

      --  Probe one key that every catalog must carry, to find out which locale
      --  the fallback chain actually lands on. Recording the requested locale
      --  instead would report a language the user is not going to see.
      declare
         Probe : constant Catalog_Runtime.Resolve_Result :=
           Catalog_Runtime.Resolve (Item.Runtime, Wanted, Key (Msg_Application_Name));
         use type Catalog_Runtime.Resolve_Status;
      begin
         if Probe.Status = Catalog_Runtime.Found then
            Item.Locale :=
              US.To_Unbounded_String (Catalog_Runtime.Resolved_Locale (Probe));
         else
            Item.Locale := US.To_Unbounded_String (Wanted);
         end if;
      end;
   end Open;

   --------------
   -- Is_Ready --
   --------------

   function Is_Ready (Item : Catalog) return Boolean is
   begin
      return Item.Ready;
   end Is_Ready;

   ------------
   -- Locale --
   ------------

   function Locale (Item : Catalog) return String is
   begin
      return US.To_String (Item.Locale);
   end Locale;

   ----------
   -- Path --
   ----------

   function Path (Item : Catalog) return String is
   begin
      return US.To_String (Item.Path);
   end Path;

   -------------------
   -- Fallback_Text --
   -------------------

   function Fallback_Text
     (Key       : String;
      Arguments : Argument_List := No_Arguments) return String
   is
      Result : US.Unbounded_String;
   begin
      US.Append (Result, "!");
      US.Append (Result, Key);

      if Arguments'Length > 0 then
         US.Append (Result, "{");
         for Index in Arguments'Range loop
            if Index /= Arguments'First then
               US.Append (Result, ",");
            end if;
            US.Append (Result, Name (Arguments (Index)));
            US.Append (Result, "=");
            US.Append (Result, Value (Arguments (Index)));
         end loop;
         US.Append (Result, "}");
      end if;

      US.Append (Result, "!");
      return US.To_String (Result);
   end Fallback_Text;

   ----------
   -- Text --
   ----------

   function Text
     (Item      : Catalog;
      Key       : String;
      Arguments : Argument_List := No_Arguments) return String
   is
      Values : Catalog_Arguments.Arguments;
      Result : Catalog_Result.Render_Result;
   begin
      if not Item.Ready then
         return Fallback_Text (Key, Arguments);
      end if;

      for Index in Arguments'Range loop
         Catalog_Arguments.Set
           (Values,
            Name (Arguments (Index)),
            Value (Arguments (Index)));
      end loop;

      Result :=
        Catalog_Runtime.Render (Item.Runtime, US.To_String (Item.Locale), Key, Values);

      if Result.Status = Catalog_Result.Success then
         return Catalog_Result.Output_Text (Result.Text);
      end if;

      --  A key the catalog does not carry, or a message whose placeholders do
      --  not match the arguments given. Both are catalog defects that
      --  Adash_Tests.Repository is meant to catch before a release; at run
      --  time the honest fallback is better than a partial sentence.
      return Fallback_Text (Key, Arguments);
   end Text;

   ----------
   -- Text --
   ----------

   function Text
     (Item      : Catalog;
      Id        : Message_Id;
      Arguments : Argument_List := No_Arguments) return String
   is
   begin
      return Item.Text (Key (Id), Arguments);
   end Text;

   ----------
   -- Text --
   ----------

   function Text
     (Item             : Catalog;
      Id               : Message_Id;
      Arguments        : Argument_List;
      Quoted           : Message_Id;
      Fills            : String;
      Quoted_Arguments : Argument_List := No_Arguments) return String is
   begin
      if Quoted = Msg_Error_None then
         return Item.Text (Id, Arguments);
      end if;

      --  The quoted message is rendered first and passed on as an ordinary
      --  argument, so the outer message treats it as text like any other and
      --  the fallback form of either survives into the result: a catalog that
      --  cannot answer for one of them still says which one it was.
      return Item.Text
        (Id,
         Arguments
         & Argument_List'
             (1 => Named (Fills, Item.Text (Quoted, Quoted_Arguments))));
   end Text;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Catalog) is
   begin
      if Item.Ready then
         Catalog_Runtime.Finalize (Item.Runtime);
      end if;
      Item.Ready  := False;
      Item.Locale := US.Null_Unbounded_String;
   end Close;

end Adash.Messages.Rendering;

with Ada.Directories;
with Ada.Strings.Unbounded;

with Hostkit.Fs;

package body Adash.Scripting.Modules is

   use Ada.Strings.Unbounded;

   function Has_Separator (Name : String) return Boolean is
   begin
      for Index in Name'Range loop
         if Name (Index) = '/' or else Name (Index) = '\' then
            return True;
         end if;
      end loop;

      return False;
   end Has_Separator;

   function With_Extension (Name : String) return String is
   begin
      if Name'Length >= Extension'Length
        and then Name (Name'Last - Extension'Length + 1 .. Name'Last) = Extension
      then
         return Name;
      end if;

      return Name & Extension;
   end With_Extension;

   ------------------------------
   -- User_Module_Directory --
   ------------------------------

   function User_Module_Directory return String is
      Base : constant String := Hostkit.Fs.Config_Directory;
   begin
      if Base = "" then
         return "";
      end if;

      --  Under the host's own configuration directory rather than a path from
      --  the environment, which a spawned process can set to anywhere.
      return Hostkit.Fs.Join (Hostkit.Fs.Join (Base, "adash"), "modules");
   end User_Module_Directory;

   -------------
   -- Resolve --
   -------------

   function Resolve (Name : String; Loaded_From : String := "") return Resolution is
      Result : Resolution;

      function Accept_If_Present (Path : String; Where : Search_Step) return Boolean is
      begin
         if Path /= "" and then Ada.Directories.Exists (Path) then
            Result := (Found => True,
                       Path  => To_Unbounded_String (Path),
                       Where => Where);
            return True;
         end if;

         Result.Where := Where;
         return False;
      end Accept_If_Present;

   begin
      if Name = "" then
         return Result;
      end if;

      --  A path is used as written and never searched for: `./setup` runs the
      --  one here, not one that happens to be installed.
      if Has_Separator (Name) then
         if Accept_If_Present (With_Extension (Name), Step_As_Written) then
            return Result;
         end if;

         --  Also accept it exactly as written, for a file whose name carries
         --  no extension at all.
         if Accept_If_Present (Name, Step_As_Written) then
            return Result;
         end if;

         return Result;
      end if;

      --  Beside the loader first, so a set of scripts that ship together find
      --  each other without any of them knowing where they were installed.
      if Loaded_From /= "" then
         declare
            Directory : constant String :=
              Ada.Directories.Containing_Directory (Loaded_From);
         begin
            if Accept_If_Present
              (Hostkit.Fs.Join (Directory, With_Extension (Name)),
               Step_Beside_Loader)
            then
               return Result;
            end if;
         exception
            when Ada.Directories.Use_Error | Ada.Directories.Name_Error =>
               null;
         end;
      end if;

      if Accept_If_Present
        (Hostkit.Fs.Join (User_Module_Directory, With_Extension (Name)),
         Step_User_Modules)
      then
         return Result;
      end if;

      return Result;
   end Resolve;

end Adash.Scripting.Modules;

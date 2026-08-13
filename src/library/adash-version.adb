with Adash_Config;

package body Adash.Version is

   ------------
   -- Number --
   ------------

   function Number return String is
   begin
      return Adash_Config.Crate_Version;
   end Number;

   ----------------
   -- Crate_Name --
   ----------------

   function Crate_Name return String is
   begin
      return Adash_Config.Crate_Name;
   end Crate_Name;

   --------------------
   -- Is_Prerelease --
   --------------------

   function Is_Prerelease return Boolean is
      Value : constant String := Number;
   begin
      --  A semantic version is pre-release when a '-' or '+' follows the
      --  numeric core. Scanning for either character anywhere is enough:
      --  neither may appear in the major, minor or patch fields, so the first
      --  one found is always the start of the suffix.
      for Index in Value'Range loop
         if Value (Index) = '-' or else Value (Index) = '+' then
            return True;
         end if;
      end loop;
      return False;
   end Is_Prerelease;

   -------------------
   -- Build_Profile --
   -------------------

   function Build_Profile return String is
   begin
      --  Adash_Config declares the profile as an enumeration, so this is a
      --  complete case rather than an image call: adding a profile upstream
      --  then fails to compile here instead of silently producing a name in
      --  the wrong spelling.
      case Adash_Config.Build_Profile is
         when Adash_Config.release     => return "release";
         when Adash_Config.validation  => return "validation";
         when Adash_Config.development => return "development";
      end case;
   end Build_Profile;

   ---------------------------
   -- Host_Operating_System --
   ---------------------------

   function Host_Operating_System return String is
   begin
      return Adash_Config.Alire_Host_OS;
   end Host_Operating_System;

   -----------------------
   -- Host_Architecture --
   -----------------------

   function Host_Architecture return String is
   begin
      return Adash_Config.Alire_Host_Arch;
   end Host_Architecture;

end Adash.Version;

with AUnit.Assertions;

with Adash.Version;

package body Adash_Tests.Version_Cases is

   use AUnit.Assertions;

   procedure Crate_Name_Is_Adash (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Number_Is_Not_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Prerelease_Follows_The_Number (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Build_Profile_Is_Named (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Host_Fields_Are_Populated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --------------------------
   -- Crate_Name_Is_Adash --
   --------------------------

   procedure Crate_Name_Is_Adash (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Adash.Version.Crate_Name = "adash",
              "crate name is not adash: " & Adash.Version.Crate_Name);
   end Crate_Name_Is_Adash;

   ----------------------------
   -- Number_Is_Not_Empty --
   ----------------------------

   procedure Number_Is_Not_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Value : constant String := Adash.Version.Number;
   begin
      Assert (Value'Length > 0, "version number is empty");

      --  A semantic version starts with a digit. Catches the case where the
      --  manifest field is present but empty and the generated constant ends
      --  up holding something that only looks like a version.
      Assert (Value (Value'First) in '0' .. '9',
              "version number does not start with a digit: " & Value);
   end Number_Is_Not_Empty;

   ---------------------------------------
   -- Prerelease_Follows_The_Number --
   ---------------------------------------

   procedure Prerelease_Follows_The_Number (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Value : constant String := Adash.Version.Number;
      Has_Suffix : Boolean := False;
   begin
      for Index in Value'Range loop
         if Value (Index) = '-' or else Value (Index) = '+' then
            Has_Suffix := True;
            exit;
         end if;
      end loop;

      --  Asserted against the number rather than against a literal, so this
      --  keeps testing the derivation after the release that drops "-dev"
      --  instead of turning red on it.
      Assert (Adash.Version.Is_Prerelease = Has_Suffix,
              "Is_Prerelease disagrees with the version number " & Value);
   end Prerelease_Follows_The_Number;

   -------------------------------
   -- Build_Profile_Is_Named --
   -------------------------------

   procedure Build_Profile_Is_Named (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Value : constant String := Adash.Version.Build_Profile;
   begin
      Assert (Value in "release" | "validation" | "development",
              "unexpected build profile: " & Value);
   end Build_Profile_Is_Named;

   ----------------------------------
   -- Host_Fields_Are_Populated --
   ----------------------------------

   procedure Host_Fields_Are_Populated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Adash.Version.Host_Operating_System'Length > 0,
              "host operating system is empty");
      Assert (Adash.Version.Host_Architecture'Length > 0,
              "host architecture is empty");
   end Host_Fields_Are_Populated;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Version");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Crate_Name_Is_Adash'Access, "crate name is adash");
      Register_Routine (T, Number_Is_Not_Empty'Access, "version number is a version");
      Register_Routine (T, Prerelease_Follows_The_Number'Access,
                        "Is_Prerelease is derived from the number");
      Register_Routine (T, Build_Profile_Is_Named'Access, "build profile is one of three");
      Register_Routine (T, Host_Fields_Are_Populated'Access, "host fields are populated");
   end Register_Tests;

end Adash_Tests.Version_Cases;

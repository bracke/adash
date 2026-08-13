--  Product version and build identity.
--
--  The version is not written here. It is read from the constants Alire
--  generates into Adash_Config from alire.toml, so the manifest is the single
--  place it exists. A version literal repeated in an Ada source is a version
--  literal that will disagree with the manifest at some point, and the
--  disagreement surfaces in a release archive rather than in a build.
--
--  Release tooling checks that agreement rather than assuming it; see
--  Adash_Tests.Repository.
package Adash.Version is

   --  The crate version exactly as alire.toml spells it, including any
   --  pre-release suffix such as "-dev".
   --
   --  @return Version string, for example "0.1.0-dev".
   function Number return String;

   --  The crate name, as Alire knows it.
   --
   --  @return Crate name, "adash".
   function Crate_Name return String;

   --  Whether this build came from a pre-release version -- one whose version
   --  carries a suffix after the patch number.
   --
   --  Callers use it to decide whether to say so in diagnostics and bug
   --  reports. It is derived from Number rather than set by hand, because a
   --  flag set by hand is one that stays True after the release.
   --
   --  @return True when Number carries a pre-release or build suffix.
   function Is_Prerelease return Boolean;

   --  Which build profile produced this binary: "release", "validation" or
   --  "development".
   --
   --  Worth reporting in a bug report. A development build runs at -Og with
   --  assertions enabled, so a timing or an optimizer-sensitive symptom means
   --  something different depending on which one is in the user's hands.
   --
   --  @return Build profile name.
   function Build_Profile return String;

   --  The host this binary was built for, as Alire classified it: "linux",
   --  "macos", "windows" or another value Alire recognises.
   --
   --  This is the build host, not the running host. Hostkit answers the
   --  running one, from a body per operating system that no environment can
   --  spoof; ask it, not this, when behaviour has to differ.
   --
   --  @return Host operating system name.
   function Host_Operating_System return String;

   --  The architecture this binary was built for, for example "x86_64".
   --
   --  @return Host architecture name.
   function Host_Architecture return String;

end Adash.Version;

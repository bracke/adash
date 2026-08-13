--  Turning what a user wrote into a file.
--
--  A script names another script by a path or by a bare name, and the two are
--  resolved differently on purpose:
--
--  A name containing a path separator is a path. It is used as written,
--  relative to the working directory, and is never searched for. `./setup` runs
--  the one here, not one that happens to be installed.
--
--  A bare name is searched for, in a fixed order a user can predict: beside the
--  script doing the loading first, then the user's own module directory. Beside
--  first because a set of scripts that ship together should find each other
--  without any of them knowing where they were installed.
--
--  There is no search path from the environment. A module resolution that a
--  spawned process can change is one where a script means different things on
--  different machines, and the failure is silent -- the wrong file loads and
--  runs.
package Adash.Scripting.Modules is

   --  The conventional extension for an Adash script.
   Extension : constant String := ".adash";

   --  Where a resolution looked, in the order it looked.
   type Search_Step is
     (
      --  The name was a path; nothing was searched.
      Step_As_Written,

      --  Beside the script that is loading it.
      Step_Beside_Loader,

      --  The user's module directory, from hostkit.
      Step_User_Modules);

   --  What a resolution found.
   type Resolution is record
      Found : Boolean := False;

      --  The resolved path, meaningful only when Found.
      Path : Adash.Scripting.Module_Path;

      --  Where it was found, or the last place looked when it was not.
      Where : Search_Step := Step_As_Written;
   end record;

   --  Find the file a name denotes.
   --
   --  The extension is added when the name does not already carry it, so a
   --  script may say `setup` or `setup.adash` and mean the same file.
   --
   --  @param Name The name as written.
   --  @param Loaded_From The path of the script doing the loading, or "" at
   --         the top level, where there is nothing to be beside.
   --  @return Where it is.
   function Resolve (Name : String; Loaded_From : String := "") return Resolution;

   --  The directory a user's own modules live in.
   --
   --  From hostkit, which knows where a host keeps such things. Never from an
   --  environment variable, which a spawned process can set.
   --
   --  @return The directory, or "" when the host cannot say.
   function User_Module_Directory return String;

end Adash.Scripting.Modules;

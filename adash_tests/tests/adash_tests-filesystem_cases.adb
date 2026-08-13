with Ada.Directories;
with Ada.Text_IO;

with AUnit.Assertions;

with Adash.Filesystem;

package body Adash_Tests.Filesystem_Cases is

   use AUnit.Assertions;

   package F renames Adash.Filesystem;

   use type F.Written;

   --  A file that is there for the length of one test, and gone after it.
   function Write (Name : String) return String;

   function Write (Name : String) return String is
      Path : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory, Name);
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "something");
      Ada.Text_IO.Close (File);
      return Path;
   end Write;

   procedure A_Path_Is_Asked_About_Rather_Than_Opened
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Path_Nobody_Can_Reach_Is_Answered
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Writing_Replaces_And_Appending_Adds
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Write_With_Nowhere_To_Go_Is_Refused
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   --  What a file holds, read back byte for byte.
   function Held (Path : String) return String;

   function Held (Path : String) return String is
      File : Ada.Text_IO.File_Type;
      Text : String (1 .. 1_024);
      Last : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (File) and then Last < Text'Last loop
         Ada.Text_IO.Get (File, Text (Last + 1));
         Last := Last + 1;
      end loop;

      Ada.Text_IO.Close (File);
      return Text (1 .. Last);
   end Held;

   procedure A_Path_Is_Asked_About_Rather_Than_Opened
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Path : constant String := Write ("adash-test-path");
   begin
      Assert (F.Exists (Path), "a file that is there was not found");
      Assert (not F.Is_Directory (Path), "a file was called a directory");

      --  A directory is something, and is not a file. Both questions are asked
      --  because acting on a directory as though it were a file is the mistake
      --  the second one exists to prevent.
      Assert (F.Exists (Ada.Directories.Current_Directory),
              "a directory was not found");
      Assert (F.Is_Directory (Ada.Directories.Current_Directory),
              "a directory was not called one");

      Ada.Directories.Delete_File (Path);

      Assert (not F.Exists (Path), "a file that is gone was still found");
   end A_Path_Is_Asked_About_Rather_Than_Opened;

   procedure A_Path_Nobody_Can_Reach_Is_Answered
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  Not a failure. A predicate that could fail would need a second
      --  question beside every use, and the useful answer is the same either
      --  way: it is not a file.
      Assert (not F.Exists (""), "the empty path was called a file");
      Assert (not F.Is_Directory (""), "the empty path was called a directory");
      Assert (not F.Is_Executable (""),
              "the empty path was called something to run");

      Assert (not F.Exists ("/adash-no-such-directory/and/deeper"),
              "a path under nothing was found");
      Assert (not F.Is_Directory ("/adash-no-such-directory/and/deeper"),
              "a path under nothing was called a directory");
      Assert (not F.Is_Executable ("/adash-no-such-directory/and/deeper"),
              "a path under nothing was called runnable");
   end A_Path_Nobody_Can_Reach_Is_Answered;

   procedure Writing_Replaces_And_Appending_Adds
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Path : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-written");
      Done : F.Written;
   begin
      --  A file that is not there yet is made rather than refused: a script
      --  that writes its first result should not have to make the file first.
      F.Write (Path, "alpha", Done);
      Assert (Done = F.Write_Ok, "a first write was not accepted");
      Assert (Held (Path) = "alpha", "the file did not hold what was written");

      --  Replaced, not added to. The two commands differ in exactly this, and
      --  a `Write` that appended would make the difference invisible.
      F.Write (Path, "b", Done);
      Assert (Done = F.Write_Ok, "a second write was not accepted");
      Assert (Held (Path) = "b", "writing did not replace what was there");

      F.Append (Path, "cd", Done);
      Assert (Done = F.Write_Ok, "an append was not accepted");
      Assert (Held (Path) = "bcd", "appending did not add to the end");

      Ada.Directories.Delete_File (Path);

      --  Appending to a file that is not there makes it. The first turn of a
      --  loop that collects lines is not an error.
      F.Append (Path, "fresh", Done);
      Assert (Done = F.Write_Ok, "an append to nothing was not accepted");
      Assert (Held (Path) = "fresh", "an append to nothing lost the text");

      Ada.Directories.Delete_File (Path);
   end Writing_Replaces_And_Appending_Adds;

   procedure A_Write_With_Nowhere_To_Go_Is_Refused
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Done : F.Written;
   begin
      F.Write ("", "x", Done);
      Assert (Done = F.Write_Refused, "the empty path was written to");

      F.Write ("/adash-no-such-directory/and/deeper", "x", Done);
      Assert (Done = F.Write_Refused, "a path under nothing was written to");

      --  A directory is refused before anything is opened. What a host does
      --  when asked to open one for writing is not the same everywhere, and a
      --  shell should not report whichever answer it happened to get.
      F.Write (Ada.Directories.Current_Directory, "x", Done);
      Assert (Done = F.Write_Refused, "a directory was written over");

      F.Append (Ada.Directories.Current_Directory, "x", Done);
      Assert (Done = F.Write_Refused, "a directory was appended to");
   end A_Write_With_Nowhere_To_Go_Is_Refused;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Filesystem");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Path_Is_Asked_About_Rather_Than_Opened'Access,
         "filesystem : a path is asked about rather than opened");
      Register_Routine
        (T, A_Path_Nobody_Can_Reach_Is_Answered'Access,
         "filesystem : a path nobody can reach is answered, not raised");
      Register_Routine
        (T, Writing_Replaces_And_Appending_Adds'Access,
         "filesystem : writing replaces and appending adds");
      Register_Routine
        (T, A_Write_With_Nowhere_To_Go_Is_Refused'Access,
         "filesystem : a write with nowhere to go is refused");
   end Register_Tests;

end Adash_Tests.Filesystem_Cases;

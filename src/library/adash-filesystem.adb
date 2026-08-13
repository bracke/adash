with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.IO_Exceptions;

with Hostkit.Fs;

package body Adash.Filesystem is

   use type Ada.Directories.File_Kind;

   ------------
   -- Exists --
   ------------

   function Exists (Path : String) return Boolean is
   begin
      if Path = "" then
         return False;
      end if;

      return Ada.Directories.Exists (Path);

   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         --  A path this host will not even look at -- a name it cannot form,
         --  a directory it may not read. Not there, as far as anybody asking
         --  can tell.
         return False;
   end Exists;

   ------------------
   -- Is_Directory --
   ------------------

   function Is_Directory (Path : String) return Boolean is
   begin
      if Path = "" then
         return False;
      end if;

      return Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Directory;

   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         return False;
   end Is_Directory;

   -------------------
   -- Is_Executable --
   -------------------

   function Is_Executable (Path : String) return Boolean is
   begin
      if Path = "" then
         return False;
      end if;

      --  hostkit's answer, not a guess from the name: what makes a file
      --  runnable is the host's business, and on one of them it is not a
      --  permission bit at all.
      return Hostkit.Fs.Is_Executable (Path);
   end Is_Executable;

   -----------
   -- Write --
   -----------

   procedure Write
     (Path   : String;
      Text   : String;
      Result : out Written)
   is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      if Path = "" or else Is_Directory (Path) then
         Result := Write_Refused;
         return;
      end if;

      begin
         Ada.Streams.Stream_IO.Create
           (File, Ada.Streams.Stream_IO.Out_File, Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            --  Nowhere to put it: a directory in the path that is not there.
            Result := Write_Refused;
            return;

         when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
            Result := Write_Failed;
            return;
      end;

      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      Ada.Streams.Stream_IO.Close (File);
      Result := Write_Ok;

   exception
      when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
         --  A disk that filled while writing. The file exists and is short,
         --  which is worth saying rather than reporting success.
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;

         Result := Write_Failed;
   end Write;

   ------------
   -- Append --
   ------------

   procedure Append
     (Path   : String;
      Text   : String;
      Result : out Written)
   is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      if Path = "" or else Is_Directory (Path) then
         Result := Write_Refused;
         return;
      end if;

      begin
         if Exists (Path) then
            Ada.Streams.Stream_IO.Open
              (File, Ada.Streams.Stream_IO.Append_File, Path);
         else
            --  Made rather than refused: appending to a file that is not there
            --  yet is what a script collecting output does on its first turn.
            Ada.Streams.Stream_IO.Create
              (File, Ada.Streams.Stream_IO.Out_File, Path);
         end if;
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Result := Write_Refused;
            return;

         when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
            Result := Write_Failed;
            return;
      end;

      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      Ada.Streams.Stream_IO.Close (File);
      Result := Write_Ok;

   exception
      when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;

         Result := Write_Failed;
   end Append;

end Adash.Filesystem;

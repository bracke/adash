with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.IO_Exceptions;

with Hostkit.Fs;

with Adash.Errors;
with Adash.Source;

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

   ----------
   -- Read --
   ----------

   procedure Read
     (Path   : String;
      Text   : out Ada.Strings.Unbounded.Unbounded_String;
      Result : out Reading)
   is
      use Ada.Streams;

      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Text := Ada.Strings.Unbounded.Null_Unbounded_String;

      if Path = "" or else Is_Directory (Path) then
         --  A directory is not a file that could not be read; it is not the
         --  sort of thing this asks about.
         Result := Read_Refused;
         return;
      end if;

      begin
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Result := Read_Missing;
            return;

         when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
            Result := Read_Refused;
            return;
      end;

      declare
         Chunk : Stream_Element_Array (1 .. 4_096);
         Last  : Stream_Element_Offset;
      begin
         while not Ada.Streams.Stream_IO.End_Of_File (File) loop
            Ada.Streams.Stream_IO.Read (File, Chunk, Last);

            for Index in Chunk'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Text, Character'Val (Natural (Chunk (Index))));
            end loop;
         end loop;
      end;

      Ada.Streams.Stream_IO.Close (File);

      --  Text, or nothing. A String in this language is UTF-8 and a file that
      --  is not is not a String -- handing the bytes over would put something
      --  in a variable that no operation on a String is defined for.
      declare
         Held    : constant String := Ada.Strings.Unbounded.To_String (Text);
         Checked : Adash.Source.Buffer;
         Problem : Adash.Errors.Error_Info;
      begin
         if not Adash.Source.Load
                  (Checked,
                   Adash.Source.Make_Origin (Adash.Source.Origin_File, Path),
                   Held, Problem)
         then
            Text := Ada.Strings.Unbounded.Null_Unbounded_String;
            Result := Read_Not_Text;
            return;
         end if;
      end;

      Result := Read_Ok;

   exception
      when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;

         Text := Ada.Strings.Unbounded.Null_Unbounded_String;
         Result := Read_Refused;
   end Read;

   -----------
   -- Write --
   -----------

   ---------------------
   -- Make_Directory --
   ---------------------

   procedure Make_Directory (Path : String; Result : out Written) is
   begin
      if Path = "" then
         Result := Write_Refused;
         return;
      end if;

      --  Already there, and already a directory: what the caller asked for is
      --  the state of the world, not the act.
      if Ada.Directories.Exists (Path) then
         Result :=
           (if Is_Directory (Path) then Write_Ok else Write_Refused);
         return;
      end if;

      begin
         --  Create_Path rather than Create_Directory: every missing level, in
         --  one call, which is what a script naming a path three deep means.
         Ada.Directories.Create_Path (Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            --  A name this host will not form, or something in the way that is
            --  not a directory.
            Result := Write_Refused;
            return;

         when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
            Result := Write_Failed;
            return;
      end;

      --  Asked rather than assumed: Create_Path is allowed to succeed quietly
      --  on a host that did not make anything.
      Result :=
        (if Ada.Directories.Exists (Path) and then Is_Directory (Path)
         then Write_Ok else Write_Failed);

   exception
      when others =>
         Result := Write_Failed;
   end Make_Directory;

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

with Ada.Characters.Latin_1;
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
      Result : out Reading;
      Limit  : Natural := Default_Limit)
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

         Taken : Natural := 0;
      begin
         while not Ada.Streams.Stream_IO.End_Of_File (File) loop
            Ada.Streams.Stream_IO.Read (File, Chunk, Last);

            --  Counted before it is kept, and stopped at the limit rather than
            --  after it: a shell that noticed afterwards would already be
            --  holding whatever it was asked to hold.
            if Taken + Natural (Last) > Limit then
               Ada.Streams.Stream_IO.Close (File);
               Text := Ada.Strings.Unbounded.Null_Unbounded_String;
               Result := Read_Too_Large;
               return;
            end if;

            Taken := Taken + Natural (Last);

            for Index in Chunk'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Text, Character'Val (Natural (Chunk (Index))));
            end loop;
         end loop;
      end;

      Ada.Streams.Stream_IO.Close (File);

      --  Line endings as text has them, before anything else looks at it.
      --
      --  A file written on Windows ends each line with a carriage return and a
      --  line feed, and a script comparing what it read against text it wrote
      --  itself would fail there and nowhere else, for a byte nobody can see.
      --  The other two readers already answer this way -- Read_Line drops the
      --  carriage return with the terminator, and a capture does too -- and
      --  three readers of one language disagreeing about what a line ends with
      --  is worse than any of the three answers.
      --
      --  A lone carriage return is left where it is: it is not a line ending
      --  on any host this runs on, and something carrying one meant it.
      declare
         Whole : constant String := Ada.Strings.Unbounded.To_String (Text);

         Kept  : String (1 .. Whole'Length);
         Count : Natural := 0;
      begin
         for Index in Whole'Range loop
            if Whole (Index) = Ada.Characters.Latin_1.CR
              and then Index < Whole'Last
              and then Whole (Index + 1) = Ada.Characters.Latin_1.LF
            then
               null;
            else
               Count := Count + 1;
               Kept (Count) := Whole (Index);
            end if;
         end loop;

         Text := Ada.Strings.Unbounded.To_Unbounded_String (Kept (1 .. Count));
      end;

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
         when others =>
            --  Every complaint the host makes here is a refusal.
            --
            --  Which is not how writing a file is answered, and the difference
            --  is real rather than tidy: a write can stop half way and leave a
            --  file that is neither what was there before nor what was meant,
            --  so "did not finish" is what its caller needs to hear. A
            --  directory is made or it is not.
            --
            --  Not sorted by which exception arrived, because the hosts do not
            --  agree on that: the same name, too long for both, is a Use_Error
            --  on one and a Device_Error on another, and a shell that told a
            --  user "writing did not finish" on one host and "nothing can be
            --  written" on the other would be reporting the compiler's
            --  mapping rather than what happened. What happened is that the
            --  host would not make it.
            Result := Write_Refused;
            return;
      end;

      --  Asked rather than assumed, and this is not a formality: on one host
      --  a name too long to form raises nothing at all -- Create_Path returns
      --  quietly having made nothing -- and only this notices.
      --
      --  Refused rather than failed, for the same reason the handler above
      --  is: nothing was made, so there is nothing half done to go looking
      --  for. Which is why Make_Directory never answers Write_Failed. A write
      --  can stop in the middle and a directory cannot.
      Result :=
        (if Ada.Directories.Exists (Path) and then Is_Directory (Path)
         then Write_Ok else Write_Refused);

   exception
      when others =>
         Result := Write_Refused;
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

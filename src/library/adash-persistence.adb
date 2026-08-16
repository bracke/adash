with Ada.Directories;

--  For comparing File_Kind, which is otherwise not directly visible here.
use type Ada.Directories.File_Kind;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

with Hostkit.Fs;
with Hostkit.Locks;

with Adash.Errors;
with Adash.Source;

package body Adash.Persistence is

   use Ada.Strings.Unbounded;

   --  The directory Adash owns inside whichever of the host's directories a
   --  store maps to. One name in one place: a second spelling of it somewhere
   --  else is a second set of files nobody would find.
   Application_Directory : constant String := "adash";

   --  What a lock file is called. Beside the file it guards rather than inside
   --  a shared directory, so two different files are never held up by each
   --  other, and named so that a person listing the directory can see what it
   --  is.
   Lock_Suffix : constant String := ".lock";

   function Directory_For (Kind : Store_Kind) return String;

   procedure Restrict (Path : String);
   --  Make a path readable by its owner only, where the host has the concept.
   --  A host that has not -- Windows, where a file inherits from the user's
   --  profile -- reports failure, and that is not a failure of ours: the file
   --  is as private as that host makes anything. So the answer is deliberately
   --  not checked, and this wrapper exists so that saying so takes one comment
   --  rather than three.

   --------------
   -- Restrict --
   --------------

   procedure Restrict (Path : String) is
      Applied : Boolean;
      pragma Unreferenced (Applied);
   begin
      Applied := Hostkit.Fs.Make_Private (Path);
   end Restrict;

   -------------------
   -- Directory_For --
   -------------------

   function Directory_For (Kind : Store_Kind) return String is
      Base : constant String :=
        (case Kind is
            when Configuration_Store => Hostkit.Fs.Config_Directory,
            when Data_Store          => Hostkit.Fs.Application_Data_Directory,
            when Cache_Store         => Hostkit.Fs.Cache_Directory);
   begin
      --  hostkit answers "" when the host has no such place -- a container, a
      --  daemon, an account with no home. Passing that on rather than
      --  substituting the current directory: writing a user's history into
      --  whatever directory they happen to be standing in would be worse than
      --  not writing it.
      if Base = "" then
         return "";
      end if;

      return Hostkit.Fs.Join (Base, Application_Directory);
   end Directory_For;

   --------------
   -- Path_For --
   --------------

   function Path_For (Kind : Store_Kind; Name : String) return String is
      Directory : constant String := Directory_For (Kind);
   begin
      if Directory = "" then
         return "";
      end if;

      return Hostkit.Fs.Join (Directory, Name);
   end Path_For;

   --  Make sure a file's directory exists, privately.
   function Ensure_Directory (Path : String) return Boolean;

   function Ensure_Directory (Path : String) return Boolean is
      Directory : constant String := Ada.Directories.Containing_Directory (Path);
   begin
      if Directory = "" then
         return True;
      end if;

      if Ada.Directories.Exists (Directory) then
         return Ada.Directories.Kind (Directory) = Ada.Directories.Directory;
      end if;

      Ada.Directories.Create_Path (Directory);

      --  Private the moment it exists, not afterwards as a tidy-up: a
      --  directory that was world-readable for even a moment is one another
      --  user could have opened a handle on.
      Restrict (Directory);

      return True;
   exception
      when others =>
         return False;
   end Ensure_Directory;

   ------------
   -- Exists --
   ------------

   function Exists (Path : String) return Boolean is
   begin
      if Path = "" then
         return False;
      end if;

      return Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File;
   exception
      when others =>
         return False;
   end Exists;

   ----------
   -- Read --
   ----------

   procedure Read
     (Path   : String;
      Into   : out Contents;
      Result : out Outcome;
      Limit  : Natural := Adash.Filesystem.Default_Limit)
   is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;

      File : File_Type;
   begin
      Into := Null_Unbounded_String;

      if Path = "" then
         Result := Store_Unavailable;
         return;
      end if;

      if not Exists (Path) then
         --  The ordinary case for a shell starting for the first time, and
         --  distinct from every failure so that a caller does not report a
         --  problem where there is none.
         Result := Store_Absent;
         return;
      end if;

      Open (File, In_File, Path);

      declare
         Buffer : Stream_Element_Array (1 .. 8_192);
         Last   : Stream_Element_Offset;
         Text   : Unbounded_String;
      begin
         while not End_Of_File (File) loop
            Read (File, Buffer, Last);

            --  Counted before it is kept, as everywhere else this shell reads.
            if Length (Text) + Natural (Last) > Limit then
               Close (File);
               Into := Null_Unbounded_String;
               Result := Store_Too_Large;
               return;
            end if;

            for Index in Buffer'First .. Last loop
               Append (Text, Character'Val (Buffer (Index)));
            end loop;
         end loop;

         Close (File);

         --  Checked once, here, rather than left to whichever parser first
         --  trips over it. Malformed bytes are a property of the file, and a
         --  TOML error pointing at the middle of a broken character would send
         --  the reader looking for a syntax mistake that is not there.
         declare
            Raw       : constant String := To_String (Text);
            Validated : Adash.Source.Buffer;
            Problem   : Adash.Errors.Error_Info;
         begin
            --  Adash.Source owns UTF-8 validation for this project, so the
            --  check goes through it rather than being written a second time
            --  here. The buffer is discarded: what is wanted is the verdict.
            if not Adash.Source.Load
                     (Validated,
                      Adash.Source.Make_Origin (Adash.Source.Origin_File, Path),
                      Raw, Problem)
            then
               Result := Store_Not_Text;
               return;
            end if;

            Into := Text;
            Result := Store_Ok;
         end;
      end;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         Result := Store_Absent;

      when others =>
         if Is_Open (File) then
            Close (File);
         end if;

         Into := Null_Unbounded_String;
         Result := Store_Not_Readable;
   end Read;

   --  Hold the lock for a path, run something, release it. The lock file is
   --  beside the target rather than being the target: locking the file being
   --  replaced would mean holding a descriptor on something about to be
   --  unlinked, which POSIX allows and Windows does not.
   generic
      with function Action return Outcome;
   function Under_Lock (Path : String) return Outcome;

   function Under_Lock (Path : String) return Outcome is
      Guard  : Hostkit.Locks.Lock;
      Result : Outcome;

      use type Hostkit.Locks.Lock_Outcome;
   begin
      case Hostkit.Locks.Acquire
             (Path & Lock_Suffix, Hostkit.Locks.Lock_Exclusive,
              Wait => False, Item => Guard)
      is
         when Hostkit.Locks.Lock_Ok =>
            null;

         when Hostkit.Locks.Lock_Busy =>
            --  Somebody else is writing. Not this process's error, and the
            --  caller decides whether to wait or to skip and say so.
            return Store_Busy;

         when others =>
            return Store_Not_Writable;
      end case;

      Result := Action;
      Hostkit.Locks.Release (Guard);
      return Result;
   end Under_Lock;

   --------------
   -- Replaced --
   --------------

   --  Put text in a file, atomically, with no lock of its own.
   --
   --  Separate from Write because Update needs the same act *inside* the lock
   --  it is already holding, and taking that lock twice is either a deadlock
   --  or a refusal depending on the host.
   function Replaced (Path : String; Text : String) return Outcome;

   function Replaced (Path : String; Text : String) return Outcome is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;

      --  Beside the destination, not in a temporary directory: a rename
      --  across filesystems is not atomic, and a temporary directory is
      --  routinely on a different one.
      Staging : constant String := Path & ".new";
      File    : File_Type;
   begin
      begin
         Create (File, Out_File, Staging);

         declare
            Buffer : Stream_Element_Array
                       (1 .. Stream_Element_Offset'Max (1, Text'Length));
         begin
            for Index in Text'Range loop
               Buffer (Stream_Element_Offset (Index - Text'First + 1)) :=
                 Stream_Element (Character'Pos (Text (Index)));
            end loop;

            if Text'Length > 0 then
               Write (File, Buffer (1 .. Stream_Element_Offset (Text'Length)));
            end if;
         end;

         Close (File);
      exception
         when others =>
            if Is_Open (File) then
               Close (File);
            end if;

            return Store_Not_Writable;
      end;

      --  Private before it is in place, so the finished file is never
      --  readable by anyone else even for an instant.
      Restrict (Staging);

      if not Hostkit.Fs.Replace_File (Staging, Path) then
         begin
            Ada.Directories.Delete_File (Staging);
         exception
            when others =>
               null;
         end;

         return Store_Not_Writable;
      end if;

      return Store_Ok;
   end Replaced;

   -----------
   -- Write --
   -----------

   procedure Write
     (Path   : String;
      Text   : String;
      Result : out Outcome)
   is
      function Do_Write return Outcome;

      function Do_Write return Outcome is
      begin
         return Replaced (Path, Text);
      end Do_Write;

      function Guarded is new Under_Lock (Do_Write);

   begin
      if Path = "" then
         Result := Store_Unavailable;
         return;
      end if;

      if not Ensure_Directory (Path) then
         Result := Store_Not_Writable;
         return;
      end if;

      Result := Guarded (Path);
   end Write;

   ------------
   -- Update --
   ------------

   procedure Update
     (Path   : String;
      Change : not null access procedure
                 (Text : in out Contents; Changed : out Boolean);
      Result : out Outcome)
   is
      function Do_Update return Outcome;

      function Do_Update return Outcome is
         Held    : Contents;
         Reading : Outcome;
         Changed : Boolean;
      begin
         Read (Path, Held, Reading);

         if Reading /= Store_Ok then
            return Reading;
         end if;

         Change (Held, Changed);

         if not Changed then
            return Store_Ok;
         end if;

         return Replaced (Path, To_String (Held));
      end Do_Update;

      function Guarded is new Under_Lock (Do_Update);

   begin
      if Path = "" then
         Result := Store_Unavailable;
         return;
      end if;

      if not Ensure_Directory (Path) then
         Result := Store_Not_Writable;
         return;
      end if;

      Result := Guarded (Path);
   end Update;

   ------------------
   -- Append_Line --
   ------------------

   procedure Append_Line
     (Path   : String;
      Text   : String;
      Result : out Outcome)
   is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;

      function Do_Append return Outcome;

      function Do_Append return Outcome is
         File    : File_Type;
         Newline : constant Character := Character'Val (16#0A#);
      begin
         if Ada.Directories.Exists (Path) then
            Open (File, Append_File, Path);
         else
            Create (File, Out_File, Path);
            Restrict (Path);
         end if;

         declare
            Line   : constant String := Text & Newline;
            Buffer : Stream_Element_Array
                       (1 .. Stream_Element_Offset (Line'Length));
         begin
            for Index in Line'Range loop
               Buffer (Stream_Element_Offset (Index - Line'First + 1)) :=
                 Stream_Element (Character'Pos (Line (Index)));
            end loop;

            Write (File, Buffer);
         end;

         Close (File);
         return Store_Ok;
      exception
         when others =>
            if Is_Open (File) then
               Close (File);
            end if;

            return Store_Not_Writable;
      end Do_Append;

      function Guarded is new Under_Lock (Do_Append);

   begin
      if Path = "" then
         Result := Store_Unavailable;
         return;
      end if;

      if not Ensure_Directory (Path) then
         Result := Store_Not_Writable;
         return;
      end if;

      Result := Guarded (Path);
   end Append_Line;

   ------------
   -- Remove --
   ------------

   ------------------------
   -- Ensure_Container --
   ------------------------

   function Ensure_Container (Path : String) return Boolean is
   begin
      return Ensure_Directory (Path);
   end Ensure_Container;

   procedure Remove (Path : String; Result : out Outcome) is
   begin
      if Path = "" then
         Result := Store_Unavailable;
         return;
      end if;

      if not Ada.Directories.Exists (Path) then
         --  The caller wanted it not to be there, and it is not. Reporting a
         --  failure would make every caller write the same two-branch check.
         Result := Store_Ok;
         return;
      end if;

      Ada.Directories.Delete_File (Path);
      Result := Store_Ok;
   exception
      when others =>
         Result := Store_Not_Writable;
   end Remove;

end Adash.Persistence;

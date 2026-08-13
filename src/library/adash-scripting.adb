with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

with Adash.Errors;
with Adash.Messages;
with Adash.Scripting.Modules;
with Adash.Source;

with Hostkit.Fs;

package body Adash.Scripting is

   use Ada.Strings.Unbounded;

   package D renames Adash.Diagnostics;

   -----------
   -- Depth --
   -----------

   function Depth (Item : Loading) return Natural is
   begin
      return Natural (Item.Active.Length);
   end Depth;

   ----------------
   -- Is_Active --
   ----------------

   function Is_Active (Item : Loading; Path : String) return Boolean is
   begin
      for Current of Item.Active loop
         if To_String (Current) = Path then
            return True;
         end if;
      end loop;

      return False;
   end Is_Active;

   --  Report a failure that stopped a script before it ran.
   procedure Complain
     (Report : in out D.List;
      Code   : Adash.Errors.Error_Code;
      Path   : String)
   is
   begin
      Report.Emit
        (D.Make
           (Message   => Adash.Errors.Message (Code),
            Level     => D.Severity_Fatal,
            Of_Kind   => D.Category_Execution,
            Raised_By => D.Owner_Scripting,
            Origin    => Adash.Source.Make_Origin (Adash.Source.Origin_File, Path),
            Arguments => [1 => Adash.Messages.Named ("source", Path)]));
   end Complain;

   --------------
   -- Run_Text --
   --------------

   procedure Run_Text
     (Session : in out Adash.Engine.Session;
      Text    : String;
      Name    : String;
      Result  : out Outcome;
      Status  : out Adash.Execution.Exit_Status;
      Report  : in out D.List;
      On_Output : Adash.Engine.Output_Sink_Access := null)
   is
      Submitted : Adash.Engine.Result;
      use type Adash.Engine.Submission_Kind;
   begin
      --  Through the engine, like everything else. A script that took another
      --  route would be a second interpreter.
      Adash.Engine.Submit
        (Session, Text, Name, Adash.Source.Origin_File, Submitted, Report,
         On_Output => On_Output);

      Status := Submitted.Status;

      if Submitted.Kind = Adash.Engine.Not_Understood then
         Result := Script_Rejected;
      else
         Result := Script_Ran;
      end if;
   end Run_Text;

   --------------
   -- Run_File --
   --------------

   procedure Run_File
     (Session : in out Adash.Engine.Session;
      Path    : String;
      Context : in out Loading;
      Result  : out Outcome;
      Status  : out Adash.Execution.Exit_Status;
      Report  : in out D.List;
      On_Output : Adash.Engine.Output_Sink_Access := null)
   is
      Resolved : constant String := Hostkit.Fs.Real_Path (Path);
   begin
      Status := (Kind => Adash.Execution.Exit_Start_Failure, Code => 127, others => <>);

      if Resolved = "" or else not Ada.Directories.Exists (Path) then
         Result := Script_Not_Found;
         Complain (Report, Adash.Errors.Error_Source_Unreadable, Path);
         return;
      end if;

      --  The resolved path, not the one written: two names for one file are
      --  one file, and a cycle reached through a symbolic link is still a
      --  cycle.
      if Is_Active (Context, Resolved) then
         Result := Script_Cycle;
         Complain (Report, Adash.Errors.Error_Script_Cycle, Path);
         return;
      end if;

      declare
         Content : Unbounded_String;
         File    : Ada.Streams.Stream_IO.File_Type;
      begin
         begin
            Ada.Streams.Stream_IO.Open
              (File, Ada.Streams.Stream_IO.In_File, Path);
         exception
            when Ada.IO_Exceptions.Name_Error
               | Ada.IO_Exceptions.Use_Error
               | Ada.IO_Exceptions.Status_Error =>
               --  A directory, or a file this user may not read. Reported
               --  rather than raised: a path a user typed being unreadable is
               --  an ordinary outcome.
               Result := Script_Unreadable;
               Complain (Report, Adash.Errors.Error_Source_Unreadable, Path);
               return;
         end;

         declare
            use Ada.Streams;
            Chunk : Stream_Element_Array (1 .. 64 * 1024);
            Last  : Stream_Element_Offset;
         begin
            while not Ada.Streams.Stream_IO.End_Of_File (File) loop
               Ada.Streams.Stream_IO.Read (File, Chunk, Last);

               for Index in Chunk'First .. Last loop
                  Append (Content, Character'Val (Natural (Chunk (Index))));
               end loop;
            end loop;

            Ada.Streams.Stream_IO.Close (File);
         exception
            when others =>
               if Ada.Streams.Stream_IO.Is_Open (File) then
                  Ada.Streams.Stream_IO.Close (File);
               end if;

               Result := Script_Unreadable;
               Complain (Report, Adash.Errors.Error_Source_Unreadable, Path);
               return;
         end;

         --  On the chain while it runs, off it afterwards. A script that
         --  loaded another which loaded the first would otherwise be a hang
         --  rather than a refusal.
         Context.Active.Append (To_Unbounded_String (Resolved));

         Run_Text (Session, To_String (Content), Path, Result, Status, Report,
                   On_Output => On_Output);

         Context.Active.Delete_Last;
      end;
   end Run_File;

   ----------------
   ----------------------
   -- Report_Missing --
   ----------------------

   --  Say that a name resolved to nothing, and where the search went.
   --
   --  Where it looked is the useful half: `no script called setup` leaves a
   --  reader wondering whether the shell searched at all, and a name that was
   --  taken as a path failed for a different reason than one that was searched
   --  for and not found.
   procedure Report_Missing
     (Report : in out D.List;
      Name   : String;
      Where  : Modules.Search_Step);

   procedure Report_Missing
     (Report : in out D.List;
      Name   : String;
      Where  : Modules.Search_Step) is
   begin
      Report.Emit
        (D.From_Error
           (Adash.Errors.Failure
              (Adash.Errors.Error_Module_Not_Found,
               [1 => Adash.Messages.Named ("name", Name)],
               Quoted =>
                 (case Where is
                     when Modules.Step_As_Written =>
                       Adash.Messages.Msg_Module_Looked_As_Written,
                     when Modules.Step_Beside_Loader =>
                       Adash.Messages.Msg_Module_Looked_Beside,
                     when Modules.Step_User_Modules =>
                       Adash.Messages.Msg_Module_Looked_In_Modules),
               Fills => "where"),
            D.Severity_Error, D.Category_Execution, D.Owner_Scripting));
   end Report_Missing;

   -----------------
   -- Innermost --
   -----------------

   function Innermost (Item : Loading) return String is
   begin
      if Item.Active.Is_Empty then
         return "";
      end if;

      return To_String (Item.Active.Last_Element);
   end Innermost;

   ----------------
   -- Run_Script --
   ----------------

   overriding procedure Run_Script
     (Runner : in out Scripting.Runner;
      Path   : String;
      Status : out Adash.Execution.Exit_Status;
      Failed : out Boolean)
   is
      Result : Outcome;

      --  What the name means. A path is used as written; a bare name is
      --  searched for, beside the script that asked for it and then in the
      --  user's own module directory. Adash.Scripting.Modules has decided this
      --  since Phase 14 and nothing asked it: `source ("setup")` failed unless
      --  a file of exactly that name sat in the working directory.
      Found : constant Modules.Resolution :=
        Modules.Resolve (Path, Innermost (Runner.Context.all));
   begin
      if not Found.Found then
         Report_Missing (Runner.Report.all, Path, Found.Where);
         Status := (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
         Failed := True;
         return;
      end if;

      Run_File
        (Session   => Runner.Session.all,
         Path      => To_String (Found.Path),
         Context   => Runner.Context.all,
         Result    => Result,
         Status    => Status,
         Report    => Runner.Report.all,
         On_Output => Runner.Output);

      --  Ran and failed is not the same as could not be read. The first is the
      --  script's own status and belongs to the caller; the second is this
      --  command failing, and Run_File has already said why.
      Failed := Result /= Script_Ran;

      if Failed then
         Status := (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);
      end if;
   end Run_Script;

end Adash.Scripting;

with Ada.Directories;

with Adash.Configuration;
with Adash.Execution;

with Hostkit.Fs;

with Adash.Scripting.Modules;

package body Adash.Scripting.Startup is

   File_Name         : constant String := "startup" & Adash.Scripting.Modules.Extension;
   Session_File_Name : constant String := "session" & Adash.Scripting.Modules.Extension;

   --------------
   -- Path_For --
   --------------

   function Path_For (Item : Scope) return String is
   begin
      case Item is
         when System_Scope =>
            --  Beside the installed executable rather than in a fixed system
            --  directory: an Adash installed into a home directory or a
            --  container has its administrator's file beside it, and one
            --  installed system-wide has it where the package put it. Asking
            --  hostkit for the executable's own directory is the same question
            --  in both cases.
            declare
               Beside : constant String := Hostkit.Fs.Own_Executable_Directory;
            begin
               if Beside = "" then
                  return "";
               end if;

               return Hostkit.Fs.Join
                 (Hostkit.Fs.Join (Hostkit.Fs.Join (Beside, ".."), "share"),
                  Hostkit.Fs.Join ("adash", File_Name));
            end;

         when User_Scope =>
            declare
               Base : constant String := Hostkit.Fs.Config_Directory;
            begin
               if Base = "" then
                  return "";
               end if;

               return Hostkit.Fs.Join (Hostkit.Fs.Join (Base, "adash"), File_Name);
            end;

         when Session_Scope =>
            declare
               Base : constant String := Hostkit.Fs.Config_Directory;
            begin
               if Base = "" then
                  return "";
               end if;

               return Hostkit.Fs.Join
                 (Hostkit.Fs.Join (Base, "adash"), Session_File_Name);
            end;
      end case;
   end Path_For;

   -------------
   -- Applies --
   -------------

   function Applies (Item : Scope; Interactive : Boolean) return Boolean is
   begin
      case Item is
         when System_Scope | User_Scope =>
            --  Always. A script that behaved differently from an interactive
            --  session would be one nobody could debug by hand.
            return True;

         when Session_Scope =>
            --  Interactive only: it exists to set a prompt and the like, and
            --  running it for a script would make that script mean different
            --  things depending on who ran it.
            return Interactive;
      end case;
   end Applies;

   -------------
   -- Run_All --
   -------------

   procedure Run_All
     (Session     : in out Adash.Engine.Session;
      Interactive : Boolean;
      Summary     : out Report_Summary;
      Report      : in out Adash.Diagnostics.List;
      On_Output   : Adash.Engine.Output_Sink_Access := null)
   is
   begin
      Summary := (others => 0);

      for Item in Scope loop
         --  Two conditions, and they are different questions. Applies asks
         --  whether this kind of session runs that file at all; the setting
         --  asks whether the user wants it to. Folding them together would put
         --  a setting inside a function that has no business reading one, and
         --  would make the session file untestable without configuration.
         if Applies (Item, Interactive)
           and then (Item /= Session_Scope
                     or else Adash.Configuration.Boolean_Value
                               (Adash.Engine.Settings (Session),
                                Adash.Configuration.Session_File_Setting))
         then
            declare
               Path : constant String := Path_For (Item);
            begin
               --  Absence is silent. Most machines have no system file and
               --  most users have none either; a shell that complained on
               --  every start would train its users to ignore it.
               if Path /= "" and then Ada.Directories.Exists (Path) then
                  declare
                     Context : Loading;
                     Result  : Outcome;
                     Status  : Adash.Execution.Exit_Status;
                  begin
                     Run_File (Session, Path, Context, Result, Status, Report,
                               On_Output => On_Output);

                     case Result is
                        when Script_Ran =>
                           Summary.Ran := Summary.Ran + 1;

                           if not Adash.Execution.Succeeded (Status) then
                              Summary.Failed := Summary.Failed + 1;
                           end if;

                        when Script_Rejected =>
                           Summary.Ran := Summary.Ran + 1;
                           Summary.Failed := Summary.Failed + 1;

                        when Script_Not_Found | Script_Unreadable
                           | Script_Cycle =>
                           Summary.Unreadable := Summary.Unreadable + 1;
                     end case;
                  end;
               end if;
            end;
         end if;
      end loop;

      --  Whatever happened, the shell comes up. Refusing to start over a
      --  broken startup file would leave a user without the tool they would
      --  fix it with.
      --
      --  Including when what happened was `quit`. A startup file runs before
      --  there is a session to end, so its request is withdrawn here rather
      --  than carried into one: standing, it ended the session after its first
      --  submission and reported the startup file's status instead of the
      --  session's -- and on the script path it replaced the script's status
      --  with the startup file's. What a startup file's `quit` still does is
      --  end that file, which is the submission it is in.
      Adash.Engine.Clear_Exit_Request (Session);
   end Run_All;

end Adash.Scripting.Startup;

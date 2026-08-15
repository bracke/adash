with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Adash.Commands;
with Adash.Configuration;
with Adash.Configuration.Files;
with Adash.Diagnostics;
with Adash.Source;
with Adash.Engine;
with Adash.Execution;
with Adash.Interactive.Session;
with Adash.Messages;
with Adash.Messages.Rendering;
with Adash.Persistence;
with Adash.Scripting;
with Adash.Scripting.Startup;
with Adash.Terminal;
with Adash.Version;

--  The adash executable.
--
--  This main is deliberately thin and stays that way. Its whole job is to
--  turn a command line into a request, hand that request to the subsystem
--  that owns it, and turn the answer into an exit status. Startup policy
--  belongs to Adash.Scripting.Startup, interactive sessions to
--  Adash.Interactive, and everything either of them does goes through
--  Adash.Engine -- so that a session started here and a script run under test
--  take the same route. A main that grows shell behaviour of its own is a
--  second frontend, and a second frontend is the thing this project is most
--  concerned not to acquire.
--
--  With no arguments it starts an interactive session; with a path it runs
--  that file; with an option it reports its version or its usage. All three
--  meet again inside Adash.Engine.
procedure Adash_Main is

   package CLI renames Ada.Command_Line;
   package IO renames Ada.Text_IO;
   package Msg renames Adash.Messages;

   --  A number as a person writes one, without the space Ada's Image puts
   --  where a sign would go.
   function Trimmed (Value : Natural) return String
   is (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
   package Render renames Adash.Messages.Rendering;

   --  Exit statuses this program produces. The shell-wide exit-status model --
   --  which has to distinguish an internal command from an external one, a
   --  signal from a status, and a parse failure from a runtime failure --
   --  belongs to Adash.Execution and arrives with it. These two are what a
   --  command line needs before then, and are the same values that model will
   --  give them.
   Exit_Success : constant := 0;
   Exit_Usage   : constant := 2;

   --  Indent for an option line in the usage block.
   Option_Indent : constant String := "  ";

   Catalog : Render.Catalog;

   --  Resolved once. Whether stdout is a terminal decides whether styling is
   --  emitted, and asking twice invites the two answers to differ.
   Stdout_Is_Terminal : constant Boolean :=
     Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Output);
   Stderr_Is_Terminal : constant Boolean :=
     Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Error);

   procedure Put_Line_Styled
     (File : IO.File_Type;
      Item : String;
      Role : Adash.Terminal.Style_Role;
      Destination_Is_Terminal : Boolean);
   --  Write one styled line. The only place this program emits text.

   procedure Report_Version;
   procedure Report_Usage (File : IO.File_Type; Destination_Is_Terminal : Boolean);

   function Run_Script (Path : String; First_Argument : Positive) return Natural;
   --  Run a script file and return the status the process should end with.

   ---------------------
   -- Put_Line_Styled --
   ---------------------

   procedure Put_Line_Styled
     (File : IO.File_Type;
      Item : String;
      Role : Adash.Terminal.Style_Role;
      Destination_Is_Terminal : Boolean)
   is
   begin
      IO.Put_Line (File, Adash.Terminal.Styled (Item, Role, Destination_Is_Terminal));
   end Put_Line_Styled;

   --------------------
   -- Report_Version --
   --------------------

   procedure Report_Version is
   begin
      Put_Line_Styled
        (IO.Standard_Output,
         Catalog.Text
           (Msg.Msg_Version_Line,
            [1 => Msg.Named ("version", Adash.Version.Number)]),
         Adash.Terminal.Role_Plain,
         Stdout_Is_Terminal);

      Put_Line_Styled
        (IO.Standard_Output,
         Catalog.Text
           (Msg.Msg_Version_Build,
            [Msg.Named ("profile", Adash.Version.Build_Profile),
             Msg.Named ("os",      Adash.Version.Host_Operating_System),
             Msg.Named ("arch",    Adash.Version.Host_Architecture)]),
         Adash.Terminal.Role_Muted,
         Stdout_Is_Terminal);

      if Adash.Version.Is_Prerelease then
         Put_Line_Styled
           (IO.Standard_Output,
            Catalog.Text (Msg.Msg_Version_Prerelease_Notice),
            Adash.Terminal.Role_Muted,
            Stdout_Is_Terminal);
      end if;
   end Report_Version;

   ------------------
   -- Report_Usage --
   ------------------

   procedure Report_Usage (File : IO.File_Type; Destination_Is_Terminal : Boolean) is
   begin
      Put_Line_Styled
        (File, Catalog.Text (Msg.Msg_Usage),
         Adash.Terminal.Role_Plain, Destination_Is_Terminal);
      Put_Line_Styled
        (File, Catalog.Text (Msg.Msg_Application_Summary),
         Adash.Terminal.Role_Muted, Destination_Is_Terminal);
      IO.New_Line (File);
      Put_Line_Styled
        (File, Catalog.Text (Msg.Msg_Usage_Options_Header),
         Adash.Terminal.Role_Header, Destination_Is_Terminal);

      --  The indent is applied here rather than written into the catalog.
      --  Layout is presentation, not text: a translator has no business
      --  deciding it, and the catalog reader strips leading blanks from a
      --  value anyway, so an indent written there is silently lost.
      Put_Line_Styled
        (File, Option_Indent & Catalog.Text (Msg.Msg_Usage_Option_Help),
         Adash.Terminal.Role_Plain, Destination_Is_Terminal);
      Put_Line_Styled
        (File, Option_Indent & Catalog.Text (Msg.Msg_Usage_Option_Version),
         Adash.Terminal.Role_Plain, Destination_Is_Terminal);
      IO.New_Line (File);
      Put_Line_Styled
        (File, Option_Indent & Catalog.Text (Msg.Msg_Usage_Script),
         Adash.Terminal.Role_Plain, Destination_Is_Terminal);
      IO.New_Line (File);
      Put_Line_Styled
        (File, Catalog.Text (Msg.Msg_Usage_More),
         Adash.Terminal.Role_Muted, Destination_Is_Terminal);
   end Report_Usage;

   ------------------
   -- Run_Script --
   ------------------

   function Run_Script (Path : String; First_Argument : Positive) return Natural
   is
      --  Aliased because the runner `source` uses points at all three: it
      --  shares this run's session, loading chain and diagnostics rather than
      --  starting its own.
      Session : aliased Adash.Engine.Session;
      Startup : Adash.Scripting.Startup.Report_Summary;
      Report  : aliased Adash.Diagnostics.List;
      Context : aliased Adash.Scripting.Loading;
      Result  : Adash.Scripting.Outcome;
      Status  : Adash.Execution.Exit_Status;

      use type Adash.Scripting.Outcome;

      procedure Render_Diagnostics;

      --  Diagnostics are data until here. This is the presentation boundary:
      --  the identifier becomes a sentence, and the severity becomes a style.
      procedure Render_Diagnostics is
      begin
         Report.Sort;

         for Index in 1 .. Report.Count loop
            declare
               Item : constant Adash.Diagnostics.Diagnostic :=
                 Report.Element (Index);
               Role : constant Adash.Terminal.Style_Role :=
                 (case Adash.Diagnostics.Level (Item) is
                     when Adash.Diagnostics.Severity_Note    => Adash.Terminal.Role_Muted,
                     when Adash.Diagnostics.Severity_Warning => Adash.Terminal.Role_Warning,
                     when others                             => Adash.Terminal.Role_Error);
               Said : constant String :=
                 Catalog.Text (Adash.Diagnostics.Message (Item),
                               Adash.Diagnostics.Arguments (Item),
                               Adash.Diagnostics.Detail (Item),
                               Adash.Diagnostics.Detail_Placeholder (Item),
                               Adash.Diagnostics.Detail_Arguments (Item));

               --  Where to find it, in front of what it says -- but only for a
               --  file. A line typed at a prompt is on the screen already, and
               --  a position in front of it is noise pointing at itself.
               Origin : constant Adash.Source.Origin :=
                 Adash.Diagnostics.Origin (Item);

               Place : constant Adash.Source.Location :=
                 Adash.Diagnostics.Position (Item);

               --  Only where there is a position to give. A file that
               --  could not be read at all, or a failure with no place in the
               --  text, has none -- and `path:1:1:` in front of it would be a
               --  position pointing at nothing.
               Known : constant Boolean :=
                 Adash.Source."=" (Adash.Source.Kind (Origin),
                                   Adash.Source.Origin_File)
                 and then Adash.Source.Name (Origin) /= ""
                 and then not Adash.Source.Is_Empty
                                (Adash.Diagnostics.Extent (Item));
            begin
               Put_Line_Styled
                 (IO.Standard_Error,
                  (if Known
                   then Catalog.Text
                          (Msg.Msg_Line_Diagnostic_At,
                           [Msg.Named ("path", Adash.Source.Name (Origin)),
                            Msg.Named ("line", Trimmed (Place.Line)),
                            Msg.Named ("column", Trimmed (Place.Column)),
                            Msg.Named ("text", Said)])
                   else Said),
                  Role, Stderr_Is_Terminal);

               --  The line itself, and a caret under what it is about. Dimmed:
               --  what a reader is looking for is the message, and the quote
               --  is there to save them opening the file.
               if Known
                 and then Adash.Diagnostics.Quoted_Line (Item) /= ""
               then
                  Put_Line_Styled
                    (IO.Standard_Error,
                     Adash.Diagnostics.Quoted_Line (Item),
                     Adash.Terminal.Role_Muted, Stderr_Is_Terminal);
                  Put_Line_Styled
                    (IO.Standard_Error,
                     Adash.Diagnostics.Caret (Item),
                     Adash.Terminal.Role_Muted, Stderr_Is_Terminal);
               end if;

               --  What else this is about: the earlier declaration behind
               --  "already declared", and anything else a subsystem thought a
               --  reader would want to be sent to. Each says where it is and
               --  what it is, in the same form as the diagnostic itself.
               for Which in 1 .. Adash.Diagnostics.Related_Count (Item) loop
                  declare
                     Beside : constant Adash.Diagnostics.Related_Location :=
                       Adash.Diagnostics.Related (Item, Which);
                  begin
                     if Adash.Source."=" (Adash.Source.Kind (Beside.Origin),
                                          Adash.Source.Origin_File)
                       and then Adash.Source.Name (Beside.Origin) /= ""
                       and then not Adash.Source.Is_Empty (Beside.Extent)
                     then
                        Put_Line_Styled
                          (IO.Standard_Error,
                           Catalog.Text
                             (Msg.Msg_Line_Diagnostic_At,
                              [Msg.Named
                                 ("path", Adash.Source.Name (Beside.Origin)),
                               Msg.Named ("line", Trimmed (Beside.Place.Line)),
                               Msg.Named
                                 ("column", Trimmed (Beside.Place.Column)),
                               Msg.Named
                                 ("text", Catalog.Text (Beside.Message))]),
                           Adash.Terminal.Role_Muted, Stderr_Is_Terminal);
                     end if;
                  end;
               end loop;
            end;
         end loop;
      end Render_Diagnostics;

      --  Command output is data too, and rendered the same way -- but *as the
      --  command produces it*, not once the submission has finished. A program
      --  writes to standard output as the machine runs it, so a line held back
      --  arrives after text that was written later.
      type Console is limited new Adash.Engine.Output_Sink with null record;

      overriding procedure Write
        (Sink : in out Console; Item : Adash.Commands.Line);

      overriding procedure Write
        (Sink : in out Console; Item : Adash.Commands.Line)
      is
         pragma Unreferenced (Sink);
      begin
         Put_Line_Styled
           (IO.Standard_Output,
            Catalog.Text (Adash.Commands.Message (Item),
                          Adash.Commands.Arguments (Item),
                          Adash.Commands.Detail (Item),
                          Adash.Commands.Detail_Placeholder (Item)),
            Adash.Terminal.Role_Plain, Stdout_Is_Terminal);
      end Write;

      Output_To : aliased Console;

      --  What `source` runs a script with. It shares this run's session,
      --  loading chain and diagnostics, so a sourced file is loaded exactly as
      --  the outermost one was -- and a file that sources itself closes a
      --  cycle the chain can see.
      Sourcing : aliased Adash.Scripting.Runner
        (Session => Session'Unchecked_Access,
         Context => Context'Unchecked_Access,
         Report  => Report'Unchecked_Access,
         Output  => Output_To'Unchecked_Access);

   begin
      Adash.Engine.Open (Session);
      Adash.Engine.Use_Script_Runner (Session, Sourcing'Unchecked_Access);

      --  What the script was invoked with. Everything after its path belongs
      --  to it, options included: a script's own `-v` is the script's business
      --  and not this shell's, which is the rule every shell follows and the
      --  reason the option loop below stops at the first name it sees.
      for Index in First_Argument .. CLI.Argument_Count loop
         Adash.Engine.Add_Argument
           (Session, Index - First_Argument + 1, CLI.Argument (Index));
      end loop;

      --  A script gets the user's settings too. A script that ran under the
      --  defaults while an interactive session ran under the configuration
      --  would be two shells, and the difference would be discovered by
      --  whoever tried to debug a script by hand.
      declare
         Chosen : Adash.Configuration.Settings;
         Read   : Adash.Persistence.Outcome;
      begin
         Adash.Configuration.Files.Load (Chosen, Read, Report);
         Adash.Engine.Apply_Settings (Session, Chosen);
      end;

      --  Startup runs for a script too: a script that behaved differently from
      --  an interactive session would be one nobody could debug by hand. The
      --  session file is the exception and knows it.
      Adash.Scripting.Startup.Run_All
        (Session, Interactive => False, Summary => Startup, Report => Report,
         On_Output => Output_To'Unchecked_Access);

      --  Unchecked_Access, and safe for the same reason the engine's command
      --  bridge is: the sink is used only for the duration of this call.
      Adash.Scripting.Run_File (Session, Path, Context, Result, Status, Report,
                                On_Output => Output_To'Unchecked_Access);

      Render_Diagnostics;

      if Result /= Adash.Scripting.Script_Ran then
         --  Could not be read, or did not parse. 127 for a missing file is the
         --  same convention an unstartable program gets.
         return (if Result = Adash.Scripting.Script_Not_Found then 127 else 2);
      end if;

      --  A script that asked to exit says with what.
      if Adash.Engine.Exit_Requested (Session) then
         return Adash.Execution.Numeric (Adash.Engine.Exit_Status (Session));
      end if;

      return Adash.Execution.Numeric (Status);
   end Run_Script;

begin
   --  Auto: style a terminal, leave a pipe alone, and honour NO_COLOR.
   --  Configuration and a command-line switch will feed this once
   --  Adash.Configuration exists; until then the default is the policy.
   Adash.Terminal.Set_Color_Policy (Adash.Terminal.Color_Auto);

   Catalog.Open;

   if not Catalog.Is_Ready then
      --  Reported through the catalog that just failed, which means the
      --  fallback form -- a line naming the key and the path it tried. That
      --  is the honest outcome: the alternative is an English sentence
      --  compiled into this file, which is the one thing no Adash source may
      --  contain.
      Put_Line_Styled
        (IO.Standard_Error,
         Catalog.Text
           (Msg.Msg_Catalog_Unavailable,
            [1 => Msg.Named ("path", Catalog.Path)]),
         Adash.Terminal.Role_Warning,
         Stderr_Is_Terminal);
   end if;

   --  No arguments: an interactive session. The loop owns everything from here
   --  until the user ends it, and gives back the status the process leaves
   --  with.
   if CLI.Argument_Count = 0 then
      declare
         Status : constant Natural := Adash.Interactive.Session.Run (Catalog);
      begin
         Catalog.Close;
         CLI.Set_Exit_Status (CLI.Exit_Status (Status));
         return;
      end;
   end if;

   for Index in 1 .. CLI.Argument_Count loop
      declare
         Argument : constant String := CLI.Argument (Index);
      begin
         if Argument in "--help" | "-h" then
            Report_Usage (IO.Standard_Output, Stdout_Is_Terminal);
            Catalog.Close;
            CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Success));
            return;

         elsif Argument in "--version" | "-V" then
            Report_Version;
            Catalog.Close;
            CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Success));
            return;

         elsif Argument'Length > 0 and then Argument (Argument'First) /= '-' then
            --  Anything that is not an option is a script to run. The engine
            --  does the work; this main only turns its result into an exit
            --  status, which is all a main should ever do.
            declare
               Status : constant Natural := Run_Script (Argument, Index + 1);
            begin
               Catalog.Close;
               CLI.Set_Exit_Status (CLI.Exit_Status (Status));
               return;
            end;

         else
            Put_Line_Styled
              (IO.Standard_Error,
               Catalog.Text
                 (Msg.Msg_Unknown_Option,
                  [1 => Msg.Named ("option", Argument)]),
               Adash.Terminal.Role_Error,
               Stderr_Is_Terminal);
            IO.New_Line (IO.Standard_Error);
            Report_Usage (IO.Standard_Error, Stderr_Is_Terminal);
            Catalog.Close;
            CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Usage));
            return;
         end if;
      end;
   end loop;

   Catalog.Close;
   CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Success));
end Adash_Main;

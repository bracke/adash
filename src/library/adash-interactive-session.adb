with Ada.Characters.Latin_1;
with Ada.Text_IO;

with Adash.Commands;
with Adash.Configuration;
with Adash.Configuration.Files;
with Adash.Diagnostics;
with Adash.Engine;
with Adash.Errors;
with Adash.Execution;
with Adash.Execution.Environment;
with Adash.Execution.Signals;
with Adash.Interactive.Completion;
with Adash.Interactive.Editing;
with Adash.Interactive.History;
with Adash.Interactive.Notifications;
with Adash.Interactive.Prompt;
with Adash.Persistence;
with Ada.Strings.Unbounded;

with Hostkit.Descriptors;
with Hostkit.Locks;
with Hostkit.Terminal_Control;

with Adash.Persistence.History;
with Adash.Scripting.Startup;
with Ada.Strings.Fixed;
with Adash.Source;
with Adash.Terminal;

package body Adash.Interactive.Session is

   package Msg renames Adash.Messages;

   --  What a typed line is called in a diagnostic. Not prose: it is an origin
   --  name, which the diagnostic renderer prints as a location rather than as
   --  a sentence, in the same position a file path would occupy.
   Interactive_Origin : constant String := "-";

   ---------
   -- Run --
   ---------

   --  What a completion question is asked of: a session, and the catalog to
   --  render what its commands produced.
   --
   --  An object handed to the editor rather than a pair of body-level
   --  variables. The editor used to be given an access to a function, which
   --  cannot carry a session with it, so the session had to be left where the
   --  function could find it -- and a second shell in the same process would
   --  have been answered by the first one's. This one is declared beside the
   --  session it speaks for and goes out of scope with it.
   type Session_Knowledge is limited
     new Adash.Interactive.Editing.Candidate_Supplier with record
      Shell   : access Adash.Engine.Session;
      Catalog : access Adash.Messages.Rendering.Catalog;
   end record;

   --  What a user's own subprogram says may follow a program.
   --
   --  Runs the subprogram `complete_with` named, with the word typed so far,
   --  and collects what it printed: one candidate per line, which is what a
   --  subprogram can produce with `put_line` and nothing more exotic.
   --
   --  Quiet about failure on purpose. A completion is a keystroke, and a
   --  diagnostic printed into a line being edited would tear the display apart
   --  to say something about a subprogram the user can run themselves and see.
   overriding function Candidates
     (Supplier : Session_Knowledge;
      Line     : String;
      Cursor   : Positive) return String;

   overriding function Candidates
     (Supplier : Session_Knowledge;
      Line     : String;
      Cursor   : Positive) return String
   is
      Word : Adash.Messages.Argument;

      Program : constant String :=
        Adash.Interactive.Completion.Program_Being_Argued (Line, Cursor, Word);

      Gathered : Ada.Strings.Unbounded.Unbounded_String;

      --  A sink that keeps what the subprogram printed instead of showing it.
      --
      --  Rendered through the catalog, like the console does, because what a
      --  command produces is an identifier and its arguments rather than text
      --  -- and a candidate has to be the text a user would have seen.
      type Collector is limited new Adash.Engine.Output_Sink with null record;

      overriding procedure Write
        (Sink : in out Collector; Item : Adash.Commands.Line);

      overriding procedure Write
        (Sink : in out Collector; Item : Adash.Commands.Line)
      is
         pragma Unreferenced (Sink);
      begin
         Ada.Strings.Unbounded.Append
           (Gathered,
            Supplier.Catalog.Text (Adash.Commands.Message (Item),
                                 Adash.Commands.Arguments (Item),
                                 Adash.Commands.Detail (Item),
                                 Adash.Commands.Detail_Placeholder (Item))
            & Ada.Characters.Latin_1.LF);
      end Write;

      Keeping : aliased Collector;

   begin
      if Supplier.Shell = null or else Supplier.Catalog = null
        or else Program = ""
      then
         return "";
      end if;

      declare
         Handler : constant String :=
           Adash.Engine.Completion_For (Supplier.Shell.all, Program);
      begin
         if Handler = "" then
            return "";
         end if;

         declare
            Quiet   : Adash.Diagnostics.List;
            Outcome : Adash.Engine.Result;

            --  How long a keystroke may take.
            --
            --  A completion runs inside the editor, which is where the user is
            --  typing: a handler that loops would not be a slow completion, it
            --  would be a shell that had stopped. Half a second is longer than
            --  any answer worth waiting for and short enough that a user who
            --  hits it presses Tab again rather than wondering.
            Patience : constant Duration := 0.5;

            --  Asked for from another task, because the submission is what
            --  would have to notice -- and it is this task that is inside it.
            --  The engine's token is protected, which is what makes that safe.
            task type Stopwatch is
               entry Done;
            end Stopwatch;

            task body Stopwatch is
            begin
               select
                  accept Done;
               or
                  delay Patience;
                  Adash.Engine.Request_Cancellation (Supplier.Shell.all);
                  accept Done;
               end select;
            end Stopwatch;
         begin
            declare
               Watching : Stopwatch;
            begin
               --  Submitted as a call with the word so far, which is what a
               --  subprogram asked "what may follow this" needs to know.
               Adash.Engine.Submit
                 (Supplier.Shell.all,
                  Handler & " (""" & Adash.Messages.Value (Word) & """);",
                  Name      => "complete_with",
                  Kind      => Adash.Source.Origin_Interactive,
                  Outcome   => Outcome,
                  Report    => Quiet,
                  On_Output => Keeping'Unchecked_Access);

               Watching.Done;
            end;

            --  Cleared whether or not the stopwatch fired, so the next line a
            --  user types is not stopped by a completion. A Ctrl-C pressed
            --  while a handler was running is lost with it, which is the right
            --  way round: the user was interrupting the completion.
            Adash.Engine.Clear_Cancellation (Supplier.Shell.all);
         end;
      end;

      return Ada.Strings.Unbounded.To_String (Gathered);
   end Candidates;
   function Run (Catalog : in out Adash.Messages.Rendering.Catalog)
                 return Natural
   is
      --  Aliased because the runner `source` uses points at them: a sourced
      --  file runs in this session, and its diagnostics are this session's.
      Shell   : aliased Adash.Engine.Session;
      Recall  : Adash.Interactive.History.Log;
      Waiting : Adash.Interactive.Notifications.Queue;

      Report  : aliased Adash.Diagnostics.List;

      --  The chain that sees a file sourcing itself. One per session rather
      --  than one per submission: a cycle is about the files, and the chain is
      --  empty again by the time a submission ends.
      Loading : aliased Adash.Scripting.Loading;
      Startup : Adash.Scripting.Startup.Report_Summary;

      Last_Failed : Boolean := False;

      --  What has been typed of a construct that is not finished yet, empty
      --  between submissions. A user types `if C then` and goes on; until this
      --  existed each line was a submission of its own, so the two halves of
      --  one construct were two programs and neither was what was meant.
      Pending : Ada.Strings.Unbounded.Unbounded_String;

      Chosen : Adash.Configuration.Settings := Adash.Configuration.Defaults;

      --  Read once, at the start, and held. Asking the settings on every line
      --  would make a configuration change take effect halfway through a
      --  session, which is a shell that behaves differently at the top and the
      --  bottom of one screen.
      Recording : Boolean := True;

      --  Where this session's lines are written as they are typed. The shared
      --  file when history is per-user, and a file of this session's own when
      --  it is not -- see Merge_Session_History for why that is worth doing.
      Writing_To : Ada.Strings.Unbounded.Unbounded_String;

      Per_Session : Boolean := False;

      --  Held for as long as this session runs, so that another shell sweeping
      --  the data store can tell a live session's file from an abandoned one.
      Owned : Hostkit.Locks.Lock;
      Editing_Allowed : Boolean := True;
      Recall_Limit : Positive := 1_000;

      --  Whether a leading space means "do not remember this line".
      Honouring_The_Mark : Boolean := True;

      --  Said once per session, not once per line.
      Reported_Write_Failure : Boolean := False;

      --  Whether the line now running went into the log. What `forget` needs
      --  in order to take itself out without taking one line too many: a
      --  marked line, a blank one, or a repeat of the line before it is not
      --  there to remove.
      This_Line_Recorded : Boolean := False;

      --  Whether a person is typing. A session fed a script on its input ends
      --  at a failing command when the setting asks for it; one with somebody
      --  at a keyboard does not.
      Reading_From_A_Terminal : constant Boolean :=
        Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Input);

      --  Set when that happened, and the status it happened with.
      Stopped_By_A_Failure : Boolean := False;
      Failing_Status : Adash.Execution.Exit_Status := Adash.Execution.Success;

      Stdout_Is_Terminal : constant Boolean :=
        Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Output);
      Stderr_Is_Terminal : constant Boolean :=
        Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Error);

      function Prompt_Text (Kind : Adash.Interactive.Prompt.Prompt_Kind)
                            return String;
      function Prompt_Width (Kind : Adash.Interactive.Prompt.Prompt_Kind)
                             return Natural;
      procedure Render_Diagnostics;
      procedure Deliver_Notices;

      --  Build the prompt twice: once decorated for the screen, once bare to
      --  be measured. Measuring the decorated form would count escape bytes as
      --  cells and put the cursor in the wrong place on every styled prompt.
      function Prompt_Body
        (Kind    : Adash.Interactive.Prompt.Prompt_Kind;
         Decorate : Boolean) return String;

      -----------------
      -- Prompt_Body --
      -----------------

      function Prompt_Body
        (Kind    : Adash.Interactive.Prompt.Prompt_Kind;
         Decorate : Boolean) return String
      is
         Model : constant Adash.Interactive.Prompt.Model :=
           Adash.Interactive.Prompt.Build (Shell, Kind, Last_Failed);

         Result : String (1 .. 512);
         Length : Natural := 0;

         procedure Append (Item : String);

         procedure Append (Item : String) is
            Room : constant Natural :=
              Natural'Min (Item'Length, Result'Length - Length);
         begin
            if Room > 0 then
               Result (Length + 1 .. Length + Room) :=
                 Item (Item'First .. Item'First + Room - 1);
               Length := Length + Room;
            end if;
         end Append;

      begin
         for Index in 1 .. Model.Count loop
            declare
               Part : constant Adash.Interactive.Prompt.Element :=
                 Model.Elements (Index);

               --  An element whose text is a message comes from the catalog;
               --  everything else the prompt knows for itself.
               Plain : constant String :=
                 (case Part.Kind is
                     when Adash.Interactive.Prompt.Element_Message
                        | Adash.Interactive.Prompt.Element_Status =>
                        Catalog.Text (Part.Message),
                     when others =>
                        Adash.Interactive.Prompt.Text_Of (Part));
            begin
               if Plain'Length > 0 then
                  if Decorate then
                     Append (Adash.Terminal.Styled
                               (Plain, Part.Role, Stdout_Is_Terminal));
                  else
                     Append (Plain);
                  end if;

                  --  One blank between parts, so the line the user types does
                  --  not begin against the prompt -- unless the parts came
                  --  from a format somebody wrote, where the spacing is
                  --  theirs and a blank the shell added would be a space they
                  --  cannot remove.
                  if not Model.Joined then
                     Append (" ");
                  end if;
               end if;
            end;
         end loop;

         return Result (1 .. Length);
      end Prompt_Body;

      -----------------
      -- Prompt_Text --
      -----------------

      function Prompt_Text (Kind : Adash.Interactive.Prompt.Prompt_Kind)
                            return String
      is
      begin
         return Prompt_Body (Kind, Decorate => True);
      end Prompt_Text;

      ------------------
      -- Prompt_Width --
      ------------------

      function Prompt_Width (Kind : Adash.Interactive.Prompt.Prompt_Kind)
                             return Natural
      is
         Plain : constant String := Prompt_Body (Kind, Decorate => False);
         Count : Natural := 0;
      begin
         --  Characters, not bytes: a prompt with a non-ASCII character in it
         --  occupies fewer cells than it has bytes.
         for Index in Plain'Range loop
            if Character'Pos (Plain (Index)) not in 16#80# .. 16#BF# then
               Count := Count + 1;
            end if;
         end loop;

         return Count;
      end Prompt_Width;

      -------------------------
      -- Render_Diagnostics --
      -------------------------

      procedure Render_Diagnostics is
         use Ada.Text_IO;

         --  A number as a person writes one, without the space Ada's Image
         --  puts where a sign would go.
         function Counted (Value : Natural) return String
         is (Ada.Strings.Fixed.Trim
               (Natural'Image (Value), Ada.Strings.Both));
      begin
         Report.Sort;

         for Index in 1 .. Report.Count loop
            declare
               Item : constant Adash.Diagnostics.Diagnostic :=
                 Report.Element (Index);
               Role : constant Adash.Terminal.Style_Role :=
                 (case Adash.Diagnostics.Level (Item) is
                     when Adash.Diagnostics.Severity_Note    =>
                        Adash.Terminal.Role_Muted,
                     when Adash.Diagnostics.Severity_Warning =>
                        Adash.Terminal.Role_Warning,
                     when others                             =>
                        Adash.Terminal.Role_Error);
               Said : constant String :=
                 (if Adash.Diagnostics.Detail_Key (Item) = ""
                  then Catalog.Text
                         (Adash.Diagnostics.Message (Item),
                          Adash.Diagnostics.Arguments (Item),
                          Adash.Diagnostics.Detail (Item),
                          Adash.Diagnostics.Detail_Placeholder (Item),
                          Adash.Diagnostics.Detail_Arguments (Item))

                  --  A quoted message that is not one of Adash's own, named
                  --  by key because the library that answered with it is
                  --  below the boundary that renders.
                  else Catalog.Text
                         (Adash.Diagnostics.Message (Item),
                          Adash.Diagnostics.Arguments (Item),
                          Adash.Diagnostics.Detail_Key (Item),
                          Adash.Diagnostics.Detail_Placeholder (Item),
                          Adash.Diagnostics.Detail_Arguments (Item)));

               --  Where to find it, in front of what it says -- but only for a
               --  file, which at a prompt means one a `source` brought in. The
               --  line the user just typed is on the screen above; a position
               --  in front of it would point at itself.
               From : constant Adash.Source.Origin :=
                 Adash.Diagnostics.Origin (Item);

               Place : constant Adash.Source.Location :=
                 Adash.Diagnostics.Position (Item);

               --  Only where there is a position to give. A file that
               --  could not be read at all, or a failure with no place in the
               --  text, has none -- and `path:1:1:` in front of it would be a
               --  position pointing at nothing.
               Known : constant Boolean :=
                 Adash.Source."=" (Adash.Source.Kind (From),
                                   Adash.Source.Origin_File)
                 and then Adash.Source.Name (From) /= ""
                 and then not Adash.Source.Is_Empty
                                (Adash.Diagnostics.Extent (Item));
            begin
               Put_Line
                 (Standard_Error,
                  Adash.Terminal.Styled
                    ((if Known
                      then Catalog.Text
                             (Adash.Messages.Msg_Line_Diagnostic_At,
                              [Adash.Messages.Named
                                 ("path", Adash.Source.Name (From)),
                               Adash.Messages.Named
                                 ("line", Counted (Place.Line)),
                               Adash.Messages.Named
                                 ("column", Counted (Place.Column)),
                               Adash.Messages.Named ("text", Said)])
                      else Said),
                     Role, Stderr_Is_Terminal));

               --  The line itself, and a caret under what it is about. Only
               --  for a file: a line typed here is on the screen above, and
               --  quoting it back would say the same thing twice.
               if Known
                 and then Adash.Diagnostics.Quoted_Line (Item) /= ""
               then
                  Put_Line
                    (Standard_Error,
                     Adash.Terminal.Styled
                       (Adash.Diagnostics.Quoted_Line (Item),
                        Adash.Terminal.Role_Muted, Stderr_Is_Terminal));
                  Put_Line
                    (Standard_Error,
                     Adash.Terminal.Styled
                       (Adash.Diagnostics.Caret (Item),
                        Adash.Terminal.Role_Muted, Stderr_Is_Terminal));
               end if;

               --  What else it is about, for the places that have a file to
               --  name: the earlier declaration behind "already declared", and
               --  anything else a subsystem thought a reader should be sent
               --  to.
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
                        Put_Line
                          (Standard_Error,
                           Adash.Terminal.Styled
                             (Catalog.Text
                                (Adash.Messages.Msg_Line_Diagnostic_At,
                                 [Adash.Messages.Named
                                    ("path",
                                     Adash.Source.Name (Beside.Origin)),
                                  Adash.Messages.Named
                                    ("line", Counted (Beside.Place.Line)),
                                  Adash.Messages.Named
                                    ("column", Counted (Beside.Place.Column)),
                                  Adash.Messages.Named
                                    ("text", Catalog.Text (Beside.Message))]),
                              Adash.Terminal.Role_Muted, Stderr_Is_Terminal));
                     end if;
                  end;
               end loop;
            end;
         end loop;

         --  Cleared between submissions, unlike the script path: a line typed
         --  now must not reprint the complaint about the line before it.
         Report.Clear;
      end Render_Diagnostics;

      ------------------------------------------------------------------
      --  Command output, rendered as the command produces it.
      --
      --  Not once the submission has finished, which is what it used to be. A
      --  program writes to standard output as the machine runs it, so a line
      --  held back arrives after text that was written later:
      --  `pwd; put_line ("after");` printed `after` first.
      ------------------------------------------------------------------
      type Console is limited new Adash.Engine.Output_Sink with null record;

      overriding procedure Write
        (Sink : in out Console; Item : Adash.Commands.Line);

      overriding procedure Write
        (Sink : in out Console; Item : Adash.Commands.Line)
      is
         pragma Unreferenced (Sink);
         use Ada.Text_IO;
      begin
         Put_Line
           (Standard_Output,
            Adash.Terminal.Styled
              (Catalog.Text (Adash.Commands.Message (Item),
                             Adash.Commands.Arguments (Item),
                             Adash.Commands.Detail (Item),
                             Adash.Commands.Detail_Placeholder (Item)),
               Adash.Terminal.Role_Plain, Stdout_Is_Terminal));
      end Write;

      Output_To : aliased Console;

      --  What `history` reports. The log is the session's own; this is the
      --  shape the command layer can see it through.
      type Typed_Lines is limited new Adash.Commands.History_Source
        with null record;

      overriding function Recorded (Source : Typed_Lines) return Natural;

      overriding function Recorded_Line
        (Source : Typed_Lines; Index : Positive) return String;

      overriding procedure Forget_Recent
        (Source    : in out Typed_Lines;
         Count     : Positive;
         Forgotten : out Natural;
         Failed    : out Boolean);

      overriding procedure Forget_Line
        (Source    : in out Typed_Lines;
         Text      : String;
         Forgotten : out Natural;
         Failed    : out Boolean);

      overriding function Recorded (Source : Typed_Lines) return Natural is
         pragma Unreferenced (Source);
      begin
         return Adash.Interactive.History.Count (Recall);
      end Recorded;

      overriding function Recorded_Line
        (Source : Typed_Lines; Index : Positive) return String
      is
         pragma Unreferenced (Source);
      begin
         return Adash.Interactive.History.Entry_At (Recall, Index);
      end Recorded_Line;

      --  Take the newest entries out of the session and out of the file.
      --
      --  The `forget` line itself goes with them: it is the newest entry,
      --  because a command runs immediately after its line is recorded. A
      --  history whose last entry is the command that emptied it has kept a
      --  record of the act.
      overriding procedure Forget_Recent
        (Source    : in out Typed_Lines;
         Count     : Positive;
         Forgotten : out Natural;
         Failed    : out Boolean)
      is
         pragma Unreferenced (Source);

         --  Nothing when this line was not recorded at all -- marked with a
         --  space, blank, or the same as the one before it. Removing an entry
         --  for a line that never made one would take a line the user did not
         --  ask about.
         Mine : constant Natural := (if This_Line_Recorded then 1 else 0);

         Held   : constant Natural := Adash.Interactive.History.Count (Recall);
         Taking : constant Natural := Natural'Min (Count + Mine, Held);

         --  What to take out of the file, carried as text rather than as
         --  positions: the shared file holds what several sessions wrote,
         --  interleaved, so the third line from its end is not this session's
         --  third line from the end.
         Going : Adash.Persistence.History.Log;

         Removed : Natural;
      begin
         Failed := False;

         for Index in Held - Taking + 1 .. Held loop
            Adash.Persistence.History.Add
              (Going, Adash.Interactive.History.Entry_At (Recall, Index));
         end loop;

         Adash.Interactive.History.Forget_Last (Recall, Taking, Removed);

         --  The user's own lines, not counting this one: they asked to forget
         --  two and `forget (2);` making three would read as one too many.
         Forgotten := Removed - Natural'Min (Removed, Mine);

         if not Recording then
            return;
         end if;

         declare
            Shared : constant String := Adash.Persistence.History.Path;
            Mine_File : constant String :=
              Ada.Strings.Unbounded.To_String (Writing_To);

            procedure Take_From (File : String);

            procedure Take_From (File : String) is
               Result : Adash.Persistence.Outcome;
               Taken  : Natural;

               use type Adash.Persistence.Outcome;
            begin
               Adash.Persistence.History.Forget (Going, Result, Taken, File);

               --  Absent is a file this session has not written yet, and
               --  Unavailable is a host with no data store: neither is a
               --  secret left on disk, which is what Failed is for.
               if Result /= Adash.Persistence.Store_Ok
                 and then Result /= Adash.Persistence.Store_Absent
                 and then Result /= Adash.Persistence.Store_Unavailable
               then
                  Failed := True;
               end if;
            end Take_From;
         begin
            Take_From (Mine_File);

            --  What this session's own file did not hold was typed in an
            --  earlier session and read in from the shared one at start-up.
            --  Adash.Persistence.History.Forget leaves exactly those behind,
            --  so this asks about them and nothing else.
            if Mine_File /= Shared
              and then Adash.Persistence.History.Count (Going) > 0
            then
               Take_From (Shared);
            end if;
         end;
      end Forget_Recent;

      --  Take out every entry that is exactly this line, here and on disk.
      --
      --  It reaches further than a count does. A count can only take what this
      --  session's log holds, which is the last history.limit entries of the
      --  file and no more; a line named by its text is taken out of the files
      --  whether or not this session ever read it back. That is the whole
      --  reason for the second form: a secret typed a thousand lines ago is
      --  exactly the one a count cannot get to.
      overriding procedure Forget_Line
        (Source    : in out Typed_Lines;
         Text      : String;
         Forgotten : out Natural;
         Failed    : out Boolean)
      is
         pragma Unreferenced (Source);

         --  What was asked for, and separately this command's own line -- the
         --  `forget` line carries the text as its argument, so leaving it
         --  would leave the secret in the history under a different spelling.
         --  Kept apart because the count reported is what the user asked to be
         --  rid of and not the asking.
         Asked_For : Adash.Persistence.History.Log;
         This_Line : Adash.Persistence.History.Log;

         Mine : constant String :=
           (if This_Line_Recorded
            then Adash.Interactive.History.Most_Recent (Recall) else "");

         Removed : Natural;

         Shared : constant String := Adash.Persistence.History.Path;

         Mine_File : constant String :=
           Ada.Strings.Unbounded.To_String (Writing_To);

         --  Take a list out of one file, saying how many it gave up. The list
         --  is copied per file rather than carried: the same text can be in
         --  both, written on different days, and each is asked about all of
         --  it.
         procedure Take_From
           (File : String;
            What : Adash.Persistence.History.Log;
            Gave : out Natural);

         procedure Take_From
           (File : String;
            What : Adash.Persistence.History.Log;
            Gave : out Natural)
         is
            Asking : Adash.Persistence.History.Log := What;
            Result : Adash.Persistence.Outcome;

            use type Adash.Persistence.Outcome;
         begin
            Adash.Persistence.History.Forget
              (Asking, Result, Gave, File, Every => True);

            if Result /= Adash.Persistence.Store_Ok
              and then Result /= Adash.Persistence.Store_Absent
              and then Result /= Adash.Persistence.Store_Unavailable
            then
               Failed := True;
            end if;
         end Take_From;
      begin
         Failed := False;

         Adash.Interactive.History.Forget_Matching (Recall, Text, Removed);

         --  What the session gave up, to be compared with what the files did
         --  rather than added to it: the file holds what the log holds, so a
         --  line taken out of both is one entry forgotten and not two.
         Forgotten := Removed;

         Adash.Persistence.History.Add (Asked_For, Text);

         if Mine /= "" and then Mine /= Text then
            declare
               Ignored : Natural;
            begin
               Adash.Interactive.History.Forget_Matching (Recall, Mine, Ignored);
               Adash.Persistence.History.Add (This_Line, Mine);
            end;
         end if;

         if not Recording then
            return;
         end if;

         declare
            Gave       : Natural;
            From_Files : Natural := 0;
         begin
            Take_From (Mine_File, Asked_For, Gave);
            From_Files := From_Files + Gave;

            Take_From (Mine_File, This_Line, Gave);

            if Mine_File /= Shared then
               Take_From (Shared, Asked_For, Gave);
               From_Files := From_Files + Gave;

               Take_From (Shared, This_Line, Gave);
            end if;

            --  The larger of the two, because they are the same entries seen
            --  twice -- except where they are not: a line older than the log's
            --  limit is in the file and was never in the session, and that is
            --  exactly the line a count could not reach. Reporting nothing for
            --  it would say the command had done nothing.
            Forgotten := Natural'Max (Forgotten, From_Files);
         end;
      end Forget_Line;

      Reporting : aliased Typed_Lines;

      --  What `source` runs a script with: this session, this session's
      --  diagnostics, and the one loading chain that can see a cycle.
      Sourcing : aliased Adash.Scripting.Runner
        (Session => Shell'Unchecked_Access,
         Context => Loading'Unchecked_Access,
         Report  => Report'Unchecked_Access,
         Output  => Output_To'Unchecked_Access);

      --  Declared ahead of the sweep that calls it, which is written first
      --  because it is the one the session start reaches.
      procedure Merge_History_File (Mine : String);

      ---------------------------------
      -- Sweep_Abandoned_History --
      ---------------------------------

      --  Fold the history of sessions that died before merging into the shared
      --  file, and remove what they left.
      --
      --  A file is abandoned when its ownership lock can be taken: the session
      --  that made it holds that lock from start to finish, so a lock that is
      --  free means nobody is there. Trying the lock rather than reasoning from
      --  the process id in the name matters -- ids are reused, and a sweep that
      --  believed the number would eventually take a running shell's history.
      procedure Sweep_Abandoned_History is
         Files : Adash.Persistence.History.Path_List;
         Count : Natural;
      begin
         Adash.Persistence.History.Abandoned_Session_Files (Files, Count);

         for Index in 1 .. Count loop
            declare
               Left : constant String :=
                 Ada.Strings.Unbounded.To_String (Files (Index));

               Claim : Hostkit.Locks.Lock;

               Taken : constant Hostkit.Locks.Lock_Outcome :=
                 Hostkit.Locks.Acquire
                   (Adash.Persistence.History.Owner_Lock_Path (Left),
                    Hostkit.Locks.Lock_Exclusive, Wait => False, Item => Claim);

               use type Hostkit.Locks.Lock_Outcome;
            begin
               --  Lock_Busy means that session is still running. Anything else
               --  that is not Lock_Ok means this host cannot tell, and a sweep
               --  that guessed would take a live session's history: left alone
               --  is the answer for both.
               if Taken = Hostkit.Locks.Lock_Ok then
                  Merge_History_File (Left);
                  Hostkit.Locks.Release (Claim);

                  declare
                     Gone_Owner : Adash.Persistence.Outcome;
                  begin
                     Adash.Persistence.Remove
                       (Adash.Persistence.History.Owner_Lock_Path (Left),
                        Gone_Owner);
                  end;
               end if;
            end;
         end loop;
      end Sweep_Abandoned_History;

      ---------------------------
      -- Merge_History_File --
      ---------------------------

      --  Append one history file's entries to the shared one and remove it.
      procedure Merge_History_File (Mine : String) is
         Stored : Adash.Persistence.History.Log;
         Result : Adash.Persistence.Outcome;
      begin
         Adash.Persistence.History.Load
           (Stored, Result, Recall_Limit, From => Mine);

         if Adash.Persistence.Succeeded (Result) then
            for Index in 1 .. Adash.Persistence.History.Count (Stored) loop
               declare
                  Written : Adash.Persistence.Outcome;
               begin
                  Adash.Persistence.History.Append
                    (Adash.Persistence.History.Entry_At (Stored, Index),
                     Written, Adash.Persistence.History.Path);
               end;
            end loop;
         end if;

         --  Removed whether or not the merge worked. A file left after a failed
         --  merge would be merged again by nothing and read by nothing, and
         --  keeping it would grow the data store a session at a time.
         declare
            --  Two outcomes, neither read. Removal is best effort: a file that
            --  will not go is untidy and not worth a diagnostic.
            Gone_File : Adash.Persistence.Outcome;
            Gone_Lock : Adash.Persistence.Outcome;
         begin
            Adash.Persistence.Remove (Mine, Gone_File);
            Adash.Persistence.Remove (Mine & ".lock", Gone_Lock);
         end;
      end Merge_History_File;

      -----------------------------
      -- Merge_Session_History --
      -----------------------------

      --  Fold this session's own history file into the shared one and remove
      --  it.
      --
      --  Done once, at the end, rather than line by line during the session.
      --  Two shells appending to one file a line at a time leave their commands
      --  shuffled together there, which is not what either user did and not
      --  something either can read back afterwards. Written this way the shared
      --  file holds each session's run in one piece.
      --
      --  A session that dies before reaching here leaves its file behind, and
      --  the next shell to start sweeps it up.
      procedure Merge_Session_History is
         Mine : constant String :=
           Ada.Strings.Unbounded.To_String (Writing_To);
      begin
         if not Per_Session or else Mine = ""
           or else Mine = Adash.Persistence.History.Path
         then
            --  Nothing of its own to merge. The second test matters on a host
            --  that would not say which process this is: Session_Path falls
            --  back to the shared file there, and merging a file into itself
            --  would double it.
            return;
         end if;

         Merge_History_File (Mine);

         --  Released after the merge, not before: until the file is gone this
         --  session still owns the name, and a sweep in another shell must go
         --  on seeing it as live.
         Hostkit.Locks.Release (Owned);

         declare
            Gone_Owner : Adash.Persistence.Outcome;
         begin
            Adash.Persistence.Remove
              (Adash.Persistence.History.Owner_Lock_Path (Mine), Gone_Owner);
         end;
      end Merge_Session_History;

      ----------------------
      -- Deliver_Notices --
      ----------------------

      procedure Deliver_Notices is
         use Ada.Text_IO;
         Item : Adash.Interactive.Notifications.Notice;
      begin
         --  The quiescent point: a submission has finished and no line is
         --  being edited, so nothing on screen is half-written.
         while Waiting.Ready (Editing => False)
           and then Waiting.Take (Item)
         loop
            Put_Line
              (Standard_Error,
               Adash.Terminal.Styled
                 (Catalog.Text (Item.Message,
                                Item.Arguments (1 .. Item.Count)),
                  Item.Role, Stderr_Is_Terminal));
         end loop;
      end Deliver_Notices;

      Typed : String (1 .. Adash.Interactive.Editing.Max_Line);
      Last  : Natural;

      --  What Tab asks when it wants what a user taught it. Declared with the
      --  session, so there is no moment at which it names one that has gone.
      Knowing : aliased Session_Knowledge :=
        (Shell   => Shell'Unchecked_Access,
         Catalog => Catalog'Unchecked_Access);

      use type Adash.Persistence.Outcome;

   begin
      Adash.Engine.Open (Shell);
      Adash.Engine.Use_Script_Runner (Shell, Sourcing'Unchecked_Access);

      Adash.Engine.Use_History (Shell, Reporting'Unchecked_Access);

      --  The shell takes its signal dispositions before it runs anything.
      --
      --  Adash.Execution.Signals has existed since Phase 11 and nothing called
      --  it, so until now the shell ran with the host's defaults: Ctrl-C killed
      --  it outright, and a truncated pipeline would have taken it down with
      --  SIGPIPE. An interactive session is exactly where that matters.
      --
      --  A host that will not give them is reported and the session continues.
      --  Refusing to start would leave the user without a shell over something
      --  they can neither see nor fix.
      declare
         Taken : constant Adash.Errors.Error_Info :=
           Adash.Execution.Signals.Install;
      begin
         if Adash.Errors.Is_Failure (Taken) then
            Report.Emit
              (Adash.Diagnostics.From_Error
                 (Taken,
                  Level     => Adash.Diagnostics.Severity_Warning,
                  Of_Kind   => Adash.Diagnostics.Category_Execution,
                  Raised_By => Adash.Diagnostics.Owner_Execution));
         end if;
      end;

      --  Configuration first, before anything reads a setting. Its diagnostics
      --  go out with the startup files' rather than separately: a user whose
      --  file is wrong wants both complaints at the same moment, not one now
      --  and one when the shell next does something that depends on it.
      declare
         Read_Result : Adash.Persistence.Outcome;
      begin
         Adash.Configuration.Files.Load (Chosen, Read_Result, Report);
      end;

      Adash.Engine.Apply_Settings (Shell, Chosen);

      Recording := Adash.Configuration.Boolean_Value
        (Chosen, Adash.Configuration.History_Enabled_Setting);
      Editing_Allowed := Adash.Configuration.Boolean_Value
        (Chosen, Adash.Configuration.Editing_Setting);
      Recall_Limit := Positive
        (Adash.Configuration.Integer_Value
           (Chosen, Adash.Configuration.History_Limit_Setting));
      Per_Session := Adash.Configuration.Boolean_Value
        (Chosen, Adash.Configuration.History_Per_Session_Setting);
      Honouring_The_Mark := Adash.Configuration.Boolean_Value
        (Chosen, Adash.Configuration.History_Ignore_Space_Setting);

      Writing_To := Ada.Strings.Unbounded.To_Unbounded_String
        (if Per_Session then Adash.Persistence.History.Session_Path
         else Adash.Persistence.History.Path);

      if Per_Session then
         declare
            Mine : constant String :=
              Ada.Strings.Unbounded.To_String (Writing_To);

            --  The store may not exist yet -- a first session on a new machine
            --  -- and a lock does not create it: locking is not writing, and
            --  the file being locked may never be written. Without this the
            --  claim below fails on a fresh store, every time.
            Ready : constant Boolean :=
              Adash.Persistence.Ensure_Container (Mine);

            Taken : constant Hostkit.Locks.Lock_Outcome :=
              (if Ready
               then Hostkit.Locks.Acquire
                      (Adash.Persistence.History.Owner_Lock_Path (Mine),
                       Hostkit.Locks.Lock_Exclusive, Wait => False,
                       Item => Owned)
               else Hostkit.Locks.Lock_Error);

            use type Hostkit.Locks.Lock_Outcome;
         begin
            --  Only an actually held lock will do. Anything else -- another
            --  live session on a reused process id, a store that will not take
            --  locks, a directory that could not be made -- leaves this session
            --  unable to say "this file is mine", and a session file nobody
            --  claims is one the next sweep takes away while it is still being
            --  written. The shared file is the safe answer.
            if Taken /= Hostkit.Locks.Lock_Ok then
               Per_Session := False;
               Writing_To := Ada.Strings.Unbounded.To_Unbounded_String
                 (Adash.Persistence.History.Path);
            end if;
         end;
      end if;

      if Per_Session then
         Sweep_Abandoned_History;
      end if;

      Adash.Interactive.History.Set_Limit (Recall, Recall_Limit);

      --  Whatever the colour policy says, before the first prompt is drawn.
      --  The words come from the schema, which is what validated them, so an
      --  unrecognised one cannot reach here -- and the fallback is Auto rather
      --  than an exception, because refusing to start over a colour setting
      --  would be absurd.
      declare
         Word : constant String :=
           Adash.Configuration.Choice_Value
             (Chosen, Adash.Configuration.Color_Setting);
      begin
         if Word = "always" then
            Adash.Terminal.Set_Color_Policy (Adash.Terminal.Color_Always);
         elsif Word = "never" then
            Adash.Terminal.Set_Color_Policy (Adash.Terminal.Color_Never);
         else
            Adash.Terminal.Set_Color_Policy (Adash.Terminal.Color_Auto);
         end if;
      end;

      --  Then what was typed in earlier sessions. A shell whose history began
      --  when it started would be one where recall is useful only after you
      --  have already typed the thing you wanted to recall.
      if Recording then
         declare
            Stored : Adash.Persistence.History.Log;
            Result : Adash.Persistence.Outcome;
         begin
            Adash.Persistence.History.Load (Stored, Result, Recall_Limit);

            if Result = Adash.Persistence.Store_Ok then
               for Index in 1 .. Adash.Persistence.History.Count (Stored) loop
                  Adash.Interactive.History.Record_Line
                    (Recall,
                     Adash.Persistence.History.Entry_At (Stored, Index));
               end loop;

               if Adash.Persistence.History.Skipped (Stored) > 0 then
                  --  One skipped line is a session that ended badly; hundreds
                  --  is a file that has been overwritten by something else,
                  --  and the user would want to know either way.
                  Waiting.Post
                    (Adash.Interactive.Notifications.Session_Change,
                     Msg.Msg_History_Damaged_Lines,
                     [Msg.Named ("path", Adash.Persistence.History.Path),
                      Msg.Named
                        ("detail",
                         Long_Long_Integer (Adash.Persistence.History.Skipped (Stored)))],
                     Adash.Terminal.Role_Warning);
               end if;

            elsif Result /= Adash.Persistence.Store_Absent
              and then Result /= Adash.Persistence.Store_Unavailable
            then
               Waiting.Post
                 (Adash.Interactive.Notifications.Session_Change,
                  Msg.Msg_History_Unreadable,
                  [1 => Msg.Named ("path", Adash.Persistence.History.Path)],
                  Adash.Terminal.Role_Warning);
            end if;
         end;
      end if;

      --  Startup runs before the first prompt, and its diagnostics are shown
      --  before it too: a user whose configuration is broken needs to know at
      --  the moment it failed, not the first time something behaves oddly.
      Adash.Scripting.Startup.Run_All
        (Shell, Interactive => True, Summary => Startup, Report => Report,
         On_Output => Output_To'Unchecked_Access);
      Render_Diagnostics;

      --  Said once, at the start, rather than discovered when the arrow keys
      --  start printing letters. Only to someone actually at a terminal:
      --  input from a pipe was never going to be edited, and saying so there
      --  puts a line into output that a script has to filter out.
      if Editing_Allowed
        and then Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Input)
        and then not Adash.Interactive.Editing.Supports_Editing
      then
         Waiting.Post
           (Adash.Interactive.Notifications.Session_Change,
            Msg.Msg_Interactive_Line_Editing_Unavailable,
            Role => Adash.Terminal.Role_Muted);
         Deliver_Notices;
      end if;

      loop
         declare
            --  What has been typed so far of a construct that is not finished.
            --  A user writes `if C then` and means to go on; the shell reads a
            --  line at a time and has to hold what it has until the grammar
            --  says the program is whole.
            Started : constant Boolean :=
              Ada.Strings.Unbounded.Length (Pending) > 0;

            Asking : constant Adash.Interactive.Prompt.Prompt_Kind :=
              (if Started then Adash.Interactive.Prompt.Continuation
               else Adash.Interactive.Prompt.Primary);

            Outcome : constant Adash.Interactive.Editing.Read_Outcome :=
              Adash.Interactive.Editing.Read_Line
                (Prompt       => Prompt_Text (Asking),
                 Prompt_Width => Prompt_Width (Asking),
                 Recall       => Recall,
                 Allow_Editing => Editing_Allowed,

                 --  The session's PATH, not this process's: `set
                 --  ("PATH=...")` changes what a child is started with, and
                 --  Tab has to offer the programs of the path that would run
                 --  them.
                 Search_Path  =>
                   Adash.Execution.Environment.Value
                     (Adash.Engine.Environment (Shell), "PATH"),

                 --  What a user taught Tab, asked through the engine because
                 --  answering means running their subprogram.
                 Ask_Caller   => Knowing'Unchecked_Access,

                 --  What a reverse search shows in place of the prompt. From
                 --  the catalog here rather than inside the editor, which
                 --  renders no messages of its own.
                 Search_Label => Catalog.Text (Adash.Messages.Msg_Line_Search),
                 Search_Empty =>
                   Catalog.Text (Adash.Messages.Msg_Line_Search_Empty),
                 Into         => Typed,
                 Last         => Last);

            --  The whole of what has been typed, which is what is judged,
            --  recorded and submitted. A newline between lines rather than a
            --  space: it keeps a comment from swallowing what follows it, and
            --  it is what the user wrote.
            Line : constant String :=
              (if Started
               then Ada.Strings.Unbounded.To_String (Pending) & Ada.Characters.Latin_1.LF
                    & Typed (Typed'First .. Last)
               else Typed (Typed'First .. Last));

            use type Adash.Interactive.Editing.Read_Outcome;
         begin
            if Outcome = Adash.Interactive.Editing.Input_Ended then
               --  Ended part-way through something. Submitted rather than
               --  dropped, so the user is told the construct was unfinished
               --  instead of watching it disappear.
               if Started then
                  declare
                     Answer : Adash.Engine.Result;
                  begin
                     Adash.Engine.Submit
                       (Shell,
                        Text    => Line,
                        Name    => Interactive_Origin,
                        Kind    => Adash.Source.Origin_Interactive,
                        Outcome => Answer,
                        Report  => Report,
                        On_Output => Output_To'Unchecked_Access);

                     Render_Diagnostics;
                  end;
               end if;

               exit;
            end if;

            if Outcome = Adash.Interactive.Editing.Read_Failed then
               --  The terminal stopped answering. Ending is the honest
               --  response: a loop that kept prompting into a stream it cannot
               --  read would spin without the user being able to stop it.
               Waiting.Post
                 (Adash.Interactive.Notifications.Session_Change,
                  Msg.Msg_Interactive_Read_Failed,
                  Role => Adash.Terminal.Role_Error);
               Deliver_Notices;
               return 2;
            end if;

            --  Held back rather than submitted: the grammar says this could
            --  still be completed, so nothing is recorded, nothing is
            --  analysed, and the next line joins this one.
            if Outcome = Adash.Interactive.Editing.Line_Read
              and then Adash.Engine.Wants_More (Line, Interactive_Origin)
            then
               Pending := Ada.Strings.Unbounded.To_Unbounded_String (Line);
               Deliver_Notices;
               goto Continue;
            end if;

            --  Whole again, however many lines it took.
            Pending := Ada.Strings.Unbounded.Null_Unbounded_String;

            --  Recorded whether it ran or not, and whether it was abandoned or
            --  not. A user recalling the last line usually wants the one they
            --  got wrong -- and recalls the whole of it, because half a
            --  construct is not something anybody can edit into shape.
            --
            --  Unless it was marked. A submission typed with a space in front
            --  of it is not remembered here and, because the write below
            --  happens only when this log took the line, is not written to any
            --  file either. It still runs: the mark says what to forget, not
            --  what to refuse.
            declare
               Marked : constant Boolean :=
                 Honouring_The_Mark
                   and then Adash.Interactive.History.Marked_Sensitive (Line);
            begin
               Adash.Interactive.History.Record_Line
                 (Recall, Line, Marked, This_Line_Recorded);

               --  Written only when the in-memory log actually took it, so the
               --  file gets the same treatment for blanks and consecutive
               --  duplicates as recall does. Two policies would drift, and the
               --  one on disk is the one nobody checks.
               if Recording and then This_Line_Recorded then
                  declare
                     Result : Adash.Persistence.Outcome;
                  begin
                     Adash.Persistence.History.Append
                       (Line, Result,
                        Ada.Strings.Unbounded.To_String (Writing_To));

                     if Result /= Adash.Persistence.Store_Ok
                       and then Result /= Adash.Persistence.Store_Unavailable
                       and then not Reported_Write_Failure
                     then
                        --  Said once per session. A shell that complained on
                        --  every line about a read-only home directory would be
                        --  unusable in exactly the situation where the user has
                        --  the fewest options.
                        Reported_Write_Failure := True;
                        Waiting.Post
                          (Adash.Interactive.Notifications.Session_Change,
                           Msg.Msg_History_Not_Written,
                           [1 => Msg.Named
                                   ("path", Adash.Persistence.History.Path)],
                           Adash.Terminal.Role_Warning);
                     end if;
                  end;
               end if;
            end;

            if Outcome = Adash.Interactive.Editing.Line_Read then
               --  A terminal a runaway loop can be stopped at, in whichever of
               --  the two ways this host allows.
               --
               --  The editor puts back the settings it saved when it took the
               --  line, and what it saved is whatever the terminal happened to
               --  have: a console handed over by a pseudo-console arrives
               --  without the flag that makes an interrupt key an interrupt,
               --  so a runaway loop there could not be stopped by anybody.
               --
               --  Where the host reports an interrupt to a program that is not
               --  reading, asking it to is the whole arrangement and the shell
               --  does nothing further. Where it does not -- Windows, where a
               --  spinning program is never told -- the keystroke still
               --  arrives as a byte at a terminal left raw, so the shell keeps
               --  it raw and looks between instructions instead. Which host
               --  this is is hostkit's answer, not a guess from the platform.
               declare
                  Ignored : Boolean;
               begin
                  if Hostkit.Terminal_Control
                       .Interrupt_Reaches_A_Busy_Program
                  then
                     Ignored :=
                       Hostkit.Terminal_Control.Set_Interruptible
                         (Hostkit.Descriptors.Standard_Input);
                  else
                     --  Watched instead, which leaves the terminal raw for as
                     --  long as the submission runs: a console asked to turn
                     --  Ctrl-C into an interrupt does not put the keystroke
                     --  where anybody can find it, so the shell has to be
                     --  holding the terminal open when the key is pressed
                     --  rather than looking afterwards. Anything the
                     --  submission runs gets the terminal back for its own
                     --  duration.
                     Ignored := True;

                     Adash.Execution.Signals.Watch_Terminal
                       (Hostkit.Descriptors.Standard_Input);
                  end if;
               end;

               declare
                  Answer : Adash.Engine.Result;
                  use type Adash.Engine.Submission_Kind;
               begin
                  --  Unchecked_Access, and safe for the same reason the
                  --  engine's command bridge is: the sink is used only for the
                  --  duration of this call.
                  Adash.Engine.Submit
                    (Shell,
                     Text    => Line,
                     Name    => Interactive_Origin,
                     Kind    => Adash.Source.Origin_Interactive,
                     Outcome => Answer,
                     Report  => Report,
                     On_Output => Output_To'Unchecked_Access);

                  Render_Diagnostics;

                  --  Stopped first, so that nothing between here and the next
                  --  line read takes a byte off the terminal: the editor reads
                  --  it, and a shell reading it behind the editor's back would
                  --  be two readers of one keyboard.
                  Adash.Execution.Signals.Stop_Watching;

                  --  Whether this line was interrupted, asked before the
                  --  acknowledgement below clears the answer.
                  declare
                     Interrupted : constant Boolean :=
                       Adash.Execution.Signals.Interrupt_Pending;
                  begin
                     --  Acknowledged once the submission has ended, whether it
                     --  ended because of the interrupt or in spite of it. An
                     --  interrupt that stays outstanding would stop the next
                     --  line the moment it started, and the user would have no
                     --  way to get a working prompt back.
                     Adash.Execution.Signals.Acknowledge_Interrupt;
                     Adash.Engine.Clear_Cancellation (Shell);

                     --  And what `on_interrupt` asked for.
                     --
                     --  A session is where a user meets this first -- they
                     --  register a handler and then press Ctrl-C at the prompt
                     --  -- and it ran only for scripts, which is the half a
                     --  user meets second. After the acknowledgement, like the
                     --  script path and for the same reason: a handler that
                     --  inherited the pending interrupt would be stopped
                     --  before it could do anything.
                     if Interrupted then
                        for Name of Adash.Engine.Interrupt_Handlers (Shell) loop
                           declare
                              Ran_It : Adash.Engine.Result;
                           begin
                              Adash.Engine.Submit
                                (Shell,
                                 Ada.Strings.Unbounded.To_String (Name) & ";",
                                 Name      => "on_interrupt",
                                 Kind      => Adash.Source.Origin_Interactive,
                                 Outcome   => Ran_It,
                                 Report    => Report,
                                 On_Output => Output_To'Unchecked_Access);
                           end;
                        end loop;

                        Render_Diagnostics;
                     end if;
                  end;

                  --  What `on_failure` asked for, if anything failed in that
                  --  submission. Once for the submission: a loop that fails a
                  --  hundred times is one thing gone wrong.
                  declare
                     Went_Wrong : constant Boolean :=
                       Adash.Engine.Take_Failure (Shell);
                  begin
                     if Went_Wrong then
                        for Name of Adash.Engine.Failure_Handlers (Shell) loop
                           declare
                              Ran_It : Adash.Engine.Result;
                           begin
                              Adash.Engine.Submit
                                (Shell,
                                 Ada.Strings.Unbounded.To_String (Name) & ";",
                                 Name      => "on_failure",
                                 Kind      => Adash.Source.Origin_Interactive,
                                 Outcome   => Ran_It,
                                 Report    => Report,
                                 On_Output => Output_To'Unchecked_Access);
                           end;
                        end loop;

                        Render_Diagnostics;

                        --  A handler that failed is not another thing to
                        --  handle; it says so through its own diagnostics.
                        declare
                           Ignored : constant Boolean :=
                             Adash.Engine.Take_Failure (Shell);
                           pragma Unreferenced (Ignored);
                        begin
                           null;
                        end;
                     end if;
                  end;

                  --  And whatever else arrived while that ran: a `terminate`
                  --  sent by a service manager, a `hangup` from a terminal
                  --  that went away. Asked here rather than delivered, because
                  --  all a signal does is set a flag -- turning flags into
                  --  work is the shell's to do, at a point where running a
                  --  subprogram is safe.
                  declare
                     Due : constant Hostkit.String_Vectors.Vector :=
                       Adash.Engine.Due_Signal_Handlers (Shell);
                  begin
                     for Name of Due loop
                        declare
                           Ran_It : Adash.Engine.Result;
                        begin
                           Adash.Engine.Submit
                             (Shell,
                              Ada.Strings.Unbounded.To_String (Name) & ";",
                              Name      => "on_signal",
                              Kind      => Adash.Source.Origin_Interactive,
                              Outcome   => Ran_It,
                              Report    => Report,
                              On_Output => Output_To'Unchecked_Access);
                        end;
                     end loop;

                     if not Due.Is_Empty then
                        Render_Diagnostics;
                     end if;
                  end;

                  Last_Failed :=
                    Answer.Kind = Adash.Engine.Not_Understood
                      or else (Answer.Ran
                               and then not Adash.Execution.Succeeded
                                              (Answer.Status));

                  --  A failure under stop.on-failure ends a session that is
                  --  reading a script rather than a person.
                  --
                  --  Only when nobody is typing: at a prompt the setting stops
                  --  the submission and the shell reads the next line, because
                  --  a shell that ended the session over a mistyped command is
                  --  a shell nobody could use. Fed a script on its input it is
                  --  the other way round -- carrying on past a failure is what
                  --  the setting was turned on to prevent, and the status has
                  --  to leave with it or a build system reads the zero.
                  if Last_Failed
                    and then not Reading_From_A_Terminal
                    and then Adash.Configuration.Boolean_Value
                               (Adash.Engine.Settings (Shell),
                                Adash.Configuration.Stop_On_Failure_Setting)
                  then
                     Stopped_By_A_Failure := True;
                     Failing_Status := Answer.Status;
                     exit;
                  end if;

                  exit when Adash.Engine.Exit_Requested (Shell);
               end;
            end if;

            Deliver_Notices;

            <<Continue>>
         end;
      end loop;

      --  What `on_exit` asked for, before the history is merged and the
      --  session is over: a cleanup that writes a file should be able to, and
      --  one that types something should have it recorded like anything else.
      declare
         Waiting : constant Hostkit.String_Vectors.Vector :=
           Adash.Engine.Take_Cleanups (Shell);

         Answer : Adash.Engine.Result;
      begin
         for Name of Waiting loop
            Adash.Engine.Submit
              (Shell,
               Text    => Ada.Strings.Unbounded.To_String (Name) & ";",
               Name    => Interactive_Origin,
               Kind    => Adash.Source.Origin_Interactive,
               Outcome => Answer,
               Report  => Report,
               On_Output => Output_To'Unchecked_Access);
         end loop;

         Render_Diagnostics;
      end;

      Merge_Session_History;

      if Adash.Engine.Exit_Requested (Shell) then
         return Adash.Execution.Numeric (Adash.Engine.Exit_Status (Shell));
      end if;

      --  Stopped at a failing command, with the setting that asks for it on.
      if Stopped_By_A_Failure then
         return Adash.Execution.Numeric (Failing_Status);
      end if;

      --  Ended by end of input rather than by asking. That is a successful
      --  session, not a failed one.
      return 0;
   end Run;

end Adash.Interactive.Session;

with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Adash.Configuration;
with Adash.Configuration.Files;
with Adash.Diagnostics;
with Adash.Engine;
with Adash.Errors;
with Adash.Execution.Environment;
with Adash.Interactive.Completion;
with Adash.Interactive.Highlighting;
with Adash.Language.Evaluation;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Semantics;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Persistence.History;
with Adash.Source;
with Adash.Messages;
with Adash.Messages.Rendering;
with Adash.Version;

--  adash_bench: how long the things a session does most often take.
--
--  **A number without a methodology is not a measurement.** Every figure here
--  says what was measured, how many times, and on what -- and the harness
--  reports the *median* of repeated runs rather than the mean, because a mean
--  is moved by the one iteration during which the machine did something else,
--  and that iteration is always present.
--
--  What is measured is chosen from what an interactive session actually
--  repeats. Lexing, parsing and analysing a typed line happens on every line;
--  completion happens on every tab; highlighting happens on every keystroke.
--  Those are the numbers a user feels. Throughput of a large program is not,
--  because Adash is not a batch compiler and nobody waits on it.
--
--  What is deliberately *not* here: a comparison against another shell. It
--  would be measuring two different languages doing two different things, and
--  the number would be quoted long after anybody remembered that.
--
--  Run from the adash_tests directory:
--
--     alr build && ./bin/adash_bench
--
--  The report goes through the message catalog like everything else a user
--  reads. It was plain text here for as long as this tool existed, on the
--  reasoning that a developer tool could keep its own words -- which is the
--  reasoning every hard-coded string starts from, and the rule says otherwise
--  for release tools and test runners as much as for the shell.
--
--  A catalog it cannot read leaves the invariant fallback form -- the key in
--  bangs -- which still names every figure. That is a legible report about a
--  broken catalog rather than a broken report.
procedure Adash_Bench_Main is

   package CLI renames Ada.Command_Line;
   package IO renames Ada.Text_IO;
   package RT renames Ada.Real_Time;
   package Render renames Adash.Messages.Rendering;

   Catalog : Render.Catalog;

   --  One rendered line, by key.
   function Say (Key : String) return String;
   function Say (Key : String) return String
   is (Catalog.Text (Key));

   --  A number as text, without Ada's leading blank for the sign.
   function Counted (Value : Integer) return String;
   function Counted (Value : Integer) return String
   is (Ada.Strings.Fixed.Trim (Integer'Image (Value), Ada.Strings.Both));

   --  What one measured operation is called.
   function Named (What : String) return String;
   function Named (What : String) return String
   is (Catalog.Text ("tooling.bench.what." & What));

   use type RT.Time;
   use type RT.Time_Span;

   --  Enough repetitions that a single scheduling hiccup cannot move the
   --  median, and few enough that the whole run takes seconds rather than
   --  minutes. A benchmark nobody waits for is a benchmark nobody runs.
   Default_Repetitions : constant := 200;

   Repetitions : constant Positive :=
     (if CLI.Argument_Count >= 1
      then Positive'Value (CLI.Argument (1)) else Default_Repetitions);

   --  The line a session repeats. Short, because typed lines are short: a
   --  benchmark built on a thousand-line program would measure something
   --  nobody does.
   Typical_Line : constant String :=
     "for Index in 1 .. 10 loop x := x + Index * 2; end loop;";

   type Sample_Array is array (1 .. Repetitions) of RT.Time_Span;

   --  The median, not the mean. A mean is moved by the one iteration during
   --  which the machine did something else, and that iteration is always
   --  present.
   function Median (Samples : in out Sample_Array) return Duration;

   function Median (Samples : in out Sample_Array) return Duration is
   begin
      for Outer in 2 .. Samples'Last loop
         declare
            Moving : constant RT.Time_Span := Samples (Outer);
            Inner  : Natural := Outer - 1;
         begin
            while Inner >= 1 and then Samples (Inner) > Moving loop
               Samples (Inner + 1) := Samples (Inner);
               Inner := Inner - 1;
            end loop;

            Samples (Inner + 1) := Moving;
         end;
      end loop;

      return RT.To_Duration (Samples ((Samples'Last + 1) / 2));
   end Median;

   procedure Report (What : String; Samples : in out Sample_Array);

   procedure Report (What : String; Samples : in out Sample_Array) is
      --  Tenths of a microsecond. Ada's image of a Duration carries nine
      --  decimals, and eight of them here are the clock's resolution rather
      --  than anything measured -- printing them would suggest a precision the
      --  method does not have.
      Tenths : constant Long_Long_Integer :=
        Long_Long_Integer (Median (Samples) * 10_000_000);

      Whole : constant String :=
        Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Tenths / 10),
                                Ada.Strings.Both);
      Fraction : constant String :=
        Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Tenths mod 10),
                                Ada.Strings.Both);

      --  The fastest run too. A median alone hides the shape: an operation
      --  that starts fast and gets slower shows here as a fastest run far
      --  below the median, and that gap is a defect rather than noise. The
      --  samples are already sorted by Median, so the first is the fastest.
      Best_Tenths : constant Long_Long_Integer :=
        Long_Long_Integer (RT.To_Duration (Samples (Samples'First)) * 10_000_000);

      Best_Whole : constant String :=
        Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Best_Tenths / 10),
                                Ada.Strings.Both);
      Best_Fraction : constant String :=
        Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Best_Tenths mod 10),
                                Ada.Strings.Both);

      Figure : String (1 .. 10);
      Best   : String (1 .. 10);
   begin
      Ada.Strings.Fixed.Move
        (Whole & "." & Fraction, Figure,
         Justify => Ada.Strings.Right, Drop => Ada.Strings.Left);
      Ada.Strings.Fixed.Move
        (Best_Whole & "." & Best_Fraction, Best,
         Justify => Ada.Strings.Right, Drop => Ada.Strings.Left);

      IO.Put_Line ("  " & Ada.Strings.Fixed.Head (Named (What), 34)
                   & Figure & "  " & Best);
   end Report;

   Samples : Sample_Array;
   Started : RT.Time;

begin
   --  The repository's own catalog, found from where this is run rather than
   --  from beside the binary: this tool is run from the adash_tests directory,
   --  which is the same place adash_check is run from and for the same reason.
   Catalog.Open (Catalog_Path => "../resources/messages/catalog.txt");

   IO.Put_Line (Say ("tooling.bench.header"));
   IO.Put_Line
     ("  " & Catalog.Text
        ("tooling.bench.repetitions",
         [Adash.Messages.Named ("count", Counted (Repetitions))]));
   IO.Put_Line
     ("  " & Catalog.Text
        ("tooling.bench.profile",
         [Adash.Messages.Named ("profile", Adash.Version.Build_Profile)]));
   IO.New_Line;

   --------------------------------------------------------------------
   --  The language pipeline, stage by stage. Separated on purpose: a
   --  single "how long does a line take" number cannot tell you which
   --  stage to look at when it moves.
   --------------------------------------------------------------------

   --  The column headings, laid out by the same rule as the figures beneath
   --  them: two ten-wide right-justified fields after the name column. The
   --  words come from the catalog and the spacing does not, because spacing is
   --  layout rather than text and a catalog holding it would be a catalog a
   --  translator could break the table with.
   declare
      Median_Column  : String (1 .. 10);
      Fastest_Column : String (1 .. 10);
   begin
      Ada.Strings.Fixed.Move
        (Say ("tooling.bench.column.median"), Median_Column,
         Justify => Ada.Strings.Right, Drop => Ada.Strings.Left);
      Ada.Strings.Fixed.Move
        (Say ("tooling.bench.column.fastest"), Fastest_Column,
         Justify => Ada.Strings.Right, Drop => Ada.Strings.Left);

      --  Built by the same expression Report uses, with an empty name: the
      --  heading and the figures under it cannot drift apart that way.
      IO.Put_Line
        ("  " & Ada.Strings.Fixed.Head ("", 34)
         & Median_Column & "  " & Fastest_Column);
   end;

   IO.Put_Line (Say ("tooling.bench.group.pipeline"));

   declare
      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_Interactive, "-");
      Buffer : Adash.Source.Buffer;
      Error  : Adash.Errors.Error_Info;
      Loaded : Boolean;
   begin
      for Index in 1 .. Repetitions loop
         Started := RT.Clock;
         Loaded := Adash.Source.Load (Buffer, Origin, Typical_Line, Error);
         Samples (Index) := RT.Clock - Started;
      end loop;

      if not Loaded then
         IO.Put_Line ("  " & Say ("tooling.bench.no_sample"));
         CLI.Set_Exit_Status (CLI.Failure);
         return;
      end if;

      Report ("utf8", Samples);

      declare
         Stream : Adash.Language.Tokens.Token_Stream;
         Report_List : Adash.Diagnostics.List;
      begin
         for Index in 1 .. Repetitions loop
            Started := RT.Clock;
            Adash.Language.Lexer.Scan (Buffer, Stream, Report_List);
            Samples (Index) := RT.Clock - Started;
            Report_List.Clear;
         end loop;

         Report ("lex", Samples);

         declare
            Tree : Adash.Language.Syntax.Tree;
         begin
            for Index in 1 .. Repetitions loop
               Started := RT.Clock;
               Adash.Language.Parser.Parse (Stream, Origin, Tree, Report_List);
               Samples (Index) := RT.Clock - Started;
               Report_List.Clear;
            end loop;

            Report ("parse", Samples);

            declare
               Analysis : Adash.Language.Semantics.Analysis;
            begin
               for Index in 1 .. Repetitions loop
                  Started := RT.Clock;
                  Adash.Language.Semantics.Analyse
                    (Tree, Origin, Analysis, Report_List);
                  Samples (Index) := RT.Clock - Started;
                  Report_List.Clear;
               end loop;

               Report ("analyse", Samples);

               declare
                  Ran : Adash.Language.Evaluation.Outcome;
               begin
                  for Index in 1 .. Repetitions loop
                     Started := RT.Clock;
                     Adash.Language.Evaluation.Run
                       (Tree, Analysis, Origin, Ran, Report_List);
                     Samples (Index) := RT.Clock - Started;
                     Report_List.Clear;
                  end loop;

                  Report ("run", Samples);
               end;
            end;
         end;

         --  Highlighting runs on every keystroke, so it is the one number here
         --  a user can feel directly rather than once per line.
         declare
            Coloured : Adash.Interactive.Highlighting.Highlight;
         begin
            for Index in 1 .. Repetitions loop
               Started := RT.Clock;
               Coloured := Adash.Interactive.Highlighting.Colour (Stream);
               Samples (Index) := RT.Clock - Started;
            end loop;

            pragma Assert (Coloured.Count >= 0);
            Report ("highlight", Samples);
         end;
      end;
   end;

   IO.New_Line;
   IO.Put_Line (Say ("tooling.bench.group.frontend"));

   --  Completion runs on every tab, and walks the command and predefined
   --  registries plus the filesystem.
   declare
      Candidates : Adash.Interactive.Completion.Candidate_List;
   begin
      for Index in 1 .. Repetitions loop
         Started := RT.Clock;
         Candidates := Adash.Interactive.Completion.Complete
           (Adash.Interactive.Completion.Make_Request ("qu", 3));
         Samples (Index) := RT.Clock - Started;
      end loop;

      pragma Assert (Candidates.Count >= 0);
      Report ("complete", Samples);
   end;

   --  And completion where a program is named, which is the one that walks the
   --  search path: every directory on it is listed, and the host is asked
   --  whether a file can be run only for the names the prefix already matched.
   --  That ordering is the whole reason this is worth measuring -- a Tab that
   --  asked about every file on the path would be a pause a user feels.
   declare
      Candidates : Adash.Interactive.Completion.Candidate_List;

      Path : constant String :=
        Adash.Execution.Environment.Value
          (Adash.Execution.Environment.Inherited, "PATH");
   begin
      for Index in 1 .. Repetitions loop
         Started := RT.Clock;
         Candidates := Adash.Interactive.Completion.Complete
           (Adash.Interactive.Completion.Make_Request
              ("run (""ada", 10, Path));
         Samples (Index) := RT.Clock - Started;
      end loop;

      pragma Assert (Candidates.Count >= 0);
      Report ("complete_program", Samples);
   end;

   --  Encoding a history entry happens once per accepted line, and goes
   --  through jsonlib.
   for Index in 1 .. Repetitions loop
      Started := RT.Clock;
      declare
         Encoded : constant String :=
           Adash.Persistence.History.Encode (Typical_Line);
      begin
         pragma Assert (Encoded'Length > 0);
      end;
      Samples (Index) := RT.Clock - Started;
   end loop;

   Report ("history", Samples);

   IO.New_Line;
   IO.Put_Line (Say ("tooling.bench.group.startup"));

   --  Reading the configuration happens once, and is the one thing between the
   --  user pressing return on `adash` and seeing a prompt.
   declare
      Chosen : Adash.Configuration.Settings;
      Notes  : Adash.Diagnostics.List;

      Sample_File : constant String :=
        "color = ""never""" & Character'Val (16#0A#)
        & "[history]" & Character'Val (16#0A#)
        & "limit = 500" & Character'Val (16#0A#);
   begin
      for Index in 1 .. Repetitions loop
         Started := RT.Clock;
         Adash.Configuration.Files.Read_From
           (Sample_File, "<bench>", Chosen, Notes);
         Samples (Index) := RT.Clock - Started;
         Notes.Clear;
      end loop;

      Report ("config", Samples);
   end;

   --  Opening a session is what every frontend does first.
   declare
      Session : Adash.Engine.Session;
   begin
      for Index in 1 .. Repetitions loop
         Started := RT.Clock;
         Adash.Engine.Open (Session);
         Samples (Index) := RT.Clock - Started;
      end loop;

      Report ("session", Samples);
   end;

   IO.New_Line;
   IO.Put_Line (Say ("tooling.bench.drift"));
   IO.New_Line;
   IO.Put_Line
     (Catalog.Text
        ("tooling.bench.methodology",
         [Adash.Messages.Named ("count", Counted (Repetitions))]));

   CLI.Set_Exit_Status (CLI.Success);
end Adash_Bench_Main;

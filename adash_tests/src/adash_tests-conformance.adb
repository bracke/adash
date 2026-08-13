with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;

with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Fs;
with Hostkit.Host;
with Hostkit.Spawn;

with Tomllib.Documents;
with Tomllib.Errors;
with Tomllib.Parsers;

with Adash.Messages;
with Adash.Messages.Rendering;
with Adash.Persistence;
with Adash.Version;

package body Adash_Tests.Conformance is

   use Ada.Strings.Unbounded;

   package Doc renames Tomllib.Documents;
   package Msg renames Adash.Messages;
   package Render renames Adash.Messages.Rendering;

   use type Doc.Node;
   use type Doc.Value_Kind;
   use type Hostkit.Descriptors.Transfer_Outcome;
   use type Hostkit.Spawn.Spawn_Outcome;
   use type Hostkit.Spawn.Wait_State;

   Newline : constant Character := Character'Val (16#0A#);

   --  Pointing the catalog at a path that cannot exist makes every message
   --  render as its stable identifier and arguments. That is what a
   --  conformance suite has to compare: a suite asserting on English would
   --  break on every wording change and would stop testing anything the day
   --  somebody localized the build.
   Keys_Only_Catalog : constant String :=
     "ADASH_MESSAGE_CATALOG=/nonexistent/adash-conformance";

   --  Where a case's shell keeps its state.
   --
   --  Replacing the environment is not enough on its own. A home directory is
   --  a real thing whether or not HOME is set, so hostkit asks the passwd
   --  database when it is missing -- and every case was writing its script into
   --  the history file of whoever ran the suite. That made cases depend on what
   --  had run before them, and left junk in a developer's own shell history.
   --
   --  Pointed at a directory under the host's temporary one instead, and a
   --  different one for every case: a suite where case N sees what cases 1 to
   --  N-1 left behind is one whose answers depend on the order it runs in, and
   --  the point of a conformance case is that it does not.
   --
   --  The directory need not exist. A store that cannot be reached is a session
   --  with no history, which is a perfectly good thing for a case to observe.
   Scratch_Root : constant String :=
     Hostkit.Fs.Join (Hostkit.Fs.Temp_Directory, "adash-conformance-store");

   --  How many cases have been run, which is what makes each store distinct.
   Executions : Natural := 0;

   --  The next case's store, emptied and made ready.
   --
   --  Made rather than merely named: a case that writes a file has to write it
   --  somewhere that exists, and somewhere that is gone again before the next
   --  case looks. `{store}` in a case expands to `files` inside this.
   --
   --  @return The store directory for the case about to run.
   function Next_Store return String;

   function Trimmed (Value : Integer) return String is
      Text : constant String := Integer'Image (Value);
   begin
      return Text (Text'First + 1 .. Text'Last);
   end Trimmed;

   ----------------
   -- Next_Store --
   ----------------

   function Next_Store return String is
      Store : constant String :=
        Scratch_Root & "-" & Trimmed (Executions + 1);
   begin
      Executions := Executions + 1;

      begin
         if Ada.Directories.Exists (Store) then
            Ada.Directories.Delete_Tree (Store);
         end if;

         Ada.Directories.Create_Path
           (Hostkit.Fs.Join (Store, "files"));
      exception
         when others =>
            --  A store that will not go, or will not be made, is not a reason
            --  to refuse to run: the case may not touch it at all. Cases that
            --  do will fail, and their failure is the honest report.
            null;
      end;

      return Store;
   end Next_Store;

   -----------
   -- Count --
   -----------

   function Count (Item : Report) return Natural is
   begin
      return Natural (Item.Results.Length);
   end Count;

   -------------
   -- Element --
   -------------

   function Element (Item : Report; Index : Positive) return Result is
   begin
      return Item.Results.Element (Index);
   end Element;

   --------------
   -- Count_Of --
   --------------

   function Count_Of (Item : Report; Outcome : Verdict) return Natural is
      Total : Natural := 0;
   begin
      for Index in 1 .. Natural (Item.Results.Length) loop
         if Item.Results.Element (Index).Outcome = Outcome then
            Total := Total + 1;
         end if;
      end loop;

      return Total;
   end Count_Of;

   ------------
   -- Passed --
   ------------

   function Passed (Item : Report) return Boolean is
   begin
      --  Skipped cases do not fail a run: a host that cannot exercise a case
      --  has not disproved it. A malformed one does, because it is a fault in
      --  the suite and a suite nobody can trust is worse than none.
      return Count_Of (Item, Failed) = 0 and then Count_Of (Item, Malformed) = 0;
   end Passed;

   procedure Record_Result
     (Into     : in out Report;
      Identity : String;
      Outcome  : Verdict;
      Detail   : String := "");

   --  Why a case did not run, or did not pass, as the catalog says it.
   --
   --  These are read by whoever ran the suite, so they are messages like
   --  everything else a person reads. Rendering here rather than at the point
   --  of printing is a compromise the shape of Result forces -- it carries one
   --  string -- and the catalog is still the only place the words live.
   function Because
     (Key   : String;
      Given : Msg.Argument_List := Msg.No_Arguments) return String;

   -------------------
   -- Record_Result --
   -------------------

   procedure Record_Result
     (Into     : in out Report;
      Identity : String;
      Outcome  : Verdict;
      Detail   : String := "")
   is
   begin
      Into.Results.Append
        (Result'(Identity => To_Unbounded_String (Identity),
                 Outcome  => Outcome,
                 Detail   => To_Unbounded_String (Detail)));
   end Record_Result;

   function Because
     (Key   : String;
      Given : Msg.Argument_List := Msg.No_Arguments) return String
   is
      Catalog : Render.Catalog;
   begin
      --  Opened per call. The suite reports a handful of these in a run that
      --  spawns a process per case, so the cost is not worth a shared handle
      --  that would have to be opened before the first case and closed after
      --  the last.
      Catalog.Open (Catalog_Path => "../resources/messages/catalog.txt");

      return Result : constant String := Catalog.Text (Key, Given) do
         null;
      end return;
   end Because;

   --  What running the binary produced.
   type Execution is record
      Started     : Boolean := False;
      Exit_Status : Integer := -1;
      Output      : Unbounded_String;
      Errors      : Unbounded_String;
   end record;

   function Execute
     (Binary    : String;
      Arguments : Hostkit.String_Vectors.Vector;
      Input     : String;
      Store     : String) return Execution;

   -------------
   -- Execute --
   -------------

   function Execute
     (Binary    : String;
      Arguments : Hostkit.String_Vectors.Vector;
      Input     : String;
      Store     : String) return Execution
   is
      Result : Execution;

      To_Child   : Hostkit.Descriptors.Pipe_Ends;
      From_Child : Hostkit.Descriptors.Pipe_Ends;
      From_Error : Hostkit.Descriptors.Pipe_Ends;

      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;

      procedure Drain
        (Source  : Hostkit.Descriptors.Descriptor;
         Collect : in out Unbounded_String);

      procedure Drain
        (Source  : Hostkit.Descriptors.Descriptor;
         Collect : in out Unbounded_String)
      is
         Buffer : Ada.Streams.Stream_Element_Array (1 .. 4_096);
         Last   : Ada.Streams.Stream_Element_Offset;

         use type Ada.Streams.Stream_Element_Offset;
      begin
         loop
            case Hostkit.Descriptors.Read (Source, Buffer, Last) is
               when Hostkit.Descriptors.Transfer_Ok =>
                  exit when Last < Buffer'First;

                  for Index in Buffer'First .. Last loop
                     Append (Collect, Character'Val (Buffer (Index)));
                  end loop;

               when Hostkit.Descriptors.Transfer_Interrupted =>
                  null;

               when others =>
                  exit;
            end case;
         end loop;
      end Drain;

   begin
      if not Hostkit.Descriptors.Create_Pipe (To_Child)
        or else not Hostkit.Descriptors.Create_Pipe (From_Child)
        or else not Hostkit.Descriptors.Create_Pipe (From_Error)
      then
         return Result;
      end if;

      Options.Input := To_Child.Read_End;
      Options.Output := From_Child.Write_End;
      Options.Error_Output := From_Error.Write_End;

      --  The environment is replaced rather than inherited, so a case gives
      --  the same answer on a developer's machine as in CI. A suite that
      --  inherited the environment would pass or fail depending on what the
      --  person running it happened to have set.
      Options.Replace_Environment := True;
      Options.Environment.Append (To_Unbounded_String (Keys_Only_Catalog));
      Options.Environment.Append
        (To_Unbounded_String ("PATH=/usr/bin:/bin"));

      Options.Environment.Append (To_Unbounded_String ("HOME=" & Store));
      Options.Environment.Append
        (To_Unbounded_String ("XDG_DATA_HOME=" & Store));
      Options.Environment.Append
        (To_Unbounded_String ("XDG_CONFIG_HOME=" & Store));

      if Hostkit.Spawn.Start (Binary, Arguments, Options, Child)
         /= Hostkit.Spawn.Spawn_Ok
      then
         Hostkit.Descriptors.Close (To_Child.Read_End);
         Hostkit.Descriptors.Close (To_Child.Write_End);
         Hostkit.Descriptors.Close (From_Child.Read_End);
         Hostkit.Descriptors.Close (From_Child.Write_End);
         Hostkit.Descriptors.Close (From_Error.Read_End);
         Hostkit.Descriptors.Close (From_Error.Write_End);
         return Result;
      end if;

      Result.Started := True;

      --  Our copies of the child's ends, closed at once. Holding one open
      --  means the child never sees end of input and the read below never
      --  finishes -- the classic way a test harness hangs.
      Hostkit.Descriptors.Close (To_Child.Read_End);
      Hostkit.Descriptors.Close (From_Child.Write_End);
      Hostkit.Descriptors.Close (From_Error.Write_End);

      if Input'Length > 0 then
         declare
            Bytes : Ada.Streams.Stream_Element_Array
                      (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
            From  : Ada.Streams.Stream_Element_Offset := Bytes'First;
            Last  : Ada.Streams.Stream_Element_Offset;

            use type Ada.Streams.Stream_Element_Offset;
         begin
            for Index in Input'Range loop
               Bytes (Ada.Streams.Stream_Element_Offset
                        (Index - Input'First + 1)) :=
                 Ada.Streams.Stream_Element (Character'Pos (Input (Index)));
            end loop;

            while From <= Bytes'Last loop
               case Hostkit.Descriptors.Write
                      (To_Child.Write_End, Bytes (From .. Bytes'Last), Last)
               is
                  when Hostkit.Descriptors.Transfer_Ok =>
                     exit when Last < From;
                     From := Last + 1;

                  when Hostkit.Descriptors.Transfer_Interrupted =>
                     null;

                  when others =>
                     exit;
               end case;
            end loop;
         end;
      end if;

      --  Closed before draining, so the child sees end of input and can
      --  finish. A case whose script does not end in `quit` relies on it.
      Hostkit.Descriptors.Close (To_Child.Write_End);

      Drain (From_Child.Read_End, Result.Output);
      Drain (From_Error.Read_End, Result.Errors);

      Hostkit.Descriptors.Close (From_Child.Read_End);
      Hostkit.Descriptors.Close (From_Error.Read_End);

      declare
         State  : Hostkit.Spawn.Status;
         Waited : constant Boolean :=
           Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, State);
      begin
         if Waited and then State.State = Hostkit.Spawn.Wait_Exited then
            Result.Exit_Status := State.Exit_Code;
         else
            --  Signalled or stopped. Left as -1, which no case expects, so a
            --  crash shows as a failure rather than as a mismatched status
            --  somebody might read as an ordinary difference.
            Result.Exit_Status := -1;
         end if;
      end;

      return Result;
   end Execute;

   --  The one line the runner's own arrangement produces. Pointing the catalog
   --  at a path that does not exist is how every message is made to render as
   --  its identifier, and the shell quite correctly says so on standard error.
   --  That line is an artifact of the harness, not behaviour under test, so it
   --  is dropped rather than written into every case -- where it would be
   --  repeated noise that stops being read, and would have to be updated in
   --  every case if the harness ever changed its path.
   Harness_Notice : constant String :=
     "!startup.catalog_unavailable{path=/nonexistent/adash-conformance}!";

   --  Split captured output into lines, dropping a trailing empty one so that
   --  "one line" and "one line and a terminator" compare equal. Output that
   --  ends without a newline is a real difference and is kept.
   procedure Split
     (Text : String; Into : out Hostkit.String_Vectors.Vector);

   procedure Split
     (Text : String; Into : out Hostkit.String_Vectors.Vector)
   is
      First : Natural := Text'First;
   begin
      Into.Clear;

      while First <= Text'Last loop
         declare
            Stop : Natural := First;
         begin
            while Stop <= Text'Last and then Text (Stop) /= Newline loop
               Stop := Stop + 1;
            end loop;

            if Text (First .. Stop - 1) /= Harness_Notice then
               Into.Append (To_Unbounded_String (Text (First .. Stop - 1)));
            end if;

            First := Stop + 1;
         end;
      end loop;
   end Split;

   --  Read a string array out of a case, or an empty one when it is absent.
   function String_List
     (From : in out Doc.Document;
      Item : Doc.Node;
      Named : String) return Hostkit.String_Vectors.Vector;

   --  Whether a case says anything about a stream at all.
   --
   --  Absent and empty are different assertions, and the difference is the
   --  whole reason a case can pin down that diagnostics stay off standard
   --  output: an absent key asserts nothing, and `= []` asserts that nothing
   --  came out. Treating the two the same would make one of them
   --  inexpressible, and it would be the useful one.
   function Asserts
     (From : in out Doc.Document; Item : Doc.Node; Named : String)
      return Boolean;

   function Asserts
     (From : in out Doc.Document; Item : Doc.Node; Named : String)
      return Boolean
   is
      Value : constant Doc.Node := Doc.Value (From, Item, Named);
   begin
      return Value /= Doc.No_Node
        and then Doc.Kind (From, Value) = Doc.Array_Value;
   end Asserts;

   function String_List
     (From : in out Doc.Document;
      Item : Doc.Node;
      Named : String) return Hostkit.String_Vectors.Vector
   is
      Value  : constant Doc.Node := Doc.Value (From, Item, Named);
      Result : Hostkit.String_Vectors.Vector;
   begin
      if Value = Doc.No_Node or else Doc.Kind (From, Value) /= Doc.Array_Value
      then
         return Result;
      end if;

      for Index in 1 .. Doc.Length (From, Value) loop
         declare
            Element : constant Doc.Node := Doc.Element (From, Value, Index);
         begin
            if Doc.Kind (From, Element) = Doc.String_Value then
               Result.Append
                 (To_Unbounded_String (Doc.As_String (From, Element)));
            end if;
         end;
      end loop;

      return Result;
   end String_List;

   --  Whether a case applies to this host.
   function Applies
     (From : in out Doc.Document; Item : Doc.Node) return Boolean;

   function Applies
     (From : in out Doc.Document; Item : Doc.Node) return Boolean
   is
      Wanted : constant Hostkit.String_Vectors.Vector :=
        String_List (From, Item, "platforms");

      Here : constant String :=
        (case Hostkit.Host.Current is
            when Hostkit.Host.Linux       => "linux",
            when Hostkit.Host.MacOS       => "macos",
            when Hostkit.Host.Windows     => "windows",
            when Hostkit.Host.Unsupported => "unsupported");
   begin
      --  No list means every host. Most behaviour is portable, and making
      --  every case say so would be noise that stops being read.
      if Wanted.Is_Empty then
         return True;
      end if;

      for Index in 1 .. Natural (Wanted.Length) loop
         if To_String (Wanted.Element (Index)) = Here then
            return True;
         end if;
      end loop;

      return False;
   end Applies;

   --  Compare what came out against what was expected.
   function Compare
     (Stream   : String;
      Expected : Hostkit.String_Vectors.Vector;
      Actual   : Hostkit.String_Vectors.Vector) return String;

   function Compare
     (Stream   : String;
      Expected : Hostkit.String_Vectors.Vector;
      Actual   : Hostkit.String_Vectors.Vector) return String
   is
   begin
      for Index in 1 .. Natural'Max (Natural (Expected.Length),
                                     Natural (Actual.Length))
      loop
         declare
            Wanted : constant String :=
              (if Index <= Natural (Expected.Length)
               then To_String (Expected.Element (Index)) else "<nothing>");
            Got : constant String :=
              (if Index <= Natural (Actual.Length)
               then To_String (Actual.Element (Index)) else "<nothing>");
         begin
            if Wanted /= Got then
               --  The first difference, with its line number. Reporting every
               --  difference makes a one-line change look like a rewrite.
               return Stream & " line" & Natural'Image (Index)
                 & ": expected [" & Wanted & "] got [" & Got & "]";
            end if;
         end;
      end loop;

      return "";
   end Compare;

   --  Replace {root} and {store} with the two directories a case may name.
   --
   --  @param Items The arguments as the case wrote them.
   --  @param Root The repository root.
   --  @param Files Where the case may write.
   --  @return The same arguments, expanded.
   function Rooted
     (Items : Hostkit.String_Vectors.Vector;
      Root  : String;
      Files : String) return Hostkit.String_Vectors.Vector;

   --  Replace one marker throughout one string.
   function Filled (Item : String; Marker : String; With_Text : String)
      return String;

   --  Replace every marker in one string.
   function Expanded (Item : String; Root : String; Files : String)
      return String;

   function Filled (Item : String; Marker : String; With_Text : String)
      return String
   is
      At_Position : constant Natural :=
        Ada.Strings.Fixed.Index (Item, Marker);
   begin
      if At_Position = 0 then
         return Item;
      end if;

      return Item (Item'First .. At_Position - 1) & With_Text
        & Filled (Item (At_Position + Marker'Length .. Item'Last),
                  Marker, With_Text);
   end Filled;

   --  A program a case may run on any host.
   --
   --  `{emit}` and `{upcase}` are the two companions this crate ships, named
   --  with whatever suffix the host puts on an executable. A case that wants a
   --  program to capture, to fail, to complain, or to still be running says
   --  one of these instead of naming a utility that half the hosts do not
   --  have -- which is the same reason the companions exist at all.
   --
   --  @param Root The repository root.
   --  @param Named Which companion.
   --  @return Its path.
   function Companion (Root : String; Named : String) return String;

   function Companion (Root : String; Named : String) return String is
      use type Hostkit.Host.Kind;

      --  Beside this program, not under the root: a case may `cd`, and a
      --  relative path stops meaning anything the moment one does. The
      --  companions are built into the same `bin` this runner is in, and
      --  hostkit answers where that is exactly. The root is the fallback for a
      --  host that will not say.
      Beside : constant String := Hostkit.Fs.Own_Executable_Directory;

      Where : constant String :=
        (if Beside = ""
         then Hostkit.Fs.Join
                (Hostkit.Fs.Join (Hostkit.Fs.Join (Root, "adash_tests"), "bin"),
                 Named)
         else Hostkit.Fs.Join (Beside, Named));
   begin
      return (if Hostkit.Host.Current = Hostkit.Host.Windows
              then Where & ".exe" else Where);
   end Companion;

   function Expanded (Item : String; Root : String; Files : String)
      return String
   is
      --  {store} first: a case that names both is expanding two different
      --  things, and the store is not inside the repository, so the order is
      --  a matter of reading rather than of result.
      Stored : constant String := Filled (Item, "{store}", Files);
      Rooted_At : constant String := Filled (Stored, "{root}", Root);

      --  The companions last: their own expansion names the root, and doing
      --  them first would leave a `{root}` for the line above to fill in
      --  again -- which works, and reads as though the order did not matter.
      Emitting : constant String :=
        Filled (Rooted_At, "{emit}", Companion (Root, "adash_test_emit"));
      Upcasing : constant String :=
        Filled (Emitting, "{upcase}", Companion (Root, "adash_test_upcase"));

      --  `{os}` and `{arch}` are how the build identifies itself. A case that
      --  checks what --version reports would otherwise have to be written per
      --  host, or gated to one -- and a case gated to one host is a case the
      --  other two never run.
      On_This_Os : constant String :=
        Filled (Upcasing, "{os}", Adash.Version.Host_Operating_System);
   begin
      return Filled (On_This_Os, "{arch}", Adash.Version.Host_Architecture);
   end Expanded;

   function Rooted
     (Items : Hostkit.String_Vectors.Vector;
      Root  : String;
      Files : String) return Hostkit.String_Vectors.Vector
   is
      Result : Hostkit.String_Vectors.Vector;
   begin
      for Index in 1 .. Natural (Items.Length) loop
         Result.Append
           (To_Unbounded_String
              (Expanded (To_String (Items.Element (Index)), Root, Files)));
      end loop;

      return Result;
   end Rooted;

   --  Run one case out of a parsed file.
   procedure Run_Case
     (Binary : String;
      Root   : String;
      From   : in out Doc.Document;
      Item   : Doc.Node;
      Into   : in out Report);

   procedure Run_Case
     (Binary : String;
      Root   : String;
      From   : in out Doc.Document;
      Item   : Doc.Node;
      Into   : in out Report)
   is
      Identity_Node : constant Doc.Node := Doc.Value (From, Item, "id");
   begin
      if Identity_Node = Doc.No_Node
        or else Doc.Kind (From, Identity_Node) /= Doc.String_Value
      then
         --  Without an identity there is nothing to report against, so this
         --  one cannot even be named in its own failure.
         Record_Result (Into, "<unnamed>", Malformed,
                        Because ("tooling.conformance.no_id"));
         return;
      end if;

      declare
         Identity : constant String := Doc.As_String (From, Identity_Node);

         --  Every key a case may carry. Checked because a key this runner does
         --  not know is silently ignored: `output_contains` instead of
         --  `output` reads as a case that asserts something and is one that
         --  asserts nothing, and it passes. A mistyped assertion is worse than
         --  a missing one, because it looks like coverage.
         function Is_Known (Named : String) return Boolean is
           (Named in "id" | "requirement" | "script" | "arguments"
                   | "exit_status" | "output" | "diagnostics"
                   | "platforms" | "input");

         Script_Node : constant Doc.Node := Doc.Value (From, Item, "script");
         Status_Node : constant Doc.Node :=
           Doc.Value (From, Item, "exit_status");
      begin
         for Index in 1 .. Doc.Length (From, Item) loop
            if not Is_Known (Doc.Name (From, Item, Index)) then
               Record_Result
                 (Into, Identity, Malformed,
                  Because ("tooling.conformance.unknown_key",
                          [Msg.Named ("key", Doc.Name (From, Item, Index))]));
               return;
            end if;
         end loop;

         if not Applies (From, Item) then
            Record_Result (Into, Identity, Skipped,
                           Because ("tooling.conformance.other_host"));
            return;
         end if;

         if Status_Node = Doc.No_Node
           or else Doc.Kind (From, Status_Node) /= Doc.Integer_Value
         then
            Record_Result
              (Into, Identity, Malformed,
               Because ("tooling.conformance.no_status"));
            return;
         end if;

         declare
            --  Emptied and made before anything is expanded against it, so a
            --  case that writes a file writes into a directory that exists and
            --  that no earlier case has been in.
            Store : constant String := Next_Store;
            Files : constant String := Hostkit.Fs.Join (Store, "files");

            --  {root} is expanded here as well as in the arguments: a case
            --  that asks about a file in the repository has to name it, and
            --  naming it only works from one of the two places it can be
            --  written.
            Script : constant String :=
              Expanded
                ((if Script_Node /= Doc.No_Node
                    and then Doc.Kind (From, Script_Node) = Doc.String_Value
                  then Doc.As_String (From, Script_Node) else ""),
                 Root, Files);

            --  A case may name a file in the repository. Without this every
            --  case had to feed its script through standard input, so the
            --  shell's other mode -- a script named on the command line, with
            --  arguments of its own after it -- had no case that ran one at
            --  all.
            Arguments : constant Hostkit.String_Vectors.Vector :=
              Rooted (String_List (From, Item, "arguments"), Root, Files);

            --  What the child reads. A case gives it either a script -- which
            --  the shell reads from standard input -- or input for a script
            --  named in the arguments to read for itself. Both would be one
            --  stream carrying two things.
            Given_Input : constant String :=
              (if Doc.Value (From, Item, "input") /= Doc.No_Node
                 and then Doc.Kind (From, Doc.Value (From, Item, "input"))
                          = Doc.String_Value
               then Doc.As_String (From, Doc.Value (From, Item, "input"))
               else "");

            Ran : constant Execution :=
              Execute (Binary, Arguments,
                       (if Script = "" then Given_Input
                        else Script & Newline),
                       Store);

            Wanted_Status : constant Integer :=
              Integer (Doc.As_Integer (From, Status_Node));

            Actual_Output : Hostkit.String_Vectors.Vector;
            Actual_Errors : Hostkit.String_Vectors.Vector;
         begin
            if not Ran.Started then
               Record_Result
                 (Into, Identity, Failed, Because ("tooling.conformance.no_binary"));
               return;
            end if;

            if Ran.Exit_Status /= Wanted_Status then
               Record_Result
                 (Into, Identity, Failed,
                  Because ("tooling.conformance.wrong_status",
                           [Msg.Named ("expected",
                                       Integer'Image (Wanted_Status)),
                            Msg.Named ("found",
                                       Integer'Image (Ran.Exit_Status))]));
               return;
            end if;

            Split (To_String (Ran.Output), Actual_Output);
            Split (To_String (Ran.Errors), Actual_Errors);

            if Asserts (From, Item, "output") then
               declare
                  Problem : constant String :=
                    Compare ("output",
                             --  Expanded on this side too: a case that names a
                             --  directory in its script has to name the same
                             --  one in the line it expects back.
                             Rooted (String_List (From, Item, "output"),
                                     Root, Files),
                             Actual_Output);
               begin
                  if Problem /= "" then
                     Record_Result (Into, Identity, Failed, Problem);
                     return;
                  end if;
               end;
            end if;

            if Asserts (From, Item, "diagnostics") then
               declare
                  Problem : constant String :=
                    Compare ("diagnostics",
                             Rooted (String_List (From, Item, "diagnostics"),
                                     Root, Files),
                             Actual_Errors);
               begin
                  if Problem /= "" then
                     Record_Result (Into, Identity, Failed, Problem);
                     return;
                  end if;
               end;
            end if;

            Record_Result (Into, Identity, Passed);
         end;
      end;
   end Run_Case;

   --  Run every case in one file.
   procedure Run_File
     (Binary : String; Root : String; Path : String; Into : in out Report);

   procedure Run_File
     (Binary : String; Root : String; Path : String; Into : in out Report)
   is
      Text     : Adash.Persistence.Contents;
      Outcome  : Adash.Persistence.Outcome;
      Document : Doc.Document;
      Error    : Tomllib.Errors.Error_Info;
   begin
      Adash.Persistence.Read (Path, Text, Outcome);

      if not Adash.Persistence.Succeeded (Outcome) then
         Record_Result
           (Into, Ada.Directories.Simple_Name (Path), Malformed,
            Because ("tooling.conformance.unreadable",
                 [Msg.Named ("reason",
                             Adash.Persistence.Outcome'Image (Outcome))]));
         return;
      end if;

      Tomllib.Parsers.Parse (To_String (Text), Document, Error);

      if Tomllib.Errors.Failed (Error) then
         Record_Result
           (Into, Ada.Directories.Simple_Name (Path), Malformed,
            Because ("tooling.conformance.malformed_toml",
                     [Msg.Named ("line",
                                 Positive'Image (Error.At_Position.Line)),
                      Msg.Named ("reason",
                                 Tomllib.Errors.Identifier (Error.Code))]));
         return;
      end if;

      declare
         Cases : constant Doc.Node :=
           Doc.Value (Document, Doc.Root (Document), "case");
      begin
         if Cases = Doc.No_Node
           or else Doc.Kind (Document, Cases) /= Doc.Array_Value
         then
            Record_Result
              (Into, Ada.Directories.Simple_Name (Path), Malformed,
               Because ("tooling.conformance.no_entries"));
            return;
         end if;

         for Index in 1 .. Doc.Length (Document, Cases) loop
            Run_Case (Binary, Root, Document,
                      Doc.Element (Document, Cases, Index), Into);
         end loop;
      end;
   end Run_File;

   --  The shell to test, under a root.
   --
   --  Windows names an executable with a suffix and the other two do not, so a
   --  path built without one is a path that exists only on the machine it was
   --  written on. Asking the host rather than assuming is the rule this
   --  workspace exists to follow, and a suite that spawns the shell is the
   --  last place to break it.
   --
   --  @param Root The repository root.
   --  @return The path to the built shell.
   function Shell_In (Root : String) return String;

   function Shell_In (Root : String) return String is
      Plain : constant String :=
        Hostkit.Fs.Join (Hostkit.Fs.Join (Root, "bin"), "adash");
      use type Hostkit.Host.Kind;
   begin
      return (if Hostkit.Host.Current = Hostkit.Host.Windows
              then Plain & ".exe" else Plain);
   end Shell_In;

   ---------
   -- Run --
   ---------

   procedure Run (Root : String; Into : in out Report) is
      Directory : constant String :=
        Hostkit.Fs.Join (Hostkit.Fs.Join (Root, "conformance"), "cases");
      Binary : constant String := Shell_In (Root);
   begin
      if not Ada.Directories.Exists (Directory) then
         Record_Result
           (Into, "<suite>", Malformed,
            Because ("tooling.conformance.no_cases",
                       [Msg.Named ("path", Directory)]));
         return;
      end if;

      if not Ada.Directories.Exists (Binary) then
         --  Without the binary there is nothing to conform to. Reported once,
         --  rather than as a failure of every case, which would bury it.
         Record_Result
           (Into, "<suite>", Malformed, "no binary at " & Binary);
         return;
      end if;

      declare
         Search : Ada.Directories.Search_Type;
         Found  : Ada.Directories.Directory_Entry_Type;

         --  Sorted, so a run reports its cases in the same order every time.
         --  A report that reordered itself between runs is one nobody can
         --  diff, and diffing two runs is how a regression is found.
         Names : Hostkit.String_Vectors.Vector;
      begin
         Ada.Directories.Start_Search
           (Search, Directory, "*.toml",
            [Ada.Directories.Ordinary_File => True, others => False]);

         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Found);
            Names.Append
              (To_Unbounded_String (Ada.Directories.Full_Name (Found)));
         end loop;

         Ada.Directories.End_Search (Search);

         for Outer in 2 .. Natural (Names.Length) loop
            declare
               Moving : constant Unbounded_String := Names.Element (Outer);
               Inner  : Natural := Outer - 1;
            begin
               while Inner >= 1
                 and then To_String (Names.Element (Inner)) > To_String (Moving)
               loop
                  Names.Replace_Element (Inner + 1, Names.Element (Inner));
                  Inner := Inner - 1;
               end loop;

               Names.Replace_Element (Inner + 1, Moving);
            end;
         end loop;

         for Index in 1 .. Natural (Names.Length) loop
            Run_File (Binary, Root, To_String (Names.Element (Index)), Into);
         end loop;
      end;
   end Run;

   -------------------
   -- Run_Examples --
   -------------------

   procedure Run_Examples (Root : String; Into : in out Report) is
      Directory : constant String := Hostkit.Fs.Join (Root, "examples");
      Binary    : constant String := Shell_In (Root);

      Names : Hostkit.String_Vectors.Vector;
   begin
      if not Ada.Directories.Exists (Directory) then
         Record_Result
           (Into, "<examples>", Malformed, "no directory at " & Directory);
         return;
      end if;

      if not Ada.Directories.Exists (Binary) then
         Record_Result
           (Into, "<examples>", Malformed, "no binary at " & Binary);
         return;
      end if;

      declare
         Search : Ada.Directories.Search_Type;
         Found  : Ada.Directories.Directory_Entry_Type;
      begin
         Ada.Directories.Start_Search
           (Search, Directory, "*.adash",
            [Ada.Directories.Ordinary_File => True, others => False]);

         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Found);
            Names.Append
              (To_Unbounded_String (Ada.Directories.Full_Name (Found)));
         end loop;

         Ada.Directories.End_Search (Search);
      end;

      for Outer in 2 .. Natural (Names.Length) loop
         declare
            Moving : constant Unbounded_String := Names.Element (Outer);
            Inner  : Natural := Outer - 1;
         begin
            while Inner >= 1
              and then To_String (Names.Element (Inner)) > To_String (Moving)
            loop
               Names.Replace_Element (Inner + 1, Names.Element (Inner));
               Inner := Inner - 1;
            end loop;

            Names.Replace_Element (Inner + 1, Moving);
         end;
      end loop;

      for Index in 1 .. Natural (Names.Length) loop
         declare
            Script   : constant String := To_String (Names.Element (Index));
            Identity : constant String :=
              "example." & Ada.Directories.Base_Name (Script);

            --  Every example carries the output it claims to produce, beside
            --  it. An example without one is a case nobody can check, which is
            --  how documentation starts lying.
            Expected_Path : constant String :=
              Ada.Directories.Compose
                (Ada.Directories.Containing_Directory (Script),
                 Ada.Directories.Base_Name (Script), "expected");

            Arguments : Hostkit.String_Vectors.Vector;
         begin
            if not Ada.Directories.Exists (Expected_Path) then
               Record_Result
                 (Into, Identity, Malformed,
                  Because ("tooling.conformance.no_expected"));
            else
               declare
                  Wanted  : Adash.Persistence.Contents;
                  Outcome : Adash.Persistence.Outcome;
               begin
                  Adash.Persistence.Read (Expected_Path, Wanted, Outcome);

                  if not Adash.Persistence.Succeeded (Outcome) then
                     Record_Result
                       (Into, Identity, Malformed,
                        Because ("tooling.conformance.unreadable_expected"));
                  else
                     Arguments.Append (To_Unbounded_String (Script));

                     declare
                        Ran : constant Execution :=
                          Execute (Binary, Arguments, "", Next_Store);

                        Actual_Output : Hostkit.String_Vectors.Vector;
                        Wanted_Output : Hostkit.String_Vectors.Vector;
                     begin
                        if not Ran.Started then
                           Record_Result
                             (Into, Identity, Failed,
                              Because ("tooling.conformance.no_binary"));
                        else
                           Split (To_String (Ran.Output), Actual_Output);
                           Split (To_String (Wanted), Wanted_Output);

                           declare
                              Problem : constant String :=
                                Compare ("output", Wanted_Output,
                                         Actual_Output);
                           begin
                              if Problem /= "" then
                                 Record_Result (Into, Identity, Failed, Problem);
                              else
                                 Record_Result (Into, Identity, Passed);
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Run_Examples;

end Adash_Tests.Conformance;

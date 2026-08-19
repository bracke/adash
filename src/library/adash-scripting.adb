with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

with Adash.Errors;
with Adash.Filesystem;
with Adash.Execution.Signals;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Symbols;
with Adash.Language.Syntax;
with Adash.Language.Tokens;
with Adash.Messages;
with Adash.Scripting.Modules;
with Adash.Source;

with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Fs;
with Hostkit.Terminal_Control;

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

   --  What a cleanup's diagnostics are said to be from. Not the script: a
   --  mistake in a cleanup is at the line that registered it, and pointing at
   --  the script's own text would point at whatever happened to be there.
   Name_Of_Cleanups : constant String := "on_exit";

   --  What a handler run for an interrupt is called in a diagnostic about it.
   Name_Of_Handlers : constant String := "on_interrupt";
   Name_Of_Signal_Handlers : constant String := "on_signal";
   Name_Of_Failure_Handlers : constant String := "on_failure";

   procedure Run_Text
     (Session : in out Adash.Engine.Session;
      Text    : String;
      Name    : String;
      Result  : out Outcome;
      Status  : out Adash.Execution.Exit_Status;
      Report  : in out D.List;
      On_Output : Adash.Engine.Output_Sink_Access := null;
      Carried : out Natural)
   is
      Submitted : Adash.Engine.Result;
      use type Adash.Engine.Submission_Kind;
   begin
      --  A script's runaway loop is a runaway loop too.
      --
      --  Where the host reports an interrupt to a program that is busy, the
      --  signal arrives here as it does anywhere else and there is nothing to
      --  arrange. Where it does not -- Windows -- the shell has to be watching
      --  its terminal when the key is pressed, and until now only the
      --  interactive session did that: a script on that host ran with nobody
      --  looking, so `adash loops.adash` could not be stopped.
      --
      --  Only when standard input is a terminal. A script reading a pipe has
      --  no keyboard to watch, and a shell that read that pipe looking for
      --  Ctrl-C would be eating the script's own input.
      if not Hostkit.Terminal_Control.Interrupt_Reaches_A_Busy_Program
        and then Hostkit.Descriptors.Is_Terminal
                   (Hostkit.Descriptors.Standard_Input)
      then
         Adash.Execution.Signals.Watch_Terminal
           (Hostkit.Descriptors.Standard_Input);
      end if;

      --  Through the engine, like everything else. A script that took another
      --  route would be a second interpreter.
      Adash.Engine.Submit
        (Session, Text, Name, Adash.Source.Origin_File, Submitted, Report,
         On_Output => On_Output);

      --  Put back before anything else runs, so the terminal a script leaves
      --  behind is the terminal it was given.
      Adash.Execution.Signals.Stop_Watching;

      --  Whether this script was interrupted, asked before the pending
      --  interrupt is cleared -- because clearing it is what makes the
      --  question unanswerable.
      declare
         Interrupted : constant Boolean :=
           Adash.Execution.Signals.Interrupt_Pending;
      begin
         Adash.Execution.Signals.Acknowledge_Interrupt;

         --  What `on_interrupt` asked for, and only where there was one.
         --
         --  After the acknowledgement, like the cleanups below and for the
         --  same reason: a handler runs *because* the script was interrupted,
         --  and one that inherited the pending interrupt would be stopped
         --  before it could do anything.
         if Interrupted then
            declare
               Handlers : constant Hostkit.String_Vectors.Vector :=
                 Adash.Engine.Interrupt_Handlers (Session);

               Ran_It : Adash.Engine.Result;
            begin
               for Name of Handlers loop
                  Adash.Engine.Submit
                    (Session,
                     Ada.Strings.Unbounded.To_String (Name) & ";",
                     Name    => Name_Of_Handlers,
                     Kind    => Adash.Source.Origin_Interactive,
                     Outcome => Ran_It,
                     Report  => Report,
                     On_Output => On_Output);
               end loop;
            end;
         end if;
      end;

      --  What `on_failure` asked for, if anything failed while this ran.
      --
      --  Once for the text rather than once per failing command: a script that
      --  fails a hundred times in a loop has one thing wrong with it, and a
      --  handler that wrote a line each time would bury it.
      declare
         Went_Wrong : constant Boolean :=
           Adash.Engine.Take_Failure (Session);

         Ran_It : Adash.Engine.Result;
      begin
         if Went_Wrong then
            for Name of Adash.Engine.Failure_Handlers (Session) loop
               Adash.Engine.Submit
                 (Session,
                  Ada.Strings.Unbounded.To_String (Name) & ";",
                  Name    => Name_Of_Failure_Handlers,
                  Kind    => Adash.Source.Origin_Interactive,
                  Outcome => Ran_It,
                  Report  => Report,
                  On_Output => On_Output);
            end loop;

            --  Whatever the handlers themselves did is not another failure to
            --  report: a handler that fails says so through its own
            --  diagnostics, and running it again for that would not end.
            declare
               Ignored : constant Boolean :=
                 Adash.Engine.Take_Failure (Session);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         end if;
      end;

      --  And any other signal a handler was registered for. A script is where
      --  `terminate` matters most: it is the signal a service manager sends
      --  first, and a script that writes a file wants the chance to finish it.
      declare
         Due : constant Hostkit.String_Vectors.Vector :=
           Adash.Engine.Due_Signal_Handlers (Session);

         Ran_It : Adash.Engine.Result;
      begin
         for Name of Due loop
            Adash.Engine.Submit
              (Session,
               Ada.Strings.Unbounded.To_String (Name) & ";",
               Name    => Name_Of_Signal_Handlers,
               Kind    => Adash.Source.Origin_Interactive,
               Outcome => Ran_It,
               Report  => Report,
               On_Output => On_Output);
         end loop;
      end;

      --  What `on_exit` asked for, before this text is done with.
      --
      --  After the interrupt is acknowledged, deliberately: a cleanup runs
      --  *because* the script was interrupted as often as because it finished,
      --  and one that inherited a pending interrupt would be stopped before it
      --  could remove anything.
      declare
         Waiting : constant Hostkit.String_Vectors.Vector :=
           Adash.Engine.Take_Cleanups (Session);

         Ran_It  : Adash.Engine.Result;
      begin
         for Name of Waiting loop
            --  Submitted as a call, because that is what it is. A name that
            --  turns out not to be there is reported the way any undeclared
            --  name is: the script asked for something it never declared.
            Adash.Engine.Submit
              (Session,
               Ada.Strings.Unbounded.To_String (Name) & ";",
               Name    => Name_Of_Cleanups,
               Kind    => Adash.Source.Origin_Interactive,
               Outcome => Ran_It,
               Report  => Report,
               On_Output => On_Output);
         end loop;
      end;

      Carried := Submitted.Carried_Bytes;
      Status := Submitted.Status;

      if Submitted.Kind = Adash.Engine.Not_Understood then
         Result := Script_Rejected;
      else
         Result := Script_Ran;
      end if;
   end Run_Text;

   ---------------------------------------------------------------------------
   --  Reading one script into another
   --
   --  `source ("helpers");` written at the top of a script names a file whose
   --  declarations the script wants. A script is one submission, and a
   --  submission is analysed as a whole before any of it runs -- so a call
   --  that only *runs* the other file at that point comes too late for the
   --  analysis, and the names it declares are not there to be resolved. That
   --  is why the command alone could never give a script its helpers.
   --
   --  So the file is read into the text before the text is submitted, in the
   --  place the call stood. What runs then is one program, in the order it was
   --  written, and every name the module declares is in scope for what follows
   --  it -- which is what a reader expects of the line they wrote.
   --
   --  Only a *literal* name, and only at the top of a submission. Both are the
   --  rule this language uses wherever something has to be known before the
   --  program runs -- an array's bounds, a case's choices, a parameter's
   --  default -- and `source (Env_Value ("X"))` is not. Anything else stays
   --  what it was: a command that runs a file when it is reached.
   ---------------------------------------------------------------------------

   --  A stretch of the text that came from another file.
   type Region is record
      --  Where it sits in the text that was submitted, from one.
      First : Positive := 1;
      Last  : Natural := 0;

      --  The file it came from, and what it held: a position inside this
      --  stretch is a line and a column in *that* text, and nothing else has
      --  it by the time anything asks.
      From : Unbounded_String;
      Held : Unbounded_String;

      --  How much longer the text became here: the file's length less the
      --  length of the call it replaced. What a diagnostic after this point
      --  has to be moved back by.
      Growth : Integer := 0;
   end record;

   package Region_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Region);

   --  How deep one script may read another into itself. A bound rather than a
   --  hope: the cycle check below catches a file that reads itself, and this
   --  catches a chain nobody meant to write.
   Max_Reading : constant := 8;

   --  Whether a path is already being read into something.
   --
   --  The chain rather than the loading context: what must not repeat here is
   --  a file reading itself into itself, which is a different question from a
   --  script running another that runs the first.
   function Already_Reading
     (Chain : Path_Vectors.Vector; Path : Module_Path) return Boolean;

   function Already_Reading
     (Chain : Path_Vectors.Vector; Path : Module_Path) return Boolean
   is
   begin
      for Held of Chain loop
         if Ada.Strings.Unbounded."=" (Held, Path) then
            return True;
         end if;
      end loop;

      return False;
   end Already_Reading;

   --  Blank a leading `#!` line, in place.
   --
   --  A script is a file, and a file a user made executable begins with the
   --  line the host reads to decide what runs it. That line is not Ada, so
   --  without this a script with `#!/usr/bin/env adash` at the top is a script
   --  whose first line is a syntax error -- which is what stood between this
   --  shell and being usable the way every other shell's scripts are.
   --
   --  Blanked rather than removed, and the newline kept, so that every byte
   --  after it stays where it was: a diagnostic still names the line the
   --  reader is looking at, and a span still covers what a reader would
   --  highlight. Dropping the line would move every position in the file by
   --  its length and quietly misplace every message about it.
   --
   --  Only at the very start, and only `#!`. A `#` anywhere else in this
   --  language is not a comment and must not be treated as one.
   procedure Blank_A_Shebang (Text : in out Unbounded_String);

   procedure Blank_A_Shebang (Text : in out Unbounded_String) is
   begin
      if Length (Text) < 2
        or else Slice (Text, 1, 2) /= "#!"
      then
         return;
      end if;

      for Index in 1 .. Length (Text) loop
         exit when Element (Text, Index) = Ada.Characters.Latin_1.LF;
         Replace_Element (Text, Index, ' ');
      end loop;
   end Blank_A_Shebang;

   --  Read what a script asks for into its text.
   --
   --  Never reports anything. A file that does not parse, a name that resolves
   --  to nothing, a cycle: each is left exactly as it was written, so the
   --  ordinary path reports it in its own words rather than this reporting it
   --  first and differently.
   --
   --  @param Text What was read from the file.
   --  @param Loaded_From The script's own path, for resolving a bare name.
   --  @param Depth How many files deep this already is.
   --  @param Reading The chain of paths being read, for the cycle check.
   --  @param Regions Where each included stretch ended up.
   --  @return The text to submit.
   function Read_Into
     (Text        : String;
      Loaded_From : String;
      Depth       : Natural;
      Reading     : in out Path_Vectors.Vector;
      Regions     : in out Region_Vectors.Vector) return String;

   function Read_Into
     (Text        : String;
      Loaded_From : String;
      Depth       : Natural;
      Reading     : in out Path_Vectors.Vector;
      Regions     : in out Region_Vectors.Vector) return String
   is
      package S renames Adash.Language.Syntax;
      use type S.Node_Kind;

      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_File, Loaded_From);

      Buffer : Adash.Source.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Tree   : S.Tree;
      Aside  : D.List;
      Error  : Adash.Errors.Error_Info;

      Built : Unbounded_String;
      Taken : Natural := 0;

      --  What one file holds, or "" when it cannot be read. Reading a file
      --  that is not there is not an error here: the call is left alone and
      --  the command says so when it runs.
      function Contents (Path : String) return String;

      function Contents (Path : String) return String is
         File   : Ada.Streams.Stream_IO.File_Type;
         Result : Unbounded_String;
      begin
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, Path);

         declare
            use Ada.Streams;
            Chunk : Stream_Element_Array (1 .. 64 * 1024);
            Last  : Stream_Element_Offset;
         begin
            while not Ada.Streams.Stream_IO.End_Of_File (File) loop
               Ada.Streams.Stream_IO.Read (File, Chunk, Last);

               --  The same bound as the script itself. A module is read into
               --  the text of the script that asked for it, so a module nobody
               --  can hold is a script nobody can hold; "" is what this
               --  answers for anything it cannot read, and the command that
               --  asked says so when it runs.
               if Length (Result) + Natural (Last)
                  > Adash.Filesystem.Default_Limit
               then
                  Ada.Streams.Stream_IO.Close (File);
                  return "";
               end if;

               for Index in Chunk'First .. Last loop
                  Append (Result, Character'Val (Natural (Chunk (Index))));
               end loop;
            end loop;
         end;

         Ada.Streams.Stream_IO.Close (File);

         --  A module can be a script somebody also made executable.
         Blank_A_Shebang (Result);
         return To_String (Result);

      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;

            return "";
      end Contents;
   begin
      if Depth >= Max_Reading then
         return Text;
      end if;

      if not Adash.Source.Load (Buffer, Origin, Text, Error) then
         return Text;
      end if;

      Adash.Language.Lexer.Scan (Buffer, Stream, Aside);
      Adash.Language.Parser.Parse (Stream, Origin, Tree, Aside);

      if S.Has_Errors (Tree) then
         --  Not this routine's to report: the submission is about to be
         --  parsed again, by the engine, which says what is wrong with it.
         return Text;
      end if;

      declare
         Root : constant S.Node_Id := S.Root (Tree);
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Statement : constant S.Node_Id := S.Child (Tree, Root, Index);
               Prefix    : S.Node_Id;
               Arguments : S.Node_Id;
            begin
               --  A call as a statement holds the call itself, which is
               --  where the name and the arguments are: the statement node
               --  says only that a call stands here.
               if S.Kind (Tree, Statement) = S.Node_Procedure_Call
                 and then S.Kind (Tree, S.First (Tree, Statement))
                          = S.Node_Call
               then
                  Prefix := S.First (Tree, S.First (Tree, Statement));
                  Arguments := S.Second (Tree, S.First (Tree, Statement));

                  if S.Kind (Tree, Prefix) = S.Node_Name
                    and then Adash.Language.Symbols.Fold
                               (S.Text (Tree, Prefix)) = "source"
                    and then S.Is_Present (Arguments)
                    and then S.Child_Count (Tree, Arguments) = 1
                    and then S.Kind (Tree, S.Child (Tree, Arguments, 1))
                             = S.Node_String_Literal
                  then
                     declare
                        Named : constant String :=
                          S.Text (Tree, S.Child (Tree, Arguments, 1));

                        Found : constant Adash.Scripting.Modules.Resolution :=
                          Adash.Scripting.Modules.Resolve (Named, Loaded_From);

                        Extent : constant Adash.Source.Span :=
                          S.Extent (Tree, Statement);
                     begin
                        if Found.Found
                          and then not Already_Reading (Reading, Found.Path)
                        then
                           declare
                              Path : constant String :=
                                To_String (Found.Path);

                              Held : constant String := Contents (Path);
                           begin
                              if Held /= "" then
                                 Reading.Append (Found.Path);

                                 declare
                                    Inner : constant String :=
                                      Read_Into (Held, Path, Depth + 1,
                                                 Reading, Regions);

                                    Replaced : constant Natural :=
                                      Adash.Source.Length (Extent);

                                    Starts : constant Positive :=
                                      Length (Built) + 1;
                                 begin
                                    --  Everything up to the call, then the
                                    --  file in its place.
                                    Append
                                      (Built,
                                       Text (Text'First + Taken
                                             .. Text'First + Extent.First - 2));
                                    Append (Built, Inner);

                                    Regions.Append
                                      (Region'
                                         (First  => Starts
                                                    + (Extent.First - 1 - Taken),
                                          Last   => Starts
                                                    + (Extent.First - 1 - Taken)
                                                    + Inner'Length - 1,
                                          From   => Found.Path,
                                          Held   =>
                                            To_Unbounded_String (Inner),
                                          Growth => Inner'Length - Replaced));

                                    Taken := Extent.Last;
                                 end;

                                 Reading.Delete_Last;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end if;
            end;
         end loop;
      end;

      if Taken = 0 then
         return Text;
      end if;

      Append (Built, Text (Text'First + Taken .. Text'Last));
      return To_String (Built);
   end Read_Into;

   --  Say where each diagnostic is really about.
   --
   --  The session analysed one text: what it carried forward, then the
   --  script, with any file the script asked for read into it. A diagnostic
   --  carries a position in *that* text. This turns it back into a position in
   --  a file somebody wrote -- the module for anything inside a stretch that
   --  came from one, and the script itself for everything else, moved back by
   --  however much the reading made the text grow before it.
   --
   --  @param Report The list to correct, in place.
   --  @param From The first entry this run added; earlier ones are somebody
   --         else's and are left alone.
   --  @param Regions Where each included stretch ended up.
   --  @param Carried How many bytes the session put in front.
   --  @param Path The script's own path.
   procedure Relocate
     (Report  : in out D.List;
      From    : Natural;
      Regions : Region_Vectors.Vector;
      Carried : Natural;
      Path    : String;
      Text    : String);

   procedure Relocate
     (Report  : in out D.List;
      From    : Natural;
      Regions : Region_Vectors.Vector;
      Carried : Natural;
      Path    : String;
      Text    : String)
   is
      Mine : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_File, Path);

      --  A line and a column in a text, which is what a reader counts. Read
      --  from a buffer rather than by counting newlines here: a column is in
      --  characters and this language is UTF-8, and Adash.Source already knows
      --  that.
      procedure Place_In
        (What   : String;
         Offset : Natural;
         Place  : out Adash.Source.Location;
         Quote  : out Unbounded_String);

      procedure Place_In
        (What   : String;
         Offset : Natural;
         Place  : out Adash.Source.Location;
         Quote  : out Unbounded_String)
      is
         Buffer : Adash.Source.Buffer;
         Error  : Adash.Errors.Error_Info;
      begin
         Place := (Line => 1, Column => 1);
         Quote := Null_Unbounded_String;

         if Offset < 1
           or else not Adash.Source.Load
                         (Buffer,
                          Adash.Source.Make_Origin
                            (Adash.Source.Origin_File, Path),
                          What, Error)
         then
            return;
         end if;

         Place := Adash.Source.Where_Is
                    (Buffer, Adash.Source.Byte_Offset (Offset));
         Quote := To_Unbounded_String
                    (Adash.Source.Line_Text (Buffer, Place.Line));
      end Place_In;
   begin
      if Regions.Is_Empty then
         return;
      end if;

      for Index in From + 1 .. D.Count (Report) loop
         declare
            Item   : constant D.Diagnostic := D.Element (Report, Index);
            Extent : constant Adash.Source.Span := D.Extent (Item);

            --  Where it is in the text this package assembled.
            Here : constant Integer :=
              Integer (Extent.First) - Integer (Carried);

            Shift : Integer := 0;
            Moved : Boolean := False;
         begin
            --  The places it points at besides its own move with it: they
            --  are offsets into the same assembled text and would otherwise
            --  name a line of the script that has nothing to do with them.
            for Which in 1 .. D.Related_Count (Item) loop
               declare
                  Beside : constant D.Related_Location :=
                    D.Related (Item, Which);

                  There : constant Integer :=
                    Integer (Beside.Extent.First) - Integer (Carried);

                  Moved : Boolean := False;
                  Back  : Integer := 0;

                  Place : Adash.Source.Location;
                  Quote : Unbounded_String;
               begin
                  if not Adash.Source.Is_Empty (Beside.Extent)
                    and then There >= 1
                  then
                     for Region of Regions loop
                        if There >= Region.First and then There <= Region.Last
                        then
                           Place_In (To_String (Region.Held),
                                     There - Region.First + 1, Place, Quote);
                           D.Locate_Related
                             (Report, Index, Which,
                              Adash.Source.Make_Origin
                                (Adash.Source.Origin_File,
                                 To_String (Region.From)),
                              (First => Adash.Source.Byte_Offset
                                          (There - Region.First + 1),
                               Last  => Adash.Source.Byte_Offset
                                          (There - Region.First + 1)),
                              Place);
                           Moved := True;
                           exit;

                        elsif There > Region.Last then
                           Back := Back + Region.Growth;
                        end if;
                     end loop;

                     if not Moved then
                        Place_In (Text, There - Back, Place, Quote);
                        D.Locate_Related
                          (Report, Index, Which, Mine,
                           (First => Adash.Source.Byte_Offset (There - Back),
                            Last  => Adash.Source.Byte_Offset (There - Back)),
                           Place);
                     end if;
                  end if;
               end;
            end loop;

            if Adash.Source.Is_Empty (Extent) or else Here < 1 then
               --  No position, or a position in what the session carried --
               --  which is the session's own text and not this script's.
               null;

            else
               for Region of Regions loop
                  if Here >= Region.First and then Here <= Region.Last then
                     --  Inside a module: its own file, at its own offset.
                     declare
                        Place : Adash.Source.Location;
                        Quote : Unbounded_String;
                     begin
                        Place_In (To_String (Region.Held),
                                  Here - Region.First + 1, Place, Quote);

                        D.Locate
                          (Report, Index,
                           Adash.Source.Make_Origin
                             (Adash.Source.Origin_File,
                              To_String (Region.From)),
                           (First => Adash.Source.Byte_Offset
                                       (Here - Region.First + 1),
                            Last  => Adash.Source.Byte_Offset
                                       (Integer (Extent.Last)
                                        - Integer (Carried)
                                        - Region.First + 1)),
                           Place, To_String (Quote));
                     end;
                     Moved := True;
                     exit;

                  elsif Here > Region.Last then
                     Shift := Shift + Region.Growth;
                  end if;
               end loop;

               if not Moved and then Shift /= 0 then
                  --  After a module: the script's own text, moved back by what
                  --  the reading added before it.
                  declare
                     Place : Adash.Source.Location;
                     Quote : Unbounded_String;
                  begin
                     Place_In (Text, Here - Shift, Place, Quote);

                     D.Locate
                       (Report, Index, Mine,
                        (First => Adash.Source.Byte_Offset (Here - Shift),
                         Last  => Adash.Source.Byte_Offset
                                    (Integer (Extent.Last) - Integer (Carried)
                                     - Shift)),
                        Place, To_String (Quote));
                  end;
               end if;
            end if;
         end;
      end loop;
   end Relocate;

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
      --  A leading tilde is this user's home directory here as everywhere
      --  else: `source ("~/setup.adash")` is a path a user writes, and a
      --  script found through one is a script found.
      Written  : constant String := Adash.Filesystem.Expanded (Path);
      Resolved : constant String := Hostkit.Fs.Real_Path (Written);
   begin
      Status := (Kind => Adash.Execution.Exit_Start_Failure, Code => 127, others => <>);

      if Resolved = "" or else not Ada.Directories.Exists (Written) then
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

               --  A script is a file a user named, and a file a user named can
               --  be the wrong one. Without this, `adash some-disk-image` is a
               --  session that grows until the host ends it rather than a
               --  refusal -- and a shell asked to run something it cannot hold
               --  should say so, which is what Script_Unreadable says.
               if Length (Content) + Natural (Last)
                  > Adash.Filesystem.Default_Limit
               then
                  Ada.Streams.Stream_IO.Close (File);
                  Result := Script_Unreadable;
                  Complain (Report, Adash.Errors.Error_Source_Too_Large, Path);
                  return;
               end if;

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

         --  The line the host read to find this shell, if there is one.
         Blank_A_Shebang (Content);

         --  On the chain while it runs, off it afterwards. A script that
         --  loaded another which loaded the first would otherwise be a hang
         --  rather than a refusal.
         Context.Active.Append (To_Unbounded_String (Resolved));

         declare
            --  What the script asks to have read into it, read in before it
            --  is submitted: a submission is analysed as a whole, so a module
            --  the script wants names from has to be part of that whole.
            Reading : Path_Vectors.Vector;
            Regions : Region_Vectors.Vector;

            Whole : Unbounded_String;

            Before  : constant Natural := D.Count (Report);
            Carried : Natural := 0;
         begin
            --  The script itself goes on the chain first, so a module that
            --  reads it back is caught at the first repeat rather than once
            --  the depth runs out.
            Reading.Append (To_Unbounded_String (Resolved));
            Whole := To_Unbounded_String
              (Read_Into (To_String (Content), Resolved, 0, Reading, Regions));

            Run_Text (Session, To_String (Whole), Path, Result, Status, Report,
                      On_Output => On_Output, Carried => Carried);

            --  Every position in what came back is a position in the text the
            --  session assembled. What a reader needs is the file and the line
            --  they wrote, and only this knows how the two line up.
            Relocate (Report, Before, Regions, Carried, Path,
                      To_String (Content));
         end;

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

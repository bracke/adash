
with Ada.Characters.Latin_1;

with Hostkit;

with Adash.Errors;
with Adash.Execution.Commands;
with Adash.Execution.Pipelines;
with Adash.Execution.Streams;
with Adash.Filesystem;
with Adash.Execution.Internal_Commands;
with Adash.Language.Evaluation;
with Adash.Language.Lexer;
with Adash.Language.Parser;
with Adash.Language.Semantics;
with Ada.Strings.Fixed;

with Adash.Language.Symbols;
with Adash.Predefined;
with Adash.Language.Values;
with Adash.Messages;

package body Adash.Engine is

   package S renames Adash.Language.Syntax;
   package D renames Adash.Diagnostics;
   package Ev renames Adash.Language.Evaluation;

   ---------------------------------------------------------------------
   --  What a lowered program calls when it reaches a shell command.
   --
   --  Adash.Language.Evaluation will not call Adash.Commands: the language
   --  subsystem has no business knowing the shell's vocabulary. It takes a
   --  sink instead, and this is it -- implemented here because the engine is
   --  the one place that already owns both.
   ---------------------------------------------------------------------
   --  What the machine asks, between instructions, to find out whether the
   --  program should stop. A session's cancellation token is the answer; this
   --  is only the shape the language subsystem asks it in, so that the machine
   --  does not need to know what a session is.
   type Cancel_Bridge is limited new Ev.Cancellation_Source with record
      Token : access Adash.Execution.Cancellation.Token;
   end record;

   overriding function Is_Cancelled (Source : Cancel_Bridge) return Boolean;

   overriding function Is_Cancelled (Source : Cancel_Bridge) return Boolean is
   begin
      --  Two ways to be asked to stop, and they are not the same thing. A
      --  caller may set the token -- a test, a timeout, a future job control
      --  -- and a user may press Ctrl-C, which arrives as a signal the shell
      --  records rather than dies of. Either means stop.
      --
      --  Not acknowledged here: this is asked between instructions and may be
      --  asked again, and clearing the arrival on the first ask would let a
      --  program carry on if the machine happened to ask twice. Whoever
      --  started the program acknowledges once it has ended.
      --  The token answers for the recorded interrupt too, so there is one
      --  place that knows Ctrl-C means stop rather than one per waiter.
      return Source.Token /= null and then Source.Token.Is_Requested;
   end Is_Cancelled;

   type Command_Bridge is limited new Ev.Command_Sink with record
      --  What the command may read and change. All three belong to the Submit
      --  that is running; see the note where the bridge is filled in.
      Shell    : access Adash.Commands.State;
      Produced : access Adash.Commands.Output;
      Notes    : access D.List;

      --  Where the lines it produces are rendered, as it produces them.
      Written_To : Output_Sink_Access;

      --  Where a variable's value goes on its way out of the machine.
      Keeping : access Held_Vectors.Vector;
   end record;

   overriding procedure Invoke
     (Sink      : in out Command_Bridge;
      Name      : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Failed    : out Boolean;
      Halt      : out Boolean);

   overriding procedure Keep_Value
     (Sink  : in out Command_Bridge;
      Named : String;
      Shape : String;
      Given : String);

   overriding procedure Ask
     (Sink      : in out Command_Bridge;
      Named     : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Answer    : out Adash.Language.Values.Value);

   ---------
   -- Ask --
   ---------

   overriding procedure Ask
     (Sink      : in out Command_Bridge;
      Named     : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Answer    : out Adash.Language.Values.Value)
   is
      Which : Adash.Predefined.Entity_Id;

      --  One argument, as text, or "" where none was given.
      function Text_At (Position : Positive) return String is
        (if Position <= Count
         then Adash.Language.Values.Text (Arguments (Position)) else "");
   begin
      --  Answered as the empty string unless the entity below says otherwise.
      --  What the answer's type is decides which cell it travels back in, so
      --  this is also the default shape.
      Answer := Adash.Language.Values.To_Value (String'(""));

      if Sink.Shell = null or else not Adash.Predefined.Find (Named, Which) then
         --  The analyser resolved this name to a predefined function, so not
         --  finding it here would mean the two registries disagree.
         return;
      end if;

      case Which is
         when Adash.Predefined.Entity_Env_Value =>
            --  The session's environment, which is what children inherit --
            --  not the shell's own. A program asking what a child will see
            --  should be told what a child will see.
            --
            --  An unset name is the empty string rather than a failure, as it
            --  is in every shell: a program testing whether something is set
            --  compares it, and an error would make that untestable.
            Answer := Adash.Language.Values.To_Value
              (Adash.Execution.Environment.Value
                 (Sink.Shell.Environment, Text_At (1)));

         when Adash.Predefined.Entity_Status =>
            --  The one exit-status model, reduced to its number. A program
            --  killed by a signal reads as 128 plus the signal, a missing
            --  program as 127: the same scale the shell exits with, so a
            --  script forwarding a status does not have to translate it.
            Answer := Adash.Language.Values.To_Value
              (Integer (Adash.Execution.Numeric (Sink.Shell.Last_Status)));

         when Adash.Predefined.Entity_Argument_Count =>
            Answer := Adash.Language.Values.To_Value
              (Adash.Commands.Length (Sink.Shell.Arguments));

         when Adash.Predefined.Entity_Argument =>
            declare
               Position : Integer := 0;
            begin
               --  Out of range answers with the empty string rather than
               --  failing, as an unset variable does: a script asking for an
               --  argument it was not given is asking whether it was given
               --  one, and Argument_Count is there for a script that wants to
               --  ask directly.
               if Count >= 1
                 and then Adash.Language.Values.Get (Arguments (1), Position)
                 and then Position >= 1
               then
                  Answer := Adash.Language.Values.To_Value
                    (Adash.Commands.Element (Sink.Shell.Arguments, Position));
               end if;
            end;

         when Adash.Predefined.Entity_Output_Of =>
            --  The one predefined entity that runs something. What it wrote to
            --  standard output comes back as the value; what it wrote to
            --  standard error is not collected and reaches the user, because a
            --  program explaining why it failed should be heard rather than
            --  swallowed into a value the script is about to compare.
            declare
               Args    : Hostkit.String_Vectors.Vector;
               Line    : Adash.Execution.Pipelines.Plan :=
                 Adash.Execution.Pipelines.Empty_Plan;
               Written : Ada.Strings.Unbounded.Unbounded_String;
               Final   : Adash.Execution.Pipelines.Outcome;
               Failure : Adash.Errors.Error_Info;
               Stop    : Natural;
            begin
               if Count = 0 or else Text_At (1) = "" then
                  --  Nothing to run. Answered as empty rather than reported:
                  --  the analyser has already required an argument, so this is
                  --  a program that computed an empty program name.
                  return;
               end if;

               for Position in 2 .. Count loop
                  Args.Append
                    (Ada.Strings.Unbounded.To_Unbounded_String
                       (Text_At (Position)));
               end loop;

               Adash.Execution.Pipelines.Add_Stage
                 (Line,
                  Adash.Execution.Commands.Make (Text_At (1), Args));

               if not Adash.Execution.Pipelines.Capture
                        (Line, Sink.Shell.Interrupt, Written, Final, Failure)
               then
                  Sink.Notes.Emit
                    (D.From_Error
                       (Failure, D.Severity_Error, D.Category_Execution,
                        D.Owner_Commands));
                  Sink.Shell.Last_Status :=
                    Adash.Execution.From_Start_Error (Failure.Code);
                  return;
               end if;

               Sink.Shell.Last_Status := Final.Status;

               --  Without the newline it ended with, which is the convention
               --  every shell follows and the reason `cd (Output_Of ("pwd"))`
               --  works. Only from the end, and only line endings: what is in
               --  the middle is what the program wrote.
               Stop := Ada.Strings.Unbounded.Length (Written);

               while Stop > 0
                 and then Ada.Strings.Unbounded.Element (Written, Stop)
                          in Ada.Characters.Latin_1.LF
                            | Ada.Characters.Latin_1.CR
               loop
                  Stop := Stop - 1;
               end loop;

               Answer := Adash.Language.Values.To_Value
                 (Ada.Strings.Unbounded.Slice (Written, 1, Stop));
            end;

         when Adash.Predefined.Entity_Read_Line =>
            declare
               Ended : Boolean;
               Line  : constant String :=
                 Adash.Execution.Streams.Read_Line (Ended);
            begin
               --  Remembered rather than answered here: a line and whether
               --  there was one are two questions, and an empty line is a line
               --  a file may genuinely contain.
               Sink.Shell.Input_Ended := Ended;
               Answer := Adash.Language.Values.To_Value (Line);
            end;

         when Adash.Predefined.Entity_Input_Ended =>
            Answer := Adash.Language.Values.To_Value (Sink.Shell.Input_Ended);

         when Adash.Predefined.Entity_Exists =>
            Answer := Adash.Language.Values.To_Value
              (Adash.Filesystem.Exists (Text_At (1)));

         when Adash.Predefined.Entity_Is_Directory =>
            Answer := Adash.Language.Values.To_Value
              (Adash.Filesystem.Is_Directory (Text_At (1)));

         when Adash.Predefined.Entity_Is_Executable =>
            Answer := Adash.Language.Values.To_Value
              (Adash.Filesystem.Is_Executable (Text_At (1)));

         when others =>
            null;
      end case;
   end Ask;

   ------------------
   -- Keep_Value --
   ------------------

   overriding procedure Keep_Value
     (Sink  : in out Command_Bridge;
      Named : String;
      Shape : String;
      Given : String)
   is
      --  A String arrives as its contents and has to be written back as a
      --  literal; everything else arrives as `'Image` already, which this
      --  language reads back as it stands.
      Written : constant String :=
        (if Shape = "String" or else Shape = "constant String"
         then Adash.Language.Values.Literal
                (Adash.Language.Values.To_Value (Given))
         else Ada.Strings.Fixed.Trim (Given, Ada.Strings.Both));
   begin
      if Sink.Keeping = null then
         return;
      end if;

      --  A member of a package, a task or a protected object comes back as an
      --  *assignment* rather than as a declaration: its name has a dot in it,
      --  and a dotted name cannot be declared. What declares it is the
      --  declaration that holds it, which is carried too and comes first --
      --  so this puts the value back into what that re-elaborated.
      --
      --  Without it a package variable was reset by every submission, and
      --  `P.Count := P.Count + 1` twice running counted to one.
      Sink.Keeping.Append
        (Held_Declaration'
           (Key       => Ada.Strings.Unbounded.To_Unbounded_String
                           (Adash.Language.Symbols.Fold (Named)),
            Text      => Ada.Strings.Unbounded.To_Unbounded_String
                           (if Ada.Strings.Fixed.Index (Named, ".") > 0
                            then Named & " := " & Written & ";"
                            else Named & " : " & Shape & " := "
                                 & Written & ";"),
            Is_Object => True));
   end Keep_Value;

   ------------
   -- Invoke --
   ------------

   overriding procedure Invoke
     (Sink      : in out Command_Bridge;
      Name      : String;
      Arguments : Ev.Argument_Values;
      Count     : Natural;
      Failed    : out Boolean;
      Halt      : out Boolean)
   is
      Which  : Adash.Commands.Command_Id;
      Given  : Adash.Commands.Argument_Set;
      Status : Adash.Execution.Exit_Status;
   begin
      Failed := True;
      Halt := False;

      if Sink.Shell = null
        or else not Adash.Execution.Internal_Commands.Is_Internal (Name, Which)
      then
         --  The analyser resolved this name to a command, so failing to find
         --  it here would mean the two registries disagree. Nothing useful can
         --  be done about it from inside a running program.
         return;
      end if;

      --  Both bounds are real: the machine carries a fixed number of slots and
      --  a command's own table holds a fixed number of values. Taking the
      --  smaller is what keeps a widening on one side from writing past the
      --  other.
      Given.Count :=
        Natural'Min (Count, Adash.Commands.Max_Parameters);

      for Position in 1 .. Given.Count loop
         Given.Given (Position) := Arguments (Position);
      end loop;

      declare
         Before : constant Natural := Sink.Produced.Count;
      begin
         Status := Adash.Commands.Execute
           (Which, Given, Sink.Shell.all, Sink.Produced.all,
            Sink.Notes.all);

         --  Whatever this command added, rendered now rather than after the
         --  submission. A program's own output goes to the same stream as the
         --  machine runs it, so anything held back arrives in the wrong place.
         if Sink.Written_To /= null then
            for Index in Before + 1 .. Sink.Produced.Count loop
               Write (Sink.Written_To.all, Sink.Produced.Element (Index));
            end loop;
         end if;
      end;

      --  What a program reads through `Status`. Recorded for every command,
      --  internal or external: a shell that only remembered the failures would
      --  answer for something older than the last thing that ran.
      Sink.Shell.Last_Status := Status;

      Failed := not Adash.Execution.Succeeded (Status);

      --  `quit` is the command that ends a session, and it says so by setting
      --  this rather than by being named here: a second command that ended a
      --  session would otherwise have to be added in two places.
      Halt := Sink.Shell.Exit_Requested;
   end Invoke;

   use type Ev.Outcome;

   ----------
   -- Open --
   ----------

   procedure Open (Item : in out Session) is
   begin
      Adash.Commands.Initialize (Item.Shell);
      Item.Output.Clear;
      Item.Cancel.Reset;
      Item.Opened := True;
   end Open;

   --  The name a call statement names, or "" when the statement is not one.
   ------------
   -- Submit --
   ------------

   ------------------------
   -- Use_Script_Runner --
   ------------------------

   procedure Use_Script_Runner
     (Item : in out Session; Runner : Adash.Commands.Runner_Access) is
   begin
      if not Item.Opened then
         Open (Item);
      end if;

      Item.Shell.Scripts := Runner;
   end Use_Script_Runner;

   -------------------
   -- Use_History --
   -------------------

   procedure Use_History
     (Item : in out Session; Source : Adash.Commands.History_Access) is
   begin
      if not Item.Opened then
         Open (Item);
      end if;

      Item.Shell.History := Source;
   end Use_History;

   ----------------
   -- Carried --
   ----------------

   --  Everything this session is holding that the submission does not replace.
   function Carried
     (Item : Session; Replaced : Held_Vectors.Vector) return String
   is
      use type Ada.Strings.Unbounded.Unbounded_String;
      Text : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Held of Item.Kept loop
         declare
            Superseded : Boolean := False;
         begin
            for Gone of Replaced loop
               if Gone.Key = Held.Key then
                  Superseded := True;
               end if;
            end loop;

            if not Superseded
              and then Held.Text /= Ada.Strings.Unbounded.Null_Unbounded_String
            then
               Ada.Strings.Unbounded.Append (Text, Held.Text);
               Ada.Strings.Unbounded.Append (Text, ASCII.LF);
            end if;
         end;
      end loop;

      return Ada.Strings.Unbounded.To_String (Text);
   end Carried;

   -------------------
   -- Profile_Key --
   -------------------

   --  What makes two declarations the same declaration.
   --
   --  Name, the type names of the parameters, and the result type name -- the
   --  language's own rule for whether a call could tell two subprograms apart,
   --  applied across submissions. Redefining `LL` replaces the `LL` that was
   --  there; declaring an `LL` that takes something different adds an overload.
   --
   --  Built from the tree rather than from the resolved symbols, because it has
   --  to be known *before* anything is analysed: a submission that redefines
   --  something must not have the old definition prepended to it, or the two
   --  collide inside one program and the redefinition is reported as a
   --  duplicate. Type names are written directly in this language, so the
   --  syntactic key and the semantic one agree.
   function Profile_Key
     (Tree : Adash.Language.Syntax.Tree;
      Node : Adash.Language.Syntax.Node_Id) return String
   is
      package S renames Adash.Language.Syntax;

      Formals : constant S.Node_Id := S.Child (Tree, Node, 2);
      Result  : constant S.Node_Id := S.Child (Tree, Node, 3);

      Text : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (Adash.Language.Symbols.Fold (S.Text (Tree, S.Child (Tree, Node, 1))));
   begin
      Ada.Strings.Unbounded.Append
        (Text,
         "/" & (if S.Is_Present (Result)
                then Adash.Language.Symbols.Fold (S.Text (Tree, Result))
                else ""));

      for Index in 1 .. S.Child_Count (Tree, Formals) loop
         Ada.Strings.Unbounded.Append
           (Text,
            "/" & Adash.Language.Symbols.Fold
                    (S.Text (Tree, S.Second (Tree, S.Child (Tree, Formals, Index)))));
      end loop;

      return Ada.Strings.Unbounded.To_String (Text);
   end Profile_Key;

   ---------------------
   -- Redefined_Here --
   ---------------------

   --  The keys of the subprograms a piece of source declares at its top level.
   --
   --  Parsed on its own, which costs a second parse of every submission and
   --  buys the only ordering that works: what a session is carrying can only be
   --  put in front of a submission once it is known what that submission
   --  replaces.
   function Redefined_Here
     (Text : String; Origin : Adash.Source.Origin) return Held_Vectors.Vector
   is
      package S renames Adash.Language.Syntax;
      use type S.Node_Kind;

      Found : Held_Vectors.Vector;

      Probe   : Scratch;
      Ignored : D.List;
      Error   : Adash.Errors.Error_Info;
   begin
      if not Adash.Source.Load (Probe.Buffer, Origin, Text, Error) then
         return Found;
      end if;

      Adash.Language.Lexer.Scan (Probe.Buffer, Probe.Stream, Ignored);
      Adash.Language.Parser.Parse (Probe.Stream, Origin, Probe.Tree, Ignored);

      declare
         Root : constant S.Node_Id := S.Root (Probe.Tree);
      begin
         for Index in 1 .. S.Child_Count (Probe.Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Probe.Tree, Root, Index);
            begin
               if S.Kind (Probe.Tree, Node) = S.Node_Object_Declaration then
                  Found.Append
                    (Held_Declaration'
                       (Key       => Ada.Strings.Unbounded.To_Unbounded_String
                                       (Adash.Language.Symbols.Fold
                                          (S.Text (Probe.Tree,
                                                   S.First (Probe.Tree, Node)))),
                        Text      =>
                          Ada.Strings.Unbounded.Null_Unbounded_String,
                        Is_Object => True));

               elsif S.Kind (Probe.Tree, Node) = S.Node_Subprogram_Declaration
               then
                  Found.Append
                    (Held_Declaration'
                       (Key       => Ada.Strings.Unbounded.To_Unbounded_String
                                       (Profile_Key (Probe.Tree, Node)),
                        Text      =>
                          Ada.Strings.Unbounded.Null_Unbounded_String,
                        Is_Object => False));
               end if;
            end;
         end loop;
      end;

      return Found;
   end Redefined_Here;

   -----------------------
   -- Keep_Declarations --
   -----------------------

   --  Remember the subprograms a submission declared.
   --
   --  Only the ones written at the top level: a subprogram nested inside
   --  another comes back with the body that encloses it, and carrying it
   --  separately would declare it where it cannot be called.
   procedure Keep_Declarations
     (Item   : in out Session;
      Tree   : Adash.Language.Syntax.Tree;
      Buffer : Adash.Source.Buffer;
      Report : in out D.List)
   is
      package S renames Adash.Language.Syntax;
      use type Ada.Strings.Unbounded.Unbounded_String;
      use type S.Node_Kind;

      Root : constant S.Node_Id := S.Root (Tree);

      --  Whether a name was declared as a task *type* in this submission.
      --
      --  A task type's body starts nothing -- it is what its objects run, and
      --  each of those is where a task begins -- so it is carried like a
      --  package body. A single task's body is not, because running it is what
      --  starts the task and carrying it would start one again on every line
      --  typed after it.
      --
      --  The tree is the whole answer: what an earlier submission declared was
      --  carried into this one and stands here as well.
      function Declares_Task_Type (Name : String) return Boolean;

      --  Whether a name was declared as a protected *type* in this
      --  submission.
      --
      --  An object of one is state and a lock, and it is carried the way a
      --  protected object written out in full is: by replaying the
      --  declaration and handing its state back. What must not happen is its
      --  being carried as a *value*, which is what an ordinary object
      --  declaration is kept as -- a protected object has no value, so
      --  nothing came back and the name was gone with it.
      function Declares_Guarded_Type (Name : String) return Boolean;

      --  Say that a definition was not remembered.
      --
      --  A definition silently not kept would look like one that was, until
      --  the line that used it failed for no visible reason. That was true of
      --  variables until it was written down: the warning existed and only the
      --  subprogram-and-type path reached it, so a session past the limit lost
      --  its next variable without a word and the line after it reported an
      --  undeclared name.
      --
      --  @param Named The name that will not be there next time.
      procedure Not_Remembered (Named : S.Node_Id);

      procedure Not_Remembered (Named : S.Node_Id) is
      begin
         Report.Emit
           (D.Make
              (Message   =>
                 Adash.Errors.Message (Adash.Errors.Error_Too_Many_Kept),
               Level     => D.Severity_Warning,
               Of_Kind   => D.Category_Semantic,
               Raised_By => D.Owner_Language,
               Origin    => Adash.Source.From (Buffer),
               Extent    => S.Extent (Tree, Named),
               Arguments =>
                 [Adash.Messages.Named ("name", S.Text (Tree, Named)),
                  Adash.Messages.Named
                    ("limit", Natural'Image (Max_Kept))]));
      end Not_Remembered;

      --  Keep one declaration as the source text it was written as.
      --
      --  @param Node The declaration.
      --  @param Named The name it introduced, which the entry is keyed on.
      procedure Keep_As_Text (Node, Named : S.Node_Id);

      procedure Keep_As_Text (Node, Named : S.Node_Id) is
         --  Keyed on what kind of declaration it is as well as on the name, so
         --  a package and its body are two entries and neither replaces the
         --  other -- and a `use` is one entry per package, so writing it twice
         --  does not accumulate.
         Entry_To_Keep : constant Held_Declaration :=
           (Key       =>
              Ada.Strings.Unbounded.To_Unbounded_String
                (S.Node_Kind'Image (S.Kind (Tree, Node)) & " "
                 & Adash.Language.Symbols.Fold (S.Text (Tree, Named))),
            Text      =>
              Ada.Strings.Unbounded.To_Unbounded_String
                (Adash.Source.Slice (Buffer, S.Extent (Tree, Node))),
            Is_Object => False);

         Replaced : Boolean := False;
      begin
         for Position in 1 .. Natural (Item.Kept.Length) loop
            if Item.Kept.Element (Position).Key = Entry_To_Keep.Key then
               Item.Kept.Replace_Element (Position, Entry_To_Keep);
               Replaced := True;
               exit;
            end if;
         end loop;

         if Replaced then
            null;

         elsif Natural (Item.Kept.Length) < Max_Kept then
            Item.Kept.Append (Entry_To_Keep);

         else
            Not_Remembered (Named);
         end if;
      end Keep_As_Text;

      function Declares_Guarded_Type (Name : String) return Boolean is
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Protected_Declaration
                 and then S.Text (Tree, Node) = "type"
                 and then Adash.Language.Symbols.Fold
                            (S.Text (Tree, S.First (Tree, Node)))
                          = Adash.Language.Symbols.Fold (Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Declares_Guarded_Type;

      function Declares_Task_Type (Name : String) return Boolean is
      begin
         for Index in 1 .. S.Child_Count (Tree, Root) loop
            declare
               Node : constant S.Node_Id := S.Child (Tree, Root, Index);
            begin
               if S.Kind (Tree, Node) = S.Node_Task_Declaration
                 and then S.Text (Tree, Node) = "type"
                 and then Adash.Language.Symbols.Fold
                            (S.Text (Tree, S.First (Tree, Node)))
                          = Adash.Language.Symbols.Fold (Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Declares_Task_Type;
   begin
      for Index in 1 .. S.Child_Count (Tree, Root) loop
         declare
            Node : constant S.Node_Id := S.Child (Tree, Root, Index);
         begin
            if S.Kind (Tree, Node) = S.Node_Object_Declaration
              and then Declares_Guarded_Type
                         (S.Text (Tree, S.Second (Tree, Node)))
            then
               --  Kept as what was written, so that the next submission
               --  declares the object again and its state comes back into it.
               Keep_As_Text (Node, S.First (Tree, Node));

            elsif S.Kind (Tree, Node) = S.Node_Object_Declaration then
               --  Recorded here so that its position is the one the source
               --  gave it. The value arrives later, from the program itself.
               --
               --  A name this session is already holding keeps what it is
               --  holding. Every carried variable is declared again in every
               --  submission -- that is how its value comes back -- so
               --  emptying it here would leave the whole session's variables
               --  waiting for a hand-back that a program stopping early never
               --  makes, and one raise would take them all. What a submission
               --  that stops early loses is what *it* declared, which has no
               --  entry yet and gets an empty one.
               declare
                  Named : constant S.Node_Id := S.First (Tree, Node);

                  Placed : constant Held_Declaration :=
                    (Key       => Ada.Strings.Unbounded.To_Unbounded_String
                                    (Adash.Language.Symbols.Fold
                                       (S.Text (Tree, Named))),
                     Text      => Ada.Strings.Unbounded.Null_Unbounded_String,
                     Is_Object => True);

                  Already : Boolean := False;
               begin
                  for Position in 1 .. Natural (Item.Kept.Length) loop
                     if Item.Kept.Element (Position).Key = Placed.Key then
                        Already := True;
                        exit;
                     end if;
                  end loop;

                  if Already then
                     null;

                  elsif Natural (Item.Kept.Length) < Max_Kept then
                     Item.Kept.Append (Placed);

                  else
                     --  Said out loud, as a definition is. What follows
                     --  otherwise is a line reporting an undeclared name for a
                     --  variable the user watched themselves declare.
                     Not_Remembered (Named);
                  end if;
               end;

            elsif S.Kind (Tree, Node) in S.Node_Type_Declaration
                                       | S.Node_Subtype_Declaration
                                       | S.Node_Record_Declaration
                                       | S.Node_Array_Declaration
                                       | S.Node_Package_Declaration
                                       | S.Node_Package_Body
                                       | S.Node_Use
                                       | S.Node_Generic_Declaration
                                       | S.Node_Instantiation

                                       --  A protected object is state and is
                                       --  carried like a package. A task
                                       --  *declaration* is a name and is
                                       --  carried too, so that a body typed on
                                       --  the next line finds it.
                                       --
                                       --  A task *body* is not carried. The
                                       --  declarative region that declared the
                                       --  task is its master, a submission is
                                       --  that region, and Ada says a task
                                       --  cannot outlive its master -- so
                                       --  carrying the body would start the
                                       --  task again on every line typed after
                                       --  it.
                                       | S.Node_Protected_Declaration
                                       | S.Node_Protected_Body
                                       | S.Node_Task_Declaration

                                       --  An exception is a name and nothing
                                       --  else, so what is carried is the
                                       --  declaration that makes the name --
                                       --  there is no value to hand back, and
                                       --  a raise on the next line has to
                                       --  find the same name a handler will.
                                       | S.Node_Exception_Declaration
              or else (S.Kind (Tree, Node) = S.Node_Task_Body
                       and then Declares_Task_Type
                                  (S.Text (Tree, S.First (Tree, Node))))
            then
               --  Carried as its source text, the way a subprogram is: a type
               --  is a declaration, the next submission has to see the same
               --  one, and replaying what the user wrote is the only way to
               --  get the literals back with it. Keyed on the type's name, so
               --  declaring it again replaces it rather than accumulating.
               --
               --  A generic's name is its subprogram's, which is the second
               --  child: the first is the formals it was written with.
               Keep_As_Text
                 (Node,
                  (if S.Kind (Tree, Node) = S.Node_Generic_Declaration
                   then S.First (Tree, S.Second (Tree, Node))
                   else S.First (Tree, Node)));

            elsif S.Kind (Tree, Node) = S.Node_Subprogram_Declaration
              and then S.Is_Present (S.Child (Tree, Node, 5))
            then
               declare
                  Named : constant S.Node_Id := S.Child (Tree, Node, 1);
               begin
                  if True then
                     declare
                        Key : constant String := Profile_Key (Tree, Node);

                        Entry_To_Keep : constant Held_Declaration :=
                          (Key       =>
                             Ada.Strings.Unbounded.To_Unbounded_String (Key),
                           Text      =>
                             Ada.Strings.Unbounded.To_Unbounded_String
                               (Adash.Source.Slice
                                  (Buffer, S.Extent (Tree, Node))),
                           Is_Object => False);

                        Replaced : Boolean := False;
                     begin
                        for Position in 1 .. Natural (Item.Kept.Length) loop
                           if Item.Kept.Element (Position).Key = Entry_To_Keep.Key
                           then
                              Item.Kept.Replace_Element (Position, Entry_To_Keep);
                              Replaced := True;
                              exit;
                           end if;
                        end loop;

                        if not Replaced then
                           if Natural (Item.Kept.Length) < Max_Kept then
                              Item.Kept.Append (Entry_To_Keep);
                           else
                              Not_Remembered (Named);
                           end if;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Keep_Declarations;

   ------------------
   -- Wants_More --
   ------------------

   function Wants_More (Text : String; Name : String) return Boolean is
      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_Interactive, Name);

      Buffer : Adash.Source.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Aside  : D.List;
      Error  : Adash.Errors.Error_Info;
   begin
      --  Asked of the text on its own rather than of the session's carried
      --  declarations and this text together: what the user is part-way
      --  through typing is this, and prefixing it with everything the session
      --  remembers would answer about a program they did not write.
      if not Adash.Source.Load (Buffer, Origin, Text, Error) then
         --  Not valid UTF-8, which more input cannot mend.
         return False;
      end if;

      Adash.Language.Lexer.Scan (Buffer, Stream, Aside);

      return Adash.Language.Parser.Wants_More (Stream, Origin);
   end Wants_More;

   procedure Submit
     (Item    : in out Session;
      Text    : String;
      Name    : String;
      Kind    : Adash.Source.Origin_Kind := Adash.Source.Origin_Interactive;
      Outcome : out Result;
      Report  : in out D.List;
      On_Output : Output_Sink_Access := null)
   is
      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Kind, Name);
      Load_Error : Adash.Errors.Error_Info;

      --  A submission made while another is running -- `source` inside one --
      --  cannot use the session's buffer, token stream or tree: the outer
      --  submission is still reading from them.
      Nested : constant Boolean := Item.Busy;

      Own : aliased Scratch;

      --  Points at the session's set, or at the one above when nested. The
      --  access lives exactly as long as this call, which is why taking it of
      --  a local is safe here and would not be if it were stored anywhere.
      Work : constant Scratch_Access :=
        (if Nested then Own'Unchecked_Access else Item.Work'Unchecked_Access);

      Was_Busy : constant Boolean := Item.Busy;

      --  The submission proper. A procedure rather than the body of Submit so
      --  that the busy flag is put back in one place: there are five ways out
      --  of it, and a flag left set would make the *next* submission think it
      --  was nested and quietly work on a buffer of its own.
      procedure Run_Submission is
      begin

         Item.Output.Clear;

         --  Source acquisition and UTF-8 validation, once, for every path.
         --  What this session is holding comes first, so a definition typed
         --  earlier and the line that uses it are one program. They have to be:
         --  a name is resolved by the semantic pass, and a pass that never saw
         --  the definition cannot resolve a call to it.
         if not Adash.Source.Load
           (Work.Buffer, Origin,
            Carried (Item, Redefined_Here (Text, Origin)) & Text, Load_Error)
         then
            Report.Emit
              (D.From_Error (Load_Error, D.Severity_Fatal, D.Category_Lexical,
                             D.Owner_Source, Origin));
            Outcome.Kind := Not_Understood;
            Outcome.Status := (Kind => Adash.Execution.Exit_Parse_Failure, others => <>);
            return;
         end if;

         Adash.Language.Lexer.Scan (Work.Buffer, Work.Stream, Report);
         Adash.Language.Parser.Parse (Work.Stream, Origin, Work.Tree, Report);

         if S.Has_Errors (Work.Tree) then
            Outcome.Kind := Not_Understood;
            Outcome.Status := (Kind => Adash.Execution.Exit_Parse_Failure, others => <>);
            return;
         end if;

         if S.Child_Count (Work.Tree, S.Root (Work.Tree)) = 0 then
            --  Empty, or comments only. Not an error, and not something to run.
            return;
         end if;

         --  A program.
         declare
            Analysis : Adash.Language.Semantics.Analysis;
            Ran      : Ev.Outcome;
         begin
            Adash.Language.Semantics.Analyse (Work.Tree, Origin, Analysis, Report);

            if not Adash.Language.Semantics.Is_Legal (Analysis) then
               Outcome.Kind := Not_Understood;
               Outcome.Status :=
                 (Kind => Adash.Execution.Exit_Semantic_Failure, others => <>);
               return;
            end if;

            if Item.Cancel.Is_Requested then
               --  Asked to stop before anything ran. Reported as a cancellation
               --  rather than as success, so a script does not carry on.
               Outcome.Kind := Language_Program;
               Outcome.Status := (Kind => Adash.Execution.Exit_Cancelled, others => <>);
               return;
            end if;

            declare
               --  Unchecked_Access, and safe: the bridge is used only by Ev.Run,
               --  which returns before this block does, so everything it points
               --  at outlives it. Ada cannot see that -- Sink_Access is a general
               --  access type at library level and these are parts of a parameter
               --  and of a local -- and the alternative is a second process-wide
               --  variable holding the current session, which would be a worse
               --  answer to a narrower problem.
               Stopper : aliased Cancel_Bridge :=
                 (Token => Item.Cancel'Unchecked_Access);

               --  Where the program's own variables arrive as it ends.
               Handed_Back : aliased Held_Vectors.Vector;

               Bridge : aliased Command_Bridge :=
                 (Shell      => Item.Shell'Unchecked_Access,
                  Produced   => Item.Output'Unchecked_Access,
                  Notes      => Report'Unchecked_Access,
                  Written_To => On_Output,
                  Keeping    => Handed_Back'Unchecked_Access);
            begin
               --  Kept before it runs, not after: a program that declares a
               --  subprogram and then fails half way through still declared
               --  it, and a definition that vanished because a later line
               --  raised would be maddening to work with.
               Keep_Declarations (Item, Work.Tree, Work.Buffer, Report);

               Ev.Run (Work.Tree, Analysis, Origin, Ran, Report,
                       On_Command => Bridge'Unchecked_Access,
                       Cancel     => Stopper'Unchecked_Access);

               --  The values the program handed back, put into the places its
               --  declarations already took. A variable whose value never
               --  arrived -- because the program stopped early -- keeps an
               --  empty text and is not carried.
               for Given of Handed_Back loop
                  declare
                     Placed : Boolean := False;
                  begin
                     for Position in 1 .. Natural (Item.Kept.Length) loop
                        if Ada.Strings.Unbounded."="
                             (Item.Kept.Element (Position).Key, Given.Key)
                        then
                           Item.Kept.Replace_Element (Position, Given);
                           Placed := True;
                           exit;
                        end if;
                     end loop;

                     --  Appended when nothing was holding a place for it. A
                     --  place is held by the declaration seen at the root, and
                     --  a package member's declaration is not there -- it is
                     --  inside the package. Without this a package variable
                     --  was reset by every submission, because its value was
                     --  handed back and then dropped.
                     if Placed then
                        null;

                     elsif Natural (Item.Kept.Length) < Max_Kept then
                        Item.Kept.Append (Given);

                     elsif Ada.Strings.Fixed.Index
                             (Ada.Strings.Unbounded.To_String (Given.Key),
                              ".") > 0
                     then
                        --  Said out loud here too, for the names that reach
                        --  this branch and no other: a package's member, whose
                        --  declaration is inside the package rather than at
                        --  the root, so nothing held a place for it and
                        --  nothing has reported it yet. A plain variable was
                        --  reported where it was declared, spelt as it was
                        --  written; saying it again from a folded key would be
                        --  the same warning twice in two spellings.
                        Report.Emit
                          (D.Make
                             (Message   =>
                                Adash.Errors.Message
                                  (Adash.Errors.Error_Too_Many_Kept),
                              Level     => D.Severity_Warning,
                              Of_Kind   => D.Category_Semantic,
                              Raised_By => D.Owner_Language,
                              Origin    => Origin,
                              Extent    => Adash.Source.Nowhere,
                              Arguments =>
                                [Adash.Messages.Named
                                   ("name",
                                    Ada.Strings.Unbounded.To_String
                                      (Given.Key)),
                                 Adash.Messages.Named
                                   ("limit", Natural'Image (Max_Kept))]));
                     end if;
                  end;
               end loop;
            end;

            Outcome.Kind := Language_Program;

            case Ran is
               when Ev.Evaluated =>
                  Outcome.Ran := True;
                  Outcome.Status := Adash.Execution.Success;

               when Ev.Cancelled =>
                  --  Stopped from outside while it was running. Not a failure of
                  --  the program, and reported as its own status so a script can
                  --  tell an interruption from a fault.
                  Outcome.Ran := True;
                  Outcome.Status :=
                    (Kind => Adash.Execution.Exit_Cancelled, others => <>);

               when Ev.Raised =>
                  Outcome.Ran := True;
                  Outcome.Status :=
                    (Kind => Adash.Execution.Exit_Internal_Failure, others => <>);

               when Ev.Not_Lowerable =>
                  Outcome.Status :=
                    (Kind => Adash.Execution.Exit_Semantic_Failure, others => <>);

               when Ev.Refused =>
                  Outcome.Kind := Not_Understood;
                  Outcome.Status :=
                    (Kind => Adash.Execution.Exit_Semantic_Failure, others => <>);
            end case;
         end;
      end Run_Submission;
   begin
      Outcome := (Kind   => Nothing_Submitted,
                  Status => Adash.Execution.Success,
                  Ran    => False);

      if not Item.Opened then
         Open (Item);
      end if;

      --  The session's own token, so a command that waits for a program sees
      --  the same interrupt the machine does. Set here rather than at Open
      --  because Open may run before the token exists in a caller's order.
      Item.Shell.Interrupt := Item.Cancel'Unchecked_Access;

      Item.Busy := True;
      Run_Submission;
      Item.Busy := Was_Busy;
   end Submit;

   ---------------------
   -- Exit_Requested --
   ---------------------

   function Exit_Requested (Item : Session) return Boolean is
   begin
      return Item.Shell.Exit_Requested;
   end Exit_Requested;

   ------------------
   -- Exit_Status --
   ------------------

   function Exit_Status (Item : Session) return Adash.Execution.Exit_Status is
   begin
      return Item.Shell.Exit_Status;
   end Exit_Status;

   -------------------
   -- Output_Count --
   -------------------

   function Output_Count (Item : Session) return Natural is
   begin
      return Item.Output.Count;
   end Output_Count;

   ------------------
   -- Output_Line --
   ------------------

   function Output_Line
     (Item : Session; Index : Positive) return Adash.Commands.Line is
   begin
      return Item.Output.Element (Index);
   end Output_Line;

   ----------------------------
   -- Request_Cancellation --
   ----------------------------

   procedure Request_Cancellation (Item : in out Session) is
   begin
      Item.Cancel.Request;
   end Request_Cancellation;

   --------------------------
   -- Clear_Cancellation --
   --------------------------

   procedure Clear_Cancellation (Item : in out Session) is
   begin
      Item.Cancel.Reset;
   end Clear_Cancellation;

   ------------------------------
   -- Cancellation_Requested --
   ------------------------------

   function Cancellation_Requested (Item : Session) return Boolean is
   begin
      return Item.Cancel.Is_Requested;
   end Cancellation_Requested;

   --------------
   -- Settings --
   --------------

   function Settings (Item : Session) return Adash.Configuration.Settings is
   begin
      return Item.Shell.Chosen;
   end Settings;

   ---------------------
   -- Apply_Settings --
   ---------------------

   --------------------
   -- Add_Argument --
   --------------------

   procedure Add_Argument
     (Item     : in out Session;
      Position : Positive;
      Value    : String)
   is
      pragma Unreferenced (Position);
   begin
      Adash.Commands.Append (Item.Shell.Arguments, Value);
   end Add_Argument;

   --------------------
   -- Argument_Count --
   --------------------

   function Argument_Count (Item : Session) return Natural is
   begin
      return Adash.Commands.Length (Item.Shell.Arguments);
   end Argument_Count;

   procedure Apply_Settings
     (Item : in out Session; To : Adash.Configuration.Settings)
   is
   begin
      Item.Shell.Chosen := To;
   end Apply_Settings;

   -----------------
   -- Environment --
   -----------------

   function Environment
     (Item : Session) return Adash.Execution.Environment.Block is
   begin
      return Item.Shell.Environment;
   end Environment;

end Adash.Engine;

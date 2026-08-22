with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Errors;
with Adash.Messages;
with Adash.Source;

package body Adash_Tests.Source_Cases is

   use AUnit.Assertions;

   use type Adash.Errors.Error_Code;
   use type Adash.Diagnostics.Severity;
   use type Adash.Diagnostics.Category;
   use type Adash.Diagnostics.Owner;
   use type Adash.Messages.Message_Id;
   use type Adash.Source.Origin_Kind;

   package Src renames Adash.Source;
   package Diag renames Adash.Diagnostics;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   function Text_Origin return Src.Origin
   is (Src.Make_Origin (Src.Origin_Text, "<test>"));

   ------------------------------------------------------------------
   --  Spans
   ------------------------------------------------------------------

   procedure Spans_Follow_The_Slice_Convention
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty : constant Src.Span := Src.Nowhere;
      Three : constant Src.Span := (First => 5, Last => 7);
   begin
      Assert (Src.Is_Empty (Empty), "Nowhere is not empty");
      Assert (Src.Length (Empty) = 0, "an empty span has a length");
      Assert (Src.Length (Three) = 3, "a three byte span did not measure three");

      --  An empty span still has a position, so joining one contributes where
      --  the missing thing was expected. A parser giving a node the extent of a
      --  present child and a missing one depends on this.
      declare
         Joined : constant Src.Span := Src.Join (Three, (First => 2, Last => 1));
      begin
         Assert (Joined.First = 2, "join did not take the earlier position");
         Assert (Joined.Last = 7, "join lost the real extent");
      end;

      declare
         Both : constant Src.Span :=
           Src.Join ((First => 1, Last => 4), (First => 9, Last => 12));
      begin
         Assert (Both.First = 1 and then Both.Last = 12,
                 "join did not produce the hull");
      end;
   end Spans_Follow_The_Slice_Convention;

   ------------------------------------------------------------------
   --  Loading and encoding
   ------------------------------------------------------------------

   procedure Well_Formed_Text_Loads
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;
   begin
      Assert (Src.Load (Buffer, Text_Origin, "alpha" & LF & "beta", Error),
              "well formed text was rejected");
      Assert (Src.Is_Loaded (Buffer), "a loaded buffer says it is not");
      Assert (Src.Length (Buffer) = 10, "the buffer lost bytes");
      Assert (Src.Text (Buffer) = "alpha" & LF & "beta", "the text changed");
      Assert (Src.Kind (Src.From (Buffer)) = Src.Origin_Text,
              "the buffer lost its origin kind");
      Assert (Src.Name (Src.From (Buffer)) = "<test>",
              "the buffer lost its origin name");

      --  Multi-byte input is text, not an error. The point of validating is to
      --  accept this and refuse what is actually malformed.
      declare
         Accented : constant String := "s" & Character'Val (16#C3#)
           & Character'Val (16#A5#) & "r";
      begin
         Assert (Src.Load (Buffer, Text_Origin, Accented, Error),
                 "valid two-byte UTF-8 was rejected");
      end;
   end Well_Formed_Text_Loads;

   procedure Malformed_Encoding_Is_Refused_Once
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;

      procedure Refuses (Label : String; Text : String);

      procedure Refuses (Label : String; Text : String) is
      begin
         Assert (not Src.Load (Buffer, Text_Origin, Text, Error),
                 Label & " was accepted as UTF-8");
         Assert (Error.Code = Adash.Errors.Error_Source_Invalid_Encoding,
                 Label & " was refused for the wrong reason: "
                 & Adash.Errors.Error_Code'Image (Error.Code));
         Assert (not Src.Is_Loaded (Buffer),
                 Label & " left the buffer loaded");
      end Refuses;

   begin
      --  A continuation byte cannot start a sequence.
      Refuses ("a stray continuation byte", "ok" & Character'Val (16#80#));

      --  Truncated at the end of input.
      Refuses ("a truncated sequence", "ok" & Character'Val (16#C3#));

      --  A lead byte followed by something that is not a continuation.
      Refuses ("a broken sequence",
               Character'Val (16#C3#) & "x");

      --  An overlong encoding: a well-shaped sequence for a character that has
      --  a shorter form. Accepting these is how a check on the decoded text is
      --  smuggled past.
      Refuses ("an overlong two-byte encoding",
               Character'Val (16#C0#) & Character'Val (16#AF#));

      --  A surrogate half, which is never valid UTF-8.
      Refuses ("a surrogate half",
               Character'Val (16#ED#) & Character'Val (16#A0#)
               & Character'Val (16#80#));

      --  Beyond U+10FFFF.
      Refuses ("a sequence past the last character",
               Character'Val (16#F5#) & Character'Val (16#80#)
               & Character'Val (16#80#) & Character'Val (16#80#));

      --  And the offset is reported, so a diagnostic can point at it.
      Assert (Adash.Errors.Arguments (Error)'Length = 2,
              "the encoding failure did not carry its source and offset");
   end Malformed_Encoding_Is_Refused_Once;

   ------------------------------------------------------------------
   --  Line mapping
   ------------------------------------------------------------------

   procedure Line_Endings_Are_Normalized_Without_Moving_Offsets
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;
   begin
      --  CR LF is one terminator. Counting it as two would report twice the
      --  lines a Windows file has, and every line number in every diagnostic
      --  would be wrong.
      Assert (Src.Load (Buffer, Text_Origin, "one" & CR & LF & "two" & CR & LF & "three", Error),
              "CRLF text was rejected");
      Assert (Src.Line_Count (Buffer) = 3,
              "CRLF text reported the wrong line count:"
              & Positive'Image (Src.Line_Count (Buffer)));
      Assert (Src.Line_Text (Buffer, 1) = "one", "line one is wrong");
      Assert (Src.Line_Text (Buffer, 2) = "two", "line two is wrong");
      Assert (Src.Line_Text (Buffer, 3) = "three", "line three is wrong");

      --  The terminator is not in the line, but it is still in the buffer: the
      --  offsets index the original bytes.
      Assert (Src.Length (Buffer) = 15, "normalizing changed the buffer length");
      Assert (Src.Text (Buffer) (4) = CR, "the original bytes were rewritten");

      --  A lone CR ends a line too, and a lone LF.
      Assert (Src.Load (Buffer, Text_Origin, "a" & CR & "b" & LF & "c", Error),
              "mixed terminators were rejected");
      Assert (Src.Line_Count (Buffer) = 3,
              "mixed terminators reported the wrong line count");

      --  A last line with no terminator is still a line, or the last error in
      --  such a file would be unreportable.
      Assert (Src.Load (Buffer, Text_Origin, "only", Error), "text was rejected");
      Assert (Src.Line_Count (Buffer) = 1, "an unterminated line was dropped");
      Assert (Src.Line_Text (Buffer, 1) = "only", "the unterminated line is wrong");

      --  An empty buffer still has one empty line, so a diagnostic at offset
      --  one has somewhere to point.
      Assert (Src.Load (Buffer, Text_Origin, "", Error), "empty text was rejected");
      Assert (Src.Line_Count (Buffer) = 1, "an empty buffer has no line");
      Assert (Src.Line_Text (Buffer, 1) = "", "an empty line is not empty");
   end Line_Endings_Are_Normalized_Without_Moving_Offsets;

   procedure Columns_Count_Characters_Not_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;

      --  "så" is three bytes and two characters. A caret under what follows it
      --  has to be under the third character, not the fourth.
      Accented : constant String :=
        "s" & Character'Val (16#C3#) & Character'Val (16#A5#) & "r";
   begin
      Assert (Src.Load (Buffer, Text_Origin, "abc" & LF & Accented, Error),
              "text was rejected");

      declare
         At_Start : constant Src.Location := Src.Where_Is (Buffer, 1);
         At_Third : constant Src.Location := Src.Where_Is (Buffer, 3);
      begin
         Assert (At_Start.Line = 1 and then At_Start.Column = 1,
                 "the first byte is not line 1 column 1");
         Assert (At_Third.Line = 1 and then At_Third.Column = 3,
                 "the third byte of an ASCII line is not column 3");
      end;

      --  Byte 5 starts the second line; byte 8 is the 'r' after the two-byte
      --  character, which is the third character of that line.
      declare
         Second : constant Src.Location := Src.Where_Is (Buffer, 5);
         After  : constant Src.Location := Src.Where_Is (Buffer, 8);
      begin
         Assert (Second.Line = 2 and then Second.Column = 1,
                 "the start of line two is not column 1");
         Assert (After.Line = 2,
                 "a byte on line two was reported on another line");
         Assert (After.Column = 3,
                 "a column counted bytes rather than characters; got"
                 & Positive'Image (After.Column));
      end;

      --  Past the end reports the last position rather than raising: that is
      --  where "unexpected end of input" belongs.
      declare
         Beyond : constant Src.Location := Src.Where_Is (Buffer, 9_999);
      begin
         Assert (Beyond.Line = 2, "an offset past the end lost its line");
      end;
   end Columns_Count_Characters_Not_Bytes;

   procedure Slices_Are_Clipped_Rather_Than_Fatal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;
   begin
      Assert (Src.Load (Buffer, Text_Origin, "abcdef", Error), "text was rejected");

      Assert (Src.Slice (Buffer, (First => 2, Last => 4)) = "bcd",
              "a slice returned the wrong bytes");
      Assert (Src.Slice (Buffer, Src.Whole (Buffer)) = "abcdef",
              "the whole span did not return the whole buffer");
      Assert (Src.Slice (Buffer, Src.Nowhere) = "",
              "an empty span returned bytes");

      --  A diagnostic built from a slightly wrong span should still be
      --  reportable. Failing here would replace a small reporting problem with
      --  a crash, on the path where something has already gone wrong.
      Assert (Src.Slice (Buffer, (First => 4, Last => 99)) = "def",
              "a span past the end was not clipped");
      Assert (Src.Slice (Buffer, (First => 99, Last => 120)) = "",
              "a span entirely past the end returned bytes");
   end Slices_Are_Clipped_Rather_Than_Fatal;

   procedure An_Unreadable_File_Is_Reported_Not_Raised
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buffer : Src.Buffer;
      Error  : Adash.Errors.Error_Info;
   begin
      --  A path a user typed being unreadable is an ordinary outcome, not a
      --  defect, so it is a structured failure rather than an exception.
      Assert (not Src.Load_File (Buffer, "./no-such-source-file.adash", Error => Error),
              "loading a file that does not exist reported success");
      Assert (Error.Code = Adash.Errors.Error_Source_Unreadable,
              "a missing source file was reported as something else");
      Assert (not Src.Is_Loaded (Buffer), "a failed load left the buffer loaded");
   end An_Unreadable_File_Is_Reported_Not_Raised;

   ------------------------------------------------------------------
   --  Diagnostics
   ------------------------------------------------------------------

   procedure A_Diagnostic_Carries_Identity_Not_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item : Diag.Diagnostic := Diag.Make
        (Message   => Adash.Messages.Msg_Command_Not_Found,
         Level     => Diag.Severity_Error,
         Of_Kind   => Diag.Category_Execution,
         Raised_By => Diag.Owner_Execution,
         Origin    => Text_Origin,
         Extent    => (First => 3, Last => 9),
         Arguments => [1 => Adash.Messages.Named ("command", "nope")]);
   begin
      Assert (Diag.Message (Item) = Adash.Messages.Msg_Command_Not_Found,
              "the diagnostic lost its identity");
      Assert (Diag.Level (Item) = Diag.Severity_Error, "the severity changed");
      Assert (Diag.Of_Kind (Item) = Diag.Category_Execution, "the category changed");
      Assert (Diag.Raised_By (Item) = Diag.Owner_Execution, "the owner changed");
      Assert (Diag.Extent (Item).First = 3, "the span moved");
      Assert (Diag.Arguments (Item)'Length = 1, "the arguments were lost");
      Assert (Adash.Messages.Value (Diag.Arguments (Item) (1)) = "nope",
              "an argument value changed");

      --  Guidance that repeats the message is not guidance, so a renderer does
      --  not have to compare them and decide.
      Assert (not Diag.Has_Guidance (Item),
              "a diagnostic with no separate advice claims to have some");

      Diag.Add_Related
        (Item,
         (Origin  => Text_Origin,
          Extent  => (First => 20, Last => 24),
          Place   => (Line => 1, Column => 20),
          Message => Adash.Messages.Msg_Command_Denied));
      Assert (Diag.Related_Count (Item) = 1, "a related location was not kept");
      Assert (Diag.Related (Item, 1).Extent.First = 20,
              "a related location lost its span");
   end A_Diagnostic_Carries_Identity_Not_Text;

   procedure A_Failure_Becomes_A_Diagnostic_Without_A_Second_Table
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Failure : constant Adash.Errors.Error_Info := Adash.Errors.Failure
        (Adash.Errors.Error_Command_Not_Found,
         [1 => Adash.Messages.Named ("command", "missing")]);
      Item : constant Diag.Diagnostic := Diag.From_Error (Failure);
   begin
      --  The code's own message comes across. A second mapping here would be a
      --  second thing to keep in step, and the two would disagree eventually.
      Assert (Diag.Message (Item) = Adash.Errors.Message (Failure.Code),
              "converting a failure changed its message identity");
      Assert (Diag.Arguments (Item)'Length = 1,
              "converting a failure lost its arguments");
      Assert (Adash.Messages.Value (Diag.Arguments (Item) (1)) = "missing",
              "converting a failure changed an argument");
   end A_Failure_Becomes_A_Diagnostic_Without_A_Second_Table;

   procedure Diagnostic_Order_Is_Deterministic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : Diag.List;

      function At_Offset
        (Offset : Positive;
         Level  : Diag.Severity := Diag.Severity_Error) return Diag.Diagnostic
      is (Diag.Make
            (Message   => Adash.Messages.Msg_Command_Not_Found,
             Level     => Level,
             Of_Kind   => Diag.Category_Syntax,
             Raised_By => Diag.Owner_Language,
             Origin    => Text_Origin,
             Extent    => (First => Offset, Last => Offset)));
   begin
      --  Emitted out of order, as a phase that walks the source in its own way
      --  would produce them.
      Items.Emit (At_Offset (40));
      Items.Emit (At_Offset (10, Diag.Severity_Note));
      Items.Emit (At_Offset (10, Diag.Severity_Error));
      Items.Emit (At_Offset (25));

      Assert (Items.Count = 4, "not every diagnostic was recorded");
      Assert (Items.Has_Blocking, "a list containing errors reports none");
      Assert (Items.Count_Of (Diag.Severity_Note) = 1, "the note was miscounted");

      Items.Sort;

      Assert (Diag.Extent (Items.Element (1)).First = 10,
              "sorting did not put the earliest position first");
      --  Worst first at one position: an error and a note about the same token
      --  should lead with the error.
      Assert (Diag.Level (Items.Element (1)) = Diag.Severity_Error,
              "at one position the note came before the error");
      Assert (Diag.Level (Items.Element (2)) = Diag.Severity_Note,
              "the note did not follow the error at the same position");
      Assert (Diag.Extent (Items.Element (3)).First = 25, "the middle moved");
      Assert (Diag.Extent (Items.Element (4)).First = 40, "the last moved");

      --  Sorting an already sorted list must not disturb it.
      Items.Sort;
      Assert (Diag.Extent (Items.Element (1)).First = 10
              and then Diag.Extent (Items.Element (4)).First = 40,
              "sorting twice changed the order");
   end Diagnostic_Order_Is_Deterministic;

   procedure Warnings_Alone_Do_Not_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : Diag.List;
   begin
      Items.Emit (Diag.Make
        (Message   => Adash.Messages.Msg_Command_Denied,
         Level     => Diag.Severity_Warning,
         Of_Kind   => Diag.Category_Semantic,
         Raised_By => Diag.Owner_Language));

      --  The one question every caller of a phase asks. Warnings must not stop
      --  evaluation, or a shell would refuse to run anything it had an opinion
      --  about.
      Assert (not Items.Has_Blocking, "a warning blocked evaluation");

      Items.Emit (Diag.Make
        (Message   => Adash.Messages.Msg_Command_Denied,
         Level     => Diag.Severity_Fatal,
         Of_Kind   => Diag.Category_Semantic,
         Raised_By => Diag.Owner_Language));
      Assert (Items.Has_Blocking, "a fatal diagnostic did not block");

      Items.Clear;
      Assert (Items.Count = 0, "Clear left diagnostics behind");
      Assert (not Items.Has_Blocking, "a cleared list still blocks");
   end Warnings_Alone_Do_Not_Block;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Source and Adash.Diagnostics");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   ------------------------------------------
   -- A_Watcher_Sees_A_Diagnostic_As_It_Is_Emitted --
   ------------------------------------------

   --  A list is a report, and a frontend may also watch it.
   --
   --  `trace.commands` is why. A note belongs to its submission's report and a
   --  report is read when the submission ends, so a script file -- one
   --  submission -- announced every command after it had finished printing,
   --  and a script that never finished announced nothing at all. A frontend
   --  that is told as each diagnostic arrives can show a note where it
   --  happened.
   --
   --  Two halves, and the second is the one worth pinning: being watched must
   --  not take the diagnostic out of the report. A watcher renders; the report
   --  is still whole, and it is the frontend's business not to show a note
   --  twice.
   procedure A_Watcher_Sees_A_Diagnostic_As_It_Is_Emitted
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Watcher_Sees_A_Diagnostic_As_It_Is_Emitted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Counting_Watcher is limited new Adash.Diagnostics.Watcher with
         record
            Seen  : Natural := 0;
            Notes : Natural := 0;
         end record;

      overriding procedure Saw
        (Item : in out Counting_Watcher;
         Note : Adash.Diagnostics.Diagnostic);

      overriding procedure Saw
        (Item : in out Counting_Watcher;
         Note : Adash.Diagnostics.Diagnostic) is
      begin
         Item.Seen := Item.Seen + 1;

         if Adash.Diagnostics."=" (Adash.Diagnostics.Level (Note),
                                   Adash.Diagnostics.Severity_Note)
         then
            Item.Notes := Item.Notes + 1;
         end if;
      end Saw;

      Watching : aliased Counting_Watcher;
      Report   : Adash.Diagnostics.List;
   begin
      --  Nobody watching yet: what is emitted is recorded and no more.
      Report.Emit
        (Adash.Diagnostics.Make
           (Message   => Adash.Messages.Msg_Error_None,
            Level     => Adash.Diagnostics.Severity_Error,
            Of_Kind   => Adash.Diagnostics.Category_Syntax,
            Raised_By => Adash.Diagnostics.Owner_Language));

      Assert (Watching.Seen = 0,
              "a watcher that was never attached was told about a diagnostic");

      Report.Watch (Watching'Unchecked_Access);

      Report.Emit
        (Adash.Diagnostics.Make
           (Message   => Adash.Messages.Msg_Line_Traced,
            Level     => Adash.Diagnostics.Severity_Note,
            Of_Kind   => Adash.Diagnostics.Category_Execution,
            Raised_By => Adash.Diagnostics.Owner_Commands));

      Assert (Watching.Seen = 1,
              "the watcher was not told as the diagnostic was emitted");
      Assert (Watching.Notes = 1,
              "the watcher was told, but not what severity it was");

      --  Still in the report. A frontend that shows a note as it arrives is
      --  the one that must not show it again; the list does not forget it.
      Assert (Report.Count = 2,
              "being watched took the diagnostic out of the report");

      --  And watching stops.
      Report.Watch (null);

      Report.Emit
        (Adash.Diagnostics.Make
           (Message   => Adash.Messages.Msg_Line_Traced,
            Level     => Adash.Diagnostics.Severity_Note,
            Of_Kind   => Adash.Diagnostics.Category_Execution,
            Raised_By => Adash.Diagnostics.Owner_Commands));

      Assert (Watching.Seen = 1,
              "a watcher that was taken off was still being told");
      Assert (Report.Count = 3,
              "a diagnostic emitted with nobody watching was not recorded");
   end A_Watcher_Sees_A_Diagnostic_As_It_Is_Emitted;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Spans_Follow_The_Slice_Convention'Access,
         "source : spans follow the slice convention and join into hulls");
      Register_Routine
        (T, Well_Formed_Text_Loads'Access,
         "source : well formed text loads unchanged");
      Register_Routine
        (T, Malformed_Encoding_Is_Refused_Once'Access,
         "source : malformed UTF-8 is refused once, with an offset");
      Register_Routine
        (T, Line_Endings_Are_Normalized_Without_Moving_Offsets'Access,
         "source : line endings normalize without moving offsets");
      Register_Routine
        (T, Columns_Count_Characters_Not_Bytes'Access,
         "source : columns count characters, not bytes");
      Register_Routine
        (T, Slices_Are_Clipped_Rather_Than_Fatal'Access,
         "source : an out of range slice is clipped, not fatal");
      Register_Routine
        (T, An_Unreadable_File_Is_Reported_Not_Raised'Access,
         "source : an unreadable file is reported, not raised");
      Register_Routine
        (T, A_Diagnostic_Carries_Identity_Not_Text'Access,
         "diagnostics : a diagnostic carries identity and spans, not text");
      Register_Routine
        (T, A_Failure_Becomes_A_Diagnostic_Without_A_Second_Table'Access,
         "diagnostics : a failure converts without a second mapping table");
      Register_Routine
        (T, Diagnostic_Order_Is_Deterministic'Access,
         "diagnostics : ordering is deterministic and stable");
      Register_Routine
        (T, A_Watcher_Sees_A_Diagnostic_As_It_Is_Emitted'Access,
         "diagnostics : a watcher is told as a diagnostic is emitted");
      Register_Routine
        (T, Warnings_Alone_Do_Not_Block'Access,
         "diagnostics : warnings alone do not block evaluation");
   end Register_Tests;

end Adash_Tests.Source_Cases;

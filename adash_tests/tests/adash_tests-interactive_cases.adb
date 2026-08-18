with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Fs;
with Hostkit.Process;
with Hostkit.Pty;
with Hostkit.Signals;
with Hostkit.Spawn;
with Hostkit.Terminal_Control;
with Ada.Streams;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash.Diagnostics;
with Adash.Filesystem;
with Adash.Execution.Signals;
with Adash.Execution.Streams;
with Adash.Interactive.Completion;
with Adash.Display_Width;
with Adash.Interactive.Editing;
with Adash.Interactive.Highlighting;
with Adash.Interactive.History;
with Adash.Interactive.Notifications;
with Adash.Errors;
with Adash.Language.Lexer;
with Adash.Language.Tokens;
with Adash.Messages;
with Adash.Source;
with Adash.Terminal;

package body Adash_Tests.Interactive_Cases is

   use AUnit.Assertions;

   package Edit renames Adash.Interactive.Editing;
   package Hist renames Adash.Interactive.History;
   package Note renames Adash.Interactive.Notifications;
   package Comp renames Adash.Interactive.Completion;
   package High renames Adash.Interactive.Highlighting;
   package Str renames Adash.Execution.Streams;

   use type Edit.Key_Kind;
   use type Comp.Source_Kind;
   use type Adash.Terminal.Style_Role;

   --  "e" with an acute accent, in UTF-8: two bytes, one character. Enough to
   --  catch a cursor that moves a byte at a time.
   Accented : constant String :=
     [Character'Val (16#C3#), Character'Val (16#A9#)];

   --  Turn a string into bytes, for the decoder.
   function Bytes (Item : String) return Ada.Streams.Stream_Element_Array;

   function Bytes (Item : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Item'Length));
   begin
      for Index in Item'Range loop
         Result (Ada.Streams.Stream_Element_Offset (Index - Item'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Item (Index)));
      end loop;

      return Result;
   end Bytes;

   procedure Buffer_Inserts_And_Deletes
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Cursor_Moves_By_Character
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Buffer_Refuses_Overflow
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Word_Operations_Take_Their_Separator
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Decoder_Reads_Arrow_Keys
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Decoder_Waits_For_Split_Sequences
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Decoder_Never_Inserts_Control_Bytes
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Collapses_Consecutive_Duplicates
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Forgets_Sensitive_Lines
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Reads_The_Mark_As_A_Leading_Space
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Forgets_Its_Most_Recent_Entries
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Forgets_Every_Copy_Of_A_Line
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_At_Its_Limit_Still_Takes_A_Line
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Drops_Oldest_At_Its_Limit
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Searches_Backwards
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Notices_Wait_While_Editing
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Notices_Keep_Job_News_When_Full
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Completion_Is_Ordered_And_Deterministic
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Completion_Prefix_Is_Never_A_Guess
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Completion_Offers_Programs_Where_One_Is_Named
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Highlighting_Covers_Unparsable_Input
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------
   -- Buffer_Inserts_And_Deletes --
   ---------------------------------

   procedure Buffer_Inserts_And_Deletes
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Line    : Edit.Buffer;
      Ignored : Boolean;
   begin
      Ignored := Line.Insert ("quit");
      Assert (Line.Text = "quit", "insert did not build the line: " & Line.Text);
      Assert (Line.Cursor = 4, "cursor did not follow the insertion");

      Ignored := Line.Move (Edit.To_Start);
      Ignored := Line.Insert ("--");
      Assert (Line.Text = "--quit", "insertion at the cursor appended instead: "
              & Line.Text);

      Ignored := Line.Move (Edit.To_End);
      Assert (Line.Delete_Backward, "backspace at the end deleted nothing");
      Assert (Line.Text = "--qui", "backspace removed the wrong byte: " & Line.Text);

      Ignored := Line.Move (Edit.To_Start);
      Assert (not Line.Delete_Backward,
              "backspace at the start reported a deletion");
      Assert (Line.Delete_Forward, "delete at the start deleted nothing");
      Assert (Line.Text = "-qui", "delete removed the wrong byte: " & Line.Text);

      Assert (Line.Delete_To_End, "kill-to-end deleted nothing");
      Assert (Line.Text = "", "kill-to-end left something behind: " & Line.Text);
   end Buffer_Inserts_And_Deletes;

   ---------------------------------
   -- Cursor_Moves_By_Character --
   ---------------------------------

   procedure Cursor_Moves_By_Character
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Line    : Edit.Buffer;
      Ignored : Boolean;
   begin
      Ignored := Line.Insert ("a" & Accented & "b");

      Assert (Line.Length = 4, "the accented character was not two bytes");
      Assert (Line.Character_Count = 3,
              "three characters were counted as"
              & Natural'Image (Line.Character_Count));

      --  Left from the end: past 'b', then past the whole accented character
      --  rather than into the middle of it.
      Ignored := Line.Move (Edit.Left);
      Assert (Line.Cursor = 3, "left did not step over one byte");

      Ignored := Line.Move (Edit.Left);
      Assert (Line.Cursor = 1,
              "left stopped inside a UTF-8 character, at"
              & Natural'Image (Line.Cursor));

      Assert (Line.Cursor_Column = 1,
              "the cursor column counted bytes rather than characters");

      --  And deleting it removes both bytes, not one.
      Ignored := Line.Move (Edit.Right);
      Assert (Line.Delete_Backward, "backspace deleted nothing");
      Assert (Line.Text = "ab", "backspace split a character: " & Line.Text);
   end Cursor_Moves_By_Character;

   ---------------------------------
   -- Buffer_Refuses_Overflow --
   ---------------------------------

   procedure Buffer_Refuses_Overflow
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Line    : Edit.Buffer;
      Filler  : constant String (1 .. Edit.Max_Line - 1) := [others => 'x'];
      Ignored : Boolean;
   begin
      Assert (Line.Insert (Filler), "a line one short of the limit was refused");
      Assert (Line.Insert ("y"), "the last byte was refused");

      --  Full. The refusal has to be total: a partial insertion would leave
      --  the user with a line that looks right and is not.
      Assert (not Line.Insert ("z"), "an insertion past the limit was accepted");
      Assert (Line.Length = Edit.Max_Line,
              "a refused insertion changed the length");

      Assert (not Line.Insert ("abc"),
              "a multi-byte insertion past the limit was accepted");
      Assert (Line.Length = Edit.Max_Line,
              "a refused insertion inserted part of itself");
   end Buffer_Refuses_Overflow;

   ----------------------------------------------
   -- Word_Operations_Take_Their_Separator --
   ----------------------------------------------

   procedure Word_Operations_Take_Their_Separator
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Line    : Edit.Buffer;
      Ignored : Boolean;
   begin
      Ignored := Line.Insert ("put_line hello world");

      Assert (Line.Delete_Word_Backward, "word deletion deleted nothing");
      Assert (Line.Text = "put_line hello ",
              "word deletion left its separator behind: " & Line.Text);

      Assert (Line.Delete_Word_Backward, "the second word deletion did nothing");
      Assert (Line.Text = "put_line ",
              "the second word deletion took the wrong span: " & Line.Text);

      --  And movement agrees with deletion about where a word starts.
      Ignored := Line.Move (Edit.Word_Left);
      Assert (Line.Cursor = 0,
              "word-left did not reach the start, stopping at"
              & Natural'Image (Line.Cursor));
   end Word_Operations_Take_Their_Separator;

   ---------------------------------
   -- Decoder_Reads_Arrow_Keys --
   ---------------------------------

   procedure Decoder_Reads_Arrow_Keys
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Escape : constant Character := Character'Val (16#1B#);

      procedure Expect (Input : String; Kind : Edit.Key_Kind; Used : Natural);

      procedure Expect (Input : String; Kind : Edit.Key_Kind; Used : Natural) is
         Event    : Edit.Key_Event;
         Consumed : Natural;
      begin
         Edit.Decode (Bytes (Input), Event, Consumed);
         Assert (Event.Kind = Kind,
                 "decoded as " & Edit.Key_Kind'Image (Event.Kind)
                 & " rather than " & Edit.Key_Kind'Image (Kind));
         Assert (Consumed = Used,
                 "consumed" & Natural'Image (Consumed)
                 & " bytes rather than" & Natural'Image (Used));
      end Expect;

   begin
      Expect (Escape & "[A", Edit.Key_Up, 3);
      Expect (Escape & "[B", Edit.Key_Down, 3);
      Expect (Escape & "[C", Edit.Key_Right, 3);
      Expect (Escape & "[D", Edit.Key_Left, 3);
      Expect (Escape & "[H", Edit.Key_Home, 3);
      Expect (Escape & "[F", Edit.Key_End, 3);

      --  The numeric forms, which are what many terminals actually send.
      Expect (Escape & "[3~", Edit.Key_Delete, 4);
      Expect (Escape & "[1~", Edit.Key_Home, 4);
      Expect (Escape & "[4~", Edit.Key_End, 4);

      --  Control-arrow, whose parameters make the sequence longer without
      --  changing what it means.
      Expect (Escape & "[1;5C", Edit.Key_Word_Right, 6);
      Expect (Escape & "[1;5D", Edit.Key_Word_Left, 6);

      --  A sequence carrying several keystrokes decodes the first and leaves
      --  the rest: one read routinely holds more than one key.
      Expect (Escape & "[Ax", Edit.Key_Up, 3);
   end Decoder_Reads_Arrow_Keys;

   ------------------------------------------
   -- Decoder_Waits_For_Split_Sequences --
   ------------------------------------------

   procedure Decoder_Waits_For_Split_Sequences
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Escape : constant Character := Character'Val (16#1B#);

      procedure Expect_Incomplete (Input : String);

      procedure Expect_Incomplete (Input : String) is
         Event    : Edit.Key_Event;
         Consumed : Natural;
      begin
         Edit.Decode (Bytes (Input), Event, Consumed);
         Assert (Event.Kind = Edit.Key_Incomplete,
                 "a partial sequence decoded as "
                 & Edit.Key_Kind'Image (Event.Kind));
         Assert (Consumed = 0,
                 "an incomplete decode consumed" & Natural'Image (Consumed)
                 & " bytes, which would lose them");
      end Expect_Incomplete;

   begin
      --  Every prefix of an arrow key. A read can end at any of them, and each
      --  one has to ask for more rather than guess.
      Expect_Incomplete ("");
      Expect_Incomplete (Escape & "");
      Expect_Incomplete (Escape & "[");
      Expect_Incomplete (Escape & "[1");
      Expect_Incomplete (Escape & "[1;");
      Expect_Incomplete (Escape & "[1;5");

      --  And a UTF-8 character split across reads. Inserting the first byte
      --  alone would corrupt the line.
      Expect_Incomplete (Accented (Accented'First .. Accented'First));
   end Decoder_Waits_For_Split_Sequences;

   ----------------------------------------------
   -- Decoder_Never_Inserts_Control_Bytes --
   ----------------------------------------------

   procedure Decoder_Never_Inserts_Control_Bytes
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Event    : Edit.Key_Event;
      Consumed : Natural;
   begin
      --  No byte below a space is ever text, whether this editor binds it or
      --  not. One that leaked through would put an invisible character into
      --  the line, and the user would see a command that looks right and fails.
      for Code in 0 .. 16#1F# loop
         Edit.Decode
           (Bytes ([1 => Character'Val (Code)]), Event, Consumed);

         Assert (Event.Kind /= Edit.Key_Character,
                 "control byte" & Integer'Image (Code) & " decoded as text");

         --  Escape alone is the one that legitimately waits for more.
         if Code /= 16#1B# then
            Assert (Consumed = 1,
                    "control byte" & Integer'Image (Code) & " was not consumed");
         end if;
      end loop;

      --  A stray continuation byte cannot start a character either.
      Edit.Decode (Bytes ([1 => Character'Val (16#A9#)]), Event, Consumed);
      Assert (Event.Kind = Edit.Key_Unknown,
              "a stray continuation byte decoded as "
              & Edit.Key_Kind'Image (Event.Kind));
      Assert (Consumed = 1, "a stray continuation byte was not consumed");
   end Decoder_Never_Inserts_Control_Bytes;

   --------------------------------------------------
   -- History_Collapses_Consecutive_Duplicates --
   --------------------------------------------------

   procedure History_Collapses_Consecutive_Duplicates
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log : Hist.Log;
   begin
      Hist.Record_Line (Log, "quit;");
      Hist.Record_Line (Log, "quit;");
      Assert (Hist.Count (Log) = 1,
              "a consecutive duplicate was recorded, giving"
              & Natural'Image (Hist.Count (Log)) & " entries");

      --  A non-consecutive repeat is a real place in the session and is kept.
      Hist.Record_Line (Log, "put_line;");
      Hist.Record_Line (Log, "quit;");
      Assert (Hist.Count (Log) = 3,
              "a non-consecutive repeat was collapsed, giving"
              & Natural'Image (Hist.Count (Log)) & " entries");

      --  A blank line is not an entry: recalling one gives the user nothing.
      Hist.Record_Line (Log, "");
      Assert (Hist.Count (Log) = 3, "a blank line was recorded");

      Assert (Hist.Most_Recent (Log) = "quit;",
              "the most recent entry was " & Hist.Most_Recent (Log));
   end History_Collapses_Consecutive_Duplicates;

   -------------------------------------------
   -- History_Forgets_Sensitive_Lines --
   -------------------------------------------

   procedure History_Forgets_Sensitive_Lines
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log : Hist.Log;
   begin
      Hist.Record_Line (Log, "before;");
      Hist.Record_Line (Log, "secret;", Sensitive => True);
      Hist.Record_Line (Log, "after;");

      --  Not even a placeholder. An entry saying a secret was here is still a
      --  record of when one was typed.
      Assert (Hist.Count (Log) = 2,
              "a sensitive line left" & Natural'Image (Hist.Count (Log))
              & " entries rather than 2");
      Assert (Hist.Entry_At (Log, 1) = "before;", "the first entry moved");
      Assert (Hist.Entry_At (Log, 2) = "after;",
              "the sensitive line was recorded as " & Hist.Entry_At (Log, 2));
   end History_Forgets_Sensitive_Lines;

   ------------------------------------------------
   -- History_Reads_The_Mark_As_A_Leading_Space --
   ------------------------------------------------

   procedure History_Reads_The_Mark_As_A_Leading_Space
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Tab : constant Character := Character'Val (9);
      Newline : constant Character := Character'Val (10);
   begin
      Assert (Hist.Marked_Sensitive (" secret;"),
              "a line typed with a space in front of it was not marked");

      --  Everything else is an ordinary line. A space anywhere but the front
      --  is how Ada is written, and a marked line that had to be recognised by
      --  reading the whole of it would be one no user could predict.
      Assert (not Hist.Marked_Sensitive ("put_line (""x"");"),
              "an ordinary line was taken as marked");
      Assert (not Hist.Marked_Sensitive ("x := 1;  --  spaced"),
              "a space inside a line was taken as the mark");
      Assert (not Hist.Marked_Sensitive (""),
              "an empty line was taken as marked");

      --  Not a tab. At an editing prompt a tab is completion and cannot start
      --  a line at all, so honouring it would forget pasted indented text and
      --  nothing else.
      Assert (not Hist.Marked_Sensitive (Tab & "secret;"),
              "a leading tab was taken as the mark");

      --  The first character of the submission, not of each line in it: an
      --  entry is a submission, and Ada continuation lines are indented.
      Assert (not Hist.Marked_Sensitive ("if True then" & Newline
                                         & "   put_line (""x"");" & Newline
                                         & "end if;"),
              "an indented continuation line was taken as the mark");
      Assert (Hist.Marked_Sensitive (" if True then" & Newline
                                     & "   put_line (""x"");" & Newline
                                     & "end if;"),
              "a marked construct was not marked");
   end History_Reads_The_Mark_As_A_Leading_Space;

   -------------------------------------------
   -- History_Forgets_Its_Most_Recent_Entries --
   -------------------------------------------

   procedure History_Forgets_Its_Most_Recent_Entries
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log     : Hist.Log;
      Removed : Natural;
   begin
      Hist.Record_Line (Log, "first;");
      Hist.Record_Line (Log, "second;");
      Hist.Record_Line (Log, "third;");

      Hist.Forget_Last (Log, 2, Removed);

      Assert (Removed = 2,
              "forgetting two removed" & Natural'Image (Removed));
      Assert (Hist.Count (Log) = 1,
              "the log kept" & Natural'Image (Hist.Count (Log))
              & " entries rather than 1");
      Assert (Hist.Entry_At (Log, 1) = "first;",
              "the entry left was " & Hist.Entry_At (Log, 1));

      --  More than it holds takes what it holds. A user asking to forget
      --  twenty of one meant the one, and a refusal there would leave the
      --  thing they wanted gone in place.
      Hist.Forget_Last (Log, 20, Removed);

      Assert (Removed = 1,
              "forgetting twenty of one removed" & Natural'Image (Removed));
      Assert (Hist.Count (Log) = 0,
              "the log was not empty after forgetting everything in it");

      --  And an empty log is not an error to forget from.
      Hist.Forget_Last (Log, 3, Removed);
      Assert (Removed = 0,
              "forgetting from an empty log removed" & Natural'Image (Removed));
   end History_Forgets_Its_Most_Recent_Entries;

   -----------------------------------------
   -- History_Forgets_Every_Copy_Of_A_Line --
   -----------------------------------------

   procedure History_Forgets_Every_Copy_Of_A_Line
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log     : Hist.Log;
      Removed : Natural;
   begin
      Hist.Record_Line (Log, "secret;");
      Hist.Record_Line (Log, "pwd;");
      Hist.Record_Line (Log, "secret;");
      Hist.Record_Line (Log, "env;");

      Hist.Forget_Matching (Log, "secret;", Removed);

      --  Every copy. The one from earlier is the same line as the one from
      --  just now, and a user naming it means the line rather than an
      --  occurrence of it.
      Assert (Removed = 2,
              "forgetting a line by its text removed" & Natural'Image (Removed)
              & " of the 2 copies");
      Assert (Hist.Count (Log) = 2,
              "the log kept" & Natural'Image (Hist.Count (Log))
              & " entries rather than 2");
      Assert (Hist.Entry_At (Log, 1) = "pwd;"
              and then Hist.Entry_At (Log, 2) = "env;",
              "forgetting by text took an entry it was not asked about");

      --  A line the log has not got is not an error to forget.
      Hist.Forget_Matching (Log, "never-typed;", Removed);
      Assert (Removed = 0,
              "forgetting a line that was never typed removed"
              & Natural'Image (Removed));
   end History_Forgets_Every_Copy_Of_A_Line;

   ------------------------------------------------
   -- History_At_Its_Limit_Still_Takes_A_Line --
   ------------------------------------------------

   procedure History_At_Its_Limit_Still_Takes_A_Line
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log      : Hist.Log;
      Recorded : Boolean := False;
   begin
      Hist.Set_Limit (Log, 2);

      Hist.Record_Line (Log, "one;", False, Recorded);
      Assert (Recorded, "the first line was not taken");

      Hist.Record_Line (Log, "two;", False, Recorded);
      Assert (Recorded, "the second line was not taken");

      --  Full now. Taking a third drops the first, so the *count* does not
      --  move -- and a caller reading the count as the answer would decide
      --  the line had not been taken and stop writing it to the file. Which
      --  is what the session did, from the moment it had typed as many lines
      --  as the log holds.
      Hist.Record_Line (Log, "three;", False, Recorded);

      Assert (Recorded, "a log at its limit said it had not taken a line");
      Assert (Hist.Count (Log) = 2,
              "a log at its limit grew to" & Natural'Image (Hist.Count (Log)));
      Assert (Hist.Most_Recent (Log) = "three;",
              "the line taken at the limit was " & Hist.Most_Recent (Log));

      --  And what it refuses, it refuses out loud: a repeat of the line
      --  before it is not a new entry.
      Hist.Record_Line (Log, "three;", False, Recorded);
      Assert (not Recorded,
              "a consecutive duplicate said it had been taken");

      Hist.Record_Line (Log, "hidden;", True, Recorded);
      Assert (not Recorded, "a sensitive line said it had been taken");
   end History_At_Its_Limit_Still_Takes_A_Line;

   ----------------------------------------------
   -- History_Drops_Oldest_At_Its_Limit --
   ----------------------------------------------

   procedure History_Drops_Oldest_At_Its_Limit
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log : Hist.Log;
   begin
      Hist.Set_Limit (Log, 3);

      for Index in 1 .. 5 loop
         Hist.Record_Line (Log, "line" & Natural'Image (Index));
      end loop;

      Assert (Hist.Count (Log) = 3,
              "the limit was not honoured:" & Natural'Image (Hist.Count (Log))
              & " entries");

      --  The oldest goes, because it is the least likely to be wanted.
      Assert (Hist.Entry_At (Log, 1) = "line 3",
              "the wrong end was dropped; the first entry is "
              & Hist.Entry_At (Log, 1));
      Assert (Hist.Most_Recent (Log) = "line 5",
              "the newest entry was lost");

      --  Lowering the limit takes effect at once rather than at the next
      --  insertion, so a user who has just been asked for less gets it.
      Hist.Set_Limit (Log, 1);
      Assert (Hist.Count (Log) = 1, "a lowered limit was not applied");
      Assert (Hist.Most_Recent (Log) = "line 5", "the wrong entry survived");
   end History_Drops_Oldest_At_Its_Limit;

   ---------------------------------------
   -- History_Searches_Backwards --
   ---------------------------------------

   procedure History_Searches_Backwards
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Log   : Hist.Log;
      Found : Hist.Entry_Text;
      use Ada.Strings.Unbounded;
   begin
      Hist.Record_Line (Log, "put_line first;");
      Hist.Record_Line (Log, "quit;");
      Hist.Record_Line (Log, "put_line second;");

      --  From the newest end: "the last time I did this".
      Assert (Hist.Search_Backwards (Log, "put_line", Found),
              "a prefix that is present was not found");
      Assert (To_String (Found) = "put_line second;",
              "the search found the older match: " & To_String (Found));

      Assert (not Hist.Search_Backwards (Log, "nothing", Found),
              "a prefix that is absent was found anyway");
      Assert (Length (Found) = 0,
              "a failed search left something in the result");
   end History_Searches_Backwards;

   --------------------------------------
   -- Notices_Wait_While_Editing --
   --------------------------------------

   procedure Notices_Wait_While_Editing
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Queue : Note.Queue;
      Item  : Note.Notice;
   begin
      Queue.Post (Note.Job_Change, Adash.Messages.Msg_Error_None);

      --  Never while a line is part-typed, however long it has waited:
      --  interrupting the user's typing trades something they are doing for
      --  something they are not.
      Assert (not Queue.Ready (Editing => True),
              "a notice was offered while a line was being edited");
      Assert (Queue.Ready (Editing => False),
              "a notice was withheld at a quiescent point");

      Assert (Queue.Take (Item), "a waiting notice could not be taken");
      Assert (Queue.Pending = 0, "taking a notice left it in the queue");
      Assert (not Queue.Take (Item), "an empty queue produced a notice");
   end Notices_Wait_While_Editing;

   -------------------------------------------
   -- Notices_Keep_Job_News_When_Full --
   -------------------------------------------

   procedure Notices_Keep_Job_News_When_Full
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Queue : Note.Queue;
      Item  : Note.Notice;

      use type Note.Notice_Kind;
   begin
      --  One job change, then enough advisories to overflow. The user asked
      --  for the job and is owed the news; an advisory buried under sixty
      --  others is not worth the line it would take.
      Queue.Post (Note.Job_Change, Adash.Messages.Msg_Error_None);

      for Index in 1 .. Note.Max_Pending + 5 loop
         Queue.Post (Note.Advisory, Adash.Messages.Msg_Error_None);
      end loop;

      Assert (Queue.Pending = Note.Max_Pending,
              "the queue grew past its bound, to"
              & Natural'Image (Queue.Pending));

      Assert (Queue.Take (Item), "the queue was empty after overflowing");
      Assert (Item.Kind = Note.Job_Change,
              "the job change was dropped in favour of an advisory");
   end Notices_Keep_Job_News_When_Full;

   ---------------------------------------------------
   -- Completion_Is_Ordered_And_Deterministic --
   ---------------------------------------------------

   procedure Completion_Is_Ordered_And_Deterministic
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      First  : constant Comp.Candidate_List :=
        Comp.Complete (Comp.Make_Request ("qu", 3));
      Second : constant Comp.Candidate_List :=
        Comp.Complete (Comp.Make_Request ("qu", 3));
   begin
      Assert (First.Count > 0, "completing a known command prefix found nothing");

      --  The same request twice gives the same answer in the same order. A
      --  completion list that reordered itself would make the same keystrokes
      --  mean different things on different days.
      Assert (First.Count = Second.Count,
              "the same request produced different counts");

      for Index in 1 .. First.Count loop
         Assert (Comp.Insertion (First.Element (Index))
                 = Comp.Insertion (Second.Element (Index)),
                 "the same request produced a different order at"
                 & Natural'Image (Index));
      end loop;

      --  Commands come before everything else, because a shell prompt is
      --  where commands are typed.
      Assert (Comp.Source (First.Element (1)) = Comp.From_Command,
              "the first candidate came from "
              & Comp.Source_Kind'Image (Comp.Source (First.Element (1))));
   end Completion_Is_Ordered_And_Deterministic;

   ---------------------------------------------------
   -- Completion_Offers_Programs_Where_One_Is_Named --
   ---------------------------------------------------

   --  A program name is offered inside the string that says which program to
   --  run, and nowhere else.
   --
   --  The search path is given rather than read from this process, so the test
   --  says what is on it: the directory this suite's own binaries are in,
   --  which certainly holds programs that can be run, and a directory of its
   --  own holding a file that cannot.
   procedure Completion_Offers_Programs_Where_One_Is_Named
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Room : constant String :=
        Hostkit.Fs.Create_Temporary_Directory ("adash-completion-test");

      Binaries : constant String := Hostkit.Fs.Own_Executable_Directory;

      Path : constant String :=
        Binaries & Hostkit.Fs.Search_Path_Delimiter & Room;

      --  A companion this crate ships, so it is there on every host -- with
      --  whatever suffix the host puts on an executable, which is why what is
      --  asserted is that a candidate *begins* with the name.
      Runnable : constant String := "adash_test_emit";

      --  And a file that is not a program, in a directory of its own.
      Plain : constant String := "zzplainfile.txt";

      function Offers_Starting_With
        (Item : Comp.Candidate_List; Text : String) return Boolean;

      function Offers_Starting_With
        (Item : Comp.Candidate_List; Text : String) return Boolean is
      begin
         for Index in 1 .. Item.Count loop
            declare
               Insertion : constant String :=
                 Comp.Insertion (Item.Element (Index));
            begin
               if Insertion'Length >= Text'Length
                 and then Insertion
                            (Insertion'First
                             .. Insertion'First + Text'Length - 1) = Text
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Offers_Starting_With;
   begin
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create
           (File, Ada.Text_IO.Out_File, Hostkit.Fs.Join (Room, Plain));
         Ada.Text_IO.Put_Line (File, "not a program");
         Ada.Text_IO.Close (File);
      end;

      declare
         --  Inside the string that names the program.
         Named : constant Comp.Candidate_List :=
           Comp.Complete
             (Comp.Make_Request ("run (""adash_test_", 16, Path));

         --  The same prefix where a program name means nothing.
         Bare : constant Comp.Candidate_List :=
           Comp.Complete (Comp.Make_Request ("adash_test_", 12, Path));

         --  A string argument that is not a program: `set` takes NAME=VALUE.
         Elsewhere : constant Comp.Candidate_List :=
           Comp.Complete
             (Comp.Make_Request ("set (""adash_test_", 16, Path));

         --  And the file that cannot be run.
         Unrunnable : constant Comp.Candidate_List :=
           Comp.Complete (Comp.Make_Request ("run (""zzplain", 13, Path));

         --  The same name in the wrong case. Everything else in this list
         --  folds case, and what is inserted is the program's own spelling --
         --  so a name typed as nobody spells it completes to one that runs.
         Shouted : constant Comp.Candidate_List :=
           Comp.Complete
             (Comp.Make_Request ("run (""ADASH_TEST_", 16, Path));

         --  A prefix the pattern language would read as a pattern. The host
         --  is asked for everything and the filtering happens here, which is
         --  slower and cannot be wrong; guessing at an escape would be fast
         --  and differ between the hosts.
         Starred : constant Comp.Candidate_List :=
           Comp.Complete (Comp.Make_Request ("run (""ad*", 10, Path));
      begin
         Assert (Offers_Starting_With (Named, Runnable),
                 "a program on the search path was not offered where one is "
                 & "named");

         --  Nothing but programs there. A command name or a keyword inside a
         --  string is not something a user could have meant.
         for Index in 1 .. Named.Count loop
            Assert (Comp.Source (Named.Element (Index)) = Comp.From_Program,
                    "a candidate inside a program string came from "
                    & Comp.Source_Kind'Image
                        (Comp.Source (Named.Element (Index))));
         end loop;

         Assert (not Offers_Starting_With (Bare, Runnable),
                 "a program was offered where a name in the language belongs");
         Assert (not Offers_Starting_With (Elsewhere, Runnable),
                 "a program was offered for a string that is not one");
         Assert (not Offers_Starting_With (Unrunnable, "zzplain"),
                 "a file that cannot be run was offered as a program");

         Assert (Offers_Starting_With (Shouted, Runnable),
                 "a program name typed in the wrong case was not completed, "
                 & "though every other kind of candidate folds case");

         Assert (not Offers_Starting_With (Starred, Runnable),
                 "a prefix with a pattern character in it matched as a "
                 & "pattern rather than as the text it is");

         --  And what is offered is what a user would type. Where the host
         --  supplies a suffix for a name written without one, offering the
         --  file's own name would offer the spelling nobody uses.
         if Hostkit.Fs.Executable_Suffix /= "" then
            for Index in 1 .. Named.Count loop
               declare
                  Text : constant String :=
                    Comp.Insertion (Named.Element (Index));

                  Suffix : constant String := Hostkit.Fs.Executable_Suffix;
               begin
                  Assert (Text'Length < Suffix'Length
                          or else Text (Text'Last - Suffix'Length + 1
                                        .. Text'Last) /= Suffix,
                          "a program was offered with the suffix this host "
                          & "supplies for itself: " & Text);
               end;
            end loop;
         end if;
      end;

      Ada.Directories.Delete_Tree (Room);
   end Completion_Offers_Programs_Where_One_Is_Named;

   ------------------------------------------------
   -- Completion_Prefix_Is_Never_A_Guess --
   ------------------------------------------------

   procedure Completion_Prefix_Is_Never_A_Guess
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Candidates : constant Comp.Candidate_List :=
        Comp.Complete (Comp.Make_Request ("", 1));
      Shared     : constant String := Candidates.Common_Prefix;
   begin
      --  Whatever the shared prefix is, every candidate has to begin with it.
      --  A prefix longer than that is a guess, and a user cannot tell a
      --  completion from a mistake until it has run.
      for Index in 1 .. Candidates.Count loop
         declare
            Text : constant String := Comp.Insertion (Candidates.Element (Index));
         begin
            Assert (Text'Length >= Shared'Length
                    and then Text (Text'First .. Text'First + Shared'Length - 1)
                             = Shared,
                    "candidate " & Text & " does not begin with the common "
                    & "prefix " & Shared);
         end;
      end loop;

      --  Nothing typed and nothing in scope still answers, rather than
      --  refusing: an empty list is a fact, not a failure.
      Assert (Comp.Complete (Comp.Make_Request ("zzzqqq", 7)).Count = 0,
              "a prefix nothing matches produced candidates");
   end Completion_Prefix_Is_Never_A_Guess;

   -----------------------------------------------
   -- Highlighting_Covers_Unparsable_Input --
   -----------------------------------------------

   procedure Highlighting_Covers_Unparsable_Input
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  Deliberately not a program: an unclosed string and a missing
      --  semicolon. Highlighting runs off tokens rather than a tree precisely
      --  so that a line being typed -- which is unfinished by definition --
      --  still gets coloured.
      Text   : constant String := "if x then put_line (""unclosed";
      Origin : constant Adash.Source.Origin :=
        Adash.Source.Make_Origin (Adash.Source.Origin_Interactive, "-");

      Buffer : Adash.Source.Buffer;
      Stream : Adash.Language.Tokens.Token_Stream;
      Report : Adash.Diagnostics.List;
      Error  : Adash.Errors.Error_Info;

      Coloured : High.Highlight;
   begin
      Assert (Adash.Source.Load (Buffer, Origin, Text, Error),
              "the sample source did not load");
      Adash.Language.Lexer.Scan (Buffer, Stream, Report);
      Coloured := High.Colour (Stream);

      Assert (Coloured.Count > 0,
              "unfinished input produced no highlighting at all");

      --  The reserved words are recognised even though the line is not a
      --  program.
      declare
         Keywords : Natural := 0;
      begin
         for Index in 1 .. Coloured.Count loop
            if Coloured.Spans (Index).Role = Adash.Terminal.Role_Keyword then
               Keywords := Keywords + 1;
            end if;
         end loop;

         Assert (Keywords >= 2,
                 "if and then were not highlighted as keywords;"
                 & Natural'Image (Keywords) & " keyword spans");
      end;
   end Highlighting_Covers_Unparsable_Input;

   ----------
   -- Name --
   ----------

   procedure Width_Counts_Cells_Not_Characters
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      package W renames Adash.Display_Width;

      --  U+4E2D, a CJK ideograph: three bytes, two cells.
      Ideograph : constant String :=
        Character'Val (16#E4#) & Character'Val (16#B8#) & Character'Val (16#AD#);

      --  U+0301, a combining acute accent: two bytes, no cells of its own.
      Accent : constant String :=
        Character'Val (16#CC#) & Character'Val (16#81#);

      Line    : Edit.Buffer;
      Ignored : Boolean;
   begin
      --  Ordinary text is one cell per character, which is what it always was.
      Assert (W.Cells ("abc") = 3, "plain text was not three cells");

      --  An ideograph takes two. Counting characters gave one, which put every
      --  cell after it one place left of where the terminal drew it.
      Assert (W.Cells (Ideograph) = 2,
              "an ideograph was not two cells but"
              & Natural'Image (W.Cells (Ideograph)));

      --  A combining accent takes none: it is drawn on the character before
      --  it, so counting it would push the rest of the line one cell right.
      Assert (W.Cells ("e" & Accent) = 1,
              "a combining accent added a cell");

      --  The two questions differ, and the buffer answers both.
      Ignored := Line.Insert (Ideograph & "a");
      Assert (Line.Character_Count = 2,
              "two characters were counted as"
              & Natural'Image (Line.Character_Count));
      Assert (Line.Cell_Count = 3,
              "an ideograph and a letter were not three cells but"
              & Natural'Image (Line.Cell_Count));

      --  And so do the two cursor measures. The cursor sits after both
      --  characters: two characters back, three cells back.
      Assert (Line.Cursor_Column = 2, "the cursor was not after two characters");
      Assert (Line.Cursor_Cells = 3,
              "the cursor was not three cells in but"
              & Natural'Image (Line.Cursor_Cells));

      --  Moving left over the ideograph loses two cells, not one.
      Ignored := Line.Move (Edit.Left);
      Assert (Line.Cursor_Cells = 2,
              "stepping back over a letter did not lose one cell");
      Ignored := Line.Move (Edit.Left);
      Assert (Line.Cursor_Cells = 0,
              "stepping back over an ideograph did not lose two cells");

      --  A byte that is not valid UTF-8 counts as one cell rather than none.
      --  It should never reach here, and a character that measured zero would
      --  hide the cursor rather than misplace it.
      Assert (W.Cells (String'(1 => Character'Val (16#FF#))) = 1,
              "an invalid byte was not counted as one cell");
   end Width_Counts_Cells_Not_Characters;

   procedure A_Wrapped_Line_Places_Its_Cursor
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  U+4E2D, three bytes and two cells.
      Ideograph : constant String :=
        Character'Val (16#E4#) & Character'Val (16#B8#) & Character'Val (16#AD#);

      Line    : Edit.Buffer;
      Ignored : Boolean;

      --  A prompt of eight cells and rows of nineteen, which is what a
      --  twenty-column terminal leaves once one cell is kept free.
      Prompt : constant := 8;
      Usable : constant := 19;

      Where : Edit.Screen_Position;
   begin
      --  Thirty plain characters. The first row takes eleven of them after the
      --  prompt and the second takes nineteen, so the cursor ends at the end of
      --  the second row -- not at the start of a third.
      --
      --  That is the case arithmetic gets wrong: thirty-eight cells over rows
      --  of nineteen divides to exactly two, and a break is written *before* a
      --  character that would overflow, so a row filled exactly has none after
      --  it and the cursor has not moved down.
      for Step in 1 .. 30 loop
         Ignored := Line.Insert ("a");
      end loop;

      Where := Line.Place (Prompt, Usable, Natural'Last);
      Assert (Where.Row = 1 and then Where.Column = 19,
              "thirty characters ended at row" & Natural'Image (Where.Row)
              & " column" & Natural'Image (Where.Column)
              & " rather than row 1 column 19");

      --  At the very start, the cursor sits just past the prompt.
      Where := Line.Place (Prompt, Usable, 0);
      Assert (Where.Row = 0 and then Where.Column = Prompt,
              "the start of the line was not just past the prompt");

      --  Twelve ideographs, twenty-four cells. Five fit on the first row after
      --  the prompt -- a sixth would need twenty of the nineteen -- so that row
      --  ends a cell short, and the remaining seven put the cursor at fourteen.
      --
      --  This is what dividing gets wrong the other way: rows are not all the
      --  same width once a wide character forces an early break.
      Line.Clear;

      for Step in 1 .. 12 loop
         Ignored := Line.Insert (Ideograph);
      end loop;

      Where := Line.Place (Prompt, Usable, Natural'Last);
      Assert (Where.Row = 1 and then Where.Column = 14,
              "twelve ideographs ended at row" & Natural'Image (Where.Row)
              & " column" & Natural'Image (Where.Column)
              & " rather than row 1 column 14");

      --  A line that fits needs no rows at all.
      Line.Clear;
      Ignored := Line.Insert ("abc");
      Where := Line.Place (Prompt, Usable, Natural'Last);
      Assert (Where.Row = 0 and then Where.Column = 11,
              "a short line did not stay on the first row");
   end A_Wrapped_Line_Places_Its_Cursor;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Interactive");
   end Name;

   --------------------
   -- Register_Tests --
   --  The shell under test, beside this suite's own binary.
   function Shell_Under_Test return String is
      --  The suite runs from adash_tests, as the test guide says it must, so
      --  the shell is one directory up. Built from the run-time position
      --  rather than from the binary's own path: `Command_Name` is whatever
      --  the caller typed, and asking a relative one for its containing
      --  directory is how this first failed.
      Here : constant String := "../bin/adash";
   begin
      if Ada.Directories.Exists (Here & ".exe") then
         return Here & ".exe";
      end if;

      return Here;
   end Shell_Under_Test;

   ---------------------------------------------------------------------------
   --  A shell on the other end of a pseudo-terminal
   --
   --  Everything above tests a piece: the buffer, the decoder, the history,
   --  the completion. What a user meets is those pieces behind a terminal --
   --  keys arriving as bytes, a line redrawn, a program's output between two
   --  prompts -- and that was the part verified by a person driving it by
   --  hand.
   --
   --  Bounded at every step. A test that reads until end of file from a shell
   --  waiting for input is a test that hangs, and a hang in CI is a job that
   --  reports nothing at all.
   ---------------------------------------------------------------------------

   --  What one of these tests holds while it runs.
   type Terminal_Session is limited record
      Pair    : Hostkit.Pty.Pair;
      Child   : Hostkit.Spawn.Process_Handle;

      --  Everything read from the terminal so far: the shell's own output and
      --  the echo of what was typed, which is what a terminal gives back.
      Seen    : Ada.Strings.Unbounded.Unbounded_String;

      Started : Boolean := False;
   end record;

   --  Open a terminal and start the shell under test on it.
   --
   --  @param Item The session to fill in.
   --  @return False when this host has no pseudo-terminals, in which case
   --          nothing was started and the caller has nothing to do.
   function Start_On_A_Terminal
     (Item : in out Terminal_Session; Script : String := "") return Boolean;

   --  Type into the terminal, as a user would.
   procedure Type_Into (Item : in out Terminal_Session; Text : String);

   --  End a session without typing at it.
   --
   --  `Finish` asks the shell to quit, which means typing -- and a probe -- and a
   --  case whose shell is on its way out -- is exactly the place where the child may already be gone, where typing is
   --  refused, and where a refusal is a fact to record rather than a failure
   --  to report. Closing the terminal is the other way to say it: the child
   --  loses its input and its output at once.
   procedure Close_Without_Typing
     (Item : in out Terminal_Session; Ended : out Boolean);

   --  Whether the shell on the other end has already gone.
   --
   --  Asked only when something has gone wrong, and asked without waiting: a
   --  pty refuses a write when nothing holds the far end, so "could not type"
   --  and "the shell left" are the same event seen from two sides, and which
   --  one it was is the first thing a reader of the failure wants to know.
   function Gone (Item : in out Terminal_Session) return Boolean;

   --  What was seen so far, with the escape sequences taken out.
   function Plainly (Item : Terminal_Session) return String;

   --  Type Ctrl-C and say whether the terminal took it.
   function Try_Interrupt (Item : in out Terminal_Session) return Boolean;

   --  Type Ctrl-C.
   --
   --  The byte, on every host. A console asks for keys when it writes
   --  `ESC [ ? 9001 h`, and Ctrl-C was sent that way for a while on the
   --  reading that a byte could not be a key -- but the probe below settled
   --  it: typed as the byte, a Ctrl-C reaches a program on a console both as
   --  input to read and, where the terminal has been asked to report it, as an
   --  interrupt to a program that is reading nothing at all.
   --
   --  @param Item The session.
   procedure Type_Interrupt (Item : in out Terminal_Session);

   --  Take whatever the terminal has to give right now, without waiting.
   --
   --  @param Item The session.
   --  @return False at end of file, which is a shell that has gone.
   function Drained (Item : in out Terminal_Session) return Boolean;

   --  Read until what was asked for has been seen, or the tries run out.
   --
   --  @param Item The session.
   --  @param Marker What to wait for.
   --  @param Tries How many turns of a twentieth of a second to give it.
   --  @return True when it arrived.
   function Waited_For
     (Item   : in out Terminal_Session;
      Marker : String;
      Tries  : Positive := 200) return Boolean;

   --  How many times something has been seen, which is how a test tells one
   --  answer from the same answer twice.
   --  As Waited_For, asking about the text rather than the bytes.
   function Waited_For_Plainly
     (Item   : in out Terminal_Session;
      Marker : String;
      Tries  : Positive := 200) return Boolean;

   function Times_Seen (Item : Terminal_Session; Marker : String) return Natural;

   --  End the session: ask the shell to quit, wait for it, and close the
   --  terminal. A child still running when a test ends is a test that leaves
   --  work behind, so this asks the host to end one that would not go.
   procedure Finish (Item : in out Terminal_Session; Ended : out Boolean);

   function Start_On_A_Terminal
     (Item : in out Terminal_Session; Script : String := "") return Boolean
   is
      use type Hostkit.Spawn.Spawn_Outcome;

      Options : Hostkit.Spawn.Options;
      Args    : Hostkit.String_Vectors.Vector;
   begin
      if Script /= "" then
         --  A shell running a script rather than a prompt. The terminal is
         --  the same either way, and what a script does when a user presses
         --  Ctrl-C at it is a question only a terminal can ask.
         Args.Append (Ada.Strings.Unbounded.To_Unbounded_String (Script));
      end if;

      if not Hostkit.Pty.Is_Supported then
         --  A host with neither pseudo-terminals nor a console of its own.
         --  What the shell does there is checked by the conformance suite,
         --  which needs no terminal.
         return False;
      end if;

      Assert (Hostkit.Pty.Open (Item.Pair), "could not open a pseudo-terminal");

      --  Read without waiting where the host can express it. Where it cannot
      --  -- an anonymous pipe on Windows has no such mode -- the reads below
      --  ask Wait_Readable first, which is the same question asked the other
      --  way round. A refusal here is therefore not a failure.
      declare
         Ignored : constant Boolean :=
           Hostkit.Descriptors.Set_Non_Blocking (Item.Pair.From_Child, True);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;

      --  The child's side, and the session and controlling terminal that turn
      --  a keystroke into a signal where the host has them. Hostkit.Pty.Attach
      --  is what knows which of those this host has: a pseudo-terminal is
      --  three streams and a session, a pseudo-console is a console handed
      --  over a different way entirely.
      Assert (Hostkit.Pty.Attach (Item.Pair, Options),
              "the terminal end could not be handed to the child");

      Assert (Hostkit.Spawn.Start
                (Shell_Under_Test, Args, Options, Item.Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the shell would not start on a terminal");

      --  The parent's copy of the child's end, given up so the shell owns its
      --  terminal alone. Nothing to give up where the host's answer is a
      --  console, and asking is how this stays one program.
      Hostkit.Pty.Close_Device (Item.Pair);
      Item.Started := True;

      --  Wait for the prompt before anything is typed. Until the shell has
      --  taken the terminal into raw mode, the *driver* is still handling
      --  keys -- and its own erase key deletes a byte, which is exactly the
      --  behaviour one of these tests exists to say the shell does not have.
      --  A user waits for the prompt too; this only says so.
      --
      --  A shell running a script prints no prompt, so there is nothing to
      --  wait for: what a caller in that shape waits for is whatever the
      --  script says, which only the caller knows.
      if Script = "" then
         Assert (Waited_For (Item, "adash"),
                 "no prompt arrived on the terminal");
      end if;

      return True;
   end Start_On_A_Terminal;

   --  Type Ctrl-C and say whether it went.
   --
   --  For a case where the child may already be gone: a pty refuses a write
   --  when nothing holds the other end, and that refusal is a fact about the
   --  run rather than a failure of the test -- one worth carrying to the
   --  assertion that follows, which can then say what did happen.
   function Try_Interrupt (Item : in out Terminal_Session) return Boolean is
      Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
        [1 => Ada.Streams.Stream_Element (3)];

      Last : Ada.Streams.Stream_Element_Offset;

      use type Hostkit.Descriptors.Transfer_Outcome;
   begin
      return Hostkit.Descriptors.Write (Item.Pair.To_Child, Data, Last)
             = Hostkit.Descriptors.Transfer_Ok;
   end Try_Interrupt;

   function Gone (Item : in out Terminal_Session) return Boolean is
      Result : Hostkit.Spawn.Status;

      use type Hostkit.Spawn.Wait_State;
   begin
      return Hostkit.Spawn.Wait (Item.Child, Hostkit.Spawn.Wait_Poll, Result)
             and then Result.State /= Hostkit.Spawn.Wait_Running;
   exception
      --  A handle already reaped, or one this host will not answer about. The
      --  question is only ever asked to describe a failure, so an unanswerable
      --  one is best reported as "cannot say" rather than replacing the
      --  failure under description with a different exception.
      when others =>
         return False;
   end Gone;

   procedure Type_Interrupt (Item : in out Terminal_Session) is
   begin
      Type_Into (Item, String'(1 => Character'Val (3)));
   end Type_Interrupt;

   procedure Type_Into (Item : in out Terminal_Session; Text : String) is
      use type Hostkit.Descriptors.Transfer_Outcome;

      Data : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      for Index in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
      end loop;

      declare
         Sent : constant Hostkit.Descriptors.Transfer_Outcome :=
           Hostkit.Descriptors.Write (Item.Pair.To_Child, Data, Last);

         --  All of it, or the test is asserting about a line the shell never
         --  saw the whole of.
         Whole : constant Boolean := Ada.Streams."=" (Last, Data'Last);
      begin
         if Sent /= Hostkit.Descriptors.Transfer_Ok or else not Whole then
            --  The transcript and the shell's state, not just the refusal.
            --  A write to a pty fails for one interesting reason -- nothing
            --  holds the far end -- and a message that says only "could not
            --  type" sends a reader looking at the typing, which is never
            --  where the answer is. What the shell had already said before it
            --  went is what tells them why it went.
            Assert (False,
                    "could not type into the terminal (the shell had "
                    & (if Gone (Item) then "already gone" else "not gone")
                    & ", and on this host a refused write "
                    & (if Hostkit.Pty.Write_Fails_When_Unheld
                       then "is what a terminal nothing holds does"
                       else "is not how this host reports a child that left")
                    & ", "
                    & Ada.Streams.Stream_Element_Offset'Image (Last)
                    & " of"
                    & Ada.Streams.Stream_Element_Offset'Image (Data'Last)
                    & " bytes taken): [" & Plainly (Item) & "]");
         end if;
      end;
   end Type_Into;

   function Drained (Item : in out Terminal_Session) return Boolean is
      use type Hostkit.Descriptors.Transfer_Outcome;

      Alive : Boolean := True;
   begin
      --  Everything the terminal has, not one bufferful of it. A shell
      --  redrawing the line for every keystroke writes far more than it
      --  reads, and a reader that takes one bufferful per turn leaves the
      --  terminal full -- which stops the *shell*, since a program writing
      --  into a full terminal waits. That is what made a typed line arrive at
      --  two characters a second here.
      --
      --  Bounded anyway: a child that never stopped writing would otherwise
      --  keep this turn for ever.
      for Turn in 1 .. 64 loop
         --  Asked before it is read. A read that would wait *does* wait where
         --  the host has no non-blocking mode, and a drain that waited would
         --  be a test that hangs rather than one that says what it found.
         exit when not Hostkit.Descriptors.Wait_Readable (Item.Pair.From_Child, 0);

         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
            Last   : Ada.Streams.Stream_Element_Offset;
            Status : constant Hostkit.Descriptors.Transfer_Outcome :=
              Hostkit.Descriptors.Read (Item.Pair.From_Child, Buffer, Last);
         begin
            if Status = Hostkit.Descriptors.Transfer_End_Of_File then
               Alive := False;
               exit;
            end if;

            exit when Status /= Hostkit.Descriptors.Transfer_Ok;

            for Index in Buffer'First .. Last loop
               Ada.Strings.Unbounded.Append
                 (Item.Seen, Character'Val (Natural (Buffer (Index))));
            end loop;
         end;
      end loop;

      return Alive;
   end Drained;

   function Waited_For
     (Item   : in out Terminal_Session;
      Marker : String;
      Tries  : Positive := 200) return Boolean is
   begin
      for Attempt in 1 .. Tries loop
         declare
            More : constant Boolean := Drained (Item);
         begin
            if Marker'Length > 0
              and then Ada.Strings.Fixed.Index
                         (Ada.Strings.Unbounded.To_String (Item.Seen),
                          Marker) > 0
            then
               return True;
            end if;

            exit when not More;
            delay 0.05;
         end;
      end loop;

      return False;
   end Waited_For;

   --  What was seen, with the escape sequences taken out.
   --
   --  A terminal answer is text and control mixed: the prompt writes its
   --  failure marker and then an escape sequence to dim the directory, so `!`
   --  and the space after it are not next to each other in the bytes. A test
   --  that looked for them together found nothing and reported that the
   --  interrupt had not worked -- which it had. What a reader sees is the text
   --  without the control, so that is what an assertion should ask about.
   function Plainly (Item : Terminal_Session) return String is
      Whole  : constant String := Ada.Strings.Unbounded.To_String (Item.Seen);
      Result : String (1 .. Whole'Length);
      Kept   : Natural := 0;
      Index  : Positive := Whole'First;
   begin
      while Index <= Whole'Last loop
         if Whole (Index) = Character'Val (16#1B#)
           and then Index < Whole'Last
           and then Whole (Index + 1) = '['
         then
            --  A CSI sequence: ESC [ then parameters, then a letter.
            Index := Index + 2;

            while Index <= Whole'Last
              and then Whole (Index) not in 'A' .. 'Z' | 'a' .. 'z'
            loop
               Index := Index + 1;
            end loop;

            Index := Index + 1;

         elsif Whole (Index) = Character'Val (16#1B#)
           and then Index < Whole'Last
           and then Whole (Index + 1) = ']'
         then
            --  An OSC sequence: ESC ] then text, then a bell or ESC \.
            --
            --  What a console sets its window title with, and it arrives
            --  wherever the console feels like -- *inside a word*, in the run
            --  that made this necessary: a case waiting for RUNNING found
            --  "RUNNIN", the title, and then "G", and concluded that the shell
            --  had never started.
            Index := Index + 2;

            while Index <= Whole'Last
              and then Whole (Index) /= Character'Val (7)
            loop
               exit when Whole (Index) = Character'Val (16#1B#)
                 and then Index < Whole'Last
                 and then Whole (Index + 1) = '\';

               Index := Index + 1;
            end loop;

            --  Past the bell, or past both bytes of the ESC \.
            if Index <= Whole'Last
              and then Whole (Index) = Character'Val (16#1B#)
            then
               Index := Index + 1;
            end if;

            Index := Index + 1;

         else
            Kept := Kept + 1;
            Result (Kept) := Whole (Index);
            Index := Index + 1;
         end if;
      end loop;

      return Result (1 .. Kept);
   end Plainly;

   function Waited_For_Plainly
     (Item   : in out Terminal_Session;
      Marker : String;
      Tries  : Positive := 200) return Boolean is
   begin
      for Attempt in 1 .. Tries loop
         declare
            More : constant Boolean := Drained (Item);
         begin
            if Ada.Strings.Fixed.Index (Plainly (Item), Marker) > 0 then
               return True;
            end if;

            exit when not More;
            delay 0.05;
         end;
      end loop;

      return False;
   end Waited_For_Plainly;

   function Times_Seen (Item : Terminal_Session; Marker : String) return Natural
   is
      Whole : constant String := Ada.Strings.Unbounded.To_String (Item.Seen);
      Count : Natural := 0;
      From  : Positive := Whole'First;
   begin
      while From <= Whole'Last loop
         declare
            Found : constant Natural :=
              Ada.Strings.Fixed.Index (Whole (From .. Whole'Last), Marker);
         begin
            exit when Found = 0;
            Count := Count + 1;
            From := Found + Marker'Length;
         end;
      end loop;

      return Count;
   end Times_Seen;

   procedure Finish (Item : in out Terminal_Session; Ended : out Boolean) is
      use type Hostkit.Spawn.Wait_State;

      Result : Hostkit.Spawn.Status;
   begin
      Ended := False;
      Type_Into (Item, "quit (0);" & String'(1 => Character'Val (13)));

      --  Kept drained while it ends. A terminal holds what a program wrote
      --  until somebody reads it, and a program writing into a full one waits
      --  -- so a wait loop that does not read is a wait for a process that
      --  cannot reach its own exit.
      for Attempt in 1 .. 200 loop
         if Hostkit.Spawn.Wait (Item.Child, Hostkit.Spawn.Wait_Poll, Result)
           and then Result.State /= Hostkit.Spawn.Wait_Running
         then
            Ended := Result.State = Hostkit.Spawn.Wait_Exited;
            exit;
         end if;

         declare
            Ignored : constant Boolean := Drained (Item);
            pragma Unreferenced (Ignored);
         begin
            delay 0.05;
         end;
      end loop;

      if not Ended then
         --  It would not go. Asked to stop rather than left behind: a test
         --  that fails must not also leak a process into the rest of the run.
         declare
            Stopped : constant Boolean :=
              Hostkit.Signals.Send_To_Process
                (Hostkit.Spawn.Process_Id (Item.Child),
                 Hostkit.Signals.Signal_Terminate);
            pragma Unreferenced (Stopped);
         begin
            null;
         end;
      end if;

      Hostkit.Pty.Close (Item.Pair);
   end Finish;

   --  A whole session, through a pseudo-terminal.
   --
   --  Everything else here tests a piece: the buffer, the decoder, the
   --  history, the completion. Nothing tested the shell a user actually meets
   --  -- a terminal on the other end, a line typed, an answer printed -- and
   --  that was the one part of this crate verified by a person driving it by
   --  hand.
   --
   --  Bounded at every step. A test that reads until end of file from a shell
   --  waiting for input is a test that hangs, and a hang in CI is a job that
   --  reports nothing at all: that lesson cost two thirty-minute Windows runs
   --  today.
   procedure A_Session_Answers_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      use type Hostkit.Descriptors.Transfer_Outcome;
      use type Hostkit.Spawn.Spawn_Outcome;
      use type Hostkit.Spawn.Wait_State;

      Pair    : Hostkit.Pty.Pair;
      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;
      Result  : Hostkit.Spawn.Status;
      Args    : Hostkit.String_Vectors.Vector;

      Seen : Ada.Strings.Unbounded.Unbounded_String;

      Typed : constant String :=
        "put_line (""from a terminal"");" & Character'Val (13)
        & "quit (0);" & Character'Val (13);

      function Wrote (Item : String) return Boolean;

      function Wrote (Item : String) return Boolean is
         Data : Ada.Streams.Stream_Element_Array (1 .. Item'Length);
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         for Index in Item'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Item'First + 1)) :=
              Ada.Streams.Stream_Element (Character'Pos (Item (Index)));
         end loop;

         return Hostkit.Descriptors.Write (Pair.To_Child, Data, Last)
                = Hostkit.Descriptors.Transfer_Ok;
      end Wrote;
   begin
      if not Hostkit.Pty.Is_Supported then
         --  Windows has none, which Hostkit.Pty answers for. What the shell
         --  does there is checked by the conformance suite, which needs no
         --  terminal.
         return;
      end if;

      Assert (Hostkit.Pty.Open (Pair), "could not open a pseudo-terminal");

      --  Read without waiting, so that draining the terminal is something
      --  this test can do between two other questions rather than a place it
      --  can stop.
      declare
         Ignored : constant Boolean :=
           Hostkit.Descriptors.Set_Non_Blocking (Pair.From_Child, True);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;

      Assert (Hostkit.Pty.Attach (Pair, Options),
              "the terminal end could not be handed to the child");

      Assert (Hostkit.Spawn.Start (Shell_Under_Test, Args, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the shell would not start on a terminal");

      --  The parent's copy of the child's end, closed so the shell owns its
      --  terminal alone.
      Hostkit.Pty.Close_Device (Pair);

      Assert (Wrote (Typed), "could not type into the terminal");

      for Attempt in 1 .. 200 loop
         --  Asked before it is read, because a read that would wait does wait
         --  where the host has no non-blocking mode.
         if not Hostkit.Descriptors.Wait_Readable (Pair.From_Child, 50) then
            goto Next_Turn;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
            Last   : Ada.Streams.Stream_Element_Offset;
            Status : constant Hostkit.Descriptors.Transfer_Outcome :=
              Hostkit.Descriptors.Read (Pair.From_Child, Buffer, Last);
         begin
            if Status = Hostkit.Descriptors.Transfer_Ok then
               for Index in Buffer'First .. Last loop
                  Ada.Strings.Unbounded.Append
                    (Seen, Character'Val (Natural (Buffer (Index))));
               end loop;
            end if;

            exit when Ada.Strings.Fixed.Index
                        (Ada.Strings.Unbounded.To_String (Seen),
                         "from a terminal") > 0;

            exit when Status = Hostkit.Descriptors.Transfer_End_Of_File;

            delay 0.05;
         end;

         <<Next_Turn>>
      end loop;

      Assert (Ada.Strings.Fixed.Index
                (Ada.Strings.Unbounded.To_String (Seen),
                 "from a terminal") > 0,
              "the shell did not answer through the terminal: ["
              & Ada.Strings.Unbounded.To_String (Seen) & "]");

      --  Kept drained while it ends. A terminal holds what a program wrote
      --  until somebody reads it, and a program writing into a full one waits
      --  -- so a wait loop that does not read is a wait for a process that
      --  cannot reach its own exit. How much fits differs by host, which is
      --  why this passed on one and hung on another.
      for Attempt in 1 .. 200 loop
         exit when Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
                     and then Result.State /= Hostkit.Spawn.Wait_Running;

         if Hostkit.Descriptors.Wait_Readable (Pair.From_Child, 50) then
            declare
               Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
               Last   : Ada.Streams.Stream_Element_Offset;
               Status : constant Hostkit.Descriptors.Transfer_Outcome :=
                 Hostkit.Descriptors.Read (Pair.From_Child, Buffer, Last);
            begin
               if Status = Hostkit.Descriptors.Transfer_Ok then
                  for Index in Buffer'First .. Last loop
                     Ada.Strings.Unbounded.Append
                       (Seen, Character'Val (Natural (Buffer (Index))));
                  end loop;
               end if;
            end;
         end if;

         delay 0.05;
      end loop;

      Assert (Result.State = Hostkit.Spawn.Wait_Exited,
              "the shell did not end when it was asked to: "
              & Hostkit.Spawn.Wait_State'Image (Result.State)
              & " after ["
              & Ada.Strings.Unbounded.To_String (Seen) & "]");

      Hostkit.Pty.Close (Pair);
   end A_Session_Answers_Through_A_Terminal;

   --  Tab completes, through the terminal.
   --
   --  The unit case above asks Adash.Interactive.Completion what it would
   --  offer; this asks what a user gets for pressing Tab: the keystroke
   --  decoded, the candidate chosen because it is the only one, and the rest
   --  of the word written into the line the shell then runs.
   procedure Completion_Finishes_A_Word_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  `ver` names one thing in the whole vocabulary, so Tab has an answer.
      --  The semicolon and the return are typed after it, which is what makes
      --  the completed word a statement the shell runs -- and running it is
      --  how this knows what the line held, rather than reading an echo it
      --  would have to parse.
      Type_Into (Session, "ver" & String'(1 => Character'Val (9)));
      Type_Into (Session, ";" & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, "adash "),
              "Tab did not complete `ver` into a command that ran: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after completing a word");
   end Completion_Finishes_A_Word_Through_A_Terminal;

   --  Tab offers what a user taught it, through the terminal.
   --
   --  `complete_with` names a subprogram that says what may follow a program,
   --  and nothing else in this shell can answer that question: what may follow
   --  `git` is not in the vocabulary and not on the filesystem. So the whole
   --  path has to work -- the word under the cursor read, the program it
   --  belongs to found, the subprogram run, and what it printed offered -- and
   --  a unit test of any one piece would not say that it does.
   --
   --  Only one candidate matches `com`, so Tab has an unambiguous answer and
   --  the line that runs afterwards is what says it arrived.
   procedure Completion_Offers_What_A_User_Taught_It
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Completion_Offers_What_A_User_Taught_It
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := (1 => Character'Val (13));
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  The subprogram, and the registration, typed as a user would.
      Type_Into
        (Session,
         "procedure Git_Words (Word : String) is begin "
         & "if Starts_With (""commit"", Word) then put_line (""commit""); "
         & "end if; end Git_Words;" & Return_Key);
      Type_Into (Session, "complete_with (""git"", ""Git_Words"");" & Return_Key);

      --  Wait for the prompt to come back, so the Tab below is typed at a
      --  shell that has both of those and not at one still reading them.
      declare
         Ready : Boolean := False;
      begin
         for Attempt in 1 .. 200 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Ready := Ada.Strings.Fixed.Index
                          (Plainly (Session), "complete_with") > 0;
            end;

            exit when Ready;
            delay 0.05;
         end loop;

         Assert (Ready,
                 "the shell never took the registration: ["
                 & Plainly (Session) & "]");
      end;

      --  `com` names one of the candidates the subprogram prints, and nothing
      --  in the shell's own vocabulary, so Tab has exactly one answer.
      Type_Into (Session, "put_line (Output_Of (""git"", ""com");
      Type_Into (Session, String'(1 => Character'Val (9)));
      Type_Into (Session, """));" & Return_Key);

      Assert (Waited_For_Plainly (Session, "commit", 400),
              "Tab did not offer what the user taught it: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after completing a word");
   end Completion_Offers_What_A_User_Taught_It;

   --  A line interrupted at the prompt runs what `on_interrupt` asked for.
   --
   --  The script case beside this one covers a file; this covers the session,
   --  which is where a user meets the feature first: they register a handler
   --  and then press Ctrl-C at the prompt. It ran only for scripts at first --
   --  the half a user meets second -- and nothing said so, because the case
   --  that existed was about the other half.
   procedure An_Interrupted_Line_Runs_Its_Handler
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure An_Interrupted_Line_Runs_Its_Handler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := (1 => Character'Val (13));
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      Type_Into
        (Session,
         "procedure Note is begin put_line (To_Upper (""noted"")); end Note;"
         & Return_Key);
      Type_Into (Session, "on_interrupt (""Note"");" & Return_Key);

      --  Wait for the registration to be taken, so the loop below is typed at
      --  a shell that has the handler rather than at one still reading it.
      declare
         Ready : Boolean := False;
      begin
         for Attempt in 1 .. 200 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Ready := Ada.Strings.Fixed.Index
                          (Plainly (Session), "on_interrupt") > 0;
            end;

            exit when Ready;
            delay 0.05;
         end loop;

         Assert (Ready,
                 "the shell never took the registration: ["
                 & Plainly (Session) & "]");
      end;

      Type_Into (Session, "loop null; end loop;" & Return_Key);

      --  Long enough that the line is running rather than still being read.
      delay 1.0;

      Assert (Try_Interrupt (Session),
              "the terminal refused the interrupt: ["
              & Plainly (Session) & "]");

      declare
         Noted : Boolean := False;
      begin
         for Attempt in 1 .. 300 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Noted := Ada.Strings.Fixed.Index
                          (Plainly (Session), "NOTED") > 0;
            end;

            exit when Noted;
            delay 0.05;
         end loop;

         Assert (Noted,
                 "an interrupted line did not run what on_interrupt asked "
                 & "for: [" & Plainly (Session) & "]");
      end;

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after an interrupted line");
   end An_Interrupted_Line_Runs_Its_Handler;

   --  Up recalls what was typed, through the terminal.
   procedure History_Recalls_A_Line_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      --  Written by the program rather than typed, so the echo of the line
      --  cannot be mistaken for the answer to it: what is typed is lower case
      --  and what comes back is not.
      Answer : constant String := "RECALLED";
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      Type_Into
        (Session,
         "put_line (To_Upper (""recalled""));" & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, Answer),
              "the first line did not run: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      --  The prompt back before anything else is typed.
      --
      --  Waiting for the answer is not waiting for the shell: the answer is
      --  written while the submission is still running, and on a host where
      --  the shell watches its own terminal for Ctrl-C it is still holding
      --  that terminal raw and reading it when the answer appears. Typing into
      --  that gap is a race, and it is the race that made this case fail one
      --  run in a few on that host while the transcript showed the shell had
      --  done everything it was asked.
      --  Drained for a moment rather than waited for a marker: the editor
      --  redraws the prompt on every keystroke, so the prompt is not something
      --  a case can count, and what is wanted here is only that the shell has
      --  finished with the line before another one is typed.
      for Attempt in 1 .. 20 loop
         declare
            Ignored : constant Boolean := Drained (Session);
            pragma Unreferenced (Ignored);
         begin
            delay 0.05;
         end;
      end loop;

      --  Up, as a terminal sends it, and then a return: the recalled line runs
      --  again and the answer arrives a second time.
      Type_Into
        (Session,
         String'(1 => Character'Val (27)) & "[A"
         & String'(1 => Character'Val (13)));

      for Attempt in 1 .. 600 loop
         exit when Times_Seen (Session, Answer) >= 2;

         declare
            Ignored : constant Boolean := Drained (Session);
            pragma Unreferenced (Ignored);
         begin
            delay 0.05;
         end;
      end loop;

      Assert (Times_Seen (Session, Answer) >= 2,
              "Up did not bring the line back: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after recalling a line");
   end History_Recalls_A_Line_Through_A_Terminal;

   --  A line typed with a space in front of it is not there to recall.
   procedure History_Skips_A_Marked_Line_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];

      --  Upper case comes from the program, lower case from the echo of what
      --  was typed, so counting an answer cannot count the keystrokes.
      Marked : constant String := "MARKEDLINE";
      Kept   : constant String := "KEPTLINE";
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  The mark, typed as a user would type it. The line still runs.
      Type_Into
        (Session,
         " put_line (To_Upper (""markedline""));" & Return_Key);

      Assert (Waited_For (Session, Marked),
              "the marked line did not run: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      Type_Into
        (Session,
         "put_line (To_Upper (""keptline""));" & Return_Key);

      Assert (Waited_For (Session, Kept),
              "the second line did not run: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      --  One Up. If the marked line had been recorded this would bring it
      --  back, since it is the more recent of the two.
      Type_Into (Session, String'(1 => Character'Val (27)) & "[A" & Return_Key);

      for Attempt in 1 .. 200 loop
         exit when Times_Seen (Session, Kept) >= 2;

         declare
            Ignored : constant Boolean := Drained (Session);
            pragma Unreferenced (Ignored);
         begin
            delay 0.05;
         end;
      end loop;

      Assert (Times_Seen (Session, Kept) >= 2,
              "Up did not bring the unmarked line back: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");
      Assert (Times_Seen (Session, Marked) = 1,
              "Up recalled the marked line: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after skipping a marked line");
   end History_Skips_A_Marked_Line_Through_A_Terminal;

   --  Backspace removes a character rather than a byte, through the terminal.
   --
   --  The accented character is two bytes and one character. An editor that
   --  stepped by bytes would leave half of it in the line, the text would not
   --  be UTF-8, and the shell would report that instead of answering -- which
   --  is the failure this asserts the absence of, by asking for an answer only
   --  a whole deletion can produce.
   procedure Backspace_Removes_A_Character_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  First that backspace removes anything at all, in ASCII, so that a
      --  failure below is about the character and not about the key. The
      --  editor reads both DEL and BS as backspace; BS is what a console host
      --  sends, DEL is what a line discipline sends, and typing BS is the one
      --  that means the same thing to both.
      Type_Into (Session, "put_line (To_Upper (""okz");
      Type_Into (Session, String'(1 => Character'Val (16#08#)));
      Type_Into (Session, """));" & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, "OK"),
              "backspace removed nothing at all: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      --  Then the character -- where what is typed arrives as it was typed.
      --
      --  Two bytes, one character: an editor stepping by bytes leaves half of
      --  it, the line is no longer UTF-8, and the shell reports that rather
      --  than answering, which is what asking for an answer only a whole
      --  deletion can produce asserts the absence of.
      --
      --  Both hosts, now that a console hands its input over as UTF-8 rather
      --  than in whatever code page it was set to. What follows is what it
      --  took to find that out, kept because the wrong answers were expensive:
      --
      --  Three ways of typing the character at a console were tried:
      --  the UTF-8 as it stands; the key event the console asks for when it
      --  writes `ESC [ ? 9001 h` on attaching, with the virtual key and scan
      --  code left at nothing; and the same with VK_PACKET, which is what
      --  Windows itself uses for a key event carrying a character rather than
      --  a key somebody pressed. None of the three reached the shell: the line
      --  was never submitted and nothing came back for ten seconds.
      --
      --  What does arrive there is a key event for a key that exists -- Ctrl-C
      --  is sent that way and the editor sees it. So the remaining guess is
      --  that this input path wants a virtual key it can map and drops what it
      --  cannot, which would mean a character with no key on the host's layout
      --  cannot be typed at a console at all. A guess, and written down as one
      --  so the next person starts after these three rather than at them.
      --
      --  So it is asserted where it can hold. The shell was asked about the
      --  other host: after such a line it goes on answering, so what is
      --  missing is the keystroke and not the editor -- and the editor's own
      --  answer, that a character is not a byte, is asserted on every host by
      --  the buffer and decoder cases above.
      Type_Into (Session, "put_line (To_Upper (""fine" & Accented);
      Type_Into (Session, String'(1 => Character'Val (16#08#)));
      Type_Into (Session, """));" & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, "FINE"),
              "backspace did not remove the whole character: ["
              & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after an edited line");
   end Backspace_Removes_A_Character_Through_A_Terminal;

   --  Take whatever a terminal has to give and drop it.
   --
   --  For a test that must keep a terminal from filling up while it waits for
   --  a child: a program writing into a full one waits instead of finishing,
   --  and this test is about what the child *read*, not what it wrote.
   --
   --  @param Item The pair to drain.
   --  @return True when something was taken.
   function Drained_Into_Nothing (Item : Hostkit.Pty.Pair) return Boolean;

   function Drained_Into_Nothing (Item : Hostkit.Pty.Pair) return Boolean is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
      Last   : Ada.Streams.Stream_Element_Offset := 0;

      use type Ada.Streams.Stream_Element_Offset;
      use type Hostkit.Descriptors.Transfer_Outcome;
   begin
      if not Hostkit.Descriptors.Wait_Readable (Item.From_Child, 50) then
         return False;
      end if;

      return Hostkit.Descriptors.Read (Item.From_Child, Buffer, Last)
             = Hostkit.Descriptors.Transfer_Ok
        and then Last >= Buffer'First;
   end Drained_Into_Nothing;

   --  What actually reaches a program on this host's terminal.
   --
   --  Two questions have been asked of the documentation and answered wrongly
   --  twice: whether a Ctrl-C typed at a console reaches a program that is
   --  busy, and whether a character with no key on the host's layout can be
   --  typed at one at all. This asks the machine instead. A companion sits on
   --  the terminal, writes down every byte it reads and every interrupt it is
   --  told about, and this compares that against what was typed.
   --
   --  It asserts the one thing that must hold everywhere -- an ordinary
   --  character typed arrives -- and carries the whole record in the failure
   --  message of the two that are the open questions. A test that cannot fail
   --  usefully is a test that answers nothing, and what is wanted here is the
   --  answer.
   procedure A_Terminal_Says_What_Reaches_A_Program
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Terminal : Hostkit.Pty.Pair;
      Options  : Hostkit.Spawn.Options;
      Child    : Hostkit.Spawn.Process_Handle;
      Result   : Hostkit.Spawn.Status;

      Told : Hostkit.String_Vectors.Vector;

      Room : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Command_Line.Command_Name),
           "terminal-watch.txt");

      Said : Ada.Strings.Unbounded.Unbounded_String;

      function Wrote (Text : String) return Boolean
      is (Ada.Strings.Fixed.Index
            (Ada.Strings.Unbounded.To_String (Said), Text) > 0);

      procedure Send (Text : String);

      procedure Send (Text : String) is
         Data : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
         Last : Ada.Streams.Stream_Element_Offset;

         use type Hostkit.Descriptors.Transfer_Outcome;
      begin
         for Index in Text'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
              Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
         end loop;

         Assert (Hostkit.Descriptors.Write (Terminal.To_Child, Data, Last)
                 = Hostkit.Descriptors.Transfer_Ok,
                 "could not type into the terminal");

         --  How much of it went is not this test's question -- what the
         --  watcher read is -- but a write that stopped early would make the
         --  record short for a reason worth seeing.
         Assert (Natural (Last) = Text'Length,
                 "only part of what was typed reached the terminal");
      end Send;

      Escape : constant String := [1 => Character'Val (27)];

      use type Hostkit.Spawn.Spawn_Outcome;
      use type Hostkit.Spawn.Wait_State;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      if Ada.Directories.Exists (Room) then
         Ada.Directories.Delete_File (Room);
      end if;

      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Room));
      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String ("4"));

      Assert (Hostkit.Pty.Open (Terminal), "could not open a terminal");
      Assert (Hostkit.Pty.Set_Size (Terminal, (Rows => 24, Columns => 80)),
              "could not size the terminal");
      Assert (Hostkit.Pty.Attach (Terminal, Options),
              "could not arrange to start the watcher on the terminal");

      Assert (Hostkit.Spawn.Start
                (Ada.Directories.Compose
                   (Ada.Directories.Containing_Directory
                      (Ada.Command_Line.Command_Name),
                    (if Hostkit.Fs.Executable_Suffix = ""
                     then "adash_test_watch"
                     else "adash_test_watch" & Hostkit.Fs.Executable_Suffix)),
                 Told, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the watcher would not start on a terminal");

      Hostkit.Pty.Close_Device (Terminal);

      --  A moment for it to take the terminal, then one of each thing.
      delay 0.5;

      Send ("A");
      delay 0.2;

      --  Ctrl-C: the byte a line discipline takes, and the key event a console
      --  asks for. Both, because which of them arrives is the question.
      Send ([1 => Character'Val (3)]);
      delay 0.2;
      Send (Escape & "[67;46;3;1;8;1_" & Escape & "[67;46;3;0;8;1_");
      delay 0.2;

      --  The accented character: its UTF-8, then as a key event carrying a
      --  character.
      Send (Accented);
      delay 0.2;
      Send (Escape & "[231;0;233;1;0;1_" & Escape & "[231;0;233;0;0;1_");

      for Attempt in 1 .. 200 loop
         exit when Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
                   and then Result.State /= Hostkit.Spawn.Wait_Running;

         --  Drained while it runs: a terminal nobody reads fills up, and a
         --  program writing into a full one waits instead of finishing.
         --  Drained while it runs: a terminal nobody reads fills up, and a
         --  program writing into a full one waits instead of finishing. What
         --  it said is the watcher's business, not this test's.
         declare
            Ignored : constant Boolean := Drained_Into_Nothing (Terminal);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end loop;

      Hostkit.Pty.Close (Terminal);

      if Ada.Directories.Exists (Room) then
         declare
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Room);

            while not Ada.Text_IO.End_Of_File (File) loop
               Ada.Strings.Unbounded.Append
                 (Said, Ada.Text_IO.Get_Line (File) & " ");
            end loop;

            Ada.Text_IO.Close (File);
         end;
      end if;

      --  The claim that must hold on every host: what was typed arrives. 65 is
      --  the A.
      Assert (Wrote ("byte= 65"),
              "an ordinary character typed at a terminal did not reach the "
              & "program on it, so nothing else this records means anything: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");

      --  The two open questions. Both are asserted rather than reported,
      --  because the record travels in the message either way and a test that
      --  cannot fail answers nothing.
      Assert (Wrote ("byte= 3") or else Wrote ("interrupt"),
              "a Ctrl-C typed at the terminal reached the program as neither "
              & "a byte nor a recorded interrupt: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");

      --  And the character. Its UTF-8 is 195 169, and what a console hands
      --  over is whatever its code page says -- 130 for this character in the
      --  OEM one, which is what this probe found before raw mode started
      --  asking for UTF-8. Both are accepted here: what this case is for is
      --  that *something* arrives, and which bytes belong in the answer is
      --  hostkit's business rather than this test's.
      Assert (Wrote ("byte= 195") or else Wrote ("byte= 233")
              or else Wrote ("byte= 130") or else Wrote ("byte= 169"),
              "an accented character typed at the terminal reached the "
              & "program in no encoding at all: ["
              & Ada.Strings.Unbounded.To_String (Said) & "]");

      --  And the question a shell actually has: a program that is *not*
      --  reading, on a terminal asked to report an interrupt key. That is the
      --  shape a shell is in while a submission runs, and the answer decides
      --  whether stopping a runaway loop is the host's job or the shell's.
      --
      --  Asked twice, because the record so far says the notice never comes on
      --  one host and says nothing about why. "busy" is that host's answer
      --  again; "busy-raw" is the same spinning program with the terminal left
      --  raw and the input polled as it spins -- which is how the shell would
      --  find the keystroke itself, on a host that will not tell it. The raw
      --  record above already shows byte= 3 arriving there.
      declare
         procedure Ask_A_Watcher
           (Mode : String; File : String; Record_Into : out
              Ada.Strings.Unbounded.Unbounded_String);

         procedure Ask_A_Watcher
           (Mode : String; File : String; Record_Into : out
              Ada.Strings.Unbounded.Unbounded_String)
         is
            Second : Hostkit.Pty.Pair;
            Waiter : Hostkit.Spawn.Process_Handle;
            Asked  : Hostkit.String_Vectors.Vector;

            Elsewhere : constant String :=
              Ada.Directories.Compose
                (Ada.Directories.Containing_Directory
                   (Ada.Command_Line.Command_Name),
                 File);
         begin
            Record_Into := Ada.Strings.Unbounded.Null_Unbounded_String;

            if Ada.Directories.Exists (Elsewhere) then
               Ada.Directories.Delete_File (Elsewhere);
            end if;

            Asked.Append
              (Ada.Strings.Unbounded.To_Unbounded_String (Elsewhere));
            Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String ("4"));
            Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String (Mode));

            Assert (Hostkit.Pty.Open (Second),
                    "could not open a second terminal");
            Assert (Hostkit.Pty.Set_Size (Second, (Rows => 24, Columns => 80)),
                    "could not size the second terminal");

            declare
               Theirs : Hostkit.Spawn.Options;
            begin
               Assert (Hostkit.Pty.Attach (Second, Theirs),
                       "could not start the waiter on a terminal");
               Assert (Hostkit.Spawn.Start
                         (Ada.Directories.Compose
                            (Ada.Directories.Containing_Directory
                               (Ada.Command_Line.Command_Name),
                             "adash_test_watch"
                             & Hostkit.Fs.Executable_Suffix),
                          Asked, Theirs, Waiter)
                       = Hostkit.Spawn.Spawn_Ok,
                       "the waiter would not start on a terminal");
            end;

            Hostkit.Pty.Close_Device (Second);

            delay 0.5;

            --  A line for it to read, so it goes through what the editor does.
            declare
               Line : constant Ada.Streams.Stream_Element_Array (1 .. 2) :=
                 [Character'Pos ('x'), 13];
               Last : Ada.Streams.Stream_Element_Offset;

               use type Hostkit.Descriptors.Transfer_Outcome;

               Sent : constant Boolean :=
                 Hostkit.Descriptors.Write (Second.To_Child, Line, Last)
                 = Hostkit.Descriptors.Transfer_Ok;

               use type Ada.Streams.Stream_Element_Offset;
            begin
               Assert (Sent and then Last = Line'Last,
                       "could not type a line at the second terminal");
            end;

            delay 0.5;

            declare
               Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
                 [1 => Ada.Streams.Stream_Element (3)];
               Last : Ada.Streams.Stream_Element_Offset;

               use type Ada.Streams.Stream_Element_Offset;
               use type Hostkit.Descriptors.Transfer_Outcome;

               Sent : constant Boolean :=
                 Hostkit.Descriptors.Write (Second.To_Child, Data, Last)
                 = Hostkit.Descriptors.Transfer_Ok;
            begin
               Assert (Sent and then Last = Data'Last,
                       "could not type at the second terminal");
            end;

            for Attempt in 1 .. 200 loop
               exit when Hostkit.Spawn.Wait
                           (Waiter, Hostkit.Spawn.Wait_Poll, Result)
                         and then Result.State /= Hostkit.Spawn.Wait_Running;

               declare
                  Ignored : constant Boolean := Drained_Into_Nothing (Second);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            end loop;

            Hostkit.Pty.Close (Second);

            if Ada.Directories.Exists (Elsewhere) then
               declare
                  Kept : Ada.Text_IO.File_Type;
               begin
                  Ada.Text_IO.Open (Kept, Ada.Text_IO.In_File, Elsewhere);

                  while not Ada.Text_IO.End_Of_File (Kept) loop
                     Ada.Strings.Unbounded.Append
                       (Record_Into, Ada.Text_IO.Get_Line (Kept) & " ");
                  end loop;

                  Ada.Text_IO.Close (Kept);
               end;
            end if;
         end Ask_A_Watcher;

         Waited  : Ada.Strings.Unbounded.Unbounded_String;
         Watched : Ada.Strings.Unbounded.Unbounded_String;
         Toggled : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ask_A_Watcher ("busy", "terminal-waiting.txt", Waited);
         Ask_A_Watcher ("busy-raw", "terminal-watching.txt", Watched);
         Ask_A_Watcher ("busy-toggle", "terminal-toggling.txt", Toggled);

         --  A program that never stops computing is not told about a Ctrl-C
         --  on every host, and where it is not, the record says so rather than
         --  this case asserting one answer. What the *shell* does about it is
         --  the case below, which is the claim that matters.
         Assert (Ada.Strings.Fixed.Index
                   (Ada.Strings.Unbounded.To_String (Waited), "busy-told")
                 > 0,
                 "the busy probe did not run at all: ["
                 & Ada.Strings.Unbounded.To_String (Waited) & "]");

         Assert (Ada.Strings.Fixed.Index
                   (Ada.Strings.Unbounded.To_String (Watched), "busy-told")
                 > 0,
                 "the polling probe did not run at all: ["
                 & Ada.Strings.Unbounded.To_String (Watched) & "]");

         --  Printed, not only asserted. What this case is for is finding out,
         --  and an assertion that holds says nothing on the host whose answer
         --  is the reason the case exists -- the record has to reach a reader
         --  when it passes as well as when it fails.
         Ada.Text_IO.Put_Line
           ("busy-probe: " & Ada.Strings.Unbounded.To_String (Waited));
         Ada.Text_IO.Put_Line
           ("polling-probe: " & Ada.Strings.Unbounded.To_String (Watched));

         --  The one that matters: this is the shell's own arrangement, so a
         --  host that finds the keystroke here is a host where a runaway loop
         --  can be stopped without leaving a console raw for whatever the
         --  submission runs.
         Assert (Ada.Strings.Fixed.Index
                   (Ada.Strings.Unbounded.To_String (Toggled), "saw-three")
                 > 0,
                 "the toggling probe did not run at all: ["
                 & Ada.Strings.Unbounded.To_String (Toggled) & "]");

         Ada.Text_IO.Put_Line
           ("toggling-probe: " & Ada.Strings.Unbounded.To_String (Toggled));
      end;
   end A_Terminal_Says_What_Reaches_A_Program;

   --  Ctrl-C at the prompt abandons the line and leaves the session standing,
   --  through the terminal.
   --
   --  The half of an interrupt that is the *editor's* rather than the host's:
   --  the byte arrives as a keystroke, the line being typed is dropped, and
   --  the next prompt is a fresh one. No signal is needed for that, which is
   --  why this runs on every host that can give a child a terminal -- and on
   --  the one where an interrupt cannot stop a running loop, this is what
   --  Ctrl-C does do.
   procedure An_Interrupt_At_The_Prompt_Abandons_The_Line
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  A line that would say something if it ever ran.
      Type_Into (Session, "put_line (To_Upper (""abandoned""))");
      Type_Interrupt (Session);

      --  And then a line that does run. If the first had survived the
      --  interrupt, the two would be one line and neither would run.
      Type_Into (Session, "put_line (To_Upper (""after""));" & Return_Key);

      Assert (Waited_For (Session, "AFTER", Tries => 600),
              "the session did not answer after an interrupt at the prompt: ["
              & Plainly (Session) & "]");

      Assert (Times_Seen (Session, "ABANDONED") = 0,
              "the line the interrupt abandoned ran anyway: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after an abandoned line");
   end An_Interrupt_At_The_Prompt_Abandons_The_Line;

   --  Ctrl-C stops a program of the shell's own and leaves the session
   --  standing, through the terminal.
   --
   --  The keystroke is typed rather than the signal sent, which is the point:
   --  what a user does is press a key, and what turns that key into a signal
   --  is the terminal signalling the foreground group of the session that
   --  controls it. The shell is started in a session of its own for exactly
   --  this -- see Start_On_A_Terminal -- and until Hostkit.Spawn could do
   --  that, no test could reach this behaviour at all.
   --
   --  The loop says when it has started and never ends by itself, so nothing
   --  here is timed: what follows the interrupt is the proof that it arrived.
   procedure An_Interrupt_Stops_A_Loop_Through_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;
   begin
      --  No longer guarded by whether the host has signals.
      --
      --  It was, and the note said why: on Windows a spinning program is never
      --  told that Ctrl-C was typed -- not late, not unnoticed, never, as the
      --  probe above measures by asking again half a second after it stops
      --  spinning. Waiting for the host to say so was the wrong thing to wait
      --  for.
      --
      --  What the same probe also measures is that the keystroke itself
      --  arrives, as the byte three, at a terminal that is raw when the look
      --  happens. So the shell looks: between instructions, at most twenty
      --  times a second, it takes the terminal raw for an instant and reads
      --  what is there. That is a shell's own arrangement rather than the
      --  host's, and this case is the claim that it works.

      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      Type_Into
        (Session,
         "put_line (To_Upper (""running"")); loop null; end loop;"
         & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, "RUNNING", Tries => 600),
              "the loop never started: ["
              & Plainly (Session) & "]");

      --  Ctrl-C, as a user types it.
      Type_Interrupt (Session);

      --  The prompt comes back carrying its failure marker: a submission the
      --  interrupt ended is a submission that failed.
      Assert (Waited_For_Plainly (Session, "! ", Tries => 600),
              "the interrupt did not bring the prompt back: ["
              & Plainly (Session) & "]");

      Type_Into
        (Session,
         "put_line (To_Upper (""alive""));" & String'(1 => Character'Val (13)));

      Assert (Waited_For (Session, "ALIVE", Tries => 600),
              "the session did not answer after the interrupt: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after an interrupt");
   end An_Interrupt_Stops_A_Loop_Through_A_Terminal;

   --  What a user typed while a loop was running is still there afterwards.
   --
   --  A promise with two very different mechanisms behind it. Where the host
   --  reports the interrupt, the terminal's own buffer holds what was typed
   --  and the shell never sees it until it reads a line. Where the shell
   --  watches its terminal instead, it reads those bytes itself while looking
   --  for the Ctrl-C -- so it has to put back everything that was not the
   --  interrupt, and put a raw return back as the line feed a reader expects.
   --
   --  Neither mechanism is visible from here, which is the point: what a user
   --  is promised is that the line they typed runs, and this is that promise.
   procedure Type_Ahead_Survives_An_Interrupt
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Type_Ahead_Survives_An_Interrupt
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  A loop that ends by itself, rather than one an interrupt ends.
      --
      --  Interrupting was the first shape of this case and it asserted
      --  something untrue: a POSIX terminal flushes what has been typed when
      --  it turns Ctrl-C into a signal, deliberately, so type-ahead does not
      --  survive an interrupt anywhere and should not. What it survives is a
      --  submission that takes a while -- which is the whole of what a user
      --  typing ahead is doing.
      Type_Into
        (Session,
         "put_line (To_Upper (""running"")); for I in 1 .. 3_000_000 loop "
         & "null; end loop; put_line (To_Upper (""ended""));"
         & Return_Key);

      Assert (Waited_For (Session, "RUNNING", Tries => 600),
              "the loop never started: [" & Plainly (Session) & "]");

      --  Typed while the loop runs, and typed whole: a user who wanted to say
      --  something next does not wait for a prompt to say it.
      Type_Into (Session, "put_line (To_Upper (""kept""));" & Return_Key);

      Assert (Waited_For (Session, "ENDED", Tries => 900),
              "the submission never ended: [" & Plainly (Session) & "]");

      Assert (Waited_For (Session, "KEPT", Tries => 900),
              "the line typed while the loop ran was lost: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after keeping a typed-ahead line");
   end Type_Ahead_Survives_An_Interrupt;

   --  The shell can read a line from the terminal while a submission runs.
   --
   --  The other half of watching. A shell that watches its terminal holds it
   --  raw, and a read taken on a raw terminal answers nothing usable: no echo,
   --  and a return that arrives as a carriage return where the reader waits
   --  for a line feed -- so a script asking a question would hang with the
   --  user unable to see what they typed. The terminal is handed back for the
   --  duration of the read and taken again afterwards, and this is that.
   --
   --  Whichever way it were wrong, this would hang rather than answer, and the
   --  wait is bounded.
   procedure A_Submission_Can_Read_A_Line_From_The_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Submission_Can_Read_A_Line_From_The_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      Type_Into
        (Session,
         "put_line (To_Upper (""asking"")); put_line (To_Upper (Read_Line));"
         & Return_Key);

      Assert (Waited_For (Session, "ASKING", Tries => 600),
              "the submission never reached its question: ["
              & Plainly (Session) & "]");

      Type_Into (Session, "answered" & Return_Key);

      Assert (Waited_For (Session, "ANSWERED", Tries => 600),
              "a submission could not read a line from the terminal: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after reading a line");
   end A_Submission_Can_Read_A_Line_From_The_Terminal;

   --  A program the shell runs can read a line typed at the terminal.
   --
   --  Two arrangements meet here and a program that asks a question needs
   --  both. A job is started in a process group of its own -- that is what
   --  makes it a job -- and a POSIX terminal stops any program in another
   --  group that reads it, so the shell hands the terminal to the job while it
   --  runs and takes it back afterwards. Where the shell watches its terminal
   --  for Ctrl-C instead, watching means holding it raw, and it gives that up
   --  for the same duration.
   --
   --  This could not be written until today: the program was stopped where it
   --  asked, and a shell running `cat` looked like a shell that had hung.
   --
   --  Whichever half were missing this would hang rather than answer, and the
   --  wait is bounded.
   procedure A_Program_In_A_Submission_Can_Read_A_Line
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Program_In_A_Submission_Can_Read_A_Line
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];

      Reader : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Command_Line.Command_Name),
           "adash_test_reader" & Hostkit.Fs.Executable_Suffix);
   begin
      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      --  Through `run`, which is the path a user types and, until this was
      --  written, the one that did not hand the terminal over: it waits for
      --  the job itself rather than through Pipelines.Run, so it needed its
      --  own handover. The program writes back what it read, so what appears
      --  is told apart from the terminal's echo by its case.
      Type_Into
        (Session,
         "run (""" & Reader & """);" & Return_Key);

      --  A moment for the program to start and reach its read, drained the
      --  whole time rather than waited out: a terminal nobody reads fills up,
      --  and a shell blocked part-way through echoing a line this long is not
      --  reading the rest of what was typed either.
      for Attempt in 1 .. 40 loop
         exit when not Drained (Session);
         delay 0.05;
      end loop;

      Type_Into (Session, "typed" & Return_Key);

      --  Marked by the program, because a terminal that echoes what is typed
      --  would otherwise answer this test by itself. This pseudo-terminal does
      --  not echo and another host's may.
      Assert (Waited_For (Session, "read=typed", Tries => 600),
              "a program in a submission could not read a line from the "
              & "terminal: [" & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after a program read a line");
   end A_Program_In_A_Submission_Can_Read_A_Line;

   --  A background job is given nothing to read, where the shell is watching.
   --
   --  The rule is asked directly rather than through a job, because the only
   --  host where it fires is the one where the shell watches its terminal --
   --  and a case that could only run there would be a case nobody reads the
   --  result of. Arming the watching on a pseudo-terminal puts this host in
   --  the same state for as long as the question takes.
   --
   --  Three claims: a job whose input was redirected keeps it, a shell that is
   --  not watching changes nothing, and a shell that is watching hands over a
   --  stream of its own that reads as end of input. The last is the one that
   --  matters -- a background program racing the shell for keystrokes is the
   --  thing this prevents -- and the first is what keeps the prevention from
   --  overriding what a user asked for.
   procedure A_Background_Job_Is_Given_Nothing_To_Read
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Background_Job_Is_Given_Nothing_To_Read
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Terminal : Hostkit.Pty.Pair;

      Inherited : constant Str.Endpoint := Str.Inherited (Str.Role_Input);
   begin
      --  Not watching: everything is left as it was.
      Assert (not Adash.Execution.Signals.Watching,
              "something left the terminal watched");
      Assert (not Str.Is_Owned (Str.Background_Input (Inherited)),
              "a shell that is not watching gave a background job a stream "
              & "of its own");

      if not Hostkit.Pty.Is_Supported or else not Hostkit.Pty.Open (Terminal)
      then
         return;
      end if;

      if not Hostkit.Descriptors.Is_Valid (Terminal.Device) then
         --  A pseudo-console has no device side to hold raw, so this host
         --  cannot be put into the state the rule is about from here. What it
         --  does in that state is asserted by the host itself, through the
         --  session cases above.
         Hostkit.Pty.Close (Terminal);
         return;
      end if;

      Adash.Execution.Signals.Watch_Terminal (Terminal.Device);

      if not Adash.Execution.Signals.Watching then
         Hostkit.Pty.Close (Terminal);
         return;
      end if;

      declare
         Nothing : constant Str.Endpoint := Str.Background_Input (Inherited);

         Buffer : Ada.Streams.Stream_Element_Array (1 .. 8);
         Last   : Ada.Streams.Stream_Element_Offset;

         use type Hostkit.Descriptors.Transfer_Outcome;
      begin
         Assert (Str.Is_Owned (Nothing),
                 "a watching shell left a background job on the terminal");

         Assert (Hostkit.Descriptors.Read (Str.Handle (Nothing), Buffer, Last)
                 = Hostkit.Descriptors.Transfer_End_Of_File,
                 "what a background job was given did not read as nothing");

         --  And what the user asked for is untouched.
         declare
            Asked : constant Str.Endpoint := Str.Owned (Str.Handle (Nothing));

            use type Hostkit.Descriptors.Descriptor;
         begin
            Assert (Str.Handle (Str.Background_Input (Asked))
                    = Str.Handle (Asked),
                    "a redirected background job had its input taken away");
         end;

         declare
            Giving_Up : Hostkit.Descriptors.Descriptor := Str.Handle (Nothing);
         begin
            Hostkit.Descriptors.Close (Giving_Up);
         end;
      end;

      Adash.Execution.Signals.Stop_Watching;
      Hostkit.Pty.Close (Terminal);
   end A_Background_Job_Is_Given_Nothing_To_Read;

   --  A job waited for gets the terminal, like a program started in front.
   --
   --  `wait` is what puts a job in the foreground in the only sense a user
   --  means by the word: nothing else runs until it ends. It waits through the
   --  same call `run` does and, until this was written, without the handover
   --  `run` had just been given -- so a job that asked a question was stopped
   --  where it asked.
   --
   --  The program waits a moment before reading, because a background program
   --  that reads a POSIX terminal is stopped where it reads: one that read
   --  immediately would be stopped before the shell had handed the terminal
   --  over, and this would be measuring a race.
   procedure A_Job_Waited_For_Gets_The_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure A_Job_Waited_For_Gets_The_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Return_Key : constant String := [1 => Character'Val (13)];

      Reader : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Command_Line.Command_Name),
           "adash_test_reader" & Hostkit.Fs.Executable_Suffix);
   begin
      if not Hostkit.Terminal_Control.Supports_Foreground_Group then
         --  Where a terminal has no owning group there is nothing to hand
         --  over, and a job started into the background on that host was
         --  given nothing to read at the moment it started -- which the case
         --  above asserts, and which `wait` cannot undo.
         return;
      end if;

      if not Start_On_A_Terminal (Session) then
         return;
      end if;

      Type_Into
        (Session,
         "start (""" & Reader & """, ""2""); wait (1);" & Return_Key);

      --  Drained while the job starts and waits, rather than delayed: a
      --  terminal nobody reads fills up, and a shell blocked part-way through
      --  echoing a line this long is not reading what follows it either.
      for Attempt in 1 .. 60 loop
         exit when not Drained (Session);
         delay 0.05;
      end loop;

      Type_Into (Session, "typed" & Return_Key);

      Assert (Waited_For (Session, "read=typed", Tries => 900),
              "a job waited for could not read a line from the terminal: ["
              & Plainly (Session) & "]");

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after waiting for a job");
   end A_Job_Waited_For_Gets_The_Terminal;

   --  A script interrupted still runs what it registered.
   --
   --  `on_exit` exists for this case rather than for the tidy one: a script
   --  that reaches its own end can put the removal on the last line. The case
   --  that needs it is the script stopped half way, and until this was written
   --  the only thing asserted was ending through `quit`.
   --
   --  Through a terminal, because that is where an interrupt comes from. What
   --  the shell does with it differs by host -- a signal on two of them, a
   --  keystroke the shell reads on the third -- and both paths end in the same
   --  place, which is what this asserts.
   procedure An_Interrupted_Script_Still_Tidies_Up
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure An_Interrupted_Script_Still_Tidies_Up
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Script : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-tidy.adash");

      Written : Adash.Filesystem.Written;

      --  Whether the interrupt reached the terminal at all.
      Reached_It : Boolean := False;

      use type Adash.Filesystem.Written;
   begin
      Adash.Filesystem.Write
        (Script,
         "procedure Tidy is begin put_line (To_Upper (""tidied"")); end Tidy;"
         & Ada.Characters.Latin_1.LF
         & "on_exit (""Tidy"");" & Ada.Characters.Latin_1.LF
         & "put_line (To_Upper (""running""));" & Ada.Characters.Latin_1.LF
         & "loop null; end loop;" & Ada.Characters.Latin_1.LF,
         Written);

      Assert (Written = Adash.Filesystem.Write_Ok,
              "the script was not written");

      --  Ungated, after two hosts had to be excluded for reasons that turned
      --  out to be the case's own.
      --
      --  Windows was excluded because nothing arrived on the terminal while a
      --  script ran: that was the shell's output waiting in a block buffer,
      --  and a line written to a terminal is pushed out as it is written now.
      --  macOS was excluded because the child was gone by the time the
      --  interrupt was typed -- and between then and now the wait here stopped
      --  giving up on the first quiet drain, and the transcript stopped being
      --  read with the console's window title spliced through it. The probe
      --  below says that host's script speaks and its shell is still there
      --  when the terminal closes, so the question is asked again everywhere.

      if not Start_On_A_Terminal (Session, Script) then
         Ada.Directories.Delete_File (Script);
         return;
      end if;

      --  Waited for patiently rather than through Waited_For, which stops the
      --  moment a drain comes back with nothing: on a console that is what a
      --  terminal says while a child is still starting, and this case was
      --  reading it as "the script never started" on the one host where
      --  starting takes longest.
      declare
         Seen : Boolean := False;
      begin
         for Attempt in 1 .. 200 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Seen := Ada.Strings.Fixed.Index
                         (Plainly (Session), "RUNNING") > 0;
            end;

            exit when Seen;
            delay 0.05;
         end loop;

         Assert (Seen,
                 "the script never started: [" & Plainly (Session) & "]");
      end;

      --  Asserted, now that it is known to be true everywhere: the shell is
      --  reading its terminal at this point on all three hosts, and a refusal
      --  here would be news. The refusal this case used to fail on came later,
      --  at the typing that used to end it.
      Reached_It := Try_Interrupt (Session);

      Assert (Reached_It,
              "the terminal refused the interrupt: [" & Plainly (Session) & "]");

      declare
         Tidied : Boolean := False;
      begin
         for Attempt in 1 .. 300 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Tidied := Ada.Strings.Fixed.Index
                           (Plainly (Session), "TIDIED") > 0;
            end;

            exit when Tidied;
            delay 0.05;
         end loop;

         Assert (Tidied,
                 "an interrupted script did not run what it registered "
                 & "after an interrupt the terminal took: ["
                 & Plainly (Session) & "]");
      end;

      --  Closed rather than quit, which is what this case was getting wrong.
      --
      --  A shell whose script was interrupted runs what was registered and
      --  then leaves; `Finish` types `quit (0);` at it, and typing at a shell
      --  that is already on its way out is a race the test loses on whichever
      --  host is quickest. macOS was that host: the write came back refused,
      --  the case reported "could not type into the terminal", and that was
      --  read for a long time as the interrupt never arriving -- while the
      --  transcript printed beside it says TIDIED, which is the whole claim,
      --  already true before the typing that failed.
      --
      --  What was different about that host is a pty rule rather than a shell:
      --  a write to the terminal is refused once nothing holds the far end,
      --  where the other two accept it into a buffer nobody will read. That
      --  now has a name in the crate that owns platform differences --
      --  Hostkit.Pty.Write_Fails_When_Unheld -- and a case there that measures
      --  it, so the next caller to meet it reads an answer rather than a
      --  symptom.
      Close_Without_Typing (Session, Ended);

      Assert (Ended,
              "an interrupted script left a shell behind: ["
              & Plainly (Session) & "]");

      Ada.Directories.Delete_File (Script);
   end An_Interrupted_Script_Still_Tidies_Up;

   --  A script interrupted runs what `on_interrupt` asked for, and then what
   --  `on_exit` did.
   --
   --  The case beside this one asserts the cleanup; this asserts the other
   --  half, which is newer: until `on_interrupt` a script could tidy up after
   --  itself only if it was allowed to finish, which is the case that needs it
   --  least. Both, in that order, because a cleanup that ran first would tidy
   --  away what the handler was about to look at.
   procedure An_Interrupted_Script_Runs_Its_Handler
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure An_Interrupted_Script_Runs_Its_Handler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Script : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-handler.adash");

      Written : Adash.Filesystem.Written;

      use type Adash.Filesystem.Written;
   begin
      Adash.Filesystem.Write
        (Script,
         "procedure Note is begin put_line (To_Upper (""noted"")); end Note;"
         & Ada.Characters.Latin_1.LF
         & "procedure Tidy is begin put_line (To_Upper (""tidied"")); end Tidy;"
         & Ada.Characters.Latin_1.LF
         & "on_interrupt (""Note"");" & Ada.Characters.Latin_1.LF
         & "on_exit (""Tidy"");" & Ada.Characters.Latin_1.LF
         & "put_line (To_Upper (""running""));" & Ada.Characters.Latin_1.LF
         & "loop null; end loop;" & Ada.Characters.Latin_1.LF,
         Written);

      Assert (Written = Adash.Filesystem.Write_Ok,
              "the script was not written");

      if not Start_On_A_Terminal (Session, Script) then
         Ada.Directories.Delete_File (Script);
         return;
      end if;

      declare
         Seen : Boolean := False;
      begin
         for Attempt in 1 .. 200 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Seen := Ada.Strings.Fixed.Index
                         (Plainly (Session), "RUNNING") > 0;
            end;

            exit when Seen;
            delay 0.05;
         end loop;

         Assert (Seen,
                 "the script never started: [" & Plainly (Session) & "]");
      end;

      Assert (Try_Interrupt (Session),
              "the terminal refused the interrupt: ["
              & Plainly (Session) & "]");

      declare
         Noted  : Boolean := False;
         Tidied : Boolean := False;
      begin
         for Attempt in 1 .. 300 loop
            declare
               Ignored : constant Boolean := Drained (Session);
               pragma Unreferenced (Ignored);
            begin
               Noted := Ada.Strings.Fixed.Index
                          (Plainly (Session), "NOTED") > 0;
               Tidied := Ada.Strings.Fixed.Index
                           (Plainly (Session), "TIDIED") > 0;
            end;

            exit when Noted and then Tidied;
            delay 0.05;
         end loop;

         Assert (Noted,
                 "an interrupted script did not run what on_interrupt asked "
                 & "for: [" & Plainly (Session) & "]");

         Assert (Tidied,
                 "an interrupted script did not run its cleanup after its "
                 & "handler: [" & Plainly (Session) & "]");

         Assert (Ada.Strings.Fixed.Index (Plainly (Session), "NOTED")
                 < Ada.Strings.Fixed.Index (Plainly (Session), "TIDIED"),
                 "the cleanup ran before the handler: ["
                 & Plainly (Session) & "]");
      end;

      Close_Without_Typing (Session, Ended);

      Assert (Ended,
              "an interrupted script left a shell behind: ["
              & Plainly (Session) & "]");

      Ada.Directories.Delete_File (Script);
   end An_Interrupted_Script_Runs_Its_Handler;


   procedure Close_Without_Typing
     (Item : in out Terminal_Session; Ended : out Boolean)
   is
      Result : Hostkit.Spawn.Status;

      use type Hostkit.Spawn.Wait_State;
   begin
      Ended := False;

      Hostkit.Pty.Close (Item.Pair);

      begin
         for Attempt in 1 .. 40 loop
            if Hostkit.Spawn.Wait (Item.Child, Hostkit.Spawn.Wait_Poll, Result)
              and then Result.State /= Hostkit.Spawn.Wait_Running
            then
               Ended := True;
               exit;
            end if;

            delay 0.05;
         end loop;

      exception
         when others =>
            --  A probe records; it does not die of what it is watching.
            --
            --  This caught a real one: asking after a child whose console had
            --  just been closed raised Constraint_Error out of hostkit, which
            --  was converting a Windows exit code at the top of the unsigned
            --  range into an Integer. That is fixed where it belongs, and the
            --  handler stays -- a probe that falls over takes the record with
            --  it, which is the one thing it must not do.
            Ended := False;
      end;

      if not Ended then
         --  Still there with nothing to read and nowhere to write. Asked to
         --  stop, so a probe does not leave a process behind.
         declare
            Asked : constant Boolean :=
              Hostkit.Process.Request_Stop
                (Hostkit.Spawn.Process_Id (Item.Child));
            pragma Unreferenced (Asked);
         begin
            null;
         end;
      end if;

      Item.Started := False;
   end Close_Without_Typing;

   --  What a shell on a terminal says when it is given a script.
   --
   --  A record rather than an assertion, and the third time this file has
   --  needed one. The case above cannot ask its question on Windows because a
   --  shell started on a pseudo-console *with a script* writes nothing to that
   --  terminal at all -- not the line the script prints before it loops, not a
   --  complaint -- while the same shell on the same terminal without a script
   --  prompts and answers, which every other terminal case here depends on.
   --
   --  So this starts that shell over a script that prints one line and stops,
   --  drains the terminal for as long as it takes, and prints every byte:
   --  printable ones as themselves and the rest as their number, because what
   --  is being looked for may be something that does not print. On the two
   --  hosts that answer, the record says what the answer looks like -- which
   --  is what makes the third host's silence readable when somebody comes back
   --  to it.
   procedure What_A_Shell_Given_A_Script_Says_On_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure What_A_Shell_Given_A_Script_Says_On_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Session : Terminal_Session;
      Ended   : Boolean;

      Script : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory, "adash-test-said.adash");

      Written : Adash.Filesystem.Written;

      use type Adash.Filesystem.Written;
   begin
      --  Two scripts, because the difference between them is the question: one
      --  that says something and stops, and one that says something and keeps
      --  running. The second is the shape the interrupted-script case needs
      --  and the shape that comes back empty on Windows.
      Adash.Filesystem.Write
        (Script,
         "put_line (To_Upper (""spoken""));" & Ada.Characters.Latin_1.LF
         & "quit (0);" & Ada.Characters.Latin_1.LF,
         Written);

      Assert (Written = Adash.Filesystem.Write_Ok,
              "the script was not written");

      if not Start_On_A_Terminal (Session, Script) then
         Ada.Directories.Delete_File (Script);
         return;
      end if;

      --  Drained for a fixed while rather than waited for a marker: the point
      --  is to record whatever arrives, including nothing.
      for Attempt in 1 .. 60 loop
         exit when not Drained (Session);
         delay 0.05;
      end loop;

      declare
         Whole : constant String :=
           Ada.Strings.Unbounded.To_String (Session.Seen);

         Shown : Ada.Strings.Unbounded.Unbounded_String;
      begin
         for Index in Whole'Range loop
            if Whole (Index) in ' ' .. '~' then
               Ada.Strings.Unbounded.Append (Shown, Whole (Index));
            else
               Ada.Strings.Unbounded.Append
                 (Shown,
                  "<" & Ada.Strings.Fixed.Trim
                          (Natural'Image (Character'Pos (Whole (Index))),
                           Ada.Strings.Both) & ">");
            end if;
         end loop;

         Ada.Text_IO.Put_Line
           ("script-on-a-terminal: ["
            & Ada.Strings.Unbounded.To_String (Shown) & "]");
      end;

      Close_Without_Typing (Session, Ended);

      --  And the same question of a script that does not stop.
      declare
         Busy : constant String :=
           Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "adash-test-busy.adash");

         Second : Terminal_Session;
         Over   : Boolean;
      begin
         Adash.Filesystem.Write
           (Busy,
            "put_line (To_Upper (""spoken""));" & Ada.Characters.Latin_1.LF
            & "loop null; end loop;" & Ada.Characters.Latin_1.LF,
            Written);

         if Written = Adash.Filesystem.Write_Ok
           and then Start_On_A_Terminal (Second, Busy)
         then
            for Attempt in 1 .. 60 loop
               exit when not Drained (Second);
               delay 0.05;
            end loop;

            declare
               Whole : constant String :=
                 Ada.Strings.Unbounded.To_String (Second.Seen);

               Shown : Ada.Strings.Unbounded.Unbounded_String;
            begin
               for Index in Whole'Range loop
                  if Whole (Index) in ' ' .. '~' then
                     Ada.Strings.Unbounded.Append (Shown, Whole (Index));
                  else
                     Ada.Strings.Unbounded.Append
                       (Shown,
                        "<" & Ada.Strings.Fixed.Trim
                                (Natural'Image (Character'Pos (Whole (Index))),
                                 Ada.Strings.Both) & ">");
                  end if;
               end loop;

               Ada.Text_IO.Put_Line
                 ("busy-script-on-a-terminal: ["
                  & Ada.Strings.Unbounded.To_String (Shown) & "]");
            end;

            Close_Without_Typing (Second, Over);

            Ada.Text_IO.Put_Line
              ("busy-script-on-a-terminal: ended-when-closed="
               & Boolean'Image (Over));
         end if;

         Ada.Directories.Delete_File (Busy);
      end;

      --  And the question the interrupted-script case cannot ask: how long a
      --  shell running that script is still there.
      --
      --  The case types an interrupt after the script's first line appears,
      --  and on one host the terminal refused the byte -- which is a shell
      --  that has already gone. A refusal says the shell went; it does not say
      --  when, or what it had said by then, and those are the two facts that
      --  tell "the loop ended on its own" apart from "something ended it".
      --
      --  So: the same script the case writes, waited for in the same way, then
      --  asked every twentieth of a second whether the child is still running,
      --  with nothing typed at all. A loop with no exit should still be there
      --  when the asking stops.
      declare
         Tidy : constant String :=
           Ada.Directories.Compose
             (Ada.Directories.Current_Directory, "adash-test-lasted.adash");

         Third : Terminal_Session;
         Over  : Boolean;

         Seen  : Boolean := False;
         Left  : Natural := 0;
      begin
         Adash.Filesystem.Write
           (Tidy,
            "procedure Tidy is begin put_line (To_Upper (""tidied"")); "
            & "end Tidy;" & Ada.Characters.Latin_1.LF
            & "on_exit (""Tidy"");" & Ada.Characters.Latin_1.LF
            & "put_line (To_Upper (""running""));" & Ada.Characters.Latin_1.LF
            & "loop null; end loop;" & Ada.Characters.Latin_1.LF,
            Written);

         if Written = Adash.Filesystem.Write_Ok
           and then Start_On_A_Terminal (Third, Tidy)
         then
            for Attempt in 1 .. 200 loop
               declare
                  Ignored : constant Boolean := Drained (Third);
                  pragma Unreferenced (Ignored);
               begin
                  Seen := Ada.Strings.Fixed.Index
                            (Plainly (Third), "RUNNING") > 0;
               end;

               exit when Seen;
               delay 0.05;
            end loop;

            Ada.Text_IO.Put_Line
              ("lasting-script-on-a-terminal: said-running="
               & Boolean'Image (Seen));

            --  Kept drained while it is asked about, so that a shell stopped
            --  by a full terminal is not recorded as a shell that stayed.
            for Attempt in 1 .. 80 loop
               declare
                  Ignored : constant Boolean := Drained (Third);
                  pragma Unreferenced (Ignored);
               begin
                  if Gone (Third) then
                     Left := Attempt;
                     exit;
                  end if;
               end;

               delay 0.05;
            end loop;

            Ada.Text_IO.Put_Line
              ("lasting-script-on-a-terminal: "
               & (if Left = 0 then "still running after four seconds"
                  else "gone after"
                       & Natural'Image (Left)
                       & " twentieths of a second")
               & ", transcript=[" & Plainly (Third) & "]");

            Close_Without_Typing (Third, Over);
         end if;

         Ada.Directories.Delete_File (Tidy);
      end;

      Ada.Directories.Delete_File (Script);
   end What_A_Shell_Given_A_Script_Says_On_A_Terminal;

   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, A_Wrapped_Line_Places_Its_Cursor'Access,
         "a wrapped line puts its cursor where the text actually ends");
      Register_Routine
        (T, Width_Counts_Cells_Not_Characters'Access,
         "display width counts cells: wide characters two, combining none");
      Register_Routine (T, Buffer_Inserts_And_Deletes'Access,
                        "the buffer inserts and deletes at the cursor");
      Register_Routine (T, Cursor_Moves_By_Character'Access,
                        "the cursor never lands inside a character");
      Register_Routine (T, Buffer_Refuses_Overflow'Access,
                        "an insertion past the limit is refused whole");
      Register_Routine (T, Word_Operations_Take_Their_Separator'Access,
                        "word operations take the blanks with the word");
      Register_Routine (T, Decoder_Reads_Arrow_Keys'Access,
                        "the decoder reads the escape sequences terminals send");
      Register_Routine (T, Decoder_Waits_For_Split_Sequences'Access,
                        "a split sequence asks for more rather than guessing");
      Register_Routine (T, Decoder_Never_Inserts_Control_Bytes'Access,
                        "no control byte ever decodes as text");
      Register_Routine (T, History_Collapses_Consecutive_Duplicates'Access,
                        "history collapses consecutive duplicates only");
      Register_Routine (T, History_Forgets_Sensitive_Lines'Access,
                        "history records nothing at all for a sensitive line");
      Register_Routine (T, History_Reads_The_Mark_As_A_Leading_Space'Access,
                        "a leading space marks a submission unrecorded");
      Register_Routine (T, History_Forgets_Its_Most_Recent_Entries'Access,
                        "forgetting takes the newest entries and no more");
      Register_Routine (T, History_Forgets_Every_Copy_Of_A_Line'Access,
                        "forgetting by text takes every copy of that line");
      Register_Routine (T, History_At_Its_Limit_Still_Takes_A_Line'Access,
                        "a log at its limit still says it took the line");
      Register_Routine (T, History_Drops_Oldest_At_Its_Limit'Access,
                        "history drops its oldest entry at the limit");
      Register_Routine (T, History_Searches_Backwards'Access,
                        "history searches from the newest end");
      Register_Routine (T, Notices_Wait_While_Editing'Access,
                        "a notice waits while a line is being edited");
      Register_Routine (T, Notices_Keep_Job_News_When_Full'Access,
                        "a full queue drops advisories before job news");
      Register_Routine (T, Completion_Is_Ordered_And_Deterministic'Access,
                        "completion is deterministic and ordered by source");
      Register_Routine (T, Completion_Offers_Programs_Where_One_Is_Named'Access,
                        "programs are offered where a program is named");
      Register_Routine (T, Completion_Prefix_Is_Never_A_Guess'Access,
                        "the common prefix is shared by every candidate");
      Register_Routine (T, Highlighting_Covers_Unparsable_Input'Access,
                        "highlighting works on input that does not parse");
      Register_Routine (T, An_Interrupted_Line_Runs_Its_Handler'Access,
                        "a line interrupted at the prompt runs its handler");
      Register_Routine (T, Completion_Offers_What_A_User_Taught_It'Access,
                        "Tab offers what a user taught it");
      Register_Routine (T, Completion_Finishes_A_Word_Through_A_Terminal'Access,
                        "Tab completes a word through a terminal");
      Register_Routine (T, History_Recalls_A_Line_Through_A_Terminal'Access,
                        "Up recalls a line through a terminal");
      Register_Routine (T, History_Skips_A_Marked_Line_Through_A_Terminal'Access,
                        "a line typed with a space is not there to recall");
      Register_Routine
        (T, Backspace_Removes_A_Character_Through_A_Terminal'Access,
         "backspace removes a character through a terminal");
      Register_Routine (T, A_Terminal_Says_What_Reaches_A_Program'Access,
                        "a terminal says what reaches a program on it");
      Register_Routine (T, An_Interrupt_At_The_Prompt_Abandons_The_Line'Access,
                        "Ctrl-C at the prompt abandons the line");
      Register_Routine (T, An_Interrupt_Stops_A_Loop_Through_A_Terminal'Access,
                        "an interrupt stops a loop through a terminal");
      Register_Routine (T, Type_Ahead_Survives_An_Interrupt'Access,
                        "a line typed while a loop ran still runs after it");
      Register_Routine (T, A_Submission_Can_Read_A_Line_From_The_Terminal'Access,
                        "a submission can read a line typed at the terminal");
      Register_Routine (T, A_Program_In_A_Submission_Can_Read_A_Line'Access,
                        "a program in a submission can read a line typed at "
                        & "the terminal");
      Register_Routine (T, What_A_Shell_Given_A_Script_Says_On_A_Terminal'Access,
                        "what a shell on a terminal says when given a script");
      Register_Routine (T, An_Interrupted_Script_Still_Tidies_Up'Access,
                        "a script interrupted still runs what it registered");
      Register_Routine (T, An_Interrupted_Script_Runs_Its_Handler'Access,
                        "a script interrupted runs its handler, then its cleanup");
      Register_Routine (T, A_Job_Waited_For_Gets_The_Terminal'Access,
                        "a job waited for gets the terminal");
      Register_Routine (T, A_Background_Job_Is_Given_Nothing_To_Read'Access,
                        "a background job is given nothing to read where the "
                        & "shell watches");
      Register_Routine (T, A_Session_Answers_Through_A_Terminal'Access,
                        "a session answers through a pseudo-terminal");
   end Register_Tests;

end Adash_Tests.Interactive_Cases;

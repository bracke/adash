with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Fs;
with Hostkit.Pty;
with Hostkit.Signals;
with Hostkit.Spawn;
with Ada.Streams;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Adash.Diagnostics;
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
   function Start_On_A_Terminal (Item : in out Terminal_Session) return Boolean;

   --  Type into the terminal, as a user would.
   procedure Type_Into (Item : in out Terminal_Session; Text : String);

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

   function Start_On_A_Terminal (Item : in out Terminal_Session) return Boolean
   is
      use type Hostkit.Spawn.Spawn_Outcome;

      Options : Hostkit.Spawn.Options;
      Args    : Hostkit.String_Vectors.Vector;
   begin
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
      Assert (Waited_For (Item, "adash"),
              "no prompt arrived on the terminal");

      return True;
   end Start_On_A_Terminal;

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
         Assert (Sent = Hostkit.Descriptors.Transfer_Ok and then Whole,
                 "could not type into the terminal");
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
   function Plainly (Item : Terminal_Session) return String;

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

      --  Up, as a terminal sends it, and then a return: the recalled line runs
      --  again and the answer arrives a second time.
      Type_Into
        (Session,
         String'(1 => Character'Val (27)) & "[A"
         & String'(1 => Character'Val (13)));

      for Attempt in 1 .. 200 loop
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
      --  A terminal that is a device carries the bytes. A console host does
      --  not: it turns what arrives into key events and re-encodes them for
      --  the client, so writing two UTF-8 bytes at it is not typing that
      --  character and the line never reaches the shell at all. Asserted
      --  where it can hold, and the shell was asked: after the accented line
      --  it goes on answering, so what is missing is the keystroke and not the
      --  editor. The editor's own answer -- that a character is not a byte --
      --  is asserted on every host by the buffer and decoder cases above.
      if Hostkit.Descriptors.Is_Valid (Session.Pair.Device) then
         Type_Into (Session, "put_line (To_Upper (""fine" & Accented);
         Type_Into (Session, String'(1 => Character'Val (16#08#)));
         Type_Into (Session, """));" & String'(1 => Character'Val (13)));

         Assert (Waited_For (Session, "FINE"),
                 "backspace did not remove the whole character: ["
                 & Ada.Strings.Unbounded.To_String (Session.Seen) & "]");
      end if;

      Finish (Session, Ended);
      Assert (Ended, "the shell did not end after an edited line");
   end Backspace_Removes_A_Character_Through_A_Terminal;

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
      if not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Interrupt) then
         --  A host that cannot tell a program the user asked to interrupt.
         --  Asked as Can_Record rather than as Is_Supported, which is the
         --  narrower question and the one this is about: Windows has no
         --  signals -- nothing to number, send or give a disposition to -- and
         --  its console can still say that Ctrl-C was typed. That is enough
         --  for a shell, and Hostkit.Pty.Attach has already arranged whatever
         --  this host needs for a keystroke to reach the child: a session and
         --  a controlling terminal where there are sessions, a console where
         --  there is a console.
         return;
      end if;

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
      Type_Into (Session, String'(1 => Character'Val (3)));

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
      Register_Routine (T, Completion_Finishes_A_Word_Through_A_Terminal'Access,
                        "Tab completes a word through a terminal");
      Register_Routine (T, History_Recalls_A_Line_Through_A_Terminal'Access,
                        "Up recalls a line through a terminal");
      Register_Routine (T, History_Skips_A_Marked_Line_Through_A_Terminal'Access,
                        "a line typed with a space is not there to recall");
      Register_Routine
        (T, Backspace_Removes_A_Character_Through_A_Terminal'Access,
         "backspace removes a character through a terminal");
      Register_Routine (T, An_Interrupt_Stops_A_Loop_Through_A_Terminal'Access,
                        "an interrupt stops a loop through a terminal");
      Register_Routine (T, A_Session_Answers_Through_A_Terminal'Access,
                        "a session answers through a pseudo-terminal");
   end Register_Tests;

end Adash_Tests.Interactive_Cases;

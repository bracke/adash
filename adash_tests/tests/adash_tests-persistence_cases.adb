with Ada.Directories;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Hostkit.Fs;

with Adash.Persistence;
with Hostkit.Locks;
with Adash.Persistence.History;

package body Adash_Tests.Persistence_Cases is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   package P renames Adash.Persistence;
   package H renames Adash.Persistence.History;

   use type P.Outcome;

   Newline : constant Character := Character'Val (16#0A#);

   --  A directory of our own, removed at the end of each routine. Never the
   --  user's real store: a test that wrote there would destroy the history of
   --  whoever ran it.
   function Scratch return String;

   function Scratch return String is
   begin
      return Hostkit.Fs.Create_Temporary_Directory ("adash-persistence-test");
   end Scratch;

   procedure Discard (Directory : String);

   procedure Discard (Directory : String) is
   begin
      if Directory /= "" and then Ada.Directories.Exists (Directory) then
         Ada.Directories.Delete_Tree (Directory);
      end if;
   exception
      when others =>
         null;
   end Discard;

   procedure Absence_Is_Not_Failure
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Writing_Then_Reading_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Writing_Creates_Its_Directory
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Appending_Adds_Whole_Lines
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Removing_Is_Idempotent
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure History_Encoding_Holds_Anything
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Paths_Are_Under_One_Directory
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure A_Cache_Holds_Nothing_That_Cannot_Be_Rebuilt
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Forgetting_Takes_The_Last_Occurrence
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Forgetting_Leaves_What_The_File_Did_Not_Hold
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------
   -- Absence_Is_Not_Failure --
   ---------------------------------

   procedure Absence_Is_Not_Failure
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Room   : constant String := Scratch;
      Target : constant String := Hostkit.Fs.Join (Room, "absent.txt");
      Text   : P.Contents;
      Result : P.Outcome;
   begin
      P.Read (Target, Text, Result);

      --  A shell starting for the first time finds no files. Reporting that as
      --  a failure would make every new user's first session begin with a
      --  complaint about something that is not wrong.
      Assert (Result = P.Store_Absent,
              "a missing file reported " & P.Outcome'Image (Result));
      Assert (Length (Text) = 0, "a missing file produced contents");
      Assert (not P.Exists (Target), "a missing file reported as existing");

      --  And a path the host could not give us at all is distinct again: there
      --  is nowhere for the file to be, rather than nothing at that place.
      P.Read ("", Text, Result);
      Assert (Result = P.Store_Unavailable,
              "an empty path reported " & P.Outcome'Image (Result));

      Discard (Room);
   end Absence_Is_Not_Failure;

   ------------------------------------------------
   -- Writing_Then_Reading_Round_Trips --
   ------------------------------------------------

   procedure Writing_Then_Reading_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Room   : constant String := Scratch;
      Target : constant String := Hostkit.Fs.Join (Room, "file.txt");
      Text   : P.Contents;
      Result : P.Outcome;

      Sample : constant String :=
        "first" & Newline & "second" & Newline
        & Character'Val (16#C3#) & Character'Val (16#A9#) & Newline;
   begin
      P.Write (Target, Sample, Result);
      Assert (Result = P.Store_Ok,
              "writing reported " & P.Outcome'Image (Result));
      Assert (P.Exists (Target), "the written file does not exist");

      P.Read (Target, Text, Result);
      Assert (Result = P.Store_Ok,
              "reading back reported " & P.Outcome'Image (Result));
      Assert (To_String (Text) = Sample,
              "the file did not read back as it was written");

      --  Replacing leaves the new contents and nothing of the old, and leaves
      --  no staging file behind: one left in the directory would be read by
      --  the next thing that listed it.
      P.Write (Target, "replaced", Result);
      Assert (Result = P.Store_Ok, "replacing reported a failure");

      P.Read (Target, Text, Result);
      Assert (To_String (Text) = "replaced",
              "the replacement did not take: " & To_String (Text));
      Assert (not P.Exists (Target & ".new"),
              "a staging file was left behind");
      Assert (not P.Exists (Target & ".lock.new"),
              "a staging file was left beside the lock");

      --  An empty file is a file, not an absence.
      P.Write (Target, "", Result);
      Assert (Result = P.Store_Ok, "writing an empty file failed");
      P.Read (Target, Text, Result);
      Assert (Result = P.Store_Ok,
              "an empty file read back as " & P.Outcome'Image (Result));
      Assert (Length (Text) = 0, "an empty file read back with contents");

      Discard (Room);
   end Writing_Then_Reading_Round_Trips;

   ------------------------------------------
   -- Writing_Creates_Its_Directory --
   ------------------------------------------

   procedure Writing_Creates_Its_Directory
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Room   : constant String := Scratch;
      Nested : constant String :=
        Hostkit.Fs.Join (Hostkit.Fs.Join (Room, "one"), "two");
      Target : constant String := Hostkit.Fs.Join (Nested, "file.txt");
      Result : P.Outcome;
   begin
      --  A first run has no directory either. Making the caller create it would
      --  mean every caller doing the same thing, and one of them forgetting.
      P.Write (Target, "content", Result);
      Assert (Result = P.Store_Ok,
              "writing into a missing directory reported "
              & P.Outcome'Image (Result));
      Assert (P.Exists (Target), "the file was not created");

      Discard (Room);
   end Writing_Creates_Its_Directory;

   ---------------------------------------
   -- Appending_Adds_Whole_Lines --
   ---------------------------------------

   procedure Appending_Adds_Whole_Lines
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Room   : constant String := Scratch;
      Target : constant String := Hostkit.Fs.Join (Room, "log.txt");
      Text   : P.Contents;
      Result : P.Outcome;
   begin
      --  Appending to a file that does not exist creates it, because the first
      --  line of a history is exactly that case.
      P.Append_Line (Target, "one", Result);
      Assert (Result = P.Store_Ok,
              "appending to a missing file reported "
              & P.Outcome'Image (Result));

      P.Append_Line (Target, "two", Result);
      Assert (Result = P.Store_Ok, "the second append failed");

      P.Read (Target, Text, Result);
      Assert (To_String (Text) = "one" & Newline & "two" & Newline,
              "the appended file reads as [" & To_String (Text) & "]");

      Discard (Room);
   end Appending_Adds_Whole_Lines;

   -----------------------------------
   -- Removing_Is_Idempotent --
   -----------------------------------

   procedure Removing_Is_Idempotent
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Room   : constant String := Scratch;
      Target : constant String := Hostkit.Fs.Join (Room, "file.txt");
      Result : P.Outcome;
   begin
      P.Write (Target, "content", Result);
      Assert (Result = P.Store_Ok, "the setup write failed");

      P.Remove (Target, Result);
      Assert (Result = P.Store_Ok, "removing an existing file failed");
      Assert (not P.Exists (Target), "the file survived removal");

      --  The caller wanted it not to be there, and it is not. Reporting a
      --  failure would make every caller write the same two-branch check.
      P.Remove (Target, Result);
      Assert (Result = P.Store_Ok,
              "removing an absent file reported " & P.Outcome'Image (Result));

      Discard (Room);
   end Removing_Is_Idempotent;

   ---------------------------------------------
   -- History_Encoding_Holds_Anything --
   ---------------------------------------------

   procedure History_Encoding_Holds_Anything
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      procedure Round_Trip (Line : String);

      procedure Round_Trip (Line : String) is
         Encoded : constant String := H.Encode (Line);
         Back    : P.Contents;
      begin
         --  One line out, whatever went in. That is the whole reason for the
         --  format: an entry containing a newline cannot live in a file that
         --  separates entries by newlines.
         for Index in Encoded'Range loop
            Assert (Encoded (Index) /= Newline,
                    "the encoding of [" & Line & "] contains a newline");
         end loop;

         Assert (H.Decode (Encoded, Back),
                 "the encoding of [" & Line & "] did not decode");
         Assert (To_String (Back) = Line,
                 "[" & Line & "] came back as [" & To_String (Back) & "]");
      end Round_Trip;

      Ignored : P.Contents;
   begin
      Round_Trip ("put_line (""hello"");");
      Round_Trip ("");
      Round_Trip ("with ""quotes"" and \backslashes\");
      Round_Trip ("a" & Character'Val (16#09#) & "tab");

      --  The case a line-per-entry file cannot hold at all, and the reason this
      --  one is JSON.
      Round_Trip ("for I in 1 .. 3 loop" & Newline
                  & "   put_line (""x"");" & Newline & "end loop;");

      --  Text above ASCII, which has to survive byte for byte.
      Round_Trip ("echo " & Character'Val (16#C3#) & Character'Val (16#A9#));

      --  A line that is not one of ours is refused rather than rendered. A
      --  truncated last line is the normal thing to find in a file appended to
      --  at the end of a session.
      Assert (not H.Decode ("", Ignored),
              "an empty line decoded as an entry");
      Assert (not H.Decode ("""unterminated", Ignored),
              "a truncated line decoded as an entry");
      Assert (not H.Decode ("{""not"": ""a string""}", Ignored),
              "a JSON object decoded as an entry");
      Assert (not H.Decode ("42", Ignored),
              "a JSON number decoded as an entry");
   end History_Encoding_Holds_Anything;

   -----------------------------------------
   -- Paths_Are_Under_One_Directory --
   -----------------------------------------

   procedure Paths_Are_Under_One_Directory
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      function Mentions (Text : String; Fragment : String) return Boolean;

      function Mentions (Text : String; Fragment : String) return Boolean is
      begin
         if Fragment'Length > Text'Length then
            return False;
         end if;

         for Start in Text'First .. Text'Last - Fragment'Length + 1 loop
            if Text (Start .. Start + Fragment'Length - 1) = Fragment then
               return True;
            end if;
         end loop;

         return False;
      end Mentions;

   begin
      --  Every store answers, or every store refuses. A host where one of the
      --  three had a directory and the others did not would leave files
      --  scattered, and this is the cheapest place to notice.
      for Kind in P.Store_Kind loop
         declare
            Where : constant String := P.Path_For (Kind, "sample.txt");
         begin
            if Where /= "" then
               Assert (Mentions (Where, "adash"),
                       P.Store_Kind'Image (Kind)
                       & " does not put its files under an adash directory: "
                       & Where);
               Assert (Mentions (Where, "sample.txt"),
                       P.Store_Kind'Image (Kind)
                       & " lost the file name: " & Where);
            end if;
         end;
      end loop;

      --  And the two files this phase adds do not collide, which they would if
      --  both were named for their store rather than for themselves.
      if P.Path_For (P.Data_Store, H.File_Name) /= "" then
         Assert (Mentions (H.Path, H.File_Name),
                 "the history path does not name the history file: " & H.Path);
      end if;
   end Paths_Are_Under_One_Directory;

   ----------
   -- Name --
   ----------

   procedure A_Session_Can_Keep_Its_Own_History
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Shared  : constant String := Adash.Persistence.History.Path;
      Private_File : constant String :=
        Adash.Persistence.History.Session_Path;

      Stored : Adash.Persistence.History.Log;
      Result : Adash.Persistence.Outcome;
   begin
      if Shared = "" then
         --  No data directory on this host, so there is no file to have one
         --  of. Skipped rather than failed: the capability is the host's.
         return;
      end if;

      --  A session's file is its own, not the shared one. Two shells writing
      --  the shared file a line at a time is the thing this exists to avoid,
      --  so the two paths differing is the whole property.
      Assert (Private_File /= Shared,
              "a session's history file was the shared one");

      --  Named after the process, so a second shell gets a different one.
      Assert (Private_File'Length > Shared'Length - 1,
              "a session path was not built from the data store");

      --  It behaves like any other history file: what is appended comes back.
      Adash.Persistence.History.Append
        ("private line;", Result, Into_File => Private_File);

      if Result = Adash.Persistence.Store_Unavailable then
         return;
      end if;

      Assert (Result = Adash.Persistence.Store_Ok,
              "a session history file could not be written");

      Adash.Persistence.History.Load
        (Stored, Result, From => Private_File);

      Assert (Result = Adash.Persistence.Store_Ok,
              "a session history file could not be read back");
      Assert (Adash.Persistence.History.Count (Stored) = 1,
              "a session history file did not hold what was written");
      Assert (Adash.Persistence.History.Entry_At (Stored, 1) = "private line;",
              "a session history entry came back changed");

      --  And it can be removed, which is what merging one into the shared file
      --  ends with. A session file that outlived its session would leave one
      --  per shell in the data store.
      declare
         Gone_File : Adash.Persistence.Outcome;
         Gone_Lock : Adash.Persistence.Outcome;
      begin
         Adash.Persistence.Remove (Private_File, Gone_File);
         Adash.Persistence.Remove (Private_File & ".lock", Gone_Lock);
      end;

      Adash.Persistence.History.Load (Stored, Result, From => Private_File);
      Assert (Result /= Adash.Persistence.Store_Ok
                or else Adash.Persistence.History.Count (Stored) = 0,
              "a removed session history file still had entries");
   end A_Session_Can_Keep_Its_Own_History;

   procedure An_Abandoned_Session_File_Is_Found
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      use type Hostkit.Locks.Lock_Outcome;

      Shared : constant String := Adash.Persistence.History.Path;
      Mine   : constant String := Adash.Persistence.History.Session_Path;

      Files  : Adash.Persistence.History.Path_List;
      Count  : Natural;
      Result : Adash.Persistence.Outcome;

      --  A file shaped like another session's, made by hand.
      Orphan : constant String :=
        (if Shared = "" then ""
         else Ada.Directories.Compose
                (Ada.Directories.Containing_Directory (Shared),
                 "history-999999999.jsonl"));

      Seen : Boolean := False;
   begin
      if Shared = "" or else Mine = Shared then
         --  No data directory, or a host that will not say which process this
         --  is. Skipped rather than failed: the capability is the host's.
         return;
      end if;

      Adash.Persistence.History.Append ("orphan line;", Result, Orphan);

      if Result /= Adash.Persistence.Store_Ok then
         return;
      end if;

      Adash.Persistence.History.Abandoned_Session_Files (Files, Count);

      for Index in 1 .. Count loop
         if Ada.Strings.Unbounded.To_String (Files (Index)) = Orphan then
            Seen := True;
         end if;

         --  Never this session's own file. A sweep that returned it would
         --  merge a running session's history and delete it underneath.
         Assert (Ada.Strings.Unbounded.To_String (Files (Index)) /= Mine,
                 "the sweep offered this session's own history file");
      end loop;

      Assert (Seen, "an abandoned session file was not found");

      --  A file nobody holds can be claimed, which is how the sweep decides it
      --  is abandoned. Held, it cannot be -- and that is the property that
      --  keeps a live session's history from being taken.
      declare
         Claim : Hostkit.Locks.Lock;
         Rival : Hostkit.Locks.Lock;

         First : constant Hostkit.Locks.Lock_Outcome :=
           Hostkit.Locks.Acquire
             (Adash.Persistence.History.Owner_Lock_Path (Orphan),
              Hostkit.Locks.Lock_Exclusive, Wait => False, Item => Claim);
      begin
         if First = Hostkit.Locks.Lock_Ok then
            Assert (Hostkit.Locks.Acquire
                      (Adash.Persistence.History.Owner_Lock_Path (Orphan),
                       Hostkit.Locks.Lock_Exclusive, Wait => False,
                       Item => Rival) /= Hostkit.Locks.Lock_Ok,
                    "a held ownership lock was handed out twice");
            Hostkit.Locks.Release (Claim);
         end if;
      end;

      declare
         Gone_File  : Adash.Persistence.Outcome;
         Gone_Lock  : Adash.Persistence.Outcome;
         Gone_Owner : Adash.Persistence.Outcome;
      begin
         Adash.Persistence.Remove (Orphan, Gone_File);
         Adash.Persistence.Remove (Orphan & ".lock", Gone_Lock);
         Adash.Persistence.Remove
           (Adash.Persistence.History.Owner_Lock_Path (Orphan), Gone_Owner);
      end;
   end An_Abandoned_Session_File_Is_Found;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Persistence");
   end Name;

   -------------------------------------------------
   -- A_Cache_Holds_Nothing_That_Cannot_Be_Rebuilt --
   -------------------------------------------------

   --  The promise the three stores exist to make, tested rather than assumed.
   --
   --  A cache directory is the one a system is entitled to empty without
   --  asking -- and some do, on a schedule, without telling anybody. What must
   --  follow is that emptying it costs a user nothing they would miss, and
   --  what makes that true is that nothing they would miss is in it: the
   --  history is under the data directory and the settings under the
   --  configuration one, and neither is under the cache.
   --
   --  Nothing in this build writes a cache yet. That is exactly why this is
   --  here: an unused mechanism is one nobody would notice going wrong, and
   --  the first thing to put a file there should find the guarantee already
   --  under test rather than have to establish it.
   procedure A_Cache_Holds_Nothing_That_Cannot_Be_Rebuilt
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      --  Whether one path is inside the directory another names.
      function Inside (Path : String; Directory : String) return Boolean;

      function Inside (Path : String; Directory : String) return Boolean is
      begin
         return Directory'Length > 0
           and then Path'Length > Directory'Length
           and then Path (Path'First .. Path'First + Directory'Length - 1)
                    = Directory;
      end Inside;

      Cached   : constant String := P.Path_For (P.Cache_Store, "sample.txt");
      Kept     : constant String := P.Path_For (P.Data_Store, "sample.txt");
      Settings : constant String :=
        P.Path_For (P.Configuration_Store, "sample.txt");

      --  The directory each of those files sits in.
      function Holding (Path : String) return String
      is (if Path = "" then ""
          else Ada.Directories.Containing_Directory (Path));
   begin
      if Cached = "" then
         --  A host with no cache directory. Refusing to say where one would be
         --  is an answer, and a caller that must not lose anything is no worse
         --  off for it.
         return;
      end if;

      Assert (Kept /= "" and then Settings /= "",
              "a host that has a cache directory has no data or configuration "
              & "one, so what cannot be rebuilt has nowhere else to go");

      --  Three distinct places. Two of them sharing would mean a system
      --  emptying the cache took the history with it, which is the whole
      --  failure this arrangement is against.
      Assert (Holding (Cached) /= Holding (Kept),
              "the cache and the data store are the same directory: "
              & Holding (Cached));
      Assert (Holding (Cached) /= Holding (Settings),
              "the cache and the configuration store are the same directory: "
              & Holding (Cached));

      --  And the two files that exist today are outside it by name, not by
      --  reasoning: the history is what a user would miss most.
      Assert (not Inside (H.Path, Holding (Cached)),
              "the history file is inside the cache directory: " & H.Path);
   end A_Cache_Holds_Nothing_That_Cannot_Be_Rebuilt;

   ------------------------------------------
   -- Forgetting_Takes_The_Last_Occurrence --
   ------------------------------------------

   procedure Forgetting_Takes_The_Last_Occurrence
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Room : constant String := Scratch;
      File : constant String := Hostkit.Fs.Join (Room, "history.jsonl");

      Written : P.Outcome;
      Result  : P.Outcome;

      Going : H.Log;
      Held  : H.Log;

      Taken : Natural;

      procedure Put (Line : String);

      --  Each write checked where it happens. A short file would make every
      --  assertion below one about a file that was never written.
      procedure Put (Line : String) is
      begin
         H.Append (Line, Written, File);
         Assert (Written = P.Store_Ok, "the file could not be written: " & Line);
      end Put;
   begin
      --  The same line twice, with other work between: a user who ran the same
      --  command in the morning and again this evening.
      Put ("pwd;");
      Put ("secret;");
      Put ("env;");
      Put ("secret;");

      H.Add (Going, "secret;");
      H.Forget (Going, Result, Taken, File);

      Assert (Result = P.Store_Ok,
              "forgetting reported " & P.Outcome'Image (Result));

      --  Nothing left to forget: this file held it.
      Assert (H.Count (Going) = 0,
              "an entry the file held was left to be forgotten");

      H.Load (Held, Result, From => File);

      Assert (H.Count (Held) = 3,
              "the file kept" & Natural'Image (H.Count (Held))
              & " entries rather than 3");

      --  The *last* occurrence, not the first: what the user has just typed is
      --  the most recent of however many times it was ever typed, and the
      --  older one is a different day's work they did not ask about.
      Assert (H.Entry_At (Held, 1) = "pwd;", "the first entry moved");
      Assert (H.Entry_At (Held, 2) = "secret;",
              "the older occurrence went instead of the newer");
      Assert (H.Entry_At (Held, 3) = "env;",
              "the entry after the forgotten one moved");

      Discard (Room);
   end Forgetting_Takes_The_Last_Occurrence;

   -------------------------------------------------
   -- Forgetting_Leaves_What_The_File_Did_Not_Hold --
   -------------------------------------------------

   procedure Forgetting_Leaves_What_The_File_Did_Not_Hold
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      Room : constant String := Scratch;
      File : constant String := Hostkit.Fs.Join (Room, "history.jsonl");
      Gone : constant String := Hostkit.Fs.Join (Room, "not-written.jsonl");

      Written : P.Outcome;
      Result  : P.Outcome;
      Taken   : Natural;

      Going : H.Log;
   begin
      H.Append ("here;", Written, File);
      Assert (Written = P.Store_Ok, "the file could not be written");

      H.Add (Going, "here;");
      H.Add (Going, "elsewhere;");

      H.Forget (Going, Result, Taken, File);

      --  What is left is exactly what this file did not have, which is how a
      --  session carries the rest to the shared file rather than guessing
      --  which of the two holds what.
      Assert (H.Count (Going) = 1,
              "forgetting left" & Natural'Image (H.Count (Going))
              & " entries rather than the 1 the file did not hold");
      Assert (H.Entry_At (Going, 1) = "elsewhere;",
              "the entry left over was " & H.Entry_At (Going, 1));

      --  A file that is not there leaves everything still to be forgotten. A
      --  caller told otherwise would report a secret gone from a file it never
      --  reached.
      H.Forget (Going, Result, Taken, Gone);

      Assert (Result = P.Store_Absent,
              "a missing file reported " & P.Outcome'Image (Result));
      Assert (H.Count (Going) = 1,
              "a missing file was treated as having forgotten something");

      Discard (Room);
   end Forgetting_Leaves_What_The_File_Did_Not_Hold;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, An_Abandoned_Session_File_Is_Found'Access,
         "an abandoned session history file is found and a held one is not");
      Register_Routine
        (T, A_Session_Can_Keep_Its_Own_History'Access,
         "a session can keep its history in a file of its own");
      Register_Routine (T, Absence_Is_Not_Failure'Access,
                        "a missing file is told apart from an unreadable one");
      Register_Routine (T, Writing_Then_Reading_Round_Trips'Access,
                        "a written file reads back, and leaves no staging file");
      Register_Routine (T, Writing_Creates_Its_Directory'Access,
                        "writing creates the directory a first run has not got");
      Register_Routine (T, Appending_Adds_Whole_Lines'Access,
                        "appending creates the file and adds whole lines");
      Register_Routine (T, Removing_Is_Idempotent'Access,
                        "removing a file that is not there is not a failure");
      Register_Routine (T, History_Encoding_Holds_Anything'Access,
                        "a history entry survives, newlines and all");
      Register_Routine (T, Paths_Are_Under_One_Directory'Access,
                        "every store puts its files under one adash directory");
      Register_Routine (T, A_Cache_Holds_Nothing_That_Cannot_Be_Rebuilt'Access,
                        "a cache holds nothing that cannot be rebuilt");
      Register_Routine (T, Forgetting_Takes_The_Last_Occurrence'Access,
                        "forgetting a line takes its last occurrence");
      Register_Routine (T, Forgetting_Leaves_What_The_File_Did_Not_Hold'Access,
                        "forgetting leaves what a file did not hold");
   end Register_Tests;

end Adash_Tests.Persistence_Cases;

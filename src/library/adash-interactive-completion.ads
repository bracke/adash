private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

with Adash.Messages;
with Adash.Source;
with Adash.Terminal;

--  What could be typed next.
--
--  A request says what the line is and where the cursor sits; the answer is a
--  list of candidates, each with the text to insert, the span it replaces, what
--  sort of thing it is, and a message identifier describing it. Nothing here is
--  rendered -- the frontend decides how a list looks, and a test can assert on
--  identities.
--
--  **Completion is deterministic.** The same line and cursor produce the same
--  candidates in the same order, every time. That is not a nicety: a list that
--  reorders itself between keystrokes moves the entry under the user's finger,
--  and a user who has learned that the third entry is the one they want is
--  entitled to keep being right.
--
--  Ordering is by source first and then by name, never by a score. A ranking
--  that depends on what was used recently is a ranking that cannot be tested
--  and that surprises the person who learned it.
--
--  **Completion never runs anything.** It reads registries and the filesystem;
--  it does not evaluate the line, because a line under construction is exactly
--  the input most likely to do something unintended. `rm x` half-typed must not
--  be run to find out what could follow it.
package Adash.Interactive.Completion is

   --  Where a candidate came from. Also the order they are offered in.
   type Source_Kind is
     (
      --  An internal command. First because the shell's own vocabulary is what
      --  a user is most often reaching for at the start of a line.
      From_Command,

      --  A predefined entity: a type name, a Boolean literal, an output
      --  procedure.
      From_Predefined,

      --  A reserved word of the language.
      From_Keyword,

      --  A program on the search path, for the argument that names one.
      --
      --  Offered only inside the string that says which program to run --
      --  `run ("gi` and the like -- because that is the only place a program
      --  name means anything. Elsewhere the shell's own vocabulary is what a
      --  user is reaching for, and a list of every executable on the machine
      --  would bury it.
      From_Program,

      --  A file or directory.
      From_Path,

      --  Something the caller worked out: what a user's own subprogram said
      --  when asked what may follow this program.
      From_Caller);

   --  What the user is completing.
   type Request is record
      --  The whole line, as typed so far.
      Line : Adash.Messages.Argument;

      --  Where the cursor is, as a byte offset from one. A cursor past the end
      --  of the line means completing at the end, which is the usual case.
      Cursor : Positive := 1;

      --  Where to look for programs, as the host writes a search path.
      --
      --  Passed in rather than read here, because the session's PATH is not
      --  this process's: `set ("PATH=...")` changes what a child is started
      --  with, and completion that read its own environment would offer the
      --  programs of a path the shell no longer uses. Empty means offer none,
      --  which is what a caller that has no session to ask gets.
      Search_Path : Adash.Messages.Argument;
   end record;

   --  One thing the user could mean.
   type Candidate is private;

   --  @param Item Candidate to inspect.
   --  @return The text to insert in place of Replaces.
   function Insertion (Item : Candidate) return String;

   --  @param Item Candidate to inspect.
   --  @return What to show in a list, which may differ from what is inserted.
   function Display (Item : Candidate) return String;

   --  @param Item Candidate to inspect.
   --  @return Where it came from.
   function Source (Item : Candidate) return Source_Kind;

   --  @param Item Candidate to inspect.
   --  @return The span of the line the insertion replaces.
   function Replaces (Item : Candidate) return Adash.Source.Span;

   --  What to say about a candidate, as a message identifier.
   --
   --  A description rather than a sentence: the frontend renders it, and a
   --  list that showed English from a registry would be one nobody could
   --  translate.
   --
   --  @param Item Candidate to inspect.
   --  @return Its description.
   function Description (Item : Candidate) return Adash.Messages.Message_Id;

   --  How the candidate should be shown.
   --
   --  The same role the line will use for it once inserted, so a list does not
   --  teach a user one colour and the line another.
   --
   --  @param Item Candidate to inspect.
   --  @return Its style role.
   function Role (Item : Candidate) return Adash.Terminal.Style_Role;

   --  An ordered list of candidates.
   type Candidate_List is tagged private;

   --  @param Item List to measure.
   --  @return How many candidates it holds.
   function Count (Item : Candidate_List) return Natural;

   --  @param Item List to read.
   --  @param Index Which candidate, from one.
   --  @return That candidate.
   function Element (Item : Candidate_List; Index : Positive) return Candidate;

   --  The longest text every candidate begins with.
   --
   --  What a shell inserts when a user asks to complete and there is more than
   --  one answer: as much as is certain, and no guess beyond it.
   --
   --  @param Item List to examine.
   --  @return The common prefix, or "" when there is none.
   function Common_Prefix (Item : Candidate_List) return String;

   --  Answer a completion request.
   --
   --  @param For_Request What the user has typed and where the cursor is.
   --  @return The candidates, in their documented order.
   function Complete (For_Request : Request) return Candidate_List;

   --  Build a request from a line and a cursor.
   --
   --  @param Line The line as typed.
   --  @param Cursor Byte offset of the cursor, from one.
   --  @param Search_Path Where to look for programs; "" to offer none.
   --  @return The request.
   function Make_Request
     (Line        : String;
      Cursor      : Positive;
      Search_Path : String := "") return Request;

   --  Which program's argument the cursor is in, and how much of it is typed.
   --
   --  For a caller that can offer more than this package can: the programs a
   --  machine has are a question about the filesystem, and what `git ` may be
   --  followed by is a question only the program -- or the person who wrote a
   --  subprogram saying so -- can answer. This says *whose* argument is being
   --  completed so that a caller can go and ask.
   --
   --  @param Line The line as typed.
   --  @param Cursor Byte offset of the cursor, from one.
   --  @param Word What has been typed of the argument so far.
   --  @return The program named by the call the cursor is inside, or "" when
   --          the cursor is not in an argument of one.
   function Program_Being_Argued
     (Line   : String;
      Cursor : Positive;
      Word   : out Adash.Messages.Argument) return String;

   --  Where the word under the cursor begins and ends.
   --
   --  A caller adding its own candidates needs the same span the built-in ones
   --  replace, or Tab would insert beside what the user typed rather than over
   --  it.
   --
   --  @param Line The line as typed.
   --  @param Cursor Byte offset of the cursor, from one.
   --  @param First Where the word starts; zero when there is none.
   --  @param Last Where it ends.
   procedure Word_Bounds
     (Line   : String;
      Cursor : Positive;
      First  : out Natural;
      Last   : out Natural);

   --  Add a candidate a caller worked out for itself.
   --
   --  @param Item The list to add to.
   --  @param Insertion What Tab should insert.
   --  @param Replaces What it replaces, which is the word already typed.
   procedure Offer_From_Caller
     (Item      : in out Candidate_List;
      Insertion : String;
      Replaces  : Adash.Source.Span);

private

   type Candidate is record
      Insertion   : Ada.Strings.Unbounded.Unbounded_String;
      Display     : Ada.Strings.Unbounded.Unbounded_String;
      Source      : Source_Kind := From_Command;
      Replaces    : Adash.Source.Span := Adash.Source.Nowhere;
      Description : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Role        : Adash.Terminal.Style_Role := Adash.Terminal.Role_Plain;
   end record;

   package Candidate_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Candidate);

   type Candidate_List is tagged record
      Items : Candidate_Vectors.Vector;
   end record;

end Adash.Interactive.Completion;

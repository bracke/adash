with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Adash.Messages;

--  Checks that the repository still obeys its own rules.
--
--  These are the invariants from AI.md and ARCHITECTURE.md expressed as code,
--  because an invariant that only exists in prose is one that has already
--  been broken somewhere. Each check answers a question a reviewer would
--  otherwise have to ask by hand and would eventually stop asking: is every
--  message identifier backed by a catalog entry; does any source write a
--  terminal escape of its own; does any source reach past hostkit to the
--  operating system; does the package inventory still describe the packages
--  that exist.
--
--  Findings are structured rather than printed. A check reports a catalog key
--  and its arguments and stops there, exactly as the shell's own subsystems
--  do -- which is what lets adash_check render them for a terminal and
--  Adash_Tests.Repository_Cases assert on them without either one parsing the
--  other's output.
--
--  Nothing here raises for a failed check. A failed check is the expected
--  result of running a checker, not a programming error; exceptions are left
--  for the checker itself being broken -- an unreadable root, say.
package Adash_Tests.Repository is

   --  Largest number of arguments a finding's message can take.
   Max_Finding_Arguments : constant := 4;

   subtype Finding_Arguments is
     Adash.Messages.Argument_List (1 .. Max_Finding_Arguments);

   --  One thing found wrong.
   --
   --  Key is a catalog key rather than a sentence, so that the same finding
   --  can be rendered for a terminal, a report or a test assertion.
   type Finding is record
      Key            : Ada.Strings.Unbounded.Unbounded_String;
      Argument_Count : Natural range 0 .. Max_Finding_Arguments := 0;
      Arguments      : Finding_Arguments;
   end record;

   package Finding_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Finding);

   --  What a run of the checks found.
   type Report is tagged limited record
      Checks_Run : Natural := 0;
      Findings   : Finding_Vectors.Vector;
   end record;

   --  Run every check against a repository root.
   --
   --  @param Root Path of the repository root -- the directory holding
   --         alire.toml. Relative paths are resolved against the current
   --         working directory.
   --  @param Into Report to accumulate into. Not cleared first, so several
   --         roots can be checked into one report.
   procedure Check (Root : String; Into : in out Report);

   --  Whether a report found nothing wrong.
   --
   --  @param Item Report to inspect.
   --  @return True when no finding was recorded.
   function Passed (Item : Report) return Boolean;

   --  How many findings a report holds.
   --
   --  @param Item Report to inspect.
   --  @return Finding count.
   function Failure_Count (Item : Report) return Natural;

   --  The catalog key of a finding.
   --
   --  @param Item Finding to inspect.
   --  @return Catalog key.
   function Key (Item : Finding) return String;

   --  The arguments of a finding, as a slice ready for rendering.
   --
   --  @param Item Finding to inspect.
   --  @return Argument list of length Item.Argument_Count.
   function Arguments (Item : Finding) return Adash.Messages.Argument_List;

   ---------------------------------------------------------------------------
   --  The individual checks.
   --
   --  Exposed so a test can run one in isolation and say which invariant it
   --  is asserting. Check runs all of them, in this order.
   ---------------------------------------------------------------------------

   --  Every file ARCHITECTURE.md and the layout require is present.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_Required_Files (Root : String; Into : in out Report);

   --  Every directory the layout requires is present.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_Required_Directories (Root : String; Into : in out Report);

   --  alire.toml and repository.toml agree about the version.
   --
   --  Two files record it because they answer different questions -- one is
   --  the build's, one is the repository's inventory -- and a release that
   --  ships them disagreeing is a release nobody can identify afterwards.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_Version_Consistency (Root : String; Into : in out Report);

   --  Every spec repository.toml lists exists, and every spec that exists is
   --  listed.
   --
   --  The second direction is the one that matters: a package added without
   --  an inventory entry is a package with no recorded owner, and ownership
   --  is what the architecture is made of.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_Package_Inventory (Root : String; Into : in out Report);

   --  Every Adash.Messages.Message_Id has a catalog entry in the default
   --  locale.
   --
   --  The compiler already enforces the other direction, that every
   --  identifier has a key; nothing but this enforces that the key resolves.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_Message_Catalog (Root : String; Into : in out Report);

   --  No Adash source writes a terminal escape sequence of its own.
   --
   --  Styling belongs to terminal_styles, reached through Adash.Terminal. An
   --  escape written by hand is invisible to the colour policy, so it appears
   --  in a pipe, in a log and in a test comparing bytes.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   procedure Check_No_Terminal_Escapes (Root : String; Into : in out Report);

   --  No Adash source reaches past hostkit to the operating system.
   --
   --  Platform behaviour has one provider. A GNAT.OS_Lib or Interfaces.C
   --  appearing in src is the beginning of a second one.
   --
   --  @param Root Repository root.
   --  @param Into Report to accumulate into.
   --  No sentence is written in Ada source.
   --
   --  Every user-visible string belongs to the catalog, and four subsystems
   --  had been quietly writing English of their own: the machine, the parser,
   --  the lowering and the settings.
   --
   --  @param Root Repository root.
   --  @param Into Report to add to.
   procedure Check_No_Prose_As_Text (Root : String; Into : in out Report);

   procedure Check_No_Forbidden_Units (Root : String; Into : in out Report);

   --  The grammar reference names every syntax node, and no others.
   --
   --  A grammar written beside a parser drifts the day the parser changes.
   --  This holds `docs/grammar-reference.md` to `Adash.Language.Syntax`'s own
   --  enumeration in both directions: a construct the parser can build with no
   --  production is what the check exists for, and a production for a node
   --  that no longer exists is the other half.
   --
   --  @param Root Repository root.
   --  @param Into Report to add to.
   procedure Check_Grammar_Covers_The_Syntax
     (Root : String; Into : in out Report);

end Adash_Tests.Repository;

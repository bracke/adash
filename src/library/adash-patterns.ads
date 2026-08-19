--  Matching a name against a pattern, and telling a pattern from a name.
--
--  A leaf: no state, no host, nothing above it. It is here rather than inside
--  the machine because two callers want the same answer -- `Matches` in the
--  language, and the expansion that turns `*.log` into the files a program is
--  given -- and two copies of a matcher are two matchers that will one day
--  disagree about `[a-`.
with Ada.Containers.Indefinite_Vectors;

package Adash.Patterns is

   --  Does this whole string match this pattern?
   --
   --  `*` stands for any run of characters including none, `?` for exactly
   --  one, and `[abc]`, `[a-z]`, `[!abc]` for one out of a class. An unclosed
   --  `[` is an ordinary character, which is what somebody who typed one and
   --  meant one gets rather than a pattern that silently matches nothing.
   --
   --  Anchored at both ends: the pattern describes the whole string, not a
   --  part of it. `Index` is how a script asks about a part.
   --
   --  @param Whole The string to test.
   --  @param Pattern The pattern.
   --  @return Whether the pattern describes the whole string.
   function Matches (Whole : String; Pattern : String) return Boolean;

   --  Is there anything in this text for the matcher to do?
   --
   --  What separates an argument that is a pattern from one that is a name:
   --  `run_matching` expands the first and passes the second along untouched,
   --  and a user reads the difference off the argument rather than out of a
   --  manual.
   --
   --  @param Text The text.
   --  @return Whether it holds `*`, `?` or `[`.
   function Holds_A_Pattern (Text : String) return Boolean;

   --  Is there a brace group in this text for the expansion to work on?
   --
   --  What separates `{lib,test}` from a name with a brace in it. Answered
   --  before the expansion runs, so that a caller can pass text along
   --  untouched rather than expanding it into one copy of itself.
   --
   --  @param Text The text.
   --  @return Whether it holds a group this package would expand.
   function Holds_A_Brace_Group (Text : String) return Boolean;

   package Text_Lists is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   --  How many strings one text may expand into.
   --
   --  A bound rather than a promise. `{a,b}{a,b}{a,b}...` multiplies, so a
   --  short line can name more strings than a machine has memory for -- and
   --  the multiplying is the point of the feature, not a misuse of it.
   Maximum_Expansions : constant := 4_096;

   --  What a text with brace groups in it stands for.
   --
   --  `{lib,test}` is two strings, `a{1,2}b` is `a1b` and `a2b`, and two
   --  groups multiply: `{a,b}{1,2}` is four. `{1..4}` counts, and so does
   --  `{a..d}`. Groups nest.
   --
   --  This touches no filesystem and refuses nothing for not existing: braces
   --  say what strings to make, and whether anything is called that is a
   --  separate question, asked afterwards by whatever wanted the names.
   --
   --  A group that is not closed, or holds neither a comma nor a range, is
   --  ordinary text -- `{a}` stays `{a}`, which is what somebody who typed one
   --  and meant one gets. Text with no group at all expands to itself, so a
   --  caller never has to ask first.
   --
   --  In the order they are written, left to right, with the leftmost group
   --  varying slowest -- the order every other shell produces and the order a
   --  reader expects when they see the result.
   --
   --  @param Text The text to expand.
   --  @param Into The strings it stands for, in order.
   --  @param Refused True when it would make more than Maximum_Expansions, in
   --         which case Into is empty: a caller that ran a program over the
   --         first four thousand of five would do half a job and report that
   --         it had done it.
   procedure Expand
     (Text    : String;
      Into    : out Text_Lists.Vector;
      Refused : out Boolean);

end Adash.Patterns;

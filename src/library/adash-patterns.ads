--  Matching a name against a pattern, and telling a pattern from a name.
--
--  A leaf: no state, no host, nothing above it. It is here rather than inside
--  the machine because two callers want the same answer -- `Matches` in the
--  language, and the expansion that turns `*.log` into the files a program is
--  given -- and two copies of a matcher are two matchers that will one day
--  disagree about `[a-`.
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

end Adash.Patterns;

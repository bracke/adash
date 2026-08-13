with Hostkit;

--  The environment a child is given.
--
--  A shell's environment is not the process's own. A user sets a variable for
--  one command, or a script exports one for everything it runs, and neither may
--  change the shell's own environment behind its back -- so the child's
--  environment is built as a value and handed over, rather than assembled by
--  mutating this process and hoping to put it back.
--
--  Building it as a value also gets PATH right. A command run with a modified
--  PATH has to be *looked up* with that PATH, which is what a user who set it
--  meant; hostkit's spawn uses the environment it is given for the lookup, so
--  the two cannot disagree.
package Adash.Execution.Environment is

   --  A set of variables to give a child.
   type Block is private;

   --  The shell's own environment, as a starting point.
   --
   --  A snapshot. Later changes to this process's environment do not show up in
   --  a Block already taken, which is what makes it safe to build one, hold it,
   --  and use it for several children.
   --
   --  @return The current environment.
   function Inherited return Block;

   --  An empty environment.
   --
   --  For a command that should see nothing at all. Rare, and worth being able
   --  to say: a child given the empty environment gets no PATH either, which is
   --  the caller's problem to solve deliberately rather than a surprise.
   --
   --  @return An environment with no variables.
   function Empty return Block;

   --  Set a variable, replacing any existing one of that name.
   --
   --  @param Item Environment to change.
   --  @param Name Variable name. An empty name is ignored: there is no such
   --         variable, and inventing one would produce an entry no host can
   --         parse.
   --  @param Value Its value.
   procedure Set (Item : in out Block; Name : String; Value : String);

   --  Remove a variable.
   --
   --  @param Item Environment to change.
   --  @param Name Variable to remove; absent is not an error.
   procedure Unset (Item : in out Block; Name : String);

   --  Whether a variable is present.
   --
   --  @param Item Environment to inspect.
   --  @param Name Variable to look for.
   --  @return True when it is set.
   function Contains (Item : Block; Name : String) return Boolean;

   --  A variable's value.
   --
   --  @param Item Environment to inspect.
   --  @param Name Variable to read.
   --  @return Its value, or "" when it is not set. A caller that has to tell
   --          "unset" from "set to nothing" asks Contains first -- the
   --          difference matters to some programs.
   function Value (Item : Block; Name : String) return String;

   --  How many variables the block holds.
   --
   --  @param Item Environment to inspect.
   --  @return Variable count.
   function Length (Item : Block) return Natural;

   --  The block in the form hostkit's spawn takes: one "NAME=VALUE" per
   --  element.
   --
   --  Deterministic order -- variables come out sorted by name, whatever order
   --  they were set in. The host does not care, but a test comparing two
   --  environments does, and so does anything that hashes one.
   --
   --  @param Item Environment to render.
   --  @return The vector to hand to Hostkit.Spawn.
   function To_Vector (Item : Block) return Hostkit.String_Vectors.Vector;

private

   type Block is record
      --  Kept as "NAME=VALUE" strings, sorted by name, rather than as a map.
      --  The set is small, it has to come out in this shape anyway, and a map
      --  would need an ordering imposed on the way out regardless.
      Entries : Hostkit.String_Vectors.Vector;
   end record;

end Adash.Execution.Environment;

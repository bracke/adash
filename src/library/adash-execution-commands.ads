with Ada.Strings.Unbounded;

with Hostkit;

with Adash.Execution.Environment;
with Adash.Execution.Streams;

--  What it takes to run one command.
--
--  An Invocation is a value: everything a command needs, decided before
--  anything irreversible happens. That ordering is the point. Validating a
--  redirection, resolving a program and checking a working directory all have
--  to happen before a fork, because after one there is no way to report a
--  failure except an exit status -- and an exit status cannot say which of the
--  four things went wrong.
--
--  Arguments are a vector and never a command line. A filename containing a
--  space, a quote, a newline or a semicolon is just a filename, and it stays
--  one all the way to the host. Anything that builds a string and asks a shell
--  to split it again has re-introduced the injection this avoids.
package Adash.Execution.Commands is

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   --  One command, ready to run.
   type Invocation is record

      --  The program: a path, or a name to look up. Resolution policy is
      --  Adash.Execution.External's.
      Program : UString;

      --  Its arguments, not including the program name.
      Arguments : Hostkit.String_Vectors.Vector;

      --  The environment it is given.
      Environment : Adash.Execution.Environment.Block :=
        Adash.Execution.Environment.Empty;

      --  Where to run it; the shell's own directory when empty.
      Working_Directory : UString;

      --  Where its three streams go. Default to the shell's own, which is what
      --  an ordinary foreground command wants.
      Input        : Adash.Execution.Streams.Endpoint :=
        Adash.Execution.Streams.Inherited (Adash.Execution.Streams.Role_Input);
      Output       : Adash.Execution.Streams.Endpoint :=
        Adash.Execution.Streams.Inherited (Adash.Execution.Streams.Role_Output);
      Error_Output : Adash.Execution.Streams.Endpoint :=
        Adash.Execution.Streams.Inherited (Adash.Execution.Streams.Role_Error);

      --  True when the shell should not wait for it.
      Background : Boolean := False;
   end record;

   --  Build an invocation with the shell's own environment and streams.
   --
   --  @param Program The program to run.
   --  @param Arguments Its arguments.
   --  @return An invocation ready to be adjusted and run.
   function Make
     (Program   : String;
      Arguments : Hostkit.String_Vectors.Vector) return Invocation;

   --  Add one argument.
   --
   --  @param Item Invocation to change.
   --  @param Value The argument, taken literally.
   procedure Append_Argument (Item : in out Invocation; Value : String);

   --  The program name as a String.
   --
   --  @param Item Invocation to inspect.
   --  @return Its program.
   function Program (Item : Invocation) return String;

   --  Release every stream endpoint this invocation owns.
   --
   --  Called once the child has been started, and on every path that abandons
   --  the invocation without starting one. Until it happens the shell is
   --  holding a copy of each pipe end, and a pipe with a live write end never
   --  reports end-of-file.
   --
   --  @param Item Invocation to release.
   procedure Release (Item : in out Invocation);

end Adash.Execution.Commands;

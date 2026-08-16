with Ada.Strings.Unbounded;

with Adash.Errors;
with Adash.Execution.Commands;
with Adash.Execution.Streams;

--  Sending a command's streams somewhere other than the shell's own.
--
--  Planned first, applied second, and the order is not a style choice. Applying
--  a redirection opens files and truncates them; validating afterwards would
--  mean a command that was rejected had already destroyed something. So a Plan
--  is built and checked while nothing has happened yet, and only then applied.
--
--  Two redirections targeting the same stream are a conflict, not a
--  last-one-wins. A shell that quietly picks one has made a choice the user did
--  not make, and the file that lost is silently not written -- which they find
--  out later, from its absence. This reports Error_Redirection_Conflict and
--  runs nothing.
package Adash.Execution.Redirection is

   --  What a redirection does to a stream.
   type Redirection_Kind is
     (
      --  Read from a file. It must exist.
      Redirect_From_File,

      --  Write to a file, replacing it.
      Redirect_To_File,

      --  Write to the end of a file, creating it if absent. Append is a
      --  property of the open file rather than a seek the shell performs, so
      --  two commands appending to one log do not overwrite each other.
      Redirect_Append_File,

      --  Write to a file, refusing if it already exists. What a user asks for
      --  when they do not want to clobber anything.
      Redirect_To_New_File,

      --  Send this stream wherever the output stream is going, through the
      --  same open file rather than a second one.
      --
      --  What `2>&1` means everywhere, and the only way to get a log in which
      --  what a program said and what it complained about are in the order it
      --  wrote them: two opens of one path would be two file positions, each
      --  writing over the other's lines or -- appending -- interleaved by
      --  block rather than by line.
      --
      --  Carries no path of its own: where output is going is decided by the
      --  redirection that says so, and this one follows it. Which is why a
      --  plan with this in it and no output redirection is refused: it would
      --  mean joining a stream to the shell's own, and a caller that wanted
      --  that already has it.
      Redirect_Join_Output);

   --  One redirection, as asked for.
   type Redirection is record
      Role : Adash.Execution.Streams.Stream_Role :=
        Adash.Execution.Streams.Role_Output;
      Kind : Redirection_Kind := Redirect_To_File;
      Path : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Largest number of redirections one command may carry: one per stream,
   --  since more than one on the same stream is a conflict rather than a
   --  sequence.
   Max_Redirections : constant := 3;

   --  A checked set of redirections, ready to apply.
   type Plan is private;

   --  An empty plan.
   Nothing : constant Plan;

   --  Add a redirection to a plan, checking it against what is already there.
   --
   --  Nothing is opened. This is the phase in which a mistake is still free.
   --
   --  @param Item Plan to extend.
   --  @param Entry_To_Add The redirection.
   --  @param Error Why it was rejected, when this returns False.
   --  @return True when the redirection was accepted.
   function Add
     (Item         : in out Plan;
      Entry_To_Add : Redirection;
      Error        : out Adash.Errors.Error_Info) return Boolean;

   --  How many redirections a plan holds.
   --
   --  @param Item Plan to inspect.
   --  @return Redirection count.
   function Length (Item : Plan) return Natural;

   --  Open what the plan describes and attach it to an invocation.
   --
   --  All-or-nothing. If any file fails to open, every file this call had
   --  already opened is closed again before it returns, and the invocation is
   --  left as it was -- so a command that will not run has not half-created its
   --  output files.
   --
   --  @param Item The plan to apply.
   --  @param Target The invocation to attach the streams to.
   --  @param Error Why it could not be applied, when this returns False.
   --  @return True when every redirection was applied.
   function Apply
     (Item   : Plan;
      Target : in out Adash.Execution.Commands.Invocation;
      Error  : out Adash.Errors.Error_Info) return Boolean;

private

   type Redirection_Array is array (1 .. Max_Redirections) of Redirection;

   type Plan is record
      Count   : Natural range 0 .. Max_Redirections := 0;
      Entries : Redirection_Array;
   end record;

   Nothing : constant Plan := (Count => 0, Entries => [others => <>]);

end Adash.Execution.Redirection;

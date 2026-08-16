with Hostkit.Descriptors;

--  Where a command's input comes from and its output goes.
--
--  The type here exists for one reason, and it is the reason pipelines break:
--  whoever creates a descriptor must close it, and *when* they close it decides
--  whether the pipeline terminates. A pipe reports end-of-file only when every
--  copy of its write end is closed. The shell holds one of those copies after
--  handing it to a child, and if it does not let go, the reader at the far end
--  waits for a program that exited long ago. The symptom is a hang, under load,
--  with nothing in the code to point at.
--
--  So an Endpoint carries not only the descriptor but whether the shell owns
--  it. An inherited stream is not owned -- closing the shell's own standard
--  output would be a disaster -- and a pipe end or an opened file is. Release
--  closes exactly the owned ones, and is called once every child that needed
--  them has been started.
package Adash.Execution.Streams is

   --  Which of a command's three streams is meant.
   type Stream_Role is (Role_Input, Role_Output, Role_Error);

   --  A stable name for a role, for a diagnostic that has to say which stream
   --  went wrong. An identifier, not text for a user.
   --
   --  @param Item Role to name.
   --  @return Its name, for example "OUTPUT".
   function Name (Item : Stream_Role) return String;

   --  One end of a command's connection to the world.
   type Endpoint is private;

   --  The shell's own stream: what an ordinary foreground command gets.
   --
   --  Not owned, and Release will not close it. A shell that closed its own
   --  standard input has no way to get it back.
   --
   --  @param Role Which stream to inherit.
   --  @return An endpoint naming the shell's own.
   function Inherited (Role : Stream_Role) return Endpoint;

   --  A descriptor the shell made and must close once the child has it.
   --
   --  @param Handle The descriptor.
   --  @return An owned endpoint.
   function Owned (Handle : Hostkit.Descriptors.Descriptor) return Endpoint;

   --  What a background job's input should be, given what it was told.
   --
   --  A job started into the background cannot be handed the terminal the way
   --  a foreground one is: there is no "while it runs" for the shell to wait
   --  through, since the shell carries on. On POSIX the host settles what
   --  follows by stopping a background program that reads the terminal, and
   --  nothing here takes that decision away from it.
   --
   --  Where the shell is watching its own terminal for Ctrl-C, though, it is
   --  holding that terminal raw and reading it between instructions -- and a
   --  background program given the same terminal would race the shell for
   --  keystrokes and read them in a mode nobody chose for it. So it is given
   --  the device that reads as nothing instead, and sees end of input rather
   --  than a stream that will never answer.
   --
   --  A job whose input was redirected keeps what it was given: the user said
   --  where its input comes from, and that is not this function's business.
   --
   --  @param Given What the invocation carries now.
   --  @return What to run it with. Given itself, wherever the rule above does
   --          not apply -- including a host with no such device, where the
   --          terminal is still a worse answer than nothing at all but the
   --          only one there is.
   function Background_Input (Given : Endpoint) return Endpoint;

   --  A descriptor somebody else owns, to be handed over but not closed.
   --
   --  For the stage of a pipeline that passes a pipe end on to the next stage:
   --  exactly one holder closes it, and it is the one that made it.
   --
   --  @param Handle The descriptor.
   --  @return A borrowed endpoint.
   function Borrowed (Handle : Hostkit.Descriptors.Descriptor) return Endpoint;

   --  @param Item Endpoint to inspect.
   --  @return Its descriptor.
   function Handle (Item : Endpoint) return Hostkit.Descriptors.Descriptor;

   --  @param Item Endpoint to inspect.
   --  @return True when Release will close it.
   function Is_Owned (Item : Endpoint) return Boolean;

   --  Make this endpoint's descriptor inheritable, so a child receives it.
   --
   --  Every descriptor this crate hands out is created non-inheritable, and
   --  opening that door is per child and deliberate. An inherited endpoint
   --  needs nothing done and reports success.
   --
   --  @param Item Endpoint to prepare.
   --  @return True when the child will receive it.
   function Prepare_For_Child (Item : Endpoint) return Boolean;

   --  Close this endpoint if the shell owns it, and forget it either way.
   --
   --  Called once the child that needed it has been started. Idempotent, so the
   --  error path that releases twice is harmless.
   --
   --  @param Item Endpoint to release.
   procedure Release (Item : in out Endpoint);

   --  Read one line from the shell's own standard input.
   --
   --  What a script needs to read what it was piped, and what a program needs
   --  to ask the user something. Until this the shell could write its output
   --  and run other programs and could not read a byte of its own input.
   --
   --  The terminator is not part of the line, and a last line without one is
   --  still a line. A read that finds nothing more says so through Ended
   --  rather than by answering with an empty string, which is a line a file
   --  may genuinely contain.
   --
   --  There is one standard input, so the bytes read ahead of a line boundary
   --  are held here between calls. A caller that wants them back has asked the
   --  wrong question: they belong to the next line.
   --
   --  @param Ended True when there is no more input, in which case the result
   --         is empty.
   --  @return The line, without its terminator.
   function Read_Line (Ended : out Boolean) return String;

   --  Take everything read and not yet handed out.
   --
   --  For a frontend that reads standard input itself. There is one standard
   --  input and one buffer over it: an interactive editor that kept its own
   --  would hold the bytes a program is about to ask for, and the program
   --  would read nothing while the user's answer sat in the editor.
   --
   --  @return The held bytes, which are no longer held.
   function Take_Held return String;

   --  Give bytes back to the buffer, ahead of anything already in it.
   --
   --  @param Bytes What was read and not used.
   procedure Put_Back (Bytes : String);

private

   type Endpoint is record
      Handle : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;
      Owned  : Boolean := False;
   end record;

end Adash.Execution.Streams;

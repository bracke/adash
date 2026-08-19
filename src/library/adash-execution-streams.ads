with Hostkit.Descriptors;

with Adash.Filesystem;

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

   --  Say that this program's output has stopped taking anything.
   --
   --  The machine catches a failed write and reports it, which is right: a
   --  script whose `put_line` fails is a script that failed, and it should
   --  hear about it rather than die. But that leaves the process ending
   --  *normally* -- and ending normally runs finalization, and finalization
   --  closes the standard files, which flushes them, which fails again, which
   --  is `PROGRAM_ERROR` inside a finalizer and a stack trace on the way out.
   --
   --  So whoever catches the failure says so here, and whoever ends the
   --  program asks before it returns.
   procedure Note_Output_Gone;

   --  Whether a write to this program's output has failed.
   --
   --  @return True once Note_Output_Gone has been called.
   function Output_Is_Gone return Boolean;

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
   --  **A line longer than Limit arrives in pieces.** Input that never sends a
   --  terminator -- a program producing a stream, a file with no newline in it
   --  at all -- would otherwise grow this buffer until the host ended the
   --  session, which is the one outcome a shell must not have. Refusing was
   --  the alternative and it is worse here than for a file: a file can be
   --  asked about again, and input that has been read and dropped is gone. So
   --  what has accumulated is handed over as a line and reading goes on,
   --  which loses nothing and bounds what is held.
   --
   --  @param Ended True when there is no more input, in which case the result
   --         is empty.
   --  @param Limit The most to hold before handing over what there is.
   --         `read.limit` is where a user says, in mebibytes.
   --  @return The line, without its terminator.
   function Read_Line
     (Ended : out Boolean;
      Limit : Positive := Adash.Filesystem.Default_Limit) return String;

   --  A line, or nothing after this long.
   --
   --  What a script needs to ask a question it can carry on without: a prompt
   --  with a default, a wait for something a user may not be there to type.
   --
   --  Timed_Out and Ended are two different answers and neither is an empty
   --  line: input can genuinely hold one, so a caller that read "" would not
   --  know which of the three had happened. All three come back separately.
   --
   --  The wait is per read rather than for the whole call. A line arriving one
   --  character at a time from something slow is a line that is arriving, and
   --  giving up in the middle of it would leave the rest for whoever reads
   --  next -- which is the shell, and the characters would be a command.
   --
   --  @param Seconds How long to wait for something to arrive. Zero looks and
   --         does not wait.
   --  @param Ended True at end of input.
   --  @param Timed_Out True when nothing arrived in time.
   --  @param Limit The longest line to hand over whole.
   --  @return The line, without its terminator.
   function Read_Line_Within
     (Seconds   : Duration;
      Ended     : out Boolean;
      Timed_Out : out Boolean;
      Limit     : Positive := Adash.Filesystem.Default_Limit) return String;

   --  One character, as it is typed.
   --
   --  What a menu needs: a keypress rather than a line, so a user answering
   --  `y` does not also have to press return. The terminal is put in raw mode
   --  for the read and put back afterwards, which is what makes the character
   --  arrive at all -- a terminal in its usual mode hands over a line at a
   --  time and would wait for the return this exists to avoid.
   --
   --  Reading a pipe or a file it is simply the next byte.
   --
   --  @param Ended True at end of input.
   --  @return The character, or "" at end of input.
   function Read_Key (Ended : out Boolean) return String;

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

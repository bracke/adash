with Hostkit.Descriptors;

with Adash.Errors;

--  What the shell itself does about signals.
--
--  A shell has to refuse several signals that would kill any other program, and
--  each refusal has a specific failure behind it:
--
--  SIGPIPE. Writing to a pipe whose reader has gone kills the writer by
--  default. For most programs that is a convenience; for a shell it is fatal,
--  because `something | head -1` makes it happen on purpose. Without this the
--  shell dies the first time a user truncates a pipeline -- not the shell's
--  child, the shell. This is the one that matters most and the one with no
--  workaround anywhere else in the system.
--
--  SIGINT and SIGQUIT. The terminal sends these to the foreground process
--  group. With job control the foreground group is the *job*, not the shell, so
--  the shell would not receive them anyway -- but a shell without job control,
--  or between jobs, is the foreground group itself, and Ctrl-C would end the
--  session. It ignores them and lets the job receive its own.
--
--  SIGTSTP. Same argument: Ctrl-Z should suspend the job, not the shell. A
--  suspended shell with no parent shell to resume it is a lost terminal.
--
--  SIGTTIN and SIGTTOU. A background process reading from or writing to the
--  terminal is stopped by default. The shell does both routinely, and SIGTTOU
--  in particular is raised by the very call that hands the terminal back to the
--  shell after a job finishes -- so without ignoring it, reclaiming the
--  terminal stops the shell. That symptom, the shell freezing when a job ends,
--  looks nothing like its cause.
--
--  What this deliberately does not do is catch anything. hostkit offers only
--  "default" and "ignore", and that is enough: with job control the signals a
--  user sends reach the job, and the shell learns what happened from the job's
--  wait status rather than from a handler. Cancelling the shell's own work is
--  Adash.Execution.Cancellation's job, driven by whoever decides -- not by a
--  signal handler reaching into shared state.
--
--  Children are unaffected. Hostkit.Spawn restores the host defaults between
--  the fork and the exec, so a child does not inherit an ignored SIGINT and
--  become a foreground program that cannot be interrupted.
package Adash.Execution.Signals is

   --  Take on the shell's signal policy.
   --
   --  Idempotent. Safe to call at startup and again after anything that may
   --  have changed a disposition.
   --
   --  On a host with no signals this succeeds and does nothing: there is
   --  nothing to refuse, and reporting a failure would make every startup on
   --  that host look broken. Is_Installed reports what actually happened.
   --
   --  @return Success, or the failure that stopped it.
   function Install return Adash.Errors.Error_Info;

   --  Put the host defaults back.
   --
   --  For a shell about to replace itself with another program, and for a test
   --  that must not leave the policy behind for whatever runs next.
   --
   --  @return Success, or the failure that stopped it.
   function Restore return Adash.Errors.Error_Info;

   --  Whether the policy is currently in force.
   --
   --  False on a host without signals, where Install succeeds but changes
   --  nothing -- so a caller can tell "installed" from "not needed here".
   --
   --  @return True when the shell's dispositions are in place.
   function Is_Installed return Boolean;

   --  Whether the shell takes responsibility for a signal.
   --
   --  Exposed so a test can assert the list rather than restate it, and so a
   --  consumer that needs to reason about one signal does not have to read this
   --  package's body.
   --
   --  @param Item Signal to ask about.
   --  @return True when Install makes the shell ignore it.
   function Is_Refused_By_Shell (Item : Adash.Execution.Signal) return Boolean;

   --  Whether an interrupt has arrived since it was last acknowledged.
   --
   --  The shell records interrupts rather than discarding them: Ctrl-C while a
   --  program is running means "stop that", and a shell that threw the signal
   --  away could not tell. What to do about it is the frontend's decision, so
   --  this only reports.
   --
   --  False on a host where the disposition could not be installed -- Windows
   --  has no POSIX signals -- which is the honest answer rather than a flag
   --  nothing ever sets.
   --
   --  @return True when at least one interrupt is outstanding.
   function Interrupt_Pending return Boolean;

   --  Acknowledge every outstanding interrupt.
   --
   --  Called once whatever it meant has been dealt with. A caller that forgets
   --  leaves the next thing it runs looking already-interrupted.
   procedure Acknowledge_Interrupt;

   --  Watch the terminal for the interrupt key, on a host that will not say.
   --
   --  For the one host where Hostkit.Terminal_Control says an interrupt does
   --  not reach a busy program. There the shell is never told that Ctrl-C was
   --  typed while a submission runs, so a runaway loop cannot be stopped by
   --  anybody -- but the keystroke itself still arrives at a terminal left
   --  raw, as the byte three, which a probe measured on all three hosts.
   --
   --  So the shell looks. Watch_Terminal says which descriptor to look at, and
   --  Look_For_An_Interrupt is the looking: called between instructions, it
   --  reads whatever is there without waiting, records an interrupt if the
   --  interrupt key is among it, and puts the rest back where a reader will
   --  find it. Bytes typed ahead during a long loop are still typed ahead.
   --
   --  Deliberately not automatic. Looking means reading the terminal, and a
   --  shell that read the terminal while a foreground program had it would
   --  take that program's input; the caller knows when nobody else is reading
   --  and this package does not.
   --
   --  @param Terminal Where to look. Stop_Watching to stop.
   procedure Watch_Terminal (Terminal : Hostkit.Descriptors.Descriptor);

   --  Stop looking. Anything already recorded stays recorded.
   procedure Stop_Watching;

   --  Whether the terminal is being watched.
   --
   --  @return True between Watch_Terminal and Stop_Watching.
   function Watching return Boolean;

   --  Look once, if watching. Cheap enough to call between instructions.
   procedure Look_For_An_Interrupt;

end Adash.Execution.Signals;

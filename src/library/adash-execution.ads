with Hostkit.Signals;

with Adash.Errors;
with Adash.Messages;

--  Running things: the shell's execution policy.
--
--  This subsystem owns how a command is invoked, how a pipeline is wired, how a
--  redirection is applied, how a job lives and dies, and what any of it means
--  when it is over. It does not parse. Nothing here reads Adash source or knows
--  what the language looks like; it is given an invocation already decided and
--  carries it out. A parser appearing under Adash.Execution would be the
--  beginning of a second language.
--
--  The root package holds the one thing every part of the subsystem has to
--  agree about: what became of something that ran.
package Adash.Execution is

   --  A signal, as the shell talks about one.
   --
   --  Deliberately hostkit's type rather than a copy of it. The alternative is
   --  a second enumeration and a mapping table, and the table is what goes
   --  wrong -- a signal added on one side and not the other is a job reported
   --  as killed by the wrong thing. hostkit's type is already host-independent:
   --  it names signals, not numbers, and the numbers stay behind its per-host
   --  bodies. This is the documented exception to keeping platform types out of
   --  shell-level APIs.
   subtype Signal is Hostkit.Signals.Signal;

   --  How something that ran came to an end.
   --
   --  These are told apart because a shell has to report them differently and
   --  because a script has to be able to branch on them. Folding them into one
   --  number is what makes "the program exited 127" and "there is no such
   --  program" indistinguishable, and a user cannot act on the difference they
   --  were not told about.
   type Exit_Kind is
     (
      --  An internal command that succeeded.
      Exit_Internal_Success,

      --  An internal command that failed.
      Exit_Internal_Failure,

      --  An external program that ran and returned a status of its own.
      Exit_External,

      --  An external program killed by a signal. Not an exit code: a program
      --  killed by SIGSEGV did not choose to return anything, and reporting it
      --  as though it had hides how it died.
      Exit_Signalled,

      --  A program that could not be started at all -- not found, not
      --  executable, not permitted, or the host refused.
      Exit_Start_Failure,

      --  Source that did not parse.
      Exit_Parse_Failure,

      --  Source that parsed and was not legal.
      Exit_Semantic_Failure,

      --  Cancelled before or during execution, by a signal or by a caller.
      Exit_Cancelled,

      --  Adash itself failed. Distinct from every kind above, because every
      --  kind above is a normal outcome and this one is a defect.
      Exit_Internal_Error);

   --  What became of something that ran.
   type Exit_Status is record
      Kind : Exit_Kind := Exit_Internal_Success;

      --  Meaningful when Kind is Exit_External: the status the program chose.
      Code : Integer := 0;

      --  Meaningful when Kind is Exit_Signalled.
      Terminating_Signal : Signal := Hostkit.Signals.Signal_Terminate;

      --  False when the host reported a signal this crate does not name. The
      --  status is still Exit_Signalled -- it was killed, and that is the part
      --  that matters -- but Terminating_Signal must not be read.
      Signal_Known : Boolean := False;
   end record;

   --  The status of something that worked.
   Success : constant Exit_Status := (others => <>);

   --  What a signal is called, in words.
   --
   --  `Hostkit.Signals.Name` answers with an identifier and says so: it is
   --  something a consumer maps to a message, not text for a user. This is
   --  that map. Rendering the identifier is what put `was ended by TERMINATE`
   --  in front of users.
   --
   --  @param Item Signal to name.
   --  @return The message that says what it is.
   function Message (Item : Signal) return Adash.Messages.Message_Id;

   --  Whether a status means success.
   --
   --  Only two kinds can: an internal command that succeeded, and an external
   --  program that returned zero. Everything else, including a cancellation, is
   --  a failure for the purpose of `and then` in a script.
   --
   --  @param Item Status to test.
   --  @return True when it means success.
   function Succeeded (Item : Exit_Status) return Boolean;

   --  The single number this status reduces to, for a script that wants one and
   --  for the process exit status when the shell itself ends.
   --
   --  One documented model, used everywhere:
   --
   --    0        success
   --    1 .. 125 a status an external program chose, or an internal failure
   --    126      found, but not executable
   --    127      not found
   --    128 + n  killed by signal n
   --    130      the special case of the above that users recognise: Ctrl-C
   --    2        a parse or semantic failure
   --    70       an internal Adash failure
   --
   --  The convention is the usual one because scripts and CI already depend on
   --  it; the point of writing it down is that there is exactly one place that
   --  decides, rather than a number chosen at each site that produces a status.
   --
   --  @param Item Status to reduce.
   --  @return Its numeric form.
   function Numeric (Item : Exit_Status) return Natural;

   --  The status of an external program that returned a code.
   --
   --  @param Code The status it returned.
   --  @return The corresponding Exit_Status.
   function From_External_Code (Code : Integer) return Exit_Status;

   --  The status of an external program killed by a signal.
   --
   --  @param Terminating_Signal The signal that killed it.
   --  @param Known False when the host named a signal this crate does not.
   --  @return The corresponding Exit_Status.
   function From_Signal
     (Terminating_Signal : Signal;
      Known              : Boolean := True) return Exit_Status;

   --  The status of a command that could not be started.
   --
   --  @param Executable_Found True when the program exists but could not be
   --         run, which is 126 rather than 127. The difference is the whole
   --         reason a user can tell a typo from a permissions problem.
   --  @return The corresponding Exit_Status.
   function From_Start_Failure (Executable_Found : Boolean) return Exit_Status;

   --  What a program that would not start exited with, from what went wrong.
   --
   --  The same decision as From_Start_Failure, taken from the failure the
   --  execution subsystem reported rather than from a Boolean the caller had to
   --  work out for itself. Two callers work it out -- the `run` family and the
   --  one predefined function that runs a program -- and two copies of a
   --  mapping is how they come to disagree.
   --
   --  @param Reason What was said about it.
   --  @return The corresponding Exit_Status.
   function From_Start_Error
     (Reason : Adash.Errors.Error_Code) return Exit_Status;

end Adash.Execution;

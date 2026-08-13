--  Asking something that is running to stop.
--
--  Cancellation is state, not an exception and not a return value. The reason
--  is that the thing which decides to cancel is never the thing that has to
--  notice: a signal arrives, or the interactive frontend decides a job has run
--  long enough, while the code that must act on it is several frames down
--  inside a wait. Passing a token means the decision can be made in one place
--  and observed in another without either one knowing about the other.
--
--  It is one-way on purpose. A token that has been asked to stop stays asked
--  until somebody explicitly resets it, so a check that happens after the
--  request cannot miss it. The alternative -- a flag cleared by whoever reads
--  it first -- loses the request when two places check, which is precisely the
--  situation a pipeline is in.
--
--  Protected because the requester and the observer are usually different
--  tasks, and on POSIX the requester may be a signal-driven path. A plain
--  Boolean would be a data race that works in testing and fails under load.
package Adash.Execution.Cancellation is

   --  A request to stop, and whether it has been made.
   protected type Token is

      --  Ask whatever is watching this token to stop.
      --
      --  Idempotent: asking twice is asking once. A caller that cannot tell
      --  whether it already asked -- a signal path, typically -- does not have
      --  to find out.
      procedure Request;

      --  Whether Request has been called.
      --
      --  @return True once a cancellation has been asked for.
      function Is_Requested return Boolean;

      --  Clear the request, so the token can be used again.
      --
      --  For a shell reusing one token across commands: the interrupt that
      --  cancelled the last command must not cancel the next one before it
      --  starts. Called between commands, never by the code observing the
      --  token.
      procedure Reset;

   private
      Requested : Boolean := False;
   end Token;

   --  A token to pass where cancellation is possible but nobody will ask.
   --
   --  Named rather than left to a null access, so that a caller that does not
   --  support cancellation says so and a reader can see which it is.
   Never : aliased Token;

end Adash.Execution.Cancellation;

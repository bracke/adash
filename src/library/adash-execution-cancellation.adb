with Adash.Execution.Signals;

package body Adash.Execution.Cancellation is

   protected body Token is

      -------------
      -- Request --
      -------------

      procedure Request is
      begin
         Requested := True;
      end Request;

      -------------------
      -- Is_Requested --
      -------------------

      function Is_Requested return Boolean is
      begin
         --  Either somebody asked this token to stop, or the user did.
         --
         --  A recorded interrupt belongs here rather than at each place that
         --  waits. Every consumer of a token is something that can be waiting
         --  when Ctrl-C arrives -- the virtual machine between instructions, a
         --  pipeline between polls -- and each answering separately meant each
         --  could be forgotten separately. One of them was: a program run in
         --  the foreground waited out its full duration, because the wait
         --  polled the token and only the machine consulted the signal.
         --  And a signal that means wind up, for the same reason: a handler
         --  registered for `terminate` cannot run while the loop it was meant
         --  to interrupt is still going, and the token is the one place that
         --  knows what "stop" means.
         return Requested
           or else Adash.Execution.Signals.Interrupt_Pending
           or else Adash.Execution.Signals.Winding_Up;
      end Is_Requested;

      -----------
      -- Reset --
      -----------

      procedure Reset is
      begin
         Requested := False;
      end Reset;

   end Token;

end Adash.Execution.Cancellation;

with Adash.Diagnostics;
with Adash.Engine;

--  What the shell reads before it does anything else.
--
--  Startup is where a shell is at its least forgiving: nobody is watching, a
--  mistake affects every session afterwards, and a failure that stops the shell
--  from starting leaves a user with no way to fix it. So the rules here are
--  stated rather than left to whatever the code happens to do.
--
--  **Discovery order.** System, then user, then session. Later files run after
--  earlier ones and so win where they disagree, which is the order users expect:
--  an administrator sets a default, a user overrides it, a session overrides
--  that.
--
--  **A missing file is normal.** Most systems have no system-wide startup file
--  and most users have none either. Absence is silent.
--
--  **An unreadable file is a warning, and startup continues.** A file that
--  exists and cannot be read is worth saying -- it is usually a permissions
--  mistake -- but refusing to start the shell over it would leave the user
--  without the tool they would fix it with.
--
--  **A file that fails is reported, and startup continues.** Same reasoning.
--  The failure is reported with the file's own diagnostics, so a user can see
--  which line, and the shell still comes up.
--
--  **The session file is for interactive sessions only.** It exists to set a
--  prompt and the like; running it for a script would change what that script
--  means depending on who ran it, which is the class of bug that makes shell
--  scripts unportable between machines.
package Adash.Scripting.Startup is

   --  Which startup file.
   type Scope is
     (
      --  Installed by an administrator, for every user of the machine.
      System_Scope,

      --  The user's own, for every session.
      User_Scope,

      --  The user's own, for interactive sessions only.
      Session_Scope);

   --  Where a startup file lives.
   --
   --  From hostkit, which knows where a host keeps configuration. Never from
   --  an environment variable: a spawned process could then choose what the
   --  next shell runs at startup, which is a way in rather than a feature.
   --
   --  @param Item Which file.
   --  @return Its path, or "" when the host has no such location.
   function Path_For (Item : Scope) return String;

   --  Whether a scope applies to this kind of session.
   --
   --  @param Item Which file.
   --  @param Interactive True for a session with a user at it.
   --  @return True when the file should be run.
   function Applies (Item : Scope; Interactive : Boolean) return Boolean;

   --  What happened while starting up.
   type Report_Summary is record
      --  How many startup files existed and were run.
      Ran : Natural := 0;

      --  How many existed and could not be read.
      Unreadable : Natural := 0;

      --  How many ran and reported a problem.
      Failed : Natural := 0;
   end record;

   --  Run every applicable startup file, in order.
   --
   --  Never refuses to return: whatever the files do, the shell comes up. The
   --  summary and the diagnostics say what happened, and the caller decides
   --  whether to mention it.
   --
   --  @param Session The session they run in, and whose state they change.
   --  @param Interactive True for a session with a user at it.
   --  @param Summary What happened.
   --  @param Report Where diagnostics go.
   procedure Run_All
     (Session     : in out Adash.Engine.Session;
      Interactive : Boolean;
      Summary     : out Report_Summary;
      Report      : in out Adash.Diagnostics.List;
      On_Output   : Adash.Engine.Output_Sink_Access := null);

end Adash.Scripting.Startup;

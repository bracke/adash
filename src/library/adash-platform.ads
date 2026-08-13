with Adash.Messages;

with Adash.Errors;

--  Adash's policy over hostkit.
--
--  hostkit answers what the host can do. This decides what Adash does about the
--  answer, and it is the only place in Adash that makes that decision -- so the
--  execution subsystem, the interactive frontend and persistence cannot come to
--  three different conclusions about the same host.
--
--  It adds no platform code. There is no operating system here, no per-host
--  body, and no `src/platform` directory in this repository; a call that hostkit
--  does not provide is a call to be added to hostkit, not written below this
--  line. What is here is translation and policy: a capability question a
--  consumer can ask once at startup, and the mapping from a host refusal to an
--  Adash.Errors code that a diagnostic can be built from.
--
--  Why capabilities are asked rather than assumed. hostkit refuses signals,
--  process groups and pseudo-terminals on Windows, and refuses advisory locks on
--  a filesystem that does not carry them. Each refusal is a real answer, and the
--  shell's response is to degrade visibly: job control that is unavailable is
--  reported as unavailable, not silently skipped. A consumer that treats a
--  refusal as "not needed here" has rebuilt the bug hostkit exists to prevent.
package Adash.Platform is

   --  Something a host either can or cannot do, which changes what the shell
   --  offers.
   type Capability is
     (
      --  Signals can be sent and their dispositions set. Without it the shell
      --  cannot ignore SIGPIPE, cannot interrupt a job, and cannot survive
      --  Ctrl-C while its foreground job receives it.
      Capability_Signals,

      --  Children can be placed in process groups and a terminal handed to
      --  one. This is job control; without it a pipeline cannot be
      --  interrupted, suspended or resumed as a unit.
      Capability_Job_Control,

      --  A pseudo-terminal can be created, so a child can be run as though a
      --  user were watching it.
      Capability_Pseudo_Terminal,

      --  Advisory file locks are available, so two sessions do not overwrite
      --  each other's persistent state.
      Capability_Advisory_Locks);

   --  Whether this host has a capability.
   --
   --  Answered from hostkit, which answers from a body per host. Never from the
   --  environment, which a spawned process can spoof, and never from a build-
   --  time constant, which describes the machine that compiled Adash rather
   --  than the one running it.
   --
   --  @param Item Capability to ask about.
   --  @return True when the host provides it.
   --  What a capability is called, in words.
   --
   --  The enumeration literal is an identifier, and `this system does not
   --  support JOB_CONTROL` is what showing one to a user looks like.
   --
   --  @param Item Capability to name.
   --  @return The message that says what it is.
   function Message (Item : Capability) return Adash.Messages.Message_Id;

   function Is_Available (Item : Capability) return Boolean;

   --  A stable, host-independent name for a capability, for a diagnostic that
   --  has to say which one is missing.
   --
   --  An identifier rather than text for a user: the presentation boundary maps
   --  it into a sentence.
   --
   --  @param Item Capability to name.
   --  @return Its name, for example "JOB_CONTROL".
   function Name (Item : Capability) return String;

   --  The failure to report when a capability a caller needs is absent.
   --
   --  @param Item The missing capability.
   --  @return A structured failure naming it.
   function Unavailable (Item : Capability) return Adash.Errors.Error_Info;

end Adash.Platform;

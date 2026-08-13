private with Ada.Containers.Vectors;

with Adash.Messages;
with Adash.Terminal;

--  News that has to wait its turn.
--
--  A background job finishing, a window resizing, a file changing underfoot:
--  none of it happens when the shell is ready to talk about it. Printing it the
--  moment it arrives writes over the line the user is in the middle of typing,
--  and the line is the one thing on screen that belongs to them.
--
--  So notices are held and delivered at a **quiescent point** -- after a
--  submission has finished and before the next prompt is drawn. That is the
--  one moment when nothing on screen is half-written and nothing is being
--  edited.
--
--  This package is the queue and the policy, not the printing. It holds
--  message identifiers, so a notice is as translatable and as testable as any
--  other output.
package Adash.Interactive.Notifications is

   --  Why a notice exists. The kind is not decoration: it decides whether a
   --  notice may be dropped when the queue is full.
   type Notice_Kind is
     (
      --  A job changed state. The user asked for the job, so they are owed the
      --  news; these are kept in preference to anything else.
      Job_Change,

      --  Something about the session itself -- a reloaded configuration, a
      --  restored terminal size.
      Session_Change,

      --  A condition worth knowing about that stopped nothing.
      Advisory);

   --  How many notices are held before the oldest droppable one is discarded.
   --  Bounded because an unbounded queue turns a runaway producer into an
   --  unbounded printout the user has to scroll past.
   Max_Pending : constant := 64;

   --  A queue of notices.
   type Queue is tagged limited private;

   --  Add a notice.
   --
   --  @param Item Queue to add to.
   --  @param Kind Why the notice exists.
   --  @param Message What to say.
   --  @param Arguments Its arguments.
   --  @param Role How to style it.
   procedure Post
     (Item      : in out Queue;
      Kind      : Notice_Kind;
      Message   : Adash.Messages.Message_Id;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Role      : Adash.Terminal.Style_Role := Adash.Terminal.Role_Info);

   --  @param Item Queue to measure.
   --  @return How many notices are waiting.
   function Pending (Item : Queue) return Natural;

   --  Whether now is a moment to deliver.
   --
   --  The frontend asks rather than being told, so that the policy lives here
   --  and not in the loop. A notice is never delivered while a line is being
   --  edited, however long it has waited: interrupting the user's typing to
   --  tell them a job finished trades something they are doing for something
   --  they are not.
   --
   --  @param Item Queue to ask.
   --  @param Editing True when a line is part-typed.
   --  @return True when Take may be called.
   function Ready (Item : Queue; Editing : Boolean) return Boolean;

   --  One notice, ready to render.
   type Notice is record
      Kind      : Notice_Kind := Advisory;
      Message   : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Arguments : Adash.Messages.Argument_List (1 .. 4);
      Count     : Natural range 0 .. 4 := 0;
      Role      : Adash.Terminal.Style_Role := Adash.Terminal.Role_Info;
   end record;

   --  Take the oldest notice.
   --
   --  Oldest first, because notices about the same job read as nonsense in any
   --  other order: "started" after "finished" is worse than late news.
   --
   --  @param Item Queue to take from.
   --  @param Into The notice, meaningful only when this returns True.
   --  @return True when there was one.
   function Take (Item : in out Queue; Into : out Notice) return Boolean;

   --  Discard everything waiting.
   --
   --  @param Item Queue to clear.
   procedure Clear (Item : in out Queue);

private

   package Notice_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Notice);

   type Queue is tagged limited record
      Items : Notice_Vectors.Vector;
   end record;

end Adash.Interactive.Notifications;

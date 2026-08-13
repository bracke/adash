with Adash.Engine;
with Adash.Messages;
with Adash.Terminal;

--  What is shown before a line.
--
--  A prompt is built from parts rather than from a format string. A format
--  string would be a second small language -- with its own escapes, its own
--  errors and its own documentation -- inside a shell whose whole point is that
--  it has one language.
--
--  **Prompt generation cannot fail the shell.** Whatever goes wrong, a prompt
--  comes back: a shell that cannot draw its prompt is a shell a user cannot
--  type into, and the fault is almost always in something they configured and
--  now need the shell to fix.
package Adash.Interactive.Prompt is

   --  Which prompt.
   type Prompt_Kind is
     (
      --  Before a new line.
      Primary,

      --  Before the rest of a line that is not finished -- an unclosed
      --  construct. Distinct so a user can see at a glance that the shell is
      --  waiting for more rather than for something new.
      Continuation);

   --  What a prompt is made of.
   type Element_Kind is
     (
      --  Fixed text from the catalog.
      Element_Message,

      --  The working directory, shortened to its last component.
      Element_Directory,

      --  A marker that the last submission failed. Shown as text, never as
      --  colour alone: a prompt that says "the last thing failed" only by
      --  turning red says nothing to a reader who cannot see red.
      Element_Status);

   --  Largest number of parts a prompt has.
   Max_Elements : constant := 8;

   --  One part.
   type Element is record
      Kind    : Element_Kind := Element_Message;
      Message : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Role    : Adash.Terminal.Style_Role := Adash.Terminal.Role_Plain;
   end record;

   type Element_Array is array (1 .. Max_Elements) of Element;

   --  A prompt, as parts a frontend renders.
   type Model is record
      Count    : Natural range 0 .. Max_Elements := 0;
      Elements : Element_Array;
   end record;

   --  Build the prompt for a session.
   --
   --  The session carries the settings, so which parts appear is the user's
   --  choice rather than this package's. A prompt built from a fixed list would
   --  be one nobody could turn the directory off in, and the directory is the
   --  part that costs a syscall on every line.
   --
   --  @param Session The session, for its settings and for what it can say
   --         about itself.
   --  @param Kind Which prompt.
   --  @param Last_Failed True when the previous submission did not succeed.
   --  @return The parts to render.
   function Build
     (Session     : Adash.Engine.Session;
      Kind        : Prompt_Kind := Primary;
      Last_Failed : Boolean := False) return Model;

   --  The text of one element.
   --
   --  Everything but Element_Message resolves to text here, because the value
   --  is the shell's rather than a translator's -- a directory name is not
   --  prose. Element_Message is left to the caller's catalog.
   --
   --  @param Item The element.
   --  @return Its text, or "" for an element whose text is a message.
   function Text_Of (Item : Element) return String;

end Adash.Interactive.Prompt;

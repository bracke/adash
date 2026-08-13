with Adash.Messages.Rendering;

--  The interactive loop.
--
--  Read a line, submit it, render what comes back, deliver whatever news was
--  waiting, draw the next prompt. That is the whole of it, and it is
--  deliberately the whole of it: every decision the loop appears to make --
--  what the prompt says, what a keystroke means, what could be typed next,
--  what is worth remembering -- belongs to one of the sibling packages, and
--  what a line *means* belongs to Adash.Engine.
--
--  This is also the presentation boundary for an interactive session, the
--  counterpart of the one in the script path. Diagnostics and command output
--  arrive as identifiers and arguments and become sentences here, once.
package Adash.Interactive.Session is

   --  Run an interactive session until the user ends it.
   --
   --  @param Catalog The message catalog, already open. Passed in rather than
   --         opened here because the caller has already had to open one to
   --         report anything that went wrong before this point, and two
   --         catalogs could disagree about the locale.
   --  @return The status the process should exit with.
   function Run (Catalog : in out Adash.Messages.Rendering.Catalog)
                 return Natural;

end Adash.Interactive.Session;

--  The shell a person sits in front of.
--
--  Everything here is a frontend over Adash.Engine. The loop reads a line,
--  submits it, and renders what comes back; it does not parse, analyse, or run
--  anything itself. A frontend that did would be a second engine, and the
--  difference between the two would be discovered by users.
--
--  What the frontend owns is everything the engine deliberately does not: the
--  prompt, the line the user is editing, what has been typed before, what could
--  be typed next, how any of it is coloured, and when a background job's news
--  is allowed to appear on screen.
--
--  Its children:
--
--    Adash.Interactive.Prompt         what to show before a line
--    Adash.Interactive.Editing        reading a line
--    Adash.Interactive.History        what has been typed
--    Adash.Interactive.Completion     what could be typed next
--    Adash.Interactive.Highlighting   how a line is coloured
--    Adash.Interactive.Notifications  news that has to wait its turn
--    Adash.Interactive.Session        the loop that ties them together
--
--  Each is a model that can be tested without a terminal. That is deliberate:
--  a frontend whose logic only runs under a real terminal is one whose logic is
--  never tested, and the interactive path is where a shell spends its life.
package Adash.Interactive is
   pragma Pure;
end Adash.Interactive;

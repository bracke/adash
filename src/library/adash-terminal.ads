--  Adash's style roles, and the policy for when styling is emitted.
--
--  Adash never writes an escape sequence. terminal_styles owns the bytes;
--  this package owns the vocabulary -- what a piece of Adash output *is*, not
--  what colour it should be. A subsystem asks for Role_Error, never for red,
--  so that the mapping from meaning to appearance exists once and can be
--  changed once.
--
--  The second rule is that styling is decoration and nothing more. Every
--  line Adash emits has to remain complete and unambiguous with styling off:
--  down a pipe, into a log, on a terminal that cannot colour, or for a reader
--  who cannot see it. A message that distinguishes an error from a warning
--  only by colour is a defect, not a style choice -- and it is invisible in
--  the tests, which run without a terminal.
--
--  Roles are deliberately few. A role earns its place when some subsystem
--  needs to say something the existing roles cannot, which is how the
--  syntactic ones arrived: Adash.Interactive.Highlighting asks for a keyword,
--  a literal and a comment, and asks for nothing else.
package Adash.Terminal is

   --  What a piece of Adash output is.
   type Style_Role is
     (
      --  Ordinary output carrying no status of its own. Mapped to no styling
      --  at all, which is why it is not simply the absence of a role: passing
      --  Role_Plain says the caller considered the question.
      Role_Plain,

      --  A heading in help or a report.
      Role_Header,

      --  Neutral information.
      Role_Info,

      --  An operation that succeeded, where saying so is useful.
      Role_Success,

      --  A condition the user should know about but which did not stop
      --  anything.
      Role_Warning,

      --  A failure.
      Role_Error,

      --  Secondary detail: a path, a hint, an aside. Dimmed where possible,
      --  and never load-bearing, because "dimmed" is exactly what a reader
      --  with low contrast or a limited palette will not perceive.
      Role_Muted,

      ------------------------------------------------------------------
      --  Syntax roles.
      --
      --  Added with the highlighting model, as the note here used to say they
      --  would be. They are deliberately few: a role per token kind would tie
      --  the palette to the lexer, and every language change would become a
      --  colour change.
      ------------------------------------------------------------------

      --  A reserved word.
      Role_Keyword,

      --  A literal of any type.
      Role_Literal,

      --  A comment.
      Role_Comment,

      --  An identifier that resolved to something known -- a command, a
      --  predefined entity, a declared name.
      Role_Known_Name,

      --  An operator or delimiter.
      Role_Operator);

   --  When ANSI styling may be emitted.
   type Color_Policy is
     (
      --  Style when the destination is a terminal and NO_COLOR is unset.
      Color_Auto,

      --  Always style, whatever the destination. For a caller that is piping
      --  into something which understands escapes on purpose.
      Color_Always,

      --  Never style.
      Color_Never);

   --  Set the process-wide styling policy.
   --
   --  Process-wide because the underlying policy in terminal_styles is, and
   --  two policies that can disagree would be worse than one that is global.
   --  Adash sets it once during startup, from configuration and the command
   --  line, and does not change it afterwards.
   --
   --  @param Policy Policy to apply to subsequent Styled calls.
   procedure Set_Color_Policy (Policy : Color_Policy);

   --  The policy currently in force.
   --
   --  @return Active policy.
   function Current_Color_Policy return Color_Policy;

   --  Whether styling would be emitted for a given destination.
   --
   --  Callers that build a line by hand -- padding a column, say -- need to
   --  know whether the text they are measuring will carry invisible bytes.
   --
   --  @param Destination_Is_Terminal True when the destination is a terminal.
   --  @return True when Styled would decorate.
   function Color_Enabled (Destination_Is_Terminal : Boolean) return Boolean;

   --  Style text for a role.
   --
   --  @param Item Text to style.
   --  @param Role What the text is.
   --  @param Destination_Is_Terminal True when the destination is a terminal;
   --         under Color_Auto this decides whether anything is emitted.
   --  @return Item, decorated when the policy allows it, otherwise unchanged.
   function Styled
     (Item                    : String;
      Role                    : Style_Role;
      Destination_Is_Terminal : Boolean) return String;

   --  Whether one of the standard streams is a terminal.
   --
   --  Asked of hostkit, which has a body per host. This is here rather than
   --  left to each caller so that "is this a terminal" has one answer inside
   --  Adash, and so that the interactive frontend and the diagnostic printer
   --  cannot come to different conclusions about the same stream.
   type Stream_Kind is (Standard_Input, Standard_Output, Standard_Error);

   --  @param Stream Stream to test.
   --  @return True when that stream is attached to a terminal.
   function Is_Terminal (Stream : Stream_Kind) return Boolean;

end Adash.Terminal;

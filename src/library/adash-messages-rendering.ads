private with Ada.Strings.Unbounded;
private with Messages.Runtime;

--  The presentation boundary: identifiers in, text out.
--
--  This is the only package in Adash that reads the message catalog, and the
--  only one permitted to produce a human sentence. Everything below it --
--  the lexer, the evaluator, the execution subsystem, persistence -- reports
--  a Message_Id and typed arguments and stops there. Concentrating rendering
--  in one place is what makes a diagnostic testable by identity, re-renderable
--  for a log or a structured report, and translatable without touching Ada
--  source.
--
--  Locale precedence, applied by Open:
--
--    1  the Requested_Locale argument, when not empty
--    2  ADASH_LOCALE
--    3  the host's own locale, as hostkit reports it
--    4  the catalog's declared default locale
--    5  the invariant fallback
--
--  Failure is not an error. A shell that cannot load its catalog must still
--  be able to say so, and a catalog failure reported by way of the catalog is
--  either silence or an infinite regress. So Open never fails: Is_Ready
--  reports the outcome, and every lookup that cannot be satisfied falls back
--  to Fallback_Text below, which is deterministic, names the key, and never
--  re-enters the catalog.
--
--  Task safety: a Catalog is opened once and read afterwards. Open and Close
--  must not run concurrently with Text on the same object.
package Adash.Messages.Rendering is

   --  A loaded message catalog, resolved to one locale.
   type Catalog is tagged limited private;

   --  Open a catalog.
   --
   --  @param Item Catalog to open.
   --  @param Catalog_Path Catalog file to load; Default_Catalog_Path when empty.
   --  @param Requested_Locale Explicit locale request; see the precedence
   --         list above. Empty means no explicit request.
   procedure Open
     (Item             : in out Catalog;
      Catalog_Path     : String := "";
      Requested_Locale : String := "");

   --  Whether the catalog loaded and can render.
   --
   --  When this is False, Text still answers -- in the invariant fallback
   --  form. Callers report the degradation once, at startup, rather than
   --  checking before every lookup.
   --
   --  @param Item Catalog to inspect.
   --  @return True when messages render from the catalog.
   function Is_Ready (Item : Catalog) return Boolean;

   --  The locale this catalog resolved to.
   --
   --  @param Item Catalog to inspect.
   --  @return Locale identifier, or the empty string when not ready.
   function Locale (Item : Catalog) return String;

   --  The catalog file this catalog was opened from.
   --
   --  Worth reporting when Is_Ready is False: the usual cause is that the
   --  binary was moved away from its resources, and the path says so.
   --
   --  @param Item Catalog to inspect.
   --  @return Catalog path as opened.
   function Path (Item : Catalog) return String;

   --  Render a message.
   --
   --  @param Item Catalog to render from.
   --  @param Id Message identifier.
   --  @param Arguments Named arguments the message's placeholders expect.
   --  @return Rendered text, or the invariant fallback form on any failure.
   function Text
     (Item      : Catalog;
      Id        : Message_Id;
      Arguments : Argument_List := No_Arguments) return String;

   --  Render a message whose text embeds another message.
   --
   --  A subsystem below the presentation boundary may name a message and may
   --  not render one -- that is the whole point of the boundary -- so a line
   --  that has to *quote* a message cannot pass its text: it does not have it
   --  and must not produce it. `help` is the case that forced this. It lists a
   --  command's name beside what that command is for, and what it is for is
   --  another message; the command layer names both and this is where the two
   --  become text.
   --
   --  Quoted of Msg_Error_None means nothing is quoted, so a caller rendering
   --  lines that may or may not carry one does not need two call sites.
   --
   --  @param Item Catalog to render from.
   --  @param Id The outer message.
   --  @param Arguments Its arguments, less the one filled from Quoted.
   --  The quoted message may take arguments of its own. It did not until the
   --  machine's failures became messages: `position 9 is outside a String of 3`
   --  is quoted into an exception report and carries two numbers, and without
   --  this the only quotable messages were ones with nothing in them.
   --
   --  @param Quoted The message rendered into the outer one, or Msg_Error_None.
   --  @param Fills The placeholder Quoted's text fills, without braces.
   --  @param Quoted_Arguments The quoted message's own arguments.
   --  @return Rendered text, or the invariant fallback form on any failure.
   function Text
     (Item             : Catalog;
      Id               : Message_Id;
      Arguments        : Argument_List;
      Quoted           : Message_Id;
      Fills            : String;
      Quoted_Arguments : Argument_List := No_Arguments) return String;

   --  Render a message that embeds another named by catalog key.
   --
   --  The same shape as the overload above, for a quoted message that is not
   --  one of Adash's own. A library below the presentation boundary answers
   --  with a key -- tomllib says `toml.error.expected-key` and explains in its
   --  own source that a consumer is expected to carry the sentence -- and a
   --  key is not a Message_Id, so it cannot go through the overload above and
   --  must not be printed as it stands. It went out as it stood until this
   --  existed: `config.toml: line 1, column 1: toml.error.expected-key`.
   --
   --  @param Item Catalog to render from.
   --  @param Id The outer message.
   --  @param Arguments Its arguments, less the one filled from Quoted_Key.
   --  @param Quoted_Key The catalog key of the message rendered into the outer
   --         one. An empty key quotes nothing.
   --  @param Fills The placeholder the quoted text fills, without braces.
   --  @param Quoted_Arguments The quoted message's own arguments.
   --  @return Rendered text, or the invariant fallback form on any failure.
   function Text
     (Item             : Catalog;
      Id               : Message_Id;
      Arguments        : Argument_List;
      Quoted_Key       : String;
      Fills            : String;
      Quoted_Arguments : Argument_List := No_Arguments) return String;

   --  Render a message addressed by catalog key.
   --
   --  Adash's own messages go through the Message_Id overload above, which is
   --  checked at compile time. This one exists for the repository tooling in
   --  the adash_tests crate, whose messages are not part of the shipped
   --  product and so are not worth an entry in Message_Id -- but which must
   --  still come from a catalog rather than from Ada source.
   --
   --  @param Item Catalog to render from.
   --  @param Key Catalog key.
   --  @param Arguments Named arguments the message's placeholders expect.
   --  @return Rendered text, or the invariant fallback form on any failure.
   function Text
     (Item      : Catalog;
      Key       : String;
      Arguments : Argument_List := No_Arguments) return String;

   --  Release the catalog's storage.
   --
   --  @param Item Catalog to close.
   procedure Close (Item : in out Catalog);

   --  Where to look for the catalog when Open is given no path.
   --
   --  Searched in order: ADASH_MESSAGE_CATALOG; the installed location beside
   --  the executable; the build-tree location. The executable's own directory
   --  comes from hostkit, not from argv (0), which a caller controls and
   --  which is empty in more situations than is comfortable.
   --
   --  @return First candidate path that exists, or the installed location
   --          when none does -- so a failure names where it looked.
   function Default_Catalog_Path return String;

   --  The text a message renders to when the catalog cannot answer.
   --
   --  Deterministic, ASCII, and never a lookup: it names the key and its
   --  arguments so that a broken catalog produces one honest useless line
   --  rather than silence or a loop. Tests assert this form, so it is part of
   --  the contract rather than a debugging convenience.
   --
   --  @param Key Catalog key that could not be rendered.
   --  @param Arguments Arguments that would have been substituted.
   --  @return Fallback text, for example "!version.line{version=0.1.0-dev}!".
   function Fallback_Text
     (Key       : String;
      Arguments : Argument_List := No_Arguments) return String;

private

   --  Inside a child of Adash.Messages the parent is directly visible as
   --  `Messages`, which shadows the crate of the same name -- so a plain
   --  `Messages.Runtime` here means `Adash.Messages.Runtime`, which does not
   --  exist. Renaming from Standard says which one is meant, once, instead of
   --  spelling `Standard.` at every use.
   package Catalog_Runtime renames Standard.Messages.Runtime;

   type Catalog is tagged limited record
      Runtime : Catalog_Runtime.Runtime;
      Ready   : Boolean := False;
      Locale  : Ada.Strings.Unbounded.Unbounded_String;
      Path    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end Adash.Messages.Rendering;

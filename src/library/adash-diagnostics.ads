private with Ada.Containers.Vectors;

with Adash.Errors;
with Adash.Messages;
with Adash.Source;

--  What went wrong, as data a consumer can render, log, sort or assert on.
--
--  A diagnostic carries a stable identifier, a severity, a category, where in
--  the source it is about, structured arguments, and optionally other places
--  worth looking at. It does not carry a sentence. Nothing in this package
--  produces text, and nothing below the presentation boundary is permitted to.
--
--  That is not only about translation. A diagnostic assembled as a string at
--  the point it is detected cannot be tested by identity, cannot be given a
--  stable code in a conformance case, and cannot be re-rendered for a terminal,
--  a log and a structured report without one of them parsing another's output.
--  An identifier plus arguments survives all three.
--
--  Ordering is deterministic and is not insertion order. Diagnostics arrive in
--  whatever order the phase that found them happened to walk the source, and a
--  user reads them against the file -- so Sort puts them in source order, with
--  severity and identifier as tie-breaks and insertion order as the last one.
--  Two runs over the same input produce the same list in the same order, which
--  is what makes a conformance case possible at all.
package Adash.Diagnostics is

   --  How much a diagnostic matters.
   type Severity is
     (
      --  Context for another diagnostic, or something worth knowing. Never on
      --  its own.
      Severity_Note,

      --  Something suspicious that does not stop anything.
      Severity_Warning,

      --  The construct is wrong. Nothing that depends on it will run, but the
      --  phase continues so that a user gets more than one error per attempt.
      Severity_Error,

      --  The phase cannot continue at all -- source that will not decode, a
      --  file that will not open. Distinct from Severity_Error because it is
      --  the reason there are no further diagnostics, and a consumer that
      --  reported "1 error" without saying so would be misleading.
      Severity_Fatal);

   --  Which kind of rule a diagnostic is about.
   --
   --  Not the same question as which subsystem raised it: semantic analysis
   --  raises lexical diagnostics when it re-reads a token, and the user cares
   --  which sort of mistake they made rather than which package noticed.
   type Category is
     (Category_Lexical,
      Category_Syntax,
      Category_Semantic,
      Category_Runtime,
      Category_Execution,
      Category_Configuration,
      Category_Persistence,
      Category_Internal);

   --  Which subsystem is answerable for a diagnostic.
   --
   --  Recorded separately from Category so that a repository report can say
   --  which part of Adash produces which diagnostics, and a test can assert
   --  that a phase raised nothing outside its own vocabulary.
   type Owner is
     (Owner_Source,
      Owner_Language,
      Owner_Engine,
      Owner_Execution,
      Owner_Commands,
      Owner_Interactive,
      Owner_Scripting,
      Owner_Persistence,
      Owner_Configuration,
      Owner_Platform);

   --  Another place worth looking at: the earlier declaration a name collides
   --  with, the opening bracket that was never closed.
   type Related_Location is record
      Origin  : Adash.Source.Origin;
      Extent  : Adash.Source.Span := Adash.Source.Nowhere;

      --  What to say about this place. A related location without its own
      --  message is a bare underline the user has to guess the meaning of.
      Message : Adash.Messages.Message_Id;
   end record;

   --  Largest number of related locations one diagnostic carries.
   Max_Related : constant := 4;

   --  Largest number of structured arguments one diagnostic carries.
   Max_Arguments : constant := 4;

   --  One thing that went wrong.
   type Diagnostic is private;

   --  Build a diagnostic.
   --
   --  @param Message What to say. The stable identity of this diagnostic.
   --  @param Level How much it matters.
   --  @param Of_Kind Which sort of rule it is about.
   --  @param Raised_By Which subsystem is answerable for it.
   --  @param Origin Where the source came from.
   --  @param Extent Where in that source it is about.
   --  @param Arguments Structured detail the message expects.
   --  @param Guidance What the user could do about it, as a message identifier.
   --         Pass the same value as Message when there is no separate advice;
   --         Has_Guidance then reports False.
   --  @return The diagnostic.
   function Make
     (Message   : Adash.Messages.Message_Id;
      Level     : Severity;
      Of_Kind   : Category;
      Raised_By : Owner;
      Origin    : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent    : Adash.Source.Span := Adash.Source.Nowhere;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Guidance  : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Quoted    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills     : String := "";
      Quoted_Arguments : Adash.Messages.Argument_List :=
        Adash.Messages.No_Arguments)
      return Diagnostic;

   --  Build a diagnostic from an operational failure.
   --
   --  The bridge between Adash.Errors, which is what a subsystem returns, and
   --  this, which is what a frontend reports. The code's own message and domain
   --  come across, so the two cannot drift apart.
   --
   --  @param Failure The failure.
   --  @param Level How much it matters; a failure is an error unless the caller
   --         knows better.
   --  @param Of_Kind Which sort of rule it is about.
   --  @param Raised_By Which subsystem is answerable.
   --  @param Origin Where the source came from, when there is one.
   --  @param Extent Where in that source, when it is known.
   --  @return The diagnostic.
   function From_Error
     (Failure   : Adash.Errors.Error_Info;
      Level     : Severity := Severity_Error;
      Of_Kind   : Category := Category_Execution;
      Raised_By : Owner := Owner_Execution;
      Origin    : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent    : Adash.Source.Span := Adash.Source.Nowhere)
      return Diagnostic;

   --  Add a related location.
   --
   --  Silently ignored beyond Max_Related: a diagnostic with five related
   --  places is already more than a user will read, and dropping the fifth is
   --  better than refusing to report the diagnostic at all.
   --
   --  @param Item Diagnostic to extend.
   --  @param Location The related place.
   procedure Add_Related (Item : in out Diagnostic; Location : Related_Location);

   --  @param Item Diagnostic to inspect.
   --  @return Its message identifier, which is its stable identity.
   function Message (Item : Diagnostic) return Adash.Messages.Message_Id;

   --  @param Item Diagnostic to inspect.
   --  @return Its severity.
   function Level (Item : Diagnostic) return Severity;

   --  @param Item Diagnostic to inspect.
   --  @return Its category.
   function Of_Kind (Item : Diagnostic) return Category;

   --  @param Item Diagnostic to inspect.
   --  @return The subsystem answerable for it.
   function Raised_By (Item : Diagnostic) return Owner;

   --  @param Item Diagnostic to inspect.
   --  @return Where its source came from.
   function Origin (Item : Diagnostic) return Adash.Source.Origin;

   --  @param Item Diagnostic to inspect.
   --  @return Where in that source it is about.
   function Extent (Item : Diagnostic) return Adash.Source.Span;

   --  @param Item Diagnostic to inspect.
   --  @return Its arguments, as a slice ready for rendering.
   function Arguments (Item : Diagnostic) return Adash.Messages.Argument_List;

   --  A message this diagnostic's text quotes.
   --
   --  The same facility a command's output line has, and for the same reason:
   --  what a subsystem below the presentation boundary knows about a signal, a
   --  capability or a host's refusal is a *name* for it, and a name is an
   --  identifier rather than words. Rendering the identifier is what put
   --  `this system does not support JOB_CONTROL` in front of users.
   --
   --  @param Item Diagnostic to inspect.
   --  @return The quoted message, or Msg_Error_None when it quotes none.
   function Detail (Item : Diagnostic) return Adash.Messages.Message_Id;

   --  @param Item Diagnostic to inspect.
   --  @return The placeholder Detail's text fills, without braces.
   function Detail_Placeholder (Item : Diagnostic) return String;

   --  The quoted message's own arguments.
   --
   --  Empty until the machine's failures became messages. `position 9 is
   --  outside a String of 3` is quoted into an exception report and carries
   --  two numbers of its own, which the outer message knows nothing about.
   --
   --  @param Item Diagnostic to inspect.
   --  @return Its quoted message's arguments; empty when it quotes none.
   function Detail_Arguments
     (Item : Diagnostic) return Adash.Messages.Argument_List;

   --  @param Item Diagnostic to inspect.
   --  @return True when it carries advice distinct from its message.
   function Has_Guidance (Item : Diagnostic) return Boolean;

   --  @param Item Diagnostic to inspect.
   --  @return Its guidance message; meaningful only when Has_Guidance.
   function Guidance (Item : Diagnostic) return Adash.Messages.Message_Id;

   --  @param Item Diagnostic to inspect.
   --  @return How many related locations it carries.
   function Related_Count (Item : Diagnostic) return Natural;

   --  @param Item Diagnostic to inspect.
   --  @param Index Which related location, from one.
   --  @return That location.
   function Related (Item : Diagnostic; Index : Positive) return Related_Location;

   --  A collection of diagnostics.
   --
   --  What a phase is handed to report into, and what a frontend is given to
   --  render. Limited: it is the accumulating state of one run, and a copy
   --  would be a second run's worth of findings nobody merges back.
   type List is tagged limited private;

   --  Record a diagnostic.
   --
   --  @param Item List to add to.
   --  @param Entry_To_Add The diagnostic.
   procedure Emit (Item : in out List; Entry_To_Add : Diagnostic);

   --  @param Item List to measure.
   --  @return How many diagnostics it holds.
   function Count (Item : List) return Natural;

   --  @param Item List to inspect.
   --  @param Index Which diagnostic, from one.
   --  @return That diagnostic.
   function Element (Item : List; Index : Positive) return Diagnostic;

   --  How many diagnostics of a given severity the list holds.
   --
   --  @param Item List to inspect.
   --  @param Level Severity to count.
   --  @return The count.
   function Count_Of (Item : List; Level : Severity) return Natural;

   --  Whether anything in the list should stop what depends on it.
   --
   --  True for errors and fatals, false for warnings and notes. The one
   --  question every caller of a phase asks, given a name so that each of them
   --  does not decide for itself which severities count.
   --
   --  @param Item List to inspect.
   --  @return True when evaluation must not proceed.
   function Has_Blocking (Item : List) return Boolean;

   --  Put the list into its canonical order.
   --
   --  Source name, then position, then severity worst-first, then message
   --  identifier, then insertion order. Deterministic across runs, which is
   --  what a conformance case comparing output depends on.
   --
   --  @param Item List to sort.
   procedure Sort (Item : in out List);

   --  Forget everything.
   --
   --  @param Item List to clear.
   procedure Clear (Item : in out List);

private

   subtype Argument_Storage is
     Adash.Messages.Argument_List (1 .. Max_Arguments);

   type Related_Storage is array (1 .. Max_Related) of Related_Location;

   type Diagnostic is record
      Message        : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Level          : Severity := Severity_Error;
      Of_Kind        : Category := Category_Internal;
      Raised_By      : Owner := Owner_Engine;
      Origin         : Adash.Source.Origin;
      Extent         : Adash.Source.Span := Adash.Source.Nowhere;
      Argument_Count : Natural range 0 .. Max_Arguments := 0;
      Arguments      : Argument_Storage;

      --  What this one quotes, and where it goes. Carried from the failure it
      --  was made from, so the two say the same thing.
      Detail         : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills          : Adash.Messages.Placeholder_Name := [others => ' '];
      Detail_Count   : Natural range 0 .. Max_Arguments := 0;
      Detail_Args    : Argument_Storage;

      Guidance       : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Has_Guidance   : Boolean := False;
      Related_Count  : Natural range 0 .. Max_Related := 0;
      Related        : Related_Storage;

      --  The order this diagnostic was emitted in, kept so that Sort is stable
      --  without the sort itself having to be. Two diagnostics identical in
      --  every other key come out in the order they were found.
      Sequence : Natural := 0;
   end record;

   package Diagnostic_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Diagnostic);

   type List is tagged limited record
      Entries : Diagnostic_Vectors.Vector;
      Emitted : Natural := 0;
   end record;

end Adash.Diagnostics;

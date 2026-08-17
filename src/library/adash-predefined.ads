with Adash.Language.Scopes;
with Adash.Language.Types;
with Adash.Messages;

--  What exists before a program declares anything.
--
--  The type names, the Boolean literals, and the subprograms a script can call
--  without writing them. This package owns all of it, and owns the *metadata*
--  as well as the entities: a predefined subprogram is not just a name in a
--  scope but a signature the semantic pass checks calls against, a
--  documentation key, and a description for completion to show.
--
--  Registration is explicit and its order does not matter. The table below is
--  read in one direction to install names into a scope and in another to
--  answer "what is this?"; nothing depends on which entity was registered
--  first, so a table reordered for readability cannot change behaviour. Tests
--  assert that.
--
--  Metadata is not optional decoration. A predefined function without a
--  recorded signature cannot have its calls checked; without a documentation
--  key it cannot be written about; without a description key it appears in
--  completion as a bare name. Each is a field here rather than a convention
--  somewhere else, so adding an entity without them fails to compile.
package Adash.Predefined is

   package Types renames Adash.Language.Types;

   --  Every predefined entity, by stable identifier.
   --
   --  The identifier is what other subsystems refer to. Names are what users
   --  type and could in principle be spelled differently in a future locale of
   --  the language; identifiers are not.
   type Entity_Id is
     (
      --  The types. Names denoting a type rather than a value.
      Entity_Boolean,
      Entity_Integer,
      Entity_Float,
      Entity_Character,
      Entity_Task_Id,
      Entity_Clock,
      Entity_String,

      --  The Boolean literals, which are constants rather than keywords.
      Entity_True,
      Entity_False,

      --  Output.
      Entity_Put_Line,
      Entity_Put,
      Entity_New_Line,

      --  Reading something the shell knows. The first of these was the first
      --  predefined entity that yielded a value rather than consuming one:
      --  until it existed the language could obtain nothing from outside
      --  itself.
      Entity_Env_Value,
      Entity_Status,

      --  Running a program and reading what it wrote, as a value.
      Entity_Output_Of,
      Entity_Error_Of,
      Entity_All_Of,
      Entity_Last_Job,
      Entity_Output_Of_Pipe,
      Entity_Error_Of_Pipe,
      Entity_All_Of_Pipe,
      Entity_Argument_Count,
      Entity_Argument,

      --  Reading the shell's own input.
      Entity_Read_Line,
      Entity_Input_Ended,

      --  Asking about a path.
      Entity_Exists,
      Entity_Is_Directory,
      Entity_Is_Executable,

      --  Reading a file, which is what write_file's other half looks like from
      --  a script: text in, text out, and no program started to do it.
      Entity_Read_File,
      Entity_Current_Directory,

      --  Searching and shaping text.
      Entity_Index,
      Entity_Trim,
      Entity_To_Upper,
      Entity_To_Lower,
      Entity_Starts_With,
      Entity_Ends_With);

   --  What sort of thing an entity is.
   type Entity_Sort is
     (Sort_Type,
      Sort_Constant,
      Sort_Function,
      Sort_Procedure);

   --  Largest number of parameters a predefined subprogram takes.
   Max_Parameters : constant := 4;

   --  One formal parameter.
   type Parameter is record
      --  The name, for a named association and for completion to show.
      Name : Adash.Messages.Argument;

      --  What it accepts. Type_None marks a parameter that accepts any type,
      --  which Put_Line does -- it images whatever it is given.
      Of_Type : Types.Type_Kind := Types.Type_None;
   end record;

   type Parameter_List is array (1 .. Max_Parameters) of Parameter;

   --  Whether an entity can be used in this build.
   --
   --  An entity may be registered and not yet runnable: the lowering grows
   --  faster than the registry can be rewritten, and a user is better told
   --  "not in this build" than "no such name".
   type Availability is
     (
      --  Usable.
      Available,

      --  Registered, and the lowering cannot emit a call to it yet.
      Not_Yet_Runnable);

   --  Everything known about one predefined entity.
   type Metadata is record
      Id : Entity_Id := Entity_Boolean;

      --  As a user writes it. Case-insensitive on lookup, like every Ada name.
      Name : Adash.Messages.Argument;

      Sort : Entity_Sort := Sort_Type;

      --  The type it denotes, for a type name; the type it yields, for a
      --  function; the type it has, for a constant. Type_None for a procedure.
      Of_Type : Types.Type_Kind := Types.Type_None;

      Parameter_Count : Natural range 0 .. Max_Parameters := 0;
      Parameters      : Parameter_List;

      --  How many of the last parameters may be left out.
      --
      --  Zero for everything that takes a fixed number, which is everything
      --  but the one that runs a program: `Output_Of ("git", "status")` names
      --  a program and gives it what arguments it needs, and a fixed count
      --  cannot say that. Ada would write it as defaults; this build has none,
      --  so the profile says how many may be dropped from the end.
      Optional_Parameters : Natural range 0 .. Max_Parameters := 0;

      --  True when calling it does something beyond producing a value. A
      --  shell needs to know: an expression that can be evaluated twice
      --  without consequence is one a completer may evaluate speculatively.
      Has_Side_Effects : Boolean := False;

      --  Where its documentation lives, and what completion shows for it.
      --  Message identifiers rather than text: this package holds no prose.
      Documentation : Adash.Messages.Message_Id :=
        Adash.Messages.Msg_Error_None;
      Description   : Adash.Messages.Message_Id :=
        Adash.Messages.Msg_Error_None;

      Status : Availability := Available;
   end record;

   --  How many entities are registered.
   --
   --  @return The count.
   function Count return Natural;

   --  One entity's metadata, by position.
   --
   --  Positions are for iteration only -- a listing, a documentation
   --  generator. Nothing may depend on the order.
   --
   --  @param Index Which entity, from one.
   --  @return Its metadata.
   function Entry_At (Index : Positive) return Metadata;

   --  One entity's metadata, by identifier.
   --
   --  @param Id The entity.
   --  @return Its metadata.
   function Describe (Id : Entity_Id) return Metadata;

   --  Find an entity by the name a user wrote.
   --
   --  Case-insensitive, as Ada names are.
   --
   --  @param Name The name as written.
   --  @param Id The entity, when this returns True.
   --  @return True when the name is predefined.
   function Find (Name : String; Id : out Entity_Id) return Boolean;

   ---------------------------------------------------------------------
   --  Profiles, across everything a program can call.
   --
   --  A program's callable names come from two owners: the language's own
   --  subprograms, registered here, and the shell's internal commands,
   --  registered in Adash.Commands. Semantics needs one question answered --
   --  "what does this name accept?" -- and asking two owners would mean two
   --  places to keep a check in step, so this package answers for both.
   --
   --  That makes this package the bridge between the shell's vocabulary and
   --  the language's scope, which is what it already was for types and
   --  constants. It does *not* make it the owner of commands: Adash.Commands
   --  still holds their metadata, and this reads it.
   ---------------------------------------------------------------------

   --  What a name accepts, whoever owns it.
   type Profile is record
      --  False when no callable of that name exists. Every other field is
      --  meaningless then.
      Known : Boolean := False;

      --  How many arguments are legal. The two differ for a command that takes
      --  one optionally -- `quit` with or without a status -- which a single
      --  count cannot express.
      Minimum : Natural := 0;
      Maximum : Natural := 0;

      --  The type of each position, up to Maximum. Type_None accepts anything.
      Types_Of : Parameter_List;
   end record;

   --  What a callable name accepts.
   --
   --  @param Name The name, matched case-insensitively as Ada names are.
   --  @return Its profile, with Known False when nothing of that name is
   --          callable.
   function Profile_Of (Name : String) return Profile;

   --  Whether a name is an exception this machine raises.
   --
   --  Not a predefined *entity*: an exception is not a value, cannot be
   --  declared, and is only ever named in a handler. It is here because this
   --  is where the language's own names live, and a handler naming something
   --  else is almost always a misremembered name -- one accepted silently
   --  would simply never run.
   --
   --  @param Name The name as written, matched case-insensitively.
   --  @return True when something can raise it.
   function Is_Exception (Name : String) return Boolean;

   --  Every exception this machine raises, for a caller that has to list them.
   --
   --  @param Index Which one, from one.
   --  @return Its name, or "" past the end.
   function Exception_At (Index : Positive) return String;

   --  Declare every predefined entity in a scope.
   --
   --  Called on the outermost scope before a program is analysed. Order of
   --  declaration does not matter and is not relied on.
   --
   --  @param Into The scope chain to declare into.
   --  @return True when every entity was declared; False when one collided,
   --          which would mean two entities share a name and is a defect in
   --          the table rather than in the program being analysed.
   function Install (Into : in out Adash.Language.Scopes.Chain) return Boolean;

end Adash.Predefined;

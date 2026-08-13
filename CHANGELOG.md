# Changelog

Notable changes to Adash. Format follows [Keep a Changelog](https://keepachangelog.com/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The sixteen planned phases are complete, and a second body of language and shell
work has followed them. `ROADMAP.md` carries both as tables; this file carries
what changed.

## [Unreleased]

### Added

- Repository bootstrap: Alire manifests for the `adash` binary crate and the
  `adash_tests` child crate, GPR project files, the directory layout, and
  `repository.toml` as the package inventory.
- `Adash` — root package and project identity.
- `Adash.Version` — product version and build identity, derived from the Alire
  manifest so that no Ada source contains a version literal.
- `Adash.Messages` — stable message identifiers, their catalog keys, their
  declared placeholder names, and structured arguments.
- `Adash.Messages.Rendering` — the presentation boundary: the only package that
  turns an identifier into text. Loads a catalog, applies locale precedence, and
  degrades to a deterministic fallback form that names the key when the catalog
  cannot answer.
- `Adash.Terminal` — Adash's style roles and colour policy over
  `terminal_styles`.
- `resources/messages/catalog.txt` — the message catalog, holding every
  user-visible string in the product and in the repository tooling.
- `adash` executable supporting `--help` and `--version`, reporting the
  interactive session as unavailable in this build.
- `adash_tests` — AUnit suite covering version derivation, message identifier
  uniqueness and well-formedness, catalog rendering, the degradation path,
  styling policy, and the repository checks themselves.
- `adash_check` — repository validation: required files and directories, version
  agreement between `alire.toml` and `repository.toml`, package inventory in
  both directions, catalog completeness for every message identifier, absence of
  hand-written terminal escapes, and absence of direct operating-system
  dependencies.
- Documentation set: `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`,
  `STYLE_GUIDE.md`, `SECURITY.md`, `ROADMAP.md`, `AI.md`.
- `Adash.Persistence` — where the shell keeps things and how it puts them there:
  atomic replacement under an exclusive lock, private permissions, and a
  distinct outcome for every way a machine can refuse.
- `Adash.Persistence.History` — durable history as one JSON string per line, so
  that an entry containing a newline survives a format that separates entries by
  newlines.
- `Adash.Configuration`, `.Files`, `.Migration` — a closed schema of settings
  read from TOML, where a bad file never stops the shell and an out-of-range
  value is refused rather than clamped.
- Conformance suite (`conformance/`, `adash_conformance`) — cases as TOML data,
  run against the built binary from the outside, comparing message identifiers
  rather than English.
- Verified examples (`examples/`) — each with the output it claims, checked on
  every test run.
- Benchmark harness (`adash_bench`, `benchmarks/README.md`) — median and fastest
  of N runs, with the methodology recorded beside the numbers.
- `docs/RELEASE.md` — the release checks, in order, and what is deliberately not
  claimed about reproducibility.
- Ctrl-C interrupts a running program instead of killing the shell. The
  machine asks a cancellation source between instructions, `Adash.Execution.
  Signals` records `SIGINT` rather than discarding it, and the interactive loop
  acknowledges it once the submission has ended so the next line does not start
  already-interrupted.
- `Hostkit.Signals.Can_Record`, `Arrived` and `Clear` — the recorded-signal
  contract. A handler sets one flag and does nothing else, because a POSIX
  handler runs between two instructions and a Windows console routine runs on a
  thread of its own; a flag is what is correct under both.
- Windows support for that contract, through `SetConsoleCtrlHandler`. It is the
  one capability Windows has here: `Is_Supported` remains False for every
  signal, and `Can_Record` is True for `Signal_Interrupt` alone.
- Subprograms a program declares for itself: `procedure P (A : Integer) is
  ... begin ... end P;` and the same with `return T` for a function.
  Parameters of any of the five types, local declarations, recursion, calls
  between bodies, and internal commands called from a body. `Node_Subprogram_
  Declaration` and `Node_Parameter` in the syntax, a parameter profile on
  `Adash.Language.Symbols.Symbol`, and one activation record per call in the
  lowering.
- Declarations carried from one submission to the next: a subprogram declared on
  one line is callable on the next, and a variable keeps the value it ended
  with. Redefining a name replaces it, a different profile adds an overload.
- `Adash.Language.Evaluation.Command_Sink.Keep_Value` — how a variable's value
  leaves the machine. The lowering emits one hand-back per top-level variable
  after the statements and before the halt, because the frame it lived in is
  gone once the interpreter returns.
- `Adash.Language.Values.Literal` — a value written as source this language
  reads back, which is what carrying one between submissions needs.
- The `history` command, which reports what this session has typed, optionally
  the last N. `Adash.Commands.History_Source` is the interface that lets a
  command read a log the interactive frontend owns.
- Abandoned session history files are swept up by the next session to start.
  `Adash.Persistence.History.Abandoned_Session_Files` finds them and an
  ownership lock held for a session's lifetime distinguishes a dead session
  from a live one -- asked by trying the lock, never inferred from the process
  id, which can be reused.
- `Adash.Persistence.Ensure_Container`, because taking a lock on a file in the
  store does not create the store the way reading and writing do.
- `history.per-session`: a session keeps its history in a file of its own and
  merges it into the shared file in one block when it ends, so two shells
  running at once no longer shuffle their commands together there.
  `Adash.Persistence.History` gained `Session_Path` and per-file `Load`,
  `Append` and `Save`.
- Long lines wrap in the interactive editor instead of scrolling sideways, which
  became possible once width was counted in cells: the row count is computable
  even though the terminal will not report it.
  `Adash.Interactive.Editing.Place` derives a cursor's row and column by
  walking the line exactly as the drawing does, because arithmetic is wrong both
  at a row boundary and on any row ending in a wide character.
- `Adash.Display_Width` — how many terminal cells text occupies. The
  interactive editor scrolls, slices and positions its cursor in cells, so a
  line containing wide or combining characters redraws correctly.
- `Adash.Messages.Rendering.Text` can render a message that quotes another, and
  `Adash.Commands.Line` can name the message it quotes. A subsystem below the
  presentation boundary may name a message and may not render one, so a line
  that has to say what another message says could not be expressed at all
  before this.
- Exception handlers, on a block and on a subprogram body:
  `exception when Constraint_Error => ...`, with `others` for the rest. A
  handler catches what a call raised however deep, and what nobody answers for
  is raised again rather than swallowed.
- `Adash.Predefined.Is_Exception` — the four exceptions anything here raises, so
  a handler naming something else is refused rather than never running.
- `Adash.Machine` — this repository's own virtual machine. A stack machine with
  frames, static links and one call out to the shell, whose instruction set is
  what the lowering emits and nothing else.
- `Adash.Filesystem`, and `Exists`, `Is_Directory` and `Is_Executable` in the
  language. Asking whether a file is there is the commonest conditional in a
  shell and could not be written at all.
- `Index`, `Trim`, `To_Upper`, `To_Lower`, `Starts_With` and `Ends_With`, as
  machine instructions rather than calls out to the shell. Ada spells these in
  packages -- `Ada.Strings.Fixed.Index`, `Ada.Characters.Handling.To_Upper` --
  and this language has no packages to spell, so they are named directly.
- `write_file (Text, Path)` and `append_file (Text, Path)`, with
  `Adash.Filesystem.Write` and `.Append` beneath them. Everything that wrote a
  file before this wrote what a *program* had printed, so a value the language
  itself computed had nowhere to go. Commands rather than functions: a question
  has no consequences and belongs in a condition, and writing has consequences
  and belongs where a reader sees it happen. A write that worked says nothing,
  because a command that announced each one would put its own lines into the
  script's output.
- A conformance case expands `{store}` to a directory made for it and emptied
  before it runs, in its expected output as well as its script, so a case that
  writes a file has somewhere to write that no earlier case has been in.
- `for I in reverse L .. H loop`. Ada's spelling, in Ada's position between
  `in` and the range. The bounds are still evaluated left to right as written:
  going backwards changes where the counting starts, not what order the two
  expressions run in. A null range runs the body no times whichever way it is
  walked, and the step is taken only after the test says there is another turn
  -- so a loop reaching `Integer'First` stops rather than wrapping.
- **`requeue Later (Which);`** -- a caller may be moved to a member of a
  family, of a task's entries or a protected object's. Either end may be a
  member: where the caller was taken from and where it goes are two numbers,
  each computed the way its own entry needs, so the instruction carries neither.
- **Protected entry families.** A protected entry's body is one routine with
  one barrier, so a family of them is one routine taking which member it is
  running for -- `entry Pass (for Which in Level) when ... is` -- and the
  barrier can ask which. Each member has a queue of its own, and opening one
  says nothing about the others.
- A protected entry says which queue it joined from a number the body computes,
  rather than one written into the instruction, which is what lets one body
  serve a whole family.
- A `requeue` naming a family is refused: Ada writes `requeue Later (Which);`,
  and a member is spelled with parentheses that the target of a requeue has no
  room for here.
- **Entry families.** `entry Request (Priority);` declares one entry per value
  of Priority, and a caller says which by writing `Request (High)`. An acceptor
  can serve one member and leave the rest queued, which is a task deciding what
  to serve and not only when.
- A member's number is the family's own plus which member it is, and which
  member is a value the program computes -- so the instructions that name an
  entry take it off the stack when it is a family's, and a family reserves as
  many numbers as it has members.
- `E'Count` asks its entry from the stack now, which is what let a member of a
  family have a count of its own without a second spelling of the question.
- `Types.Admitted_Count` answers how many values a constraint lets through,
  where `Value_Count` answers for the type. A run indexed by a subtype is as
  long as the subtype admits; a case over one still has to cover the type, which
  is a separate question and stays where it was.
- **A `select ... then abort` trigger that is a protected entry call is
  cancelled** when the abortable part finishes first. It was parked at the
  barrier and nothing released it, so the run reported that every task was
  waiting for something no task would do -- the release path knew about callers
  queued at a *task* entry and not about one parked inside a protected entry's
  own body. Cancelling one is returning from that body without running it,
  which is the same unwind a return does; the entry's body never runs and its
  queue is empty again.
- **`requeue E;` and `requeue E with abort;`**, for a task entry and a
  protected one. The caller being served is put on another entry's queue and
  the body it was being served by is left; the caller does not resume and is
  not told, which is what makes a requeue different from returning and being
  called again.
- The two kinds of queue are joined differently and so are moved between
  differently. A caller of a task entry is a strand parked in a queue, so
  moving it is writing down which queue it is in; a caller of a protected entry
  queues by being *inside* that entry's own body, so moving it is a tail call
  into another body, keeping the place the call came from.
- `with abort` is accepted and means the same as leaving it out, because
  nothing here can cancel a queued call. Said rather than left to be
  discovered.
- **Discriminants may default**, on a task type and on a protected type alike,
  and a type whose discriminants all default is one an object may stand without
  a constraint on. All of them or none of them: a constraint constrains the
  whole of a type, and a partial one would leave a program saying which ones it
  meant to leave out by counting.
- A default is analysed where the *type* stands rather than at each object,
  because it belongs to the type: what a name in one means is settled by what
  is in scope where the type was written, and a default that does not fit what
  it defaults is reported there rather than at an object that never mentioned
  it.
- **Protected type discriminants.** `protected type Capped (Limit : Integer)`
  takes at elaboration what a subprogram takes at a call, and an object gives
  them where it is declared. They arrive as constants at the head of the
  object's own body -- which is what a discriminant is here -- so a barrier may
  be written against one and nothing below the analyser had a new idea to
  learn.
- **A constant member comes back by being elaborated, not by being handed
  over.** What declares one is the body it stands in, and that is carried
  between submissions as text and elaborated again. Handing it over was an
  assignment to something that cannot be assigned to, so a constant declared
  inside a protected body was lost the moment a second submission wanted it.
- **Protected types.** `protected type Counter is ... end Counter;` declares a
  type whose objects each have state and a lock of their own. An object is made
  by copying the type's declaration and body with the type's name replaced by
  the object's -- what a generic instantiation here already does -- so nothing
  below the analyser had to learn what a protected type is.
- A slot and a routine are keyed on the name a declaration introduced as well
  as on where it was written. Copies keep the span they came from on purpose,
  so a diagnostic about one points at the source the reader has to look at:
  keying on the position alone gave two objects one set of state and one set of
  operations between them, and every call reached the first object's.
- An object of a protected type is carried between submissions as the
  declaration it was written as, so the next submission declares it again and
  its state comes back into it. Kept as a *value* it was lost with the name,
  because a protected object has no value.
- **A member may be called what the shell calls something.** `Holder.Put` is
  one name with a dot in it, and nothing that resolves `Put` can reach it. It
  was refused as a clash -- for a protected object written out in full as much
  as for an object of a type -- because the check read the member's simple name
  where the whole name is what is declared.
- **A type name written where a value belongs is reported as what it is.** It
  said the type was *not* a type, which is the complaint a misspelled type mark
  gets and reads as nonsense: `Counter.Bump` for a protected type Counter is a
  program that wants an object.
- **`E'Count`**, for a task's entry and a protected object's alike. The two
  queue in different places -- one waits for a rendezvous, the other on a
  barrier -- and the attribute is the same question about either.
- A strand is in a protected entry's queue from the moment it asks until the
  moment it is through the barrier, which is longer than it is asleep on one:
  leaving the object wakes everyone waiting so that each asks again, and a
  count that only saw the sleepers reported an empty queue at exactly the
  moment the queue was being served.
- `E'Count` is refused outside the body that declares the entry, by name and
  where it is written, rather than answered with a number about the wrong
  strand.
- An entry written as an attribute prefix is no longer analysed as a call to
  it: `Put'Count` reported that Put takes one argument and was given none,
  which is a true statement about a call nobody wrote.
- **A call to a task entry can be bounded**: `select E; ... or delay D; ...
  end select;` no longer refuses when `E` is a task's entry. The call joins the
  queue carrying a deadline, and when the deadline passes the caller leaves the
  queue and the select takes its other branch. A rendezvous begun in time runs
  to its end -- Ada cancels a call that has not *started* -- and a caller past
  its deadline is no longer there to be taken, so an acceptor that arrives late
  finds the queue empty. The scheduler counts a caller waiting a bounded time
  as waiting for the clock, so such a program is not called stuck a moment
  before its wait runs out.
- The roadmap's list of attributes said nine and named the nine the language
  had before it gained tasking; there are seventeen, and the paragraph now
  names them, says which are refused where, and says plainly that `'Size` and
  `'Storage_Size` answer in this machine's own unit rather than in bits.
- **The stale-claim sweep reached the examples.** Their code is run by the
  conformance suite; their prose is not, and three claims had drifted:
  `subprograms.adash` said this language does not overload on what a function
  returns (it does, and the example now shows two functions differing only in
  that); `types.adash` called eight attributes every one a discrete type has
  (seventeen exist, and `'Size` answers for any type); and `case.adash` said
  `'Image` was the only attribute this build has, where what actually keeps
  `Integer'Last` out of a case choice is that an attribute is not read as
  static. Everything else the examples claim was probed and holds.
- **An aggregate names its parts by index, and `others` answers for the rest.**
  `(1 => 7, 2 => 8)`, `(1 => 1, others => 0)` and `(others => 5)` build an
  array; `others` fills a record too. Every part still gets exactly one value:
  a missing part, a repeated one, an index the array does not have, and an
  `others` that answers for nothing are each refused by name, and the count
  check now runs over what was covered rather than over what was written.
  Indices are known before the program runs, and an array that begins at zero
  names its first part zero.
- `examples/types.adash` said records and arrays were deliberately absent. They
  are in `examples/records.adash`, which now shows the new forms as well.
- **`abort T, U, V;`** names several tasks and stops all of them. They travel
  as one instruction rather than as several statements, because being handed
  `Tasking_Error` resumes a caller: telling one between two aborts would let it
  run while a task the same statement names is still going. Every name answers
  for itself, and a non-identifier after `abort` is now told it wanted the name
  of a task rather than the name of a package.
- **A program declares its own exceptions and raises them.** `Wrong_Kind :
  exception;` declares a name, `raise Wrong_Kind;` raises it, a handler naming
  it catches it, and `raise;` inside a handler passes on what that handler
  caught. The five the machine raises for itself may be raised by name too. An
  exception has no type, no value and no storage -- what it is is a name, which
  is what a raise and a handler have always agreed on, so the existing
  text-comparison mechanism did the work. A program's own exception carries no
  detail, and the declaration is carried between submissions the way a type is.
  Not `raise ... with "a message";`: nothing here can read one back.
- The sweep continued into the prose around those lists and found two more
  contradictions, both in the section that describes what the language does
  now: `ROADMAP.md` said this shell does not have persistence -- a definition
  typed on one line and used on the next -- sixty lines after describing the
  mechanism that gives it, and explained the hand-back's design by what HAC's
  interpreter did not offer, a dependency that ended. Both corrected, and what
  a session carries is now pinned by cases rather than described: a protected
  object keeps the state it ended with, a task object is not carried.
- **A sweep of the documented limits against what the build actually does.**
  Every claim in `ROADMAP.md`'s two "cannot do yet" lists was probed rather
  than read. Five were stale and are corrected: aggregates exist (positional,
  and named for a record) where the list said none did; a discriminant may have
  a default; `'Length` answers for any array and not only a `String`;
  `README.md` still listed generics and aggregates among what the subset leaves
  out and still said a record "would need a compiler"; and the array half of
  the attributes paragraph had survived its own correction two entries above
  this one. Nothing else in either list had drifted.
- **A range loop counts over any discrete type.** `for What in Failed .. Killed
  loop` and `for C in 'a' .. 'z' loop` are written; the range form used to
  insist on Integers. What it counts over is what its bounds are, and the
  bounds settle each other as a comparison's operands do.
- **`'First` and `'Last` on a subtype mark answered with the base type's
  bounds.** `Percent'First` was Integer'First -- a value the subtype refuses --
  and a loop over `Small'First .. Small'Last` counted from the bottom of
  Integer. They are the subtype's own now.
- **A membership settles an open value from its bound**, the way a comparison
  settles one operand from the other: `Red in Amber .. Amber` picks the type
  the bound belongs to. Comparisons already did this for calls and now do it
  for literals as well, so `Red = Amber` reads as Ada reads it.
- Where the context expects a type none of a name's declarations has, the
  diagnostic is the ordinary mismatch against what was expected rather than an
  ambiguity -- and a range loop, which counts Integers, now says that to its
  bounds instead of leaving them to be puzzled over.
- **Enumeration literals overload.** Two types may each name a `Red`, and
  which is meant is what the context expects -- an object's type, either side
  of a comparison, a case's type, a loop's, what a subprogram takes, a type
  mark's own attribute. A literal is a parameterless function returning its own
  type, so it overloads like one and is resolved like one. Two of one type are
  still a redeclaration, a variable of the same name still collides, and a name
  the shell provides is still refused. Where nothing says which type is meant,
  the use is refused as a value of several types rather than settled by
  whichever was declared last.
- **A timed call to a protected entry queues instead of polling.** It used to
  take the lock, ask the barrier, let go, sleep the whole of the delay and ask
  again -- so a barrier that opened during the wait was taken only when the
  wait ended. The call now waits the way an ordinary one does, parked at the
  barrier inside the entry body, and the deadline reaches it there: taken when
  the barrier opens, and given up on otherwise by leaving the body without
  running it, which takes the caller out of the entry's queue. The conditional
  form still asks under the lock, which is exact.
- **A caller wakes a select that is waiting.** `select ... or delay D;` waits
  for a caller or the clock; this machine slept the whole of D and looked
  afterwards, which cost latency and made a task asleep in its own wait look
  like a task waiting for nobody -- so a conditional call to one was refused
  where Ada would take it. The select's wait is now a delay a caller may cut
  short, what it is open for stays written down across the wait, and an
  arriving call wakes it. The waking forgets what it was open for, so a second
  conditional caller is told no rather than queued behind a rendezvous that is
  already going to happen. The clock still ends the wait when nobody comes.
- **`or terminate;`**, the alternative that lets a server task end. It is
  taken when the master the task depends on has finished and every task
  depending on that master is either over or waiting at one of these -- the
  scheduler decides it, at the one moment the question has an answer, and
  sends each willing task to the same `End_Task` that ends any task body.
  Anything still able to call keeps them all alive; two servers that could
  call each other end together. A guard closes it like any other alternative,
  and `terminate;` elsewhere, twice, or beside a delay or an `else` is refused.
- **`Tasking_Error` can be handled.** The machine raised it -- calling a task
  that has ended, and a task ending while somebody is queued at one of its
  entries -- while a handler naming it was refused as not an exception. A
  program could be given an exception it had no way to catch. The list a
  handler may name is now exactly the list the machine raises.
- **`requeue E with abort;` now means something.** The flag was parsed and
  never read, which was harmless while no call could be cancelled out of a
  queue and became a false claim as soon as a bounded call to a task entry
  could. Without `with abort` the requeued call is uncancellable: the deadline
  a timed call was made with stops applying, and a trigger abandoned by its
  abortable part can no longer be pulled out. With it, both still work. A
  requeued call is also un-met again, so a bounded call is answered by the
  rendezvous that actually serves it.
- **A call to a task entry can be conditional**: `select E; ... else ... end
  select;` makes the call only if a rendezvous can start at once. A task
  waiting at an accept now records what it would take -- the offer pass built
  for the queuing policy writes it down, and a plain accept says it the same
  way -- so what a conditional call asks has an exact answer, guards included.
  A call that cannot start is not made at all, leaving nothing queued at the
  task. A task asleep inside `select ... or delay D;` is waiting for nobody
  while it sleeps, which is this machine's stated latency deviation and is
  written down as a case.
- A select may offer at most `Max_Offers` alternatives at once -- thirty-two --
  and one with more is refused where it runs rather than answered wrongly.
- **`pragma Queuing_Policy (FIFO_Queuing | Priority_Queuing);`**, which says
  how callers are taken off an entry queue: the order they arrived in, or the
  highest priority first and the order they arrived in among equals.
- **A selective accept serves its best caller.** Under `Priority_Queuing` the
  alternative served is the one whose queue holds the caller who comes first,
  rather than the one written first: the alternatives are offered to a choice
  after the guards are asked and before any is tried, and only the entry the
  choice settled on may take a caller. Ties keep the written order, and a
  closed guard offers nobody. Under order of arrival the choice stays the one
  written first, which is what Ada leaves arbitrary there.
- **An entry queue now has an order.** A caller of a protected entry takes its
  place where it joins the queue, and an open barrier is no longer a turn: a
  strand goes through only if nobody queued at that same entry is ahead of it.
  Everything waiting is still woken and still tests its own barrier -- what is
  added is that the queue's order survives the waking. Before this, whoever the
  scheduler ran first went through, which was not `FIFO_Queuing` and not
  `Priority_Queuing` either.
- **`pragma Priority_Specific_Dispatching (P, First, Last);`**, which gives a
  dispatching policy to a range of priorities rather than to the whole program:
  the strands doing the important work can be left alone while the rest are
  shared out. Whether a turn ends at the quantum is now asked of the priority
  the running strand is at, which is where the pragma's meaning lives. Two
  pragmas giving one priority two policies are refused -- including
  `pragma Task_Dispatching_Policy` and `pragma Profile`, each of which answers
  for every priority -- while saying the same thing twice is not a conflict.
- **`pragma Profile (Jorvik);`**, which Ada defines as Ravenscar with four
  things given back: `Simple_Barriers` becomes `Pure_Barriers`, and
  `No_Relative_Delay`, `Max_Protected_Entries => 1` and
  `Max_Entry_Queue_Length => 1` are dropped. Everything else it keeps.
- **`Pure_Barriers`**, the restriction Jorvik needs and a `pragma Restrictions`
  can name on its own: a barrier may be worked out so long as working it out
  cannot do anything and cannot fail -- no call, and no operation that raises.
- A barrier that is a function called without parentheses is now refused under
  `Simple_Barriers` as well. It is a name to the parser and a call to everybody
  else, so what the name denotes is what decides, and the stricter restriction
  cannot admit what the relaxed one refuses.
- **`pragma Profile (Ravenscar);`**, the name for all of it said at once: the
  restrictions this language can be held to, the blocking check, and both
  policies. Read where the restrictions are, so a program that names the
  profile and one that writes the pragmas out run the same way. `No_Delay` is
  not part of it -- Ravenscar gives up a delay for a length and keeps one until
  a time -- and `Max_Task_Entries => 0` means its tasks talk through protected
  objects rather than by rendezvous. Every other name is refused.
  Worth knowing before writing it: `No_Task_Termination` makes a task that ends
  an error, and a submission ends, so a Ravenscar submission finishes by
  reporting the task that ran out.
- **The Ravenscar policy pragmas.** `pragma Task_Dispatching_Policy
  (FIFO_Within_Priorities);` gives a strand its turn until it waits for
  something instead of the fixed number of instructions the machine otherwise
  shares out -- Ada's policy on one processor, and an interleaving a reader can
  follow. `Round_Robin_Within_Priorities` names what happens when nobody says.
  `pragma Locking_Policy (Ceiling_Locking);` is accepted because it is what
  this machine already does. Every other policy is refused rather than accepted
  and ignored, because a policy is a claim about how a program runs.
- **Most of the Ravenscar profile.** `No_Relative_Delay`,
  `No_Dynamic_Priorities`, `No_Local_Protected_Objects`, `Simple_Barriers`,
  `No_Task_Termination`, `Max_Task_Entries`, `Max_Protected_Entries` and
  `Max_Entry_Queue_Length` join the six already there. What the profile is for
  is that a program giving all of this up can be reasoned about: what runs,
  what it waits for and how much of it there is are settled where the program
  begins.
- Restrictions naming things this language does not have -- allocators, heap,
  interrupts, timing events, library dependencies -- are refused as unknown
  rather than accepted and ignored, because one nobody checks is worse than
  none.
- **`No_Task_Hierarchy` and `Max_Tasks => N`.** The first says every task is
  declared where the program begins, checked where a task stands because that
  is where its master is decided. The second is the one restriction that
  carries a number and the one counted while the program runs -- what a loop
  starts is not something a reader can count -- and "at once" is what it
  counts, so starting tasks one after another stays within it.
- A restriction may take a value, written the way this language already writes
  a named argument.
- **`pragma Restrictions`**, with `No_Abort_Statements`, `No_Delay`,
  `No_Select_Statements` and `No_Requeue_Statements`. A program says what it
  will not do and the analyser holds it to it, wherever the pragma stands --
  a configuration pragma is about the whole program, so what it says is read
  before the first statement is looked at.
- A restriction name this language does not know is refused rather than
  ignored: one nobody checks is worse than none, because a program would be
  told it had given something up and go on doing it.
- **`pragma Detect_Blocking` and blocking-operation checks.** An operation that
  may wait, run inside a protected operation, raises Program_Error when the
  program asked for the check. A strand set aside while it holds a lock is
  holding it against everybody.
- The list of what counts is asked in one place, once per instruction, because
  what makes an operation blocking is not something each of them has to say
  about itself. An entry's own barrier and a requeue are not on it.
- **`Clock`, `delay until` and `T'Execution_Time`.** The seconds on the
  session's own monotonic clock, an absolute delay that takes one, and how long
  a task has had turns for -- which is not how long it has existed.
- A predefined function the machine answers itself is answered the same whether
  the program wrote its parentheses or not. `Clock` without them was asked of
  the shell, which does not have one, and what came back was not a number.
- **Dynamic priorities.** `X'Priority := N;` changes what a task runs at or
  what a protected object may be called by, while the program runs -- the one
  attribute a program may assign to.
- A ceiling lives with its object rather than in the instruction that takes its
  lock, because a program may change it and every operation has to be asking
  the same question. Reading `'Priority` asks the machine rather than the
  declaration, which would be answering about the past.
- **A priority model.** `pragma Priority (N);` says what a task runs at, and a
  strand of higher priority is preferred whenever the machine chooses which
  runs next. Among equal ones nothing changes, so a program that mentions no
  priorities interleaves exactly as it did.
- The same pragma on a protected declaration is its ceiling, and a task above
  it that calls one of its operations is told rather than let in.
- `'Priority` reads either back, and `pragma` is the one this language has --
  any other name is refused, because a mechanism that took any would be a
  second place to configure things.
- **`'Size` and `'Storage_Size`**, in slots -- this machine's own unit, where
  Ada counts bits and storage elements. A slot holds a value of any type, so
  either of Ada's counts would be a number nothing here means.
- An object of a protected type takes the run of slots its body declares, which
  the analyser answers because it is the pass that has been through that body.
- `'Size` was the example the tests used for an attribute no type has. It is
  one a type has now, so the example is one it still does not.
- **`T'Identity` and `Task_Id`.** Which task, as something a program can hold
  and compare. An identity answers the same two questions a task does, and it
  has a type of its own because a task cannot be copied.
- **A task and a protected object are limited**, which is Ada's word for what
  cannot be copied: what one is is the thing that runs or the state that is
  shared. `B : Worker := A;` was accepted and started a *third* task where the
  program meant to name the first.
- **Two tasks compare equal when they are the same task**, and not otherwise. A
  cell with no discrete value answered zero and zero equals zero, so every task
  was every other -- which no program would have noticed until it asked.
- Neither a task nor an identity of one is handed back between submissions.
  There is nothing to hand it back as: a value is carried as the text a program
  could have written, and a task has no such text, so it was carried as nothing
  and the next submission read a missing expression.
- **`T'Terminated` and `T'Callable`.** Ada's two questions about one task, and
  not each other's negation: a task that has run its body out and is still
  waiting for what depends on it has completed without having terminated, and
  answers False to both. A strand now records that its body has been run out as
  well as that it is over, which is the whole of the difference.
- An attribute whose type could not be determined no longer makes the
  expression around it complain as well. `Boolean'Image (X'Terminated)` for an
  X that has no such attribute said "expected Boolean, found " with nothing
  where a type name belongs, which is the cascade this pass exists to avoid.
- **An exception that leaves an accept body reaches the caller.** Ada re-raises
  it at the point of the entry call and releases the caller; before, the
  acceptor handled its own failure and the caller waited for a rendezvous that
  had already ended, until the run reported that every task was waiting for
  something no task would do.
- It is *carried* rather than raised. The caller is not running when the accept
  body fails -- it is set aside in the rendezvous -- and what is set aside
  cannot raise, so the exception waits with it and is raised where it resumes:
  the point of the call, the same place a caller would have raised it had the
  entry been a procedure. Its `out` argument keeps what it held, because the
  accept body never completed the write.
- **An exception completes what it leaves.** A raise on its way out of a block
  or a body waits for that master's dependents before the handler runs, and a
  raise that leaves several masters at once waits for all of them. The handler
  now sees what the abandoned block started, where it used to run beside it and
  the wait happened when the enclosing region completed.
- The unwind itself cannot wait -- it is reached from inside whatever raised,
  and waiting means giving up the turn -- so the wait stands where the unwind
  *lands*, which is the same moment from the program's point of view and a
  place a strand can be set aside from.
- A handler in the block that raised is the other side of the rule: the
  exception never left, so the block has not completed and its dependents are
  waited for at its end rather than before the handler.
- **An accept body is a master.** What a rendezvous started is finished with
  before the rendezvous completes -- the wait stands before the caller is let
  go, which is what a caller is entitled to assume of one. Ada makes an accept
  body a master for what an allocator creates in it; here what makes the rule
  worth having is that this language accepts a declaration wherever a statement
  may stand, so a task can be written in one at all.
- An accept body may hold a body at all, which it could not: the same gap a
  block had, and the same walk over statements closes it.
- **A name inside a body resolves outward through the enclosing prefixes**,
  innermost first. Trying only the innermost and the bare name left everything
  between them unreachable: a task declared inside a task body could not read
  that body's own variables, because they are declared under the outer body's
  name and the lookup was under the inner one's. It reported them undeclared,
  which was a true statement about the wrong scope.
- **A block statement is a master.** Ada makes one, and it is how a script says
  "start these, and do not go on until they are done" without writing a
  subprogram to hold them. A block makes no frame, so each is a numbered
  *region* of its frame -- numbered rather than counted, because a depth would
  make the second turn of a loop look like the first.
- A region waits for its own dependents and for every region opened inside it,
  which is what answers for a block an exception jumped out of before it could
  wait for its own.
- Falling off the end is not the only way out of a block. An `exit` completes
  however many of them stand between it and the loop; a `return` completes them
  all by leaving the frame.
- **A block may hold a body at all.** Bodies are found by walking declarative
  parts and a block is a *statement*, so one written inside a loop or an `if`
  was never collected and the whole block was refused as something this build
  could not run -- naming a limitation rather than the gap it was. A task body
  or a subprogram declared in a block now works wherever the block stands.
- **The bound on strands is how many run at once, not how many a run may ever
  start.** A strand goes back to being nobody when the region that declared it
  has waited for it, which is the moment nothing can still name it. A loop that
  started a task on each of forty turns reported that the program had run away
  on the sixteenth.
- **A master is a region, not a submission.** A subprogram no longer returns
  while a task declared inside it is still running, and a task body does not
  end while one it declared is: Ada's rule at the granularity Ada gives it. A
  task is a dependent of the *frame* that was current when it started, which is
  the region the machine can see.
- It matters for more than order. A task reads what encloses it through a
  static link into that frame, and a master that returned first left it reading
  slots the next call had taken.
- The rule lives in the machine. Every way of leaving a region goes through an
  instruction -- falling off the end, an explicit `return`, a task ending --
  and one written at each of those would be the same rule three times over. A
  run that never started a task pays a single comparison for it.
- A region waiting for something that can never end is reported rather than
  hung on, like every other wait here.
- **`select ... then abort`.** Ada's asynchronous transfer of control: the
  abortable part runs as a strand of its own and the trigger -- an entry call
  or a delay -- waits in the strand that wrote the select. That is the shape
  this machine can give it and a faithful one: a strand that is not running
  cannot be in the middle of anything, so there is nothing to unwind when it is
  abandoned.
- Either side may win. When the trigger fires, the work is abandoned where it
  would next have run; when the work finishes first the trigger is cancelled --
  a queued entry call leaves the queue with nothing raised, and a delay ends
  there rather than waiting out its own reason to exist.
- A `then abort` trigger that is neither an entry call nor a delay is named as
  that, rather than as a name that failed to be an entry -- which for a
  statement with no name at all was a complaint about `?`.
- An abortable part is a routine that nothing names, found by a walk over
  statements rather than over declarative parts, because `select ... then
  abort` is a statement and may stand wherever one may. It is told from every
  other routine by the part itself: keyed on where it was written, it collided
  with the predefined names, which are declared nowhere and so at offset zero.
- **Task discriminants.** `task type Worker (Number : Integer; Label : String)`
  takes at elaboration what a subprogram takes at a call, and
  `First : Worker (1, "first")` is where they are given. They arrive the way a
  parameter does and sit where one sits, and they are constants in the body.
  Every one is given by position: a discriminant has no default here, and an
  object with one missing would run with a value nobody wrote.
- Discriminants belong to a task *type*. A single task is elaborated where it
  is declared and there is nowhere to write what it would take.
- A strand carries the whole chain of frames it was started inside, not one
  link into it. A static link is an index into a frame array and every strand
  has an array of its own, so a link handed over on its own pointed at whatever
  that index happened to be in the new array -- for a strand's first frame,
  itself. A task or an abortable part started inside a subprogram wrote its own
  slot where it meant to write the subprogram's, and the subprogram saw
  nothing.
- **Task types.** `task type W is ... end W;` declares a type whose objects are
  each a task of their own: their own strand, their own local state, their own
  entry queues. `A : W;` starts one where it stands, which is where Ada
  elaborates it, and a task type's body starts nothing -- it is what its
  objects run.
- A task is a *value*, and what it holds names the strand running it. That is
  what a rendezvous and an abort now name: several tasks share one body, so
  naming the work would name all of them at once. `task T is ... end T;` is the
  same arrangement written for one -- a type named after it, and an object --
  so everything below the analyser sees one thing rather than two.
- An entry is declared once, beside the type. `A.Go` is the object saying whose
  and the type saying which, and a name that is not an entry of the task is
  reported as that rather than as a component a task has not got.
- An object of a task type must have a body, asked at the object rather than at
  the type: a declaration whose body is still to be typed is the ordinary way a
  session gets one, and what cannot wait is an object, which starts running
  where it stands.
- A task type is carried between submissions, body and all, because a type is a
  template and starts nothing. A task *object* is not: the submission that
  declared it is its master, and Ada says a task does not outlive its master.
- **`select` with several alternatives.** `select accept A; ... or when Ready =>
  accept B; ... end select;` is a task saying "whichever of these happens
  first". Its alternatives are accepts, where the other `select` has an entry
  call -- one is a task deciding what to serve and the other is a caller
  deciding how long to wait, and the first word after `select` tells them
  apart, as it does in Ada.
- A guard says what the task is ready for. Guards are asked once, when the
  select is reached, and their answers are kept: an alternative that was closed
  then is closed for this execution however the world changes while it waits.
- `else` is what to do when nothing can be taken now; `or delay D;` bounds the
  wait, waiting the whole of D and asking again -- the same deviation a timed
  entry call makes. A select that says both, or says `or delay` twice, is
  refused: they are different answers to one question.
- A guard's answer is kept in a slot, and whether there *is* one is recorded
  rather than inferred from the slot's address. The first slot of a frame is
  address zero, and a task body's frame starts there because it has no
  parameters: a select in a body with no other local served every guarded
  alternative whatever its guard said.
- Waiting and taking are two instructions rather than one. One accept and a
  select over several do the same thing once a caller has been taken, and what
  differed was only how they waited; the machine has `Try_Accept` and
  `Await_Caller` where it had a single blocking accept.
- **Task entries and rendezvous.** `task Server is entry Put (Which : Integer);
  end Server;` with `accept Put (Which : Integer) do ... end Put;` in its body,
  and `Server.Put (5);` on the other side. The two are one event: the caller is
  set aside until an acceptor reaches the accept, the acceptor is set aside
  until a caller arrives, and neither passes until both have. Callers queue and
  the acceptor takes the one that has waited longest, which is Ada's rule.
- The arguments travel as a *place* rather than as values. The caller writes
  them into a run of its own slots and hands over where the run starts; the
  accept body's formals are references into it. That is the only arrangement
  that works when the two sides are separate strands with frames of their own,
  and it is what makes an `out` parameter come back -- the body writes where
  the caller is reading from.
- An accept is held to repeating the profile its entry was declared with. The
  caller writes its arguments by the entry's profile and the body reads them by
  the accept's, so an accept that disagreed would have one side writing a
  number where the other reads text, which no run-time check could recover from
  because both sides think they are right.
- A protected entry with parameters is refused. What carries an entry's
  parameters is the rendezvous, and a protected object has no strand of its own
  to be the second side of one; a parameter that was accepted and never given a
  value would have been read as whatever its slot held.
- A caller queued at an entry of a task that is *aborted* is handed the same
  answer as one whose task ran to its end, and after the abort has taken effect
  rather than before. It waited for something that would never happen and the
  run reported that every task was waiting.
- Calling an entry of a task that has ended raises Tasking_Error in the caller,
  where the call left off, so a handler around the call catches it as it would
  any other. It stopped quietly before, leaving the program abandoned in the
  middle of a statement with nothing said and a status of zero.
- A strand that ends while another is set aside at an entry, in a rendezvous or
  on a barrier now reports that the program cannot go on. A strand ending is
  the end of the run only when nobody is left waiting.
- A formal list is read in one place, and a subprogram and an entry ask it the
  same question. An entry call may name its arguments and leave out the ones
  with defaults, which it could not before: the entry's profile carried types
  and modes but no names and no defaults.
- A composite entry parameter is refused. The arguments of a rendezvous live in
  a run of the caller's slots, one slot each, and a composite is itself a run;
  it raised Constraint_Error out of the machine before, which is a defect
  rather than a diagnosis.
- `error.not_an_entry` no longer says "and a select waits on one". An accept
  names an entry too, and the clause was true of one of the two places that
  report it.
- **`delay`, `select` and `abort`.** `delay 0.2;` waits in real time from Ada's
  own monotonic clock -- monotonic rather than calendar, so a script that waits
  half a second waits half a second whatever somebody does to the system time.
  A delay that only yielded would make it a lie.
- The other strands run while one waits, and when none can the machine sleeps
  until the earliest deadline rather than spinning. Every sleeper's deadline
  counts, the current strand's included: a scan that skipped it slept past its
  own whenever another strand had a later one.
- `select E; ... else ... end select;` is Ada's conditional entry call. The lock
  is taken before the barrier is asked and nothing changes strand while it is
  held, so the barrier cannot close between being asked and being acted on --
  which is the whole difficulty of writing one.
- `select E; ... or delay D; ... end select;` bounds how long the call waits. It
  does *not* take the entry the moment it opens: it waits the whole of D and
  asks again, so the outcome is Ada's and the latency is not. Said here rather
  than left to be discovered.
- An entry has a symbol kind of its own, so `select P.Some_Procedure;` is
  refused by the analyser and named by what it is. It reported "cannot yet run"
  before, which reads as a gap in the language rather than as a decision.
- `abort T;` stops a task where the strand would next have run, which is the
  next switch point -- this machine interleaves rather than pre-empts, so there
  is no moment between two instructions at which to intervene, and none is
  needed because a strand that is not running cannot be in the middle of
  anything. An aborted task does not run its handlers, which is Ada's rule too.
- **Tasks and protected objects.** `task T; task body T is ... end T;` runs
  beside what declared it, and the declarative region that declared it does not
  finish until it has -- Ada's rule about masters, and what makes a task usable
  in a script: the script waits. `protected P is ... end P;` with procedures,
  functions and entries is how two tasks share what they touch.
- Interleaved rather than parallel. The machine runs one strand at a time and
  changes strand at defined points, on a fixed instruction quantum so that a
  program interleaves the same way on every machine and a conformance case can
  say what it printed. Ada does not require parallelism -- a single-processor
  implementation is conforming -- and what a program may rely on is that its
  tasks make progress and that its synchronisation holds.
- Interleaving rather than threads is also the only answer this repository can
  give: anything platform-specific belongs to hostkit, and a machine reaching
  for threads of its own would be a second provider of them.
- Mutual exclusion is not an optimisation on top of something else. The machine
  does not change strand while a protected operation is running, and that is
  the whole implementation.
- An entry is a barrier and a body. A strand that finds the barrier closed is
  set aside until the object is next left, and *re-evaluates* it when it wakes
  -- testing the old value again would answer the question it went to sleep on
  rather than the one that woke it. Every strand waiting for something no
  strand will do is reported rather than hung on.
- A task body carries handlers, which is where most of a task's belong: a task
  that failed silently is a task nobody notices, and there is no caller to
  report to.
- A protected object is state and is carried between submissions like a
  package. A task *declaration* is carried so that a body typed on the next
  line finds it; a task *body* is not, because a task cannot outlive its
  master and carrying the body would start the task again on every line after.
- **Packages.** `package P is ... end P;` and `package body P is ... end P;`,
  with `P.X`, `use P;`, and members that may be variables, constants, types,
  subprograms or generics. A submission is a unit here, and until this the only
  way to group declarations was to keep them in a file and `source` it -- which
  shares the text and not the name.
- A package is a naming convention the analyser keeps, and nothing below it has
  to know one exists: what a package holds is declared *beside* it under a
  dotted name, so `Config.Limit` is one symbol whose name has a dot in it and
  `P.X` is a way of spelling one. Nothing carries a scope, and the lowering
  sees ordinary declarations.
- A package body completes a specification the session is still holding, so the
  two may be separate submissions -- exactly as Ada makes them separate units.
- **Generics.** `generic type Element is private; procedure Swap (...);` with
  its body as a unit of its own, and `procedure Swap_Numbers is new Swap
  (Integer);`. Generic subprograms with formal types, which is what a shell
  script's generics are.
- A generic's body is not analysed where it stands: what every name in it means
  depends on what an instantiation binds. An instantiation *copies* it --
  `Adash.Language.Syntax.Graft`, a substitution on names in the tree rather
  than on source text -- because conclusions are recorded per node, and two
  instantiations sharing nodes would overwrite each other's answers about every
  name in the generic.
- **Records and arrays.** `type Line is record Number : Integer; Text : String;
  end record;` and `type Counts is array (1 .. 4) of Integer;`, with
  aggregates positional and named, component selection, indexing, whole-value
  assignment, component-by-component equality, and passing to a subprogram.
- A composite is its parts laid end to end in the machine's slots. That is the
  whole of how one works here: a variable is a run, and reaching into it is
  arithmetic on where the run starts -- `Offset_Place` for a component,
  `Element_Place` for an element after a bounds check, `Copy_Block` to assign
  one whole, `Same_Block` to compare two.
- What a composite is *made of* lives beside its identity, in
  `Adash.Language.Semantics`, and not in the type. A type travels inside every
  symbol and every parameter profile and those are copied constantly; a
  component list riding along would make every scope lookup carry the whole
  shape of every type in sight.
- A composite is passed by reference whatever its mode: a parameter is one slot
  and a composite is many, so what travels is where the run starts. An `out`
  parameter is how a program hands one back, which is also why a function
  cannot return one -- a result is what a call leaves on the stack, and there
  is nowhere for a run of slots to be left.
- A composite variable survives a submission, carried as the aggregate that
  rebuilds it. It is the one survivor that has to be *assembled* -- part by
  part, each in the form this language reads back -- because a composite has no
  single value on the stack. `Quote_Text` is what a String component needs:
  Ada's own image of a String is the text with non-graphic characters
  bracketed, and that does not read back.
- An index outside an array raises, on a read as much as on a write: an index
  past the end would hand back whatever the next variable holds.
- **Types a program declares.** `type Colour is (Red, Green, Blue);` and
  `subtype Percent is Integer range 0 .. 100;`. Until this the five built-in
  types were the whole model, and a script that meant "a colour, and there are
  three of them" had to say "an Integer, and I promise it is 0, 1 or 2" --
  a promise nothing checked, which is exactly what `case` coverage exists to
  check.
- `Adash.Language.Types.Type_Kind` is a private type rather than an
  enumeration: a *shape* -- which of the six kinds of thing it is -- and, for a
  declared type, an identity telling one declaration from another. Two
  enumerations with the same literals spelled the same way are two types, as in
  Ada, and the identity is what says so. Its `=` compares shape and identity
  and deliberately not the constraint, because a subtype *is* its base type and
  every "is this an Integer?" in the front end means that question.
- An enumeration's literals are `Symbols.Symbol_Literal`, a kind of their own
  rather than constants: a literal is its position and has no storage, and a
  loop parameter over the same type is a constant of it that does. Treating the
  two alike made every turn of a loop the first one.
- `'Pos`, `'Val`, `'Succ`, `'Pred`, `'First`, `'Last`, `'Image` and `'Value`
  for an enumeration, `case` coverage that names the type, membership, ordering
  by declaration order, and `put_line` writing the literal's own name. The
  literal names are interned in the program's text table, one contiguous run
  per type with the type's name on the end, so the instructions that need them
  carry two numbers and no table of their own.
- `for X in T loop`, Ada's other way of writing what to count over, for every
  discrete type and for a subtype -- which counts over what it admits rather
  than over what its base type holds. It counts in a slot of its own so that a
  `Character` loop can count 0 .. 255 while the variable holds a Character.
- A subtype's range is checked at the five places a value arrives: an object's
  initial value, an assignment, an argument entering an `in` parameter, a
  caller's variable after a call wrote back through it, and a function's
  result. The last is where Ada
  puts it too, and without it a variable would quietly hold a value it says it
  cannot. A value outside an enumeration subtype is reported as the name
  somebody wrote rather than as a position.
- An enumeration literal may be a parameter's default, carried as its position
  -- which is what a literal written at the call site pushes, so the two reach
  the machine by one path. A default is analysed before it is judged, so one of
  the wrong type is reported as the mismatch it is rather than as not being a
  literal.
- A declared type is carried across submissions as the source that declared it,
  the same road a subprogram takes, so an interactive session builds up a
  vocabulary of types as well as of subprograms.
- Named arguments and default parameters. `Report (Text => S, Loud => True)`
  names them and may reorder them; `procedure P (A : Integer := 1)` gives one a
  default that a call may leave out. Overload resolution reads the names, so a
  named argument is matched to the parameter it names rather than to the
  position it was written in -- without which the resolver would reject the
  candidate that fits and accept the one that does not.
  `Adash.Language.Semantics.Match_Arguments` answers which argument goes where,
  and both the analyser and the lowering ask it rather than keeping a second
  copy of the answer beside the tree.
- A default is a literal, possibly signed, or `True`/`False`. Anything else
  would have to be evaluated at each call in the scope of the *declaration*,
  and a name resolved at the call site is exactly what cannot do that. It is
  kept as the literal's own source text, so it reaches the machine by the same
  path a literal written at the call site takes.
- `'Pos`, `'Val`, `'Succ` and `'Pred` for the discrete types, and `'First` and
  `'Last` for every scalar type. `Character'Pos` and `Character'Val` are the
  only way to reach a character code, so until this a script could not write a
  tab outside an interpolated literal, compare against a byte value, or step
  from one letter to the next. `'Succ` and `'Pred` are a position, an addition
  and a position back -- which is what Ada defines them as -- so the check that
  going past the last value raises lives in one place rather than three. An
  Integer is its own position and the lowering emits nothing for either
  direction.
- `X in L .. H` and `X not in L .. H`, as `Adash.Language.Syntax.Node_Membership`
  with three children. The value is evaluated once and kept, because Ada
  evaluates it once and a lowering that compared the expression against each
  bound would run whatever is in it twice. Only the range form: Ada also writes
  `X in Integer`, and this language has no subtypes to name.
- A quoted message may carry arguments of its own, through
  `Adash.Messages.Rendering.Text` and `Adash.Diagnostics`. Until this the only
  quotable messages were ones with nothing in them, which is why the machine's
  `position 9 is outside a String of 3` could not be one.
- `adash_check` refuses a sentence written in Ada source. Two or more ordinary
  words inside a literal, outside a comment, with `in out`, `and then`,
  `or else` and `constant String` named as Ada's own spellings. The check has a
  fixture that fails it, because a check only ever run against a repository
  that passes is a check nobody has watched work.
- A conformance case expands `{root}` in its script as well as in its
  arguments, so a case can name a file in the repository and ask about it.
- `Integer'Value ("42")` and the same for `Float`, `Boolean` and `Character`,
  with `Integer'Image (N)` the other way. A program could read a line and had no
  way to turn a number in it into one.
- A type's attribute is recognised as the call it is, so `Integer'Size` reports
  an attribute no type has rather than `Integer is not a type`.
- `Read_Line` and `Input_Ended`, which read the shell's own standard input. A
  script at the end of a pipe had no way to see anything before this.
- `Adash.Execution.Streams` owns the buffer over standard input, and the
  interactive editor borrows from it. The editor's own buffer used to hold
  bytes a program was about to ask for, so a user who typed ahead had their
  answer read by nobody.
- A conformance case may supply standard input, for a script that reads it.
- `source` resolves a name through `Adash.Scripting.Modules`: a bare name is
  looked for beside the script doing the loading and then in the user's module
  directory, and a name with a separator in it is a path used as written. The
  resolution had been complete and tested since Phase 14 with nothing calling
  it, so `source ("greeting")` only worked when a file of exactly that name sat
  in the working directory.
- `Adash.Scripting.Loading.Innermost` — which script is doing the loading, which
  is what "beside" is relative to.
- A name that resolves to no file reports where the search went.
- `settings`, which lists the shell's settings with their values and what each
  is for, and changes one; and `save_settings`, which writes them to the
  configuration file. `Adash.Configuration` had carried the registry and
  `Adash.Configuration.Files.Save` the writing since Phase 13, with nothing in
  the shell able to reach either: a setting could be seen and changed only by
  editing TOML by hand.
- The settings live in `Adash.Commands.State` beside the environment, because a
  command changes them and the command layer has to be able to see them.
- `suspend` and `resume`, which stop a job and continue it.
  `Adash.Execution.Jobs.Resume_In_Background` had been complete and tested with
  nothing calling it, and nothing in the shell could produce a job for it to
  resume.
- `Adash.Execution.External.Wait` answers with four states rather than two:
  running, suspended, resumed, ended. A suspended program had been reported as
  "not finished", the same answer a running one gets, which left every layer
  that handled suspended jobs unable to see one.
- A failure may quote a message, as a command's output line already could, so a
  subsystem that knows a *name* for something can hand it over without turning
  it into text. `Adash.Execution.Message`, `Adash.Execution.Jobs.Message` and
  `Adash.Platform.Message` map a signal, a job state and a capability to the
  words that say them.
- `adash_check` refuses an identifier passed as a message argument: an `'Image`
  of anything but a number, or a literal written entirely in capitals, on a
  line that builds a named argument.
- The block statement, `declare ... begin ... end;`, with the `declare`
  optional. `Adash.Language.Syntax.Node_Block` had existed since Phase 5 and was
  handled by both later passes; nothing produced one, so a block could not be
  written. A statement before `begin` is refused, as Ada refuses it.
- A String can be taken apart: `S (2)` is the Character at that position,
  `S (7 .. 11)` is the String between two, and `'Length`, `'First` and `'Last`
  say how far it goes. Lowered to HAC's own `SF_Element`, `SF_Slice` and
  `SF_Length`, so an index past the end raises where HAC raises.
- `&` joins a String and a Character, either way round -- Ada's rule for an
  array and one of its components. Two Characters are refused, as Ada refuses
  them.
- `Adash.Language.Syntax.Node_Range` replaces `Node_Choice_Range`: a range is
  the same shape in a case choice and in a slice, and two node kinds would have
  been two names for one thing.
- `Output_Of`, which runs a program and answers with what it wrote to standard
  output, without the newline it ended with. A shell whose language could run
  programs could not read what any of them said before this.
  `Adash.Execution.Pipelines.Capture` reads the pipe to end of file before
  waiting, because a program that writes more than a pipe holds blocks until
  somebody drains it.
- `Adash.Execution.From_Start_Error` — the one place that turns a failure to
  start into 126 or 127. It was in the `run` family's body, and a second caller
  would have been a second copy.
- A predefined entity may take a variable number of arguments, which is what
  `Output_Of` needs: a program and what to give it. `Optional_Parameters` says
  how many of the last may be left out.
- A construct may be written across several typed lines. Each line was a
  submission of its own before, so `if C then` and `end if;` were two programs
  and neither was what was written. `Adash.Language.Parser.Wants_More` decides,
  by whether parsing ran out of input rather than met something unexpected --
  the distinction that keeps a mistake from leaving the user at a prompt that
  never comes back. `Adash.Interactive.Prompt.Continuation` had existed since
  the prompt did and was selected by nothing; it is what the second line is
  asked for with.
- The `case` statement, in all four of Ada's choice forms -- a value, several
  values, a range, `others` -- over Boolean, Integer and Character. Every value
  of the type must be accounted for, as Ada requires: the analyser adds up what
  the choices cover and refuses a gap, an overlap, an `others` that is not last,
  a backwards range, and a choice that is not decidable at analysis time. The
  value is evaluated once, into a slot of the frame.
- `Adash.Language.Types.Is_Discrete` and `Value_Count` — what a case can examine
  and how many values it has to account for.
- `Adash.Language.Semantics.Static_Choice` — what counts as a static choice.
  One implementation, asked by the analyser and again by the lowering: a choice
  the two disagreed about would be an alternative that silently never runs.
- `Argument_Count` and `Argument`, what a script was invoked with. The shell ran
  the script and discarded everything after its path before this, silently --
  `adash build.adash release` did the wrong thing and said nothing. Anything
  after the path belongs to the script, options included.
- Conformance cases can name a file in the repository, with `{root}` standing
  for where it is. Every case fed its script through standard input until now,
  so running a script from a file -- the way every user of a script runs one --
  had no case that did it.
- `Status`, what the last command did, as the one exit-status model reduces it:
  0, what an external program chose, 126, 127, or 128 + n. A command is a
  procedure, so a program could run something and had no way to learn whether it
  worked -- which is most of what a shell script does. It is a function rather
  than a variable because it is not assignable, and Ada writes a call to a
  parameterless function as a bare name, so the lowering answers a name as
  readily as a call.
- A second answer cell on the machine's stub, for an answer that is a number
  rather than text. A cell carries one type, and the type of what the shell
  answers decides which cell it travels in.
- `Env_Value`, the first predefined entity that yields a value. Until it
  existed the language could obtain nothing from outside itself. The answer
  returns through a by-reference parameter on the machine's stub, which is the
  same path command substitution would use.
- `pipe` and `pipe_run`, which build a pipeline a stage at a time and run it.
  `Adash.Execution.Pipelines` had supported several stages since Phase 11 and
  the shell contained one `Add_Stage` call, so every pipeline had exactly one.
- `run_into`, `run_append`, `run_new` and `run_from`, which attach a program's
  output or input to a file -- replacing it, adding to the end, refusing one
  that already exists, or reading. `Adash.Execution.Redirection` had been
  complete and tested since Phase 11 with nothing referencing it.
- `run`, which starts a program and waits for it. Running something took `start`
  and `wait` and a job number before. `Adash.Execution.Jobs.Forget` removes a
  foreground job without marking every other job reported.
- Job control from the language: `start`, `wait` and `stop`, and `jobs` now
  lists what the session has started. `start` is what creates a job at all --
  nothing else in this language runs an external program.
- A command call carries up to four arguments from a program, where it carried
  one. The stub the machine calls through gained a kind/number/text triple per
  argument.
- The `source` command, which runs a file in the session that called it, so
  what it sets outlives it. `Adash.Commands.Script_Runner` is the interface
  that keeps the command from having to reach the engine, and
  `Adash.Scripting.Runner` implements it.
- Separate subprogram specifications: `procedure P (N : Integer);` with the
  body further down, which is what makes mutual recursion writable. A body
  completes a specification and keeps its symbol, so calls written in between
  reach it. A specification never given a body is refused.
- A comparison settles an overloaded operand from the other one, so `if F = 1`
  resolves where it used to be reported as ambiguous.
- Overloading on result type. What the context requires now participates in
  resolution -- a declared type, an assignment target, a return statement, a
  parameter, a condition, and through parentheses and operators whose result is
  their operand type. A call nothing settles is ambiguous rather than resolved
  to whichever candidate came last.
- Overloading. One name may denote several subprograms, resolved by argument
  count and types. `Adash.Language.Scopes.Candidates` gathers what a name could
  mean and `Adash.Language.Symbols.Same_Profile` decides what counts as a
  redeclaration. Not resolved by result type, which would need an expected type
  pushed down into the expression.
- Nested subprograms. A body declared inside another reads and writes the
  frames enclosing it, up to nineteen levels; deeper is refused by name. Routines are now keyed by the declaration their name was
  written at rather than by the name, because nesting makes a name ambiguous.
- The rest of Ada 2022's interpolation escapes: `\" \n \t \r \a \b \f \v
  \0` alongside the braces and backslash. The set and each escape's value were
  determined by compiling them with GNAT and reading the result back rather
  than from memory.
- Interpolated string literals, `f"a{X}b"`, rewritten to concatenation. Three
  token kinds carry the pieces so the expressions are lexed in place and keep
  their spans; nesting falls out of the same mechanism. `\{`, `\}` and `\\`
  are the escapes this build defines, and any other is refused by name.
- The `'Image` attribute, for `Integer`, `Float`, `Boolean` and `Character`,
  emitted as HAC's own `SF_Image_Attribute_*` builtins so the text is Ada's.
  This is what string formatting was waiting for: a computed value can now go
  inside a sentence.
- Parameter modes: `in`, `out` and `in out`. The last two pass the caller's
  variable by address and write through it. `Adash.Language.Symbols` gained
  `Parameter_Mode`, and the lowering a distinction between a variable's address
  and a by-reference parameter's -- for the first the slot *is* the address,
  for the second the slot contains one.
- `Adash.Language.Symbols.Has_Profile` — whether a symbol carries a parameter
  list of its own, which is a different question from having no parameters.
  Without it every predefined name, all of which are in scope as symbols, would
  report as taking nothing and start rejecting its own arguments.

### Removed

- `alias`, which had been registered and unavailable since Phase 9. Within a
  submission a subprogram is already a checked, composable short name for
  something longer -- what its own documentation said alias was for -- and the
  three ways to build it each cost something the shell will not spend: textual
  expansion is a second command language, a dynamic name makes the analyser
  depend on session state, and a binding invoked by another command buys nothing
  the language does not already give. `ROADMAP.md` carries the reasoning.

### Changed

- **Adash no longer depends on HAC.** The lowering emits `Adash.Machine`
  instructions rather than HAC p-code, and the manifest no longer names the
  crate. The front end had grown to rival the compiler it replaced, and reached
  HAC's interpreter by building that compiler's own identifier and block tables
  -- a seam that produced defects rather than preventing them. See
  `docs/hac-assessment.md`.
- A program's output goes through the machine's own `Write`, `Write_Line` and
  `New_Line`, which is where the format-parameter counting per type went: the
  machine carries the type with the value, so there is no count to get wrong.
- `and`, `or` and `xor` are instructions rather than arithmetic on the 0 and 1 a
  Boolean used to be on the stack.
- The exception detail for an index past the end of a String, and for a function
  that ends without returning, is now this repository's wording.

- The machine's stub carries five value slots rather than four, so a command
  call may carry five arguments and a call answered by the shell four -- the
  latter spends its first slot on the name of what is being asked for.
  `Adash.Commands.Max_Parameters` moved with it; the two have to agree, and a
  command layer that accepted fewer would take the extra arguments off again
  without a word.

### Fixed

- **`adash_bench` printed its entire report in English**, and the repository
  tooling was never scanned for that. `adash_check` looked only at the shell
  crate's sources; the rule about user-visible text names release tools and
  test runners in as many words, and nothing had ever looked where they live.
  The benchmark harness and the conformance runner's own diagnostics go through
  the catalog now, and the check scans both trees.
- The prose rule allowed only letters and spaces, so a sentence with a full
  stop in it was invisible to it -- which is how `which is a defect rather than
  noise. See ...` survived the pass that introduced the rule. It counts words
  that contain a letter now, which also stops it firing on
  `Character'Val (27)`, the escape rule's own needle.
- `adash_bench` pointed at `benchmarks/README.md`, which did not exist. The
  document does now, as `docs/benchmark-guide.md` -- the name the docs index
  had been planning for it -- and says what the numbers are,
  what they are not, and what moved when the type model opened.

- A block's declarative part refused a type declaration. The list of what may
  stand before `begin` was written when the only answers were an object and a
  subprogram, and nothing had added to it since.
- A call written without parentheses -- `S;` -- to a subprogram whose
  parameters all have defaults refused itself. Written that way a call is a
  *name* rather than a call node, so the lowering had no prefix to ask what it
  resolved to and asked the name for its own first child, which a leaf has not
  got. The callee is handed to the emitter now rather than found from the node.
- **An `if` with two or more `elsif` branches had never parsed.** Each `elsif`
  hands the rest of the chain to the next one, which consumes the single
  closing `end if;` -- and then consumed a second on the way back out, so the
  statement asked for one `end if;` per `elsif`. One `elsif` worked, because
  the `if` above it returns rather than consuming, which is exactly what the
  `elsif` was missing. Found while writing an example: a function classifying
  an exit status is the commonest chain of that length anybody writes.
- **Four subsystems were writing English.** `Adash.Machine` said `the
  arithmetic does not hold` and `position 9 is outside a String of 3`; the
  parser said `an expression` and invented a token called `end of input`; the
  lowering said `a call with the wrong number of arguments` and thirty-three
  more; the settings said `true or false` and `a whole number`. Every one of
  those reached a user, none of those packages is a presentation boundary, and
  the rule has been that no user-visible string exists outside the catalog. All
  of them are message identifiers now, quoted into the message that reports
  them and rendered where everything else is. `adash_check` has a rule so this
  class cannot come back.
- The parser reported `expected ;, found end of input` when the input had
  simply ended — naming a token nobody typed, in English, in a file that may
  hold no English at all. It reports `expected ; here` now, which is what
  `Error_Syntax_Missing` had been declared for since it was written and what
  nothing had ever raised.
- The machine's working store — its operand stack and its slots, megabytes
  together — was a local of `Run`, and is on the heap now. It is also given
  back when a run ends rather than held between two typed lines.

- Waiting for a suspended job never returned. The host reports a stop once, so
  a blocking wait afterwards had no event left to return and waited for an
  ending a stopped program cannot reach. A suspended job is reported as
  suspended now, whether or not the caller can interrupt the wait.
- `stop` reported `this system does not support job control` whatever went
  wrong, discarding what the job table had said about it.
- `jobs` printed a job's state as the Ada enumeration literal -- `[1]
  JOB_RUNNING  sleep 30` -- for as long as `jobs` has existed. A terminated job
  was `ended by TERMINATE`, and a host that could not do something said `this
  system does not support JOB_CONTROL`; a program that would not start blamed
  `HOST_REFUSED` or `STREAM_SETUP`. All of them are identifiers where the
  catalog promises words, and none of them was translatable.
- `Node_Block` was handled as though it had one child in both the semantic pass
  and the lowering, so a block would have run its declarations and none of its
  statements. Neither could be noticed while nothing produced the node.
- A name declared in a block was handed back to the session and outlived the
  block by the rest of it. A block shares the frame and the level of the code
  around it, so the lowering counts the blocks it is inside rather than asking
  either.
- A comment in the lowering said String concatenation was refused, and stood
  directly above the code that emits it. It described a HAC defect that no
  longer reproduces.
- `end` was accepted-if-present rather than required for `if`, `while`, `for`
  and `loop`, so an unfinished construct parsed as a finished one with an empty
  body: `if C then` at the end of the input ran and did nothing, and `loop` on
  its own became a loop that never stops. Each now says which word it wanted.
- The argument of a call answered by the shell was pushed into the machine's
  text slot whatever its type, so the first such call to take a number --
  `Argument (I)` -- was refused by the machine rather than run. Which slot it
  travels in is decided by the argument now, as it already was for a command's.
- Declaring a name the shell provides was reported as "already declared in this
  scope, on line 1" -- a line nothing declared it on, and in a one-line
  submission the very line being complained about. `Error_Name_Is_Predefined`
  and its message existed and were reached only for a subprogram named after a
  predefined *subprogram*: never for a variable, a type name or a command.
  `Adash.Language.Symbols` records whether the shell put a name in scope, which
  is also the honest answer to why it has no position.
- `help` listed every command's name beside a blank where the summary belongs,
  and had done for as long as `help` has existed: the summary argument was the
  empty string in the source. A command may not render -- it produces
  identifiers and typed arguments, and an argument is text in its final form --
  so it now names the message that says what the command does, and the frontend
  renders that one into this one.
- The documentation of `run`, `run_into`, `run_from`, `run_append`, `run_new`,
  `pipe`, `pipe_run`, `start`, `wait` and `stop` was a lowercase fragment where
  every other command's is a sentence. Invisible until `help` began showing
  them side by side.
- A conformance case with a key the runner does not know asserted nothing and
  passed: `output_contains` instead of `output` reads as coverage and is none.
  Unknown keys are reported as malformed now, which fails the suite.
- A program that would not start answered 1, whatever was wrong with it.
  `Adash.Execution` documents 127 for not found and 126 for found and not
  executable, and `Adash.Execution.From_Start_Failure` decides between them --
  it existed, was tested, and was called by nothing in the product. `run`,
  `start` and `pipe_run` report it now. Nothing could observe the difference
  until a program could read `Status`.
- A command called inside a subprogram left the machine addressing the frame
  that had just been popped, so the first local read after it went through the
  wrong one. The stub every command call travels through is
  declared outermost, and a call to something declared further out has always
  needed that fix-up -- this was the one path that did not emit it. A command
  written as the last statement of a body hid the defect, because nothing read
  a local afterwards; `Env_Value` in a body's declaration made it immediate.
- The two cells the stub writes through were taken from whichever frame was
  being emitted when the first call needed them. A body has its own allocator,
  so a program whose only command call was inside a subprogram gave a body's
  offsets to an address read at the outermost level -- one of the submission's
  own variables. They are taken from the submission's frame before anything is
  emitted now.
- A call that yields a value is no longer accepted as a statement. Ada has no
  expression statement and neither does this: a user's function ran and had its
  result dropped without a word, and a predefined one was reported as a call
  this build cannot run, which named a limitation that does not exist. `X;` for
  a variable X went the same way and is reported as what it is.
- A subprogram named without the arguments it requires is reported wherever the
  name stands. The statement form, `source;`, said so already; the expression
  form, `S : String := Env_Value;`, answered with the result type and left the
  omission to be found by the lowering.
- A condition of the form `Find (..., Known) and then Describe (Known) = ...`
  tested the *initial* value of `Known` rather than what `Find` wrote into it:
  GNAT propagates an initialiser through an `out` parameter here, and the
  initialiser was there only to silence a spurious "may be referenced before it
  has a value" warning. Silencing the warning changed the behaviour. The call
  and the test are separate statements now, which is immune to both.
- Twenty GNAT style diagnostics that had gone unreported since Phase 1: the
  build was being checked for `error` and `warning`, and GNAT prefixes style
  diagnostics with `(style)` instead. The build is now clean under a check that
  looks for all three.
- `Adash.Interactive.Editing.Buffer` named its private components `Text`,
  `Length` and `Cursor`, shadowing its own accessors — component selection beats
  a primitive operation, so `Line.Text` silently returned the whole fixed-size
  component rather than the trimmed string.
- Bytes read but not decoded were held in a variable local to `Read_Line`, so
  type-ahead and the second line of a paste were discarded silently.
- `Hostkit.Terminal_Control` entered raw mode with `TCSAFLUSH`, discarding input
  the user had already typed; it now uses `TCSADRAIN`.
- A statement's source extent reached one token past itself: it ended at the
  token that comes next rather than at the last one consumed. Present since
  Phase 5 and harmless while spans were only pointed at, not while the source
  under one is read back. All forty sites are swept: thirty-seven now end at the
  last token consumed, and three keep the old form deliberately -- an error node
  reached without consuming anything should reach the token it is stuck on. A
  parser test slices every statement kind back out of the buffer and requires it
  to equal what was written.
- The conformance suite wrote every case's script into the history file of
  whoever ran it. Replacing the environment was not enough: a home directory is
  found through the passwd database when `HOME` is unset. Cases now get a data
  store each, under the host's temporary directory, which also stops case N
  seeing what earlier cases left.
- A doubled `""` inside an interpolated string literal was accepted as a single
  quote. Ada 2022 forbids it outright -- `\"` is what puts a quote in one -- so
  this took a program GNAT rejects. Found by asking GNAT rather than by reading
  the code.
- `Adash.Language.Semantics` walked a command's parameter profile up to the
  command's stated maximum, which is `Natural'Last` for one taking any number.
  Latent until a command with unbounded arity became callable, then an index
  check inside the analyser.
- The `alias` registry entry named parameters 1 and 2 with no `others`, so
  raising the parameter bound left the aggregate incomplete -- a range check at
  elaboration rather than a compile error.
- `wait` reported "status 0" for a job the host had killed. An exit code is only
  meaningful for a program that chose one; a signalled job now names the signal.
- Three reentrancy defects that a submission made during another submission
  would have hit, found while making `source` work: the engine reused one
  buffer, token stream and tree across submissions; the evaluator cleared its
  command sink on the way out rather than restoring it; and HAC's lowering stub
  had a fixed filename, so a nested run reopened a file the outer run held open.
  The last also collided between two shells running at once.
- The lowering stub file was left in the temporary directory after every run.
  It is deleted now.
- A bare name denoting a subprogram resolved to whichever was declared last
  rather than to the one taking no arguments, so `G` alongside `G (Integer)`
  emitted a call one argument short. Only reachable once overloading existed.
- A `for` loop re-evaluated its upper bound on every turn, so `for I in 1 .. N`
  with a body that changed `N` looped for ever. Ada evaluates the range once;
  the bound now lives in an unnamed slot in the frame.
- A `for` loop incremented its parameter before testing it, so a loop whose
  upper bound was the largest value the type holds raised `Constraint_Error`
  computing a value it would never use.
- An unsupported attribute was reported as an undeclared name, so `X'Size` said
  "Size is not declared here" and sent the reader looking for a declaration they
  never wrote.
- `Adash.Language.Symbols.Is_Assignable` reported every parameter as
  assignable, so `procedure P (N : in Integer) is begin N := 1;` was accepted.
  It could not have said otherwise before modes existed.
- A program that raised reported **nothing at all**: no output, no diagnostic
  and a successful exit, which is indistinguishable from a program that ran and
  printed nothing. `1 / 0` had been silent since the day it started running.
  The exit-status model is unchanged -- a failed statement still does not set
  it -- but the diagnostic is emitted. Subprograms are what made this urgent:
  runaway recursion and a function that never returns are both new ways to die.
- `Adash.Execution.Signals.Install` had existed since Phase 11 and **nothing
  ever called it**, so the shell ran with the host's default dispositions:
  Ctrl-C killed it outright, and a truncated pipeline would have taken it down
  with `SIGPIPE`. The interactive session now installs them. The package's own
  tests had passed throughout, because they tested the package rather than
  whether anything used it.

### Known limitations

Where the subset ends -- generics, tasks,
user-declared exceptions and `raise`, `goto` and labels, `renames`, loop names,
user-defined operators and aggregates -- is written down in `ROADMAP.md` with a
reason for each. None of it is pending work. What follows is what is inside the
subset and imperfect.

- **Overload resolution is outside-in, not simultaneous.** What the context
  requires flows down, and a comparison settles one operand from the other, but
  Ada resolves a call and everything around it together.
- **A subprogram cannot be named after a predefined one or an internal
  command.** Those accept any type, so a user's version would fit every call the
  original does and every one would be ambiguous.
- **A command call carries at most four arguments** from a program. The
  activation record the machine builds has a fixed shape, decided when the stub
  is built rather than when a call is written.
- **Subprograms nest nineteen deep.** Not a machine limit since the machine
  gained static links: what it bounds is the front end, where the analyser and
  the lowering each recurse once per level.
- **Everything is passed by reference**, where Ada passes elementary types by
  copy. Reading an `out` parameter before writing it, and aliasing two
  write-back arguments, are defined here and erroneous or unspecified in Ada. No
  *correct* Ada program can tell the difference.
- **`'Image` is the only attribute**, and it is refused for a `String`: Ada 2022
  defines that as the text in quotes with non-graphic characters bracketed,
  which is not the text itself.
- **Display width covers the ranges named in `Adash.Display_Width`**; a code
  point in none of them is one cell, which is an assumption rather than
  knowledge.
- **Configuration is per-user.** Only history has a per-session notion.
- **A program that stops early carries nothing forward.** `quit`, `return` and
  an unhandled exception all leave the hand-back unreached.
- **A line taller than the screen scrolls horizontally rather than wrapping.**
  Wrapping it would scroll the terminal, and a redraw cannot find its way back
  to a row that has scrolled off.
- **Windows has no pseudo-terminals and no process groups.** The one thing that
  host can do is report Ctrl-C, which `Hostkit.Signals.Can_Record` answers for.
- **Byte-identical binaries are not claimed**; see `docs/RELEASE.md`.

[Unreleased]: https://github.com/bracke/adash

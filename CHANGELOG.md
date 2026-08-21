# Changelog

Notable changes to Adash. Format follows [Keep a Changelog](https://keepachangelog.com/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The sixteen planned phases are complete, and a second body of language and shell
work has followed them. `ROADMAP.md` carries both as tables; this file carries
what changed.

## [Unreleased]

### Added

- **Four more cases for features in combination.** The creation mask reaches
  both kinds of write — the file this shell creates itself and the one a child
  creates through a descriptor the shell opened, which would otherwise be a
  `umask` meaning different things depending on which command you used next.
  `stop.on-failure` ends a submission on a failing *pipeline* as it does on a
  failing `run`. A placement that cannot be made under `stop.on-failure`
  produces **one** complaint rather than two, because the script stops at the
  file it could not open and never reaches the `pipe_run` that would have said
  the pipeline was given up. And a program that takes over with `run_instead`
  leaves a running job behind: the job is a different process, and nothing
  waits for it any more because what was waiting was the shell.

- **Seven files the suite wrote had been committed, and two rules that nothing
  enforced now do.** A check for what the suite leaves behind found
  `adash-test-store-large.lock` in the repository root *and* in the test crate
  — zero bytes each, from a case that removed its store file and not the lock
  beside it — plus five `adash-test-*.adash` scripts. One of those was a case
  that really does not clean up (it writes an anchor file to find a directory
  and removes only the other file); the rest were committed when a run was
  interrupted. Both cases clean up now, the seven files are gone, and a
  repository holding one fails the check. Beside it, "no non-Ada repository
  tooling" — an invariant with nothing behind it until now — refuses a `.sh`,
  `.py`, `.ps1` or `Makefile` anywhere in the tree; the two deliberate
  exceptions are the manifest's own `sh -c` test action and the CI workflow,
  and neither is a file this could see.

- **The presentation boundary is checked too.** `Adash.Messages.Rendering` says
  in its own specification that "a subsystem below the presentation boundary
  may name a message and may not render one — that is the whole point of the
  boundary", and nothing enforced it. Only a frontend may name that package
  now: below it a message travels as a `Message_Id`, because rendering needs a
  catalog and a locale, and a subsystem holding those would be choosing a
  diagnostic's language from underneath the frontend that knows. It held
  already — two units render, the interactive session and the main program.

- **The layering invariant is checked rather than asserted.**
  `ARCHITECTURE.md` lists "package dependencies are acyclic and point downward"
  among the invariants that "hold at every commit", and nothing checked the
  downward half — acyclic is Ada's own rule for specs, but the direction is
  not. `adash_check` now reads every `with` of an Adash unit, looks up both
  subsystems in `repository.toml`, and refuses four edges: a frontend named
  from below, the engine named from below, a foundation naming anything above
  it, and another subsystem's `internal` package. They hold today — 200 checks,
  no findings — and each was watched failing before being believed. Sideways
  edges are deliberately not judged, and the file now says why.

- **The conformance suite runs against a release build.** Three cases spelled
  `profile=development` into their expected output, so a release build failed
  them — which means the profile a user would actually ship (`-O3`, inlining)
  had never been through the suite at all, while `RELEASE.md` rests its
  reproducibility claim on that suite comparing observable output. The runner
  fills `{profile}` from the binary under test, beside the `{os}` and `{arch}`
  markers that exist for the same reason, and refuses a profile that is not one
  of the three a build can have. A release build now passes all 841 cases, and
  the arithmetic checks Adash reports failures from are still there under `-O3`
  — measured, not assumed.

- **A benchmark for what a session's own history costs it.** `analyse a line
  beside 128 declarations`: a submission is analysed together with everything
  the session still holds, so the same line that takes about 3 ms on its own
  takes about 80 beside 128 declarations, and a session carries up to 256. That
  is the design — a script pays none of it, because a file is one submission —
  but nothing showed the shape, and the figure is there to notice the day it
  stops being linear in the count. The language reference says so too now.

- **Two bounds nobody had ever watched hold now have cases.** `adash_check`
  lets a diagnostic be listed as one no case can produce, with a reason; two
  were listed on the grounds that reaching them would cost real time or real
  disk. Measured, neither did: a nineteen-megabyte script is refused in a third
  of a second, and four thousand one hundred empty files take a second and a
  half to make. `error.too_many_matches` has a conformance case that makes them
  and asks for `*.log`, and the unit case that grows a script past the read
  limit now asserts `error.source_too_large` **by name** rather than only that
  something was said — a file that large can also fail to open or be read
  short, and each of those is the same outcome with a different diagnostic, so
  the case was not asserting what it was named after. The list they were on is
  empty of size bounds now.

- **Three cases for what a script is made of** — a byte-order mark at the start
  is skipped, one in the middle is still refused, and a non-breaking space
  between two tokens costs exactly one complaint that names it `U+00A0`. The
  third holds a real invisible character on purpose, and says so where somebody
  tidying the file will read it.

- **A case for every awkward line, saying which of three things it must do.**
  The hostile-input case asserted "ran or complained", which is satisfied by a
  submission that parses half its text, runs that half and drops the rest --
  exactly what a stray `end` did. Each of the twenty entries now says whether it
  is unfinished, complained about, or runs, and the case compares that with what
  happens; a submission that fails and says nothing is never right and is
  noticed on its own. All twenty mismatches are gathered and reported together,
  because a failed assertion ends the routine and reporting the first one hides
  the nineteen behind it. Writing the table down is what caught the continuation
  prompt that could not be satisfied, and settled that a four-thousand-character
  identifier is a name like any other: two that differ in the last character
  keep their own values.
- **A case for `error.lexical.unterminated_string`.** It used to be produced
  only as the *second* complaint about something else, so when those learned to
  carry on scanning the literal, the one diagnostic that is really about an
  unclosed literal stopped being produced by anything at all -- which the
  repository check said before a person did.

- **Two more combinations**: a program that takes over with `run_instead` writes
  where the shell was sent by `redirect` — one feature moves a descriptor the
  process holds, the other keeps the process holding it — and two pipelines run
  into one redirected stream land in it in order, because there is one file
  description rather than two opens. A third was probed and needs no case: a
  signal arriving while a suspended job is brought to the foreground reaches its
  handler, which the three signal cases already cover between them.
- **Six cases for features in combination** — stopping still runs both kinds of
  handler and in which order; a pipeline's status is its last stage's, so a
  failing first stage does not stop a submission and a failing last one does; a
  job writes where it was started while the shell's reports about it follow a
  later redirect; a pattern answers where the shell is standing after
  `push_directory`; braces make the words and patterns then name the files; and
  an expansion that names nothing stops a stopping script, which is the one that
  matters because a script that expands a pattern is usually about to do
  something irreversible with what it found.

- **Unit cases for `Adash.Interactive.Prompt`** — five, asserting the model
  rather than a terminal: the built-in prompt puts a blank between its parts and
  a format does not (the spacing is the user's), a `{word}` this shell does not
  know stays the text it is rather than vanishing, a `{failed}` marker waits for
  a failure, and `{status}` shows the number the last submission ended with.
- **Unit cases for `Adash.Patterns`** — six of them, covering what a conformance
  case would need a directory to reach: anchoring at both ends, a star that has
  to give ground, a class that is negated, an unclosed bracket that stands for
  itself, nested groups, ranges that count backwards, an empty alternative, and
  the expansion bound refusing whole rather than handing back the first four
  thousand. A sweep for library packages no test names found four; two are
  exercised through the shell, and this is the first of the two that were not.

- `run_with` takes as many assignments as you write, and `start_with` does the
  same without waiting. The boundary is the first argument that is not of the
  form `NAME=VALUE`, which has exactly one exception, written down where the
  command is registered: a program whose own name contains an `=` must be run
  by `run` with the variables `set`.
- **A directory stack**: `push_directory` goes somewhere and sets aside where
  you were, `pop_directory` comes back to the most recent of those, and
  `directories` lists what is waiting. They nest, which one previous directory
  cannot — `cd ("-")` answers "where was I before this one", these answer "where
  was I before I went off to do something else". A `pop_directory` with nothing
  set aside is refused rather than treated as home: a script that thought it had
  gone back would do the rest of its work in the wrong place. A failed
  `push_directory` sets nothing aside, for the same reason.
- **`on_failure`**, which is what `trap … ERR` is elsewhere. `stop.on-failure`
  stops; this one *tells*, and a script that wants both does both. Once per
  submission rather than once per failing command: a loop that fails a hundred
  times is one thing gone wrong, and a handler writing a line each time would
  bury it. A handler's own failure is not another thing to handle.
- **`Read_Line_Within`, `Read_Key`, `Input_Timed_Out`.** A read that gives up
  after a while is what a script needs to ask a question it can carry on
  without, and there are three answers — a line, the end of the input, giving up
  — none of which is an empty line, because input can genuinely hold one.
  `Read_Key` is one character as it is typed: the terminal goes raw for the read
  and back afterwards, which is what makes `y` an answer rather than `y` and a
  return. The waiting is per read rather than for the whole call, so a line
  arriving slowly is a line that is arriving; giving up in the middle would
  leave the rest for the shell to read as a command.
- **Ctrl-Y puts back what a cut took out.** `Ctrl-K`, `Ctrl-U` and `Ctrl-W` fill
  one buffer; one rather than a ring, because what you want back is what you
  just cut.
- **`redirect`, `redirect_append`, `redirect_back`** — the other half of what
  `exec` does elsewhere: point the shell's *own* output, errors, or both at a
  file for the rest of the session. What the programs it starts write goes there
  too, because it is the process's stream that moved — which is the difference
  between this and `run_into`, and the reason a script can log everything it
  does with one line at the top. The stream is named (`output`, `errors`,
  `both`) rather than numbered: numbers are a convention this shell has never
  used, and a shell that accepted `2` would have to decide what `3` meant.
  `redirect_back` is why `redirect` saves what was there — once a file is
  assigned over standard output, nothing in the process remembers where it used
  to point.

  On every host. It was two for a while: Windows moves a stream with
  `SetStdHandle`, which changes what a *new* reader of the standard handles
  finds and leaves this program's own writes where they were — the shell's line
  came out on the console with the file empty — so the command refused there
  rather than reporting success and moving nothing. hostkit moves the runtime
  descriptor as well now (`_open_osfhandle`, `_flushall`, `_dup2`, which is what
  `dup2` does in one call elsewhere), a case there asserts it by writing through
  `Ada.Text_IO` and reading the file back, and the refusal is gone.
- **Columns without a format string.** `Left_Aligned`, `Right_Aligned`,
  `Zero_Padded` and `Decimals` do what `printf "%-20s %06.2f"` does, as calls the
  compiler type-checks. A format string is a second language inside the first —
  its own escapes, its own type letters, its own rules for when the letter and
  the value disagree — and this shell has one language. Text already longer than
  the width comes back whole rather than cut: a formatter that shortened a name
  to keep a column straight would lose the thing the line was written for. And
  `Decimals (2.0, 0)` is `2`, not `2.0`, because none means none.
- **Brace expansion.** `{lib,test}` is two strings, `{1..4}` counts, two groups
  multiply, and groups nest. `run_matching` expands braces before patterns —
  `run_matching ("mkdir", "-p", "src/{lib,test}")` works — and `Braces_Count` /
  `Braces_At` are the same expansion as a question. Braces touch no filesystem
  and refuse nothing for not existing: they say what strings to make, and
  whether anything is called that is asked afterwards by whatever wanted the
  names. A group with neither a comma nor a range says nothing and stays as it
  was written, so `{a}` is `{a}`.
- **`stop.on-failure`**, which is what `set -e` is elsewhere: a submission stops
  at the first command that fails and reports that failure instead of success. A
  script file is one submission, so a script stops; a script fed in on standard
  input stops being read, which is what makes the exit status mean something to
  whatever ran it; at a prompt the shell reads the next line, because a session
  that ended over a mistyped command would be one nobody could use. Off by
  default — a shell that stopped on the first failure would break every script
  written against this one — and a command whose failure a script means to
  inspect must not run under it, the same trap `set -e` has everywhere.
- **`run_instead`**, which is `exec`: become the program, keeping the process,
  its open files and its place in the terminal. Nothing runs after it, including
  what `on_exit` asked for — there is no exit, this process does not end, it
  becomes something else. The refusals come first, in order: a host with no such
  call says which capability is missing (Windows, whose CreateProcess would make
  a *new* process and change the very thing this exists to keep), and a program
  that cannot be found is refused while there is still a shell to report it
  with. The unit case starts a shell, has it become another program, and reaps
  the process id it started — the part no conformance case can see.
- **`cd ("-")` goes back to where the last `cd` came from**, and twice in a row
  returns to where it started, because going back is itself a move. A session
  that has not moved says so rather than treating the dash as the home
  directory, which would take somebody somewhere they had never been and call it
  going back. The value is readable as `Previous_Directory` for a script that
  wants to remember where it was rather than go there. Kept in the shell rather
  than exported as `OLDPWD`: a variable a child can set is a variable that can
  lie about where this shell has been.
- **A job has a process id.** `Job_Process (Last_Job)` is the number, which is
  what a script needs to hand a job to another program — or to `signal_process`,
  which until now could be aimed at every process on the machine except the ones
  this shell had started itself. The first stage of a pipeline, which is the one
  a job is listed under; `stop` remains how a whole pipeline is ended. Zero for
  a job that is not there or has been reaped, because answering with somebody
  else's process id is the one wrong thing it could do.
- **`~other` is that user's home directory**, asked of the host's user database
  through the new `Hostkit.Fs.Home_Directory_Of`. A name the host does not know
  — and every name on Windows, where a profile folder belongs to whoever is
  logged in — leaves the path exactly as it was written, so a path that meant
  itself survives and one that meant a user fails as a path that is not there
  rather than as the wrong directory.
- **`**` walks a tree.** `logs/**/*.log` finds what is directly in `logs` as
  well as what is under it, because `**` stands for any run of directories
  *including none* — one pattern rather than two, since a user who has to write
  both has to remember which found what. `logs/**` names the directories
  themselves. Every segment is matched now, so `src/*/*.ads` means what it says,
  while a single `*` still stops at a separator. A walk never goes through a
  symbolic link — one pointing at its own parent is a walk with no end — and
  never deeper than sixty-four levels.
- **Ctrl-R searches the history.** Backwards, for a line *holding* what you
  type, which is the difference between it and the up key: you remember a word
  from the middle of a line, not how it began. What is being searched for
  replaces the prompt while the search runs, and the match is the line being
  edited — so Enter runs it, any other key starts editing it, another Ctrl-R
  walks to the match before that one, and Ctrl-C gives up on the search and
  hands back what you had been typing rather than abandoning the line.
- **A leading `~` is your home directory**, everywhere the shell resolves a path:
  `cd ("~/src")`, `read_file ("~/notes.txt")`, `run_into ("~/log.txt", ...)`,
  `source ("~/setup.adash")`, the listings and the pattern expansion. This is the
  one expansion done without being asked, and the reason is that it cannot change
  how many arguments there are: a pattern turns one word into several, which is
  why `run_matching` is a command somebody writes on purpose, and a tilde turns
  one path into one path. `~other` is somebody else's home, which needs a lookup
  this shell does not have, so it is left exactly as written rather than guessed
  at. Asked of the host rather than read from `HOME`, which a spawned process can
  set to anything.
- **`prompt.format`** — the prompt is yours now, not two switches.
  `settings ("prompt.format", "[{path}]{status}$ ")` and that is the prompt;
  `{directory}`, `{path}`, `{status}` and `{failed}` are filled in and everything
  else is literal, spacing included. Empty brings the built-in prompt back.
  Control characters are refused: a prompt is written before everything else on
  the line, so text that moved a cursor would break the display it appears in,
  and what colour a prompt has is the style package's decision. This is the first
  free-text setting — the argument against them is about values whose wrongness
  shows up somewhere else later, and a prompt's is on the screen immediately.
- **`on_signal` and `signal_process`** — signals beyond the interrupt.
  `on_signal ("terminate", "Save_And_Quit")` runs a subprogram when the signal a
  service manager sends first arrives, which nothing in this shell could hear
  before; `signal_process (1234, "hangup")` sends one, naming it rather than
  numbering it. The names are the host's own in lower case. `kill` and `stop`
  cannot be caught by anybody and are refused when asked for rather than accepted
  and never run, and Windows — which has no signals beyond a console's interrupt
  — refuses the rest.
- **A wait is a place the shell looks for a reason to stop.** The machine asked
  every thousand instructions, which is right for a loop that computes and wrong
  for the loop people write: `loop delay 0.2; end loop;` runs a handful of
  instructions a second, so a thousand of them was ten seconds — ten seconds
  between a Ctrl-C and anything happening. It asks after every wait now, and both
  Ctrl-C and a signal handler are immediate.
- **Pattern expansion**, which is the largest thing this shell did not have.
  `run_matching ("rm", "-f", "*.log")` replaces every argument holding `*`, `?`
  or `[` with the paths it names, sorted, and passes every other argument along
  untouched — so a flag and a pattern stand side by side. `Match_Count` and
  `Match_At` are the same expansion as a question, for a script that wants the
  paths rather than a program run over them.

  Expansion is asked for, never implicit. An argument in this language is a
  string literal, and a shell that quietly turned one into several would be a
  shell whose quoting rules somebody has to learn before they can name a file
  with a star in it — so `run` still hands a program exactly what it was
  written with, and there is a case saying so beside the one that says
  `run_matching` does not.

  A pattern that names nothing refuses the command rather than passing the
  pattern on as a word. That is where `rm *.log` in a directory with no logs
  becomes a program asked to remove a file called `*.log`, and a shell that
  expands on purpose can afford to say so instead. A pattern naming more than
  4096 paths is refused whole rather than cut short, and the two refusals are
  told apart: one is a typing mistake, the other is a directory somebody else
  filled.

  Only the last segment of a pattern is matched — `build/*.o` looks in `build`
  and the paths keep that directory — and a name beginning with a dot answers
  only a pattern beginning with one, which is the rule every shell has.
  `Adash.Patterns` now owns the matcher that `Matches` was already using, since
  two copies of a matcher are two matchers that will one day disagree.
- `resource_limit` and `resource_ceiling` — what the host will let this shell
  use, which every other shell exposes as `ulimit`. With no argument the first
  lists every limit; with a resource it shows the limit and the ceiling it may
  be raised to; with both it sets one. Sizes are bytes, `processor_time` is
  seconds, the rest are counts, and `unlimited` is a value. Limits are
  inherited, so a script that lowers one has lowered it for everything it
  starts afterwards — which is the point. Windows has no per-process limits of
  this kind (a job object is attached to a set of processes rather than
  inherited by them, and a process cannot lower its own), so the shell says the
  host has none rather than printing numbers a script could not act on. Named
  `resource_limit` rather than `limit`: a command name cannot be redeclared, and
  `Limit` is a variable somebody has already written — one of the conformance
  cases here declares it.
- `time (Program, …)` — runs a program and reports how long it took, in
  wall-clock seconds. Only wall time: a user time and a system time are a
  different measurement the host reports for a process it has reaped, and
  reporting a number the shell has not got would be worse than one honest one.
- `umask` — what the host takes away from the permissions of a new file, shown
  or set in octal. Windows has no per-process mask at all, and says so rather
  than reporting a zero a script would act on; the capability is
  `Hostkit.Fs.Creation_Mask`, added for this.
- `on_interrupt` fires at the prompt as well as in a script. It was wired into
  the script path only, which is the half a user meets second: they register a
  handler and then press Ctrl-C at a prompt.
- A completion handler is bounded. It runs inside the editor, where the user is
  typing, so a handler that loops would not be a slow completion — it would be
  a shell that had stopped. Half a second, asked for from a stopwatch task
  because the submission is what has to notice and the editor's task is inside
  it.
- `complete_with (Program, Name)` — teaches Tab what may follow a program. The
  shell knows its own vocabulary and what the filesystem holds; it cannot know
  that `git ` is followed by `commit`, and nothing it could read would tell it.
  A subprogram prints one candidate per line and Tab offers them, after the
  shell's own candidates so that the list does not move under the user's
  finger.
- **A script may begin with `#!`.** The line the host reads to decide what runs
  a file is blanked rather than removed, so every position after it is
  unchanged and a diagnostic still names the line a reader is looking at. Until
  now an executable script's first line was a syntax error.
- `on_interrupt (Name)` — what to run when the user interrupts, beside
  `on_exit`'s what to run when a session ends. It stays registered, because an
  interrupt can happen twice; cleanups still run afterwards, handler first.
- `stop_process (Process)` — asks a process this session did not start to stop.
  `stop` takes a job; a user who wants to stop a build left running in another
  window has a process id and had nothing to type. A separate command, because
  job 3 and process 3 are both plausible.
- `Matches (Whole, Pattern)` — pattern matching over strings: `*`, `?`,
  `[abc]`, `[a-z]`, `[!abc]`. Glob *expansion* remains refused — nothing
  rewrites an argument list from the filesystem — but a script can now ask
  whether a name matches, which is what `for f in *.log` and `case $f in` are
  for. It reads nothing, and is case-sensitive on every host.
- `run_from_text (Input, Program, …)` — runs a program with its input read from
  text the script computed, which is what `printf '%s' "$x" | tool` says
  elsewhere. The text goes through a private file rather than a pipe: a pipe
  holds one bufferful, and a shell writing more than that into one waits for a
  program that is waiting for the shell. The file is removed however the
  command ends, including when it is refused or interrupted.
- `pipe_from_text (Input)` — takes a pipeline's input from text the script
  computed, which with `Output_Of_Pipe` after it makes `printf '%s' "$x" | tool
  | other` expressible with the answer handed back. The file belongs to the
  session, so it outlives the submission that built the pipeline and a job
  placed in the background.
- `run_with (Assignment, Program, …)` — runs a program with one variable set
  for it alone, written `NAME=VALUE` as `set` writes one. It adds to what the
  child would have had rather than replacing it.
- `benchmarks/ceilings.toml` — a ceiling for every figure `adash_bench`
  measures. A figure over its ceiling, or a figure with no ceiling at all,
  makes the tool exit non-zero, which is what lets CI run the benchmarks on
  all three hosts on every push. The bounds are an order of magnitude above
  what the operations take, because a gate that fails on a loaded CI runner is
  a gate somebody disables.
- `adash_check` reads the message catalog in both directions, which
  `docs/RELEASE.md` has always claimed it did: a catalog key no source can
  reach is a finding, and a `tooling.*` key a tool names and the catalog lacks
  is a finding. Keys built at run time are credited through the dotted prefix
  their source joins to. It found two unreachable keys on its first run.
- `adash_bench` fails on drift as well as on a ceiling: a median more than four
  times the operation's own fastest run means it gets slower as it repeats,
  which the report has called a defect since it was written and nothing could
  fail on.
- `Hostkit.Pty.Write_Fails_When_Unheld` (in hostkit) — whether writing to a
  terminal fails once nothing holds the device side. macOS refuses the write;
  Linux and Windows take the bytes into a buffer nobody reads. Adash's terminal
  tests had been reading that refusal as a keystroke that never arrived.

### Added

- **Three diagnostics that nothing could ever produce are gone.**
  `error.not_an_array`, `error.generic_not_callable` and `error.not_runnable_yet`
  had messages, keys, catalogue rows and translations — and no line of code
  anywhere raised them. A diagnostic nothing can produce is worse than a missing
  one: it describes behaviour the shell does not have. Found by the rule below,
  which asked me to justify each unproduced message and could not be answered for
  these three.
- **An empty array type and nesting past the floor** now have cases —
  `array (5 .. 1)`, and a twenty-first nested subprogram. The nesting case
  asserts all twenty-one follow-on complaints rather than the first: that wall is
  what a user sees, and somebody who improves it will find the case and change it
  deliberately.
- **`adash_check` refuses a diagnostic no case produces.** A message nobody has
  produced is a message nobody has read: its placeholders have never been
  filled, its sentence has never been seen next to the mistake it describes,
  and its translation has never been exercised. The ones that cannot be produced
  by a case are listed in the checker with the reason — the machine's own
  defensive checks, host refusals a case cannot arrange, bounds that would cost
  real time or disk — and the list is checked in *both* directions, so a message
  that stops being produced has to join it and a stale entry fails too. The list
  only shrinks by somebody doing the work. It found three of my own entries
  wrong on the first run: `redirection_conflict`, `command.unavailable` and
  `script_cycle` are produced by unit cases I had missed.
- **`adash_check` refuses a command or function no case runs.** Being listed by
  `help` is not being tested: that case pins the whole vocabulary in registry
  order, so everything appears in it whether or not anything calls it. The new
  rule reads what the cases actually run — the `script`, `arguments` and `input`
  of every case, the fixtures they name, the unit sources — and asks whether each
  registered name appears there. It exists because the same hole opened three
  times in one week, always the same way: a family shared code with something
  covered, and the sharing was the argument for not testing the rest.
- **A script that is not UTF-8, and a write the host refuses**, both have cases
  now. The second needed no permission command: `umask ("777")` takes every bit
  away from what is created next, which is the only way a script can make itself
  a directory it cannot write — and is the mask doing exactly what it is for.
- **Every diagnostic a mistyped line produces now has a case.** The whole
  `lexical.*` family and `syntax.mixed_logical` were reachable, documented,
  translated — and never once produced by anything that runs. Eleven cases cover
  them, plus `return_without_value`, `not_a_record`, `no_history_here` in a
  script, and a program this host will not run. The cascade is asserted rather
  than trimmed: one stray character costs four complaints, because the parser
  tries the line as an expression, as a statement and as the end of one, and a
  case that expected only the first would let the other three change unnoticed.
  47 of 197 error messages had never been produced; 38 remain, of which 13 are
  the machine's own defensive checks.
- **The eleven things nothing ran now have cases**: `umask` (and its refusal on
  the host that has no creation mask), `start_with`, the eight pipeline
  redirection forms, and `Error_Of_Pipe`. Writing them recorded a behaviour
  nobody had written down: a refused placement takes the pipeline with it, so the
  `pipe_run` after it reports an empty pipeline — two diagnostics for one
  mistake.

### Fixed

- **A deeply nested expression is refused instead of ending the session.**
  `put_line ((((…1…))))` a hundred brackets deep raised `STORAGE_ERROR` out of
  the process: six parsing routines call each other in a ring, so a hundred
  levels is six hundred frames of a rule carrying its own locals. Sixty-four
  levels is the bound now — eighty parsed before it existed, a hundred did not
  — and the refusal is a diagnostic like every other bound this build has.
  Statements never had the shape: a hundred and fifty nested `if`s parse and
  run. The refusal says so **once**: unwinding a hundred brackets asks for a
  `)` at every level on the way out, so it first arrived with a complaint per
  bracket behind it. And it is a refusal rather than an unfinished line, since
  no amount of further typing reduces nesting.

- **The conformance runner no longer collides with itself.** Every run used one
  store directory name, so two suites at once — which is what happens the
  moment somebody starts one while another is still going — wrote into each
  other's files and produced failures neither run's shell had caused. A run
  claims a root of its own by making it, puts every case's store inside it, and
  takes the lot away when it ends. Removing it needs care one case earns: it
  makes a directory with no permissions on purpose, and `Delete_Tree` stopped
  there, leaving 697 of 841 stores behind and swallowing the reason.

- **A handler that is not a name is refused where it is written.**
  `on_failure`, `on_exit` and `on_signal` take the *name* of a subprogram to
  call, and anything non-empty was accepted — so somebody who has used a shell
  where the argument is code writes `on_failure ("put_line (""x"");")`, and this
  shell took it and then reported a syntax error about a semicolon at the moment
  some *other* command failed. Two mistakes at once, neither of them where the
  reader was looking. The argument is checked when it is given now: a name is a
  letter or underscore followed by letters, digits and underscores, and may be
  dotted, since a handler in a package is `P.Note`. Whether that name exists is
  still asked when the handler runs, because a session may declare it after
  registering it.

- **`resource_limit` reads what the caller wrote before it asks what the host
  has.** A value that is not a number is a mistake in the program and travels
  with it; a host without that limit is a fact about where it is running.
  Asking the host first told a Windows user their host has no limits and sent
  the typo home with the script — and the case that asserts the refusal had to
  be gated to the two hosts where the answer came out right, which is how this
  was found. Auditing why each of the nine skipped conformance cases is skipped
  is worth doing: a case gated to make a run green is the same sin as a matrix
  reduced to make one green. The other gates all name a thing Windows does not
  have — signals, rlimits, `exec`, a creation mask, job control — and stay.

- **`Index (Whole, "")` answers zero instead of ending the session.** Ada's own
  `Index` raises `Pattern_Error` when the piece is empty, and that exception
  came out of the process — a separator read out of a configuration that did
  not carry it would end the session rather than the search. Answering rather
  than raising is what this call is documented for: "`Index` answering zero
  rather than raising is what lets a script test before it slices". Zero is the
  position no string has, and it sends a caller down the branch they already
  wrote for "not there".

- **Start-up stopped growing with the square of what the user had typed.** The
  history loader keeps the newest `history.limit` lines by dropping the older
  ones, and it dropped them **one at a time** — each `Delete_First` shifting
  every line after it. On a log this shell had written itself in a day's use
  (7584 lines), that was 1.8 seconds of pure computation before the first
  prompt; a file script, which loads no history, took 0.06. Dropped in one move
  now: 8000 lines cost 0.03 seconds instead of 1.8, and the growth is gone.
  Nothing had measured it — the benchmark beside it times *encoding one line* —
  so `read a saved history log` is a figure now, with a ceiling, and a unit
  case pins which lines survive, since dropping from the wrong end would leave
  a history that reads back as somebody's first hundred commands for ever.

- **Three ways to end the session with a GNAT traceback, from one line each.**
  `put_line (-9223372036854775808)` — the smallest whole number this build
  holds — read the magnitude first and raised `Constraint_Error` out of
  `'Value`, past the engine and out of the process. Ada folds a minus in front
  of a literal while the number is still universal, which is exactly what makes
  that number writable, so the lowering folds it too. `-X` and `abs X` on the
  same value overflow, and those two instructions were the only arithmetic in
  the machine with no guard around them; they report what every other overflow
  reports. And a literal too large to hold at all is now refused by name rather
  than crashing, the way a Float literal already was.

  `error.machine.arithmetic` came off the list of diagnostics no case can
  produce while this was written. It had been filed among the machine's
  defensive checks — "a case that could produce one would be a case that had
  broken the machine on purpose" — and `1 / 0` reaches it.

- **Three things stop a `cd`, and they are told apart.** `Set_Directory` raises
  the same exception for a directory that is not there and one this user may
  not enter, and the shell took the exception's word for it — so `cd` into a
  directory whose mode is `000` said "no such directory" and sent the reader
  hunting for a typo in a name that was right. The path is asked instead:
  nothing there is *not found*, something there that is not a directory is *not
  a directory* (a new message; `cd` into a file used to be "no such directory"
  too), and a directory that will not open is *denied*. That last message
  existed and nothing had ever produced it — it was on the list of diagnostics
  no case can make, described as "a directory that denies rather than hides",
  and it is off that list now with a unit case that makes one through hostkit
  and puts the mode back whatever the assertion does.

- **`set ("PATH =/opt/bin")` is refused rather than obeyed.** The name had to be
  followed by an `=` and nothing else was asked of it, so a space nobody meant
  made a variable called `PATH ` — which no program looks up, because no shell
  can write that name down — left `PATH` alone, and said nothing, while `env`
  showed a line that reads correctly at a glance. A name is a letter or an
  underscore followed by letters, digits and underscores, and `set` asks the
  same rule `run_with` asks. It was not asking it at all: the helper that
  decides what an assignment looks like says in its own comment that this is
  "the same question asked twice, so it is asked in one place", and `set` had
  the second copy.

- **A pipeline that was given up no longer reports that nothing was added to
  it.** A placement that cannot be made -- a file in a directory that is not
  there, a path that is a directory -- throws the stages away, so the
  `pipe_run` that follows found an empty pipeline and said so: two diagnostics
  for one mistake, the second telling a user who had just built two stages and
  been told about a file that they had never built anything. It says the
  pipeline was *given up* now, which is about the same event as the first.
  Three conformance cases pinned the old wording, and one had the wart written
  into its requirement as something "written down here rather than left to be
  discovered".

- **A configuration mistake is a sentence, not a key.** The TOML parser under
  the configuration reader answers with a catalog key -- and says so in its own
  source, where `Identifier` is written: the identifiers are keys, and the
  sentences belong to whoever renders them. Nobody had rendered them, so a
  broken `config.toml` came back as `line 1, column 1: toml.error.expected-key`,
  a machine's name for the mistake standing where a sentence about it belongs.
  The twenty-seven sentences are in the catalog now and quoted into
  `config.syntax`, which supplies the file and the position. A diagnostic can
  carry a quoted message named by key as well as by `Message_Id`, which is what
  a library below the presentation boundary can offer; the mapping from
  tomllib's codes is written out in Adash, over an enumeration with no
  `others`, so a code added upstream stops the build until somebody writes the
  sentence for it.

- **Numbers in diagnostics are written the way a reader writes them.**
  `Integer'Image` puts a blank where the minus sign would go, and forty-nine
  message arguments passed it straight through: `line  1, column  1`, `expects
   1 and was given  0`, `more than  4096`. Seventy-eight conformance
  expectations had the blank written into them, which is how long it had been
  there. `Messages.Named` takes a number now and does the trimming once, so a
  call site cannot forget; the two places that build a *phrase* around numbers
  (`1 .. 4`, `2 or more`) trim it themselves and say why.

- **The build says nothing again, and CI is what will notice next time.** Four
  complaints had accumulated where nobody could see them -- two blank lines, a
  `use` clause with no effect, a redundant conversion, a variable that could be
  constant -- because `alr build` exits 0 with warnings on its output and an
  incremental build does not recompile the file that carries one. The rule that
  a clean build says nothing was being checked by hand, against a build that
  had not compiled the file. Both workflows now read the build's output and
  fail on any line that names a file and a position: a fresh runner compiles
  everything, which is exactly where the question belongs.

- **A script that begins with a byte-order mark runs.** It is what a Windows
  editor writes when it saves as UTF-8, so it arrives on files nobody edited by
  hand, and it was read as a character: the script was refused for a stray
  character invisible in every editor that produced it, at column 1 of a line
  that looked perfectly ordinary. GNAT compiles a source that begins with one
  without remark, and this language is Ada. Skipped only at the very start —
  a mark in the middle of a program is a zero-width space somebody pasted, and
  that is still refused.

- **One character the language has no use for costs one complaint, and is named
  by number when it cannot be shown.** Outside ASCII a character is two, three
  or four bytes; the scanner stepped a byte at a time, so one pasted mark
  produced three diagnostics, each naming a third of a character — which
  renders as a replacement glyph and gives a reader nothing to search for. The
  width now comes from the leading byte, and a character below `U+0020` or
  above `U+007E` is reported as `U+00A0` rather than as itself, because
  `U+00A0 does not begin anything the language recognises` is a sentence with a
  subject in it.

- **A stray `end` no longer swallows the rest of the line in silence.** A
  sequence stops at `end` whoever asked for it, because nothing in this language
  begins with one; at the top level there is nobody to have asked, and the
  parser handed back what it had. `put_line ("before"); end; put_line
  ("after");` printed the first line, dropped the second and said nothing about
  why. What is left over is named now, and an error node goes with the
  complaint, so the half that did parse does not run either. Said only where
  nothing else was: a submission that already has a complaint has an
  explanation, and adding "and there was text left over" to it costs a place in
  a bounded report -- it displaced "too many parameters" while this was being
  written.

- **One mistyped byte produces one complaint.** A lexical mistake used to be
  reported and then scanned *around*: the scanner gave up where it stood, the
  rest of the line was read as code, and the parser complained three more times
  about the bytes that followed. `put_line (f"closes } nothing");` -- a finished
  line with one wrong character in it -- came back as an unescaped brace, an
  unterminated string, a missing bracket and a missing semicolon, and a reader
  who fixed the last three still had the first. The three recoveries inside an
  interpolated literal (an unescaped `}`, a doubled quote, an escape this
  language does not define) now say what is wrong and take the character as
  what it looks like, so the literal still ends at its closing quote. Text the
  scanner complained about is not parsed at all: an error node stands for the
  submission, which is what stops it running. That gate is in the parser rather
  than in the shell, so everything that parses agrees -- the shell, a test that
  lowers a program by hand, and anything later that reads a submission before
  running it.

- **An unclosed literal is no longer a continuation prompt that cannot be
  satisfied.** `put_line ("hello` and Enter asked for more input, and no more
  input could mend it: Ada's literals do not span lines, so the next line the
  user typed was swallowed into the same broken submission, and the one after
  that too. The shell asks the grammar whether a line wants finishing only when
  the scanner had nothing to say about it; otherwise the line is submitted and
  the complaint arrives beside it.

- **A signal reaches its handler while the shell is waiting for a key.**
  `Read_Key` is its own loop around its own read, so it had its own copy of the
  defect below and needed its own fix. A menu waiting for `y` is the place a
  user is most likely to walk away from, which makes it the place a `terminate`
  is most likely to arrive.
- **A signal reaches its handler while the shell is waiting for input.** The
  same defect as the one below, wearing a different hat: a blocking read cannot
  be interrupted, because the host restarts it when a signal arrives — which is
  what `signal` asks for and what every other caller wants. So a script waiting
  for a line read again for ever, and the handler it had registered for
  `terminate` ran when the input finally came; for a pipe nobody writes to, that
  is never. The wait happens in a poll now, in fifths of a second, and the read
  is only ever made when it will not wait. Between polls the shell can notice it
  has been asked to stop.
- **A signal reaches its handler while the shell is waiting for a job.** `wait`
  blocked in the host with no cancellation token, which was fine while the only
  interruption anybody expected was Ctrl-C — that reaches the job through the
  terminal, and the job dying is what ends the wait. It was not fine for a signal
  sent to the *shell*: a `terminate` arriving while a script waited was recorded
  and then ignored until the job ended on its own, so the handler the script
  registered ran a minute late, or never. A script waiting on a long-running
  child is exactly where a service manager's `terminate` lands. The wait takes
  the session's token now: the job's group is ended, the wait returns, and the
  handler runs — one second after the signal in the case, against sixty before.
  Found by testing features in combination; each half passed alone.

- **`{1..d}` keeps its braces.** A group with `..` in it was treated as a group
  even when its ends were not the same shape, so the braces came off and nothing
  was put in their place — `{1..d}` expanded to `1..d`, where every other shell
  leaves it exactly as written. A group speaks only if it holds a comma or a
  range this package would actually count. Found by the first unit case written
  for `Adash.Patterns`, minutes after the package got one.

- **A variable holding a newline no longer breaks the rest of the session.** A
  value is carried from one submission to the next as the text that declares it,
  and a String was written back as a quoted literal with its contents verbatim —
  so a newline inside one ended the line and produced a literal that was never
  closed. Every submission after it answered "this string literal is not closed",
  which is to say that `Held : String := Read_File (…)` poisoned the session. It
  is written back as a concatenation now, with each control character as the
  character it is, which is how somebody writing a newline in this language
  writes one. Found while closing a test-coverage hole: two new cases that read a
  file into a variable failed, and the third case pins the defect itself.

- `adash_check` checks `docs/diagnostics-catalog.md` against the catalog it
  claims to be — a row for every message, a message for every row, and the same
  words in both. That document said of itself "the catalog file is the source;
  if the two disagree, the file is right and this is stale", and it was stale
  by 87 of 519 messages. The table is regenerated and the check keeps it true.
- **A refused submission always says why.** A procedure written where a value
  belongs — `X : String := "a" & New_Line;` — printed *nothing at all* and
  exited 2. The analyser noted the operand's type as unknown, the rule that
  keeps one unknown type from producing a complaint per operator it flows
  through kept quiet, and the submission was refused in silence. Two fixes: a
  procedure used as a value is reported where it is written, by name, in all
  three of its forms; and the rule that suppresses a cascade now suppresses
  only *after* something has been said, so an analyser that refuses a
  submission can no longer refuse it without a reason.
- **A child now inherits what `set` set.** The catalog has described `set` as
  "a variable children will inherit" since the command existed, and no child
  ever inherited one: the session kept its own block — `env` listed it,
  `Env_Value` answered from it — while every program the shell started was
  given this process's environment instead. `set`, `unset` and the session's
  variables now reach programs started by `run`, by a pipeline stage, and by a
  captured run.
- `adash_check` verifies that `alire.toml` and `repository.toml` agree about
  the version, which the release guide has always claimed and which had never
  been true: both reads returned nothing and two nothings compare equal. The
  same reader bug had disabled the half of the inventory check that says every
  spec named in `repository.toml` exists. A value that cannot be read is now a
  finding rather than a silent agreement.
- `adash_bench` reports a bad repetition count instead of raising
  `Constraint_Error` with a traceback, and refuses a count large enough to
  exhaust the stack.

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
- **CI runs on three hosts**, which is what a crate built on hostkit has to do:
  ubuntu, macos-15-intel and windows-latest, with the conformance suite added
  to what each runs. Making that honest needed two fixes. The conformance
  runner built the path to the shell as `bin/adash` with no suffix, so on
  Windows it would have spawned nothing -- it asks the host now. And ten cases
  spawned `cat`, `echo`, `true`, `sh` or `sleep` without saying which hosts
  they hold on; they carry a `platforms` key now, which means capture,
  redirection and job states are checked on two hosts of the three. The
  workflow says so rather than leaving it to be discovered.
- **A definition past what the session carries says so, whatever kind it is.**
  The limit is 256, and the warning for passing it was written when the limit
  was — with the comment "a definition silently not kept would look like one
  that was, until the line that used it failed for no visible reason". Four
  paths drop a definition and only one of them reached that warning, so the
  257th *variable* vanished in silence and the next line reported an undeclared
  name the user had watched themselves declare.

  All four say it now, through one procedure rather than four copies. The path
  where a package's member arrives says it only for a dotted name: a plain
  variable was reported where it was declared, spelt as it was written, and
  saying it again from a folded key would be the same warning twice in two
  spellings.
- **A construct with more parts than this build carries is refused, not
  truncated.** The parser collects into fixed-size lists, and seventeen loops
  stopped at the end of one without a word. A select of thirty-three
  alternatives therefore served thirty-two, never offered the last, and left a
  caller of it deadlocked — `tasks_stuck`, which reads as a defect in the
  program rather than a bound in the build, and which `ROADMAP.md` had promised
  would not happen: "refused where it runs rather than answered wrongly".

  Every one of those loops reports now, by a message naming what was being
  collected and how many fit — `error.too_many_at_once`, with the noun quoted
  from a message of its own so it stays translatable. Each also leaves an error
  node, because what decides whether a submission runs is whether the tree
  holds one; complaining without that would report the bound and run the
  truncated program anyway, which was the first version of this fix.

  A subprogram's profile is the same defect one layer down — the parser holds
  sixty-four formals and `Symbols.Max_Parameters` is sixteen — so a declaration
  with seventeen silently became one with sixteen, and its calls were then
  refused with "expected 16" for a reason nothing had said. Refused by name
  now.

  `adash_check` refuses the pattern in the parser, which is where what is
  dropped is what somebody wrote; elsewhere a loop that stops at a bound is a
  cap on what this build looks at rather than a loss of what it was given.

  Five more sites turned up when the check was written to match what stands
  beside a bound rather than one counter's name: the choices of a case
  alternative and the exceptions a handler names counted with `Chosen`, the
  names one formal declares counted with `Named`, and two loops stopped from
  their own condition -- `and then Count < Collected'Last` -- which reads as a
  guard rather than as a truncation and is how the case statement's own
  alternatives and a body's handlers kept theirs a turn longer. All five report
  now, and the check would have caught them the first time.
- **A submission that stops early no longer takes the session's variables with
  it.** `quit`, `return` and an unhandled exception leave the hand-back
  unreached, and the documented rule is that the variables of *that* submission
  are not kept. What the build did was wider: every carried variable is
  declared again in every submission — replaying its declaration is how its
  value comes back — and the replay emptied the place the session was holding
  before the program ran. So one raise anywhere left every variable in the
  session waiting for a hand-back that never came, and each was dropped. A
  subprogram carried alongside them then stopped analysing, naming something
  that had just ceased to exist.

  The replay leaves what it finds alone now. A name the session was already
  holding keeps what it is holding until a value arrives to replace it; only a
  name it was not holding gets an empty place, and that is the one a failed
  submission loses. What a failed submission did to an older variable is lost
  with it, which is the rule as written: its effect is either all there or not
  there at all.

  Found while writing a conformance case for something else, when a diagnostic
  turned up that nothing in the case explained. Nothing covered a raise
  followed by more submissions -- which is the shape every interactive session
  takes -- so six cases and an engine test now do: what a failed submission
  keeps (its subprograms and its types, deliberately) and does not (its
  variables, and what it did to older ones), a handled exception as the
  contrast, two raises in a row, a raise from a subprogram and from a task, a
  protected object's state across one, and a sourced file that raises.
- **The unconstrained array type**: `type Line is array (Integer range <>) of
  Integer;`, which is what a subprogram taking arrays of several lengths is
  written with. A variable of one says how long it is where it is declared,
  `X : Line (1 .. 4)`; a parameter of one takes a run of any length, and
  `'Length` and `'Last` are asked of the value rather than of the type.

  A variable of one takes its length from a constraint, `X : Line (1 .. 4)`, or
  from what it is given: `X : Line := (1, 2, 3)`, another array of the type, or
  a slice of one. Ada reads it that way and a script wants it that way -- the
  length written once, in the thing that has it. Only a positional aggregate
  says how long it is: `(others => 0)` answers for the parts nothing else
  named, and where nothing says how many there are it answers for no number at
  all. Working the length out from the value means analysing the value before
  the variable's type is known, so it is analysed once and kept rather than
  twice -- a value with something wrong in it would otherwise report it twice.

  **The length travels in the place.** A composite is passed as where its run
  of slots starts, so a place now carries how long the run at it is — three
  instructions (`Run_Of`, `Extent_Of`, `Element_Place_Counted`) and one field
  on a place cell. The alternative was a second slot in every call, which is
  the machine's calling convention, and every array in the language would have
  paid for the one that needs it.

  `'First` is one, as it is for a String and for every part of one: a place
  carries a length and nothing else, so there is nowhere to keep a first index
  that is not one. A variable of such a type is therefore declared from one,
  and says so if it is not.

  **A slice of one is taken**, which is what a body working on part of a run it
  was handed needs. The ends are known where the slice is written and how far
  the run reaches is not, so the far end is checked where the program runs —
  `Run_Covers`, one instruction, against what the caller passed. What such a
  parameter does not take is a whole assignment: `R := Y` is right only when
  the two are the same length, and neither that nor the copy's size is known
  here, so it is refused with a message naming the slice as the way to say it.

  Two things fell out of doing it. An array's elements are now counted from its
  *width* rather than from what its declaration listed, which is what lets one
  declaration answer for the array, a slice of it, and a variable of an
  unconstrained type — the same arithmetic the slice work needed in two places
  by hand. And `Is_Acceptable` learned that an open type takes any length,
  beside the length check it learned for slices.
- **A slice as an argument** is pinned rather than added: a composite travels
  to a subprogram as where its run of slots starts, so a slice of the
  parameter's own length already went where the array goes and the callee wrote
  through it. Two cases and a line of the reference now say so, because
  behaviour nothing asserts is behaviour nobody can rely on.

  What is *not* here, and is now stated with its cost rather than left as a
  one-line limit: a parameter that takes more than one length. That is Ada's
  unconstrained array type, and the reason it is a feature rather than a fix is
  the calling convention -- a composite parameter is one slot holding a place,
  so a length would be a second slot in every call, and with it would come a
  `'Length` that is read rather than known (and so no longer usable as a case
  choice, an aggregate index or a subtype bound), an element check against a
  count rather than a bound entry, and a block copy whose size is a value.
  Doing it to the parameters of a constrained type would take staticness away
  from programs that have it today.
- **A part of a part, for an array too**: `A (2 .. 5) (1 .. 2)`,
  `A (3 .. 5) (2)`, and as deep as it is written. Each level answers about the
  level outside it, which came down to one thing: how many elements a type
  holds is read from its width rather than from what its identity was declared
  with. A slice shares the array's identity and is shorter, so asking the
  declaration bounded an inner slice -- and an index into a part -- by the
  whole array. Both the analyser and the instruction that checks an index name
  the part now, so `A (2 .. 3) (5)` reports against `Row (2 .. 3)` and the two
  numbers in the message are the two a reader can compare.

  Positions inside a part begin where a value of the type begins: one for a
  String and for an array declared from one, and the array's own first index
  otherwise. `F (6 .. 8) (5)` is the first element of the part, for an array
  declared from five.

  The array analysis moved into a function of its own to be asked twice -- once
  of a name, once of whatever a part yielded -- which is what let the two
  shapes stay one implementation rather than two that drift.
- **An array is sliced**: `A (2 .. 3) := B (1 .. 2)`, and `=` between two
  slices. A slice is a place and never a value, which is what every composite
  is here -- so the copy is the block move a whole array's assignment already
  was, from a start moved along to the first element the slice covers, and the
  comparison is the same block comparison.

  Its ends are known before the program runs, as an array's own bounds and a
  case choice are: what a slice becomes is a distance and a count of slots,
  both written into the instruction. A bound that is not static gets the
  refusal an array's own bound gets, in the same words.

  A slice's type is the array's identity with a length of its own, and
  `Is_Acceptable` now compares the lengths of two composites -- which is what
  stops `A := B (1 .. 2)` from copying two slots into three and reading a slot
  belonging to something else. The type carries its ends in its name, so the
  refusal reads `found=Row (1 .. 2), expected=Row` rather than naming `Row`
  twice and leaving a reader to work out which side was which.

  No null slice. Ada's `A (3 .. 2)` is a value of no elements; a value here is
  a run of slots and a run of none is not one, so a backwards slice is refused
  alongside an end outside the array -- `error.no_such_slice`, the one message
  this added.

  One conformance case changed rather than being added to: `A (1 .. 2)'Image`
  had been pinned as the refusal of an array range, which was the right
  expectation for a language that did not slice arrays and is the wrong one for
  a language that does.
- **A part of a part is assigned to**: `S (2 .. 5) (1 .. 2) := "XY"`, as deep
  as it is written. Each level yields the text of the level outside it and the
  outermost change is stored in the variable the chain bottoms out at, so one
  statement is one store. The instructions were already the right shape for it
  -- each takes a whole and yields a whole -- so this is the order they are
  emitted in rather than anything new in the machine, and each level checks
  against the length it can see, which is what makes the message name a number
  the reader can find in the line.

  The owning variable's symbol travels out through the chain, as it does
  through one level, so a constant's or an `in` parameter's nested part is
  refused by the name of the String. A chain rooted in a call is refused by the
  name it is written on: `F (1 .. 4) (1 .. 2) := "XY"` names F.

  Positions inside a part are the part's own, counted from one. Ada's slice
  keeps the index range it came from, which makes this expression an error
  there; a String here is a value rather than a view of one, and there is
  nowhere to carry a lower bound that is not one. `ROADMAP.md` says so under
  what is imperfect rather than leaving it to be discovered.
- **A part of what a call yields**: `F (2 .. 4)`, `F (1) (2 .. 4)` and
  `S (2 .. 5) (1 .. 2)`, which Ada writes and this had reported as a call with
  one argument -- or, for a prefix that was itself a call, as an undeclared
  name with nothing in it. What tells the two apart is the range, which no call
  could take, and the prefix being a call already, which means it yields a
  value rather than being one. Read only: a value has nowhere to put anything,
  and assigning to one is refused by name.

  Two things came out of it. `A (1 .. 2)` on an array had been read as the
  position at the low end -- a wrong answer given confidently -- and is refused
  now, since Ada slices an array and this does not. And a call to a package
  member returning a String was briefly lowered as a slice while this was being
  written, which the packages example caught: the rule that tells the shapes
  apart is stated in the analyser and read back in the lowering, so both had to
  say the same thing. One message added, `error.not_taken_apart`.
- **A part of a String is assigned to**: `S (2 .. 4) := "xyz"` and
  `S (2) := 'x'`, which is how a script fixes a field of a fixed-width line
  without rebuilding the line around it. Two instructions, `Text_Set_Element`
  and `Text_Set_Slice`, because a String is one cell rather than a run of slots
  and there is no place inside one to store to: the machine builds the whole
  text changed and the assignment stores that. What the checks catch is Ada's:
  a position or a bound outside the String raises where a read of one does, and
  a value that is not as long as the slice it goes into is `Constraint_Error`
  rather than a String that is quietly the wrong length --
  `error.machine.slice_lengths`, the one message this added.

  It also closed a hole that had been open since slices were readable. What a
  part of a String may be assigned to is what the String may be, and the check
  the other composites had was missing here because a String part carried no
  symbol for the assignment to ask about -- so `S : constant String := …;
  S (2 .. 3) := "XY";` was quietly written, as was an `in` parameter's. The
  part carries the prefix's symbol now, as an array element already did, and
  both are refused by the name of the String.
- **Membership against a type mark**: `X in Small`, `X not in Colour`, and a
  mark that may carry dots. The bounds are the type's own, so this emits the
  two comparisons the range form emits with constants from the declaration
  rather than from an expression, and the value is evaluated once as before. A
  mark that names something other than a discrete type is refused where it
  stands -- a variable is not a type, and `X in String` has no first value to
  compare against. Ada admits `X in Float` and answers True always; this
  refuses it rather than emitting a test that cannot fail.

  Doing it the way a `for` loop over a named type already does it -- parser
  records the shape, semantics decides what the name denotes -- found a defect
  in the loop: `for C in P.Verdict loop` reported an undeclared name with
  nothing in it, because a type mark naming a package member is one name with a
  dot in it and the loop handed over an expression's reach into a value. Both
  fold it to a name now.

  This one was documented as a deliberate boundary, with the reason "there are
  no subtypes to name". That was true when written and stopped being true when
  subtypes arrived. It was found by probing the documented limits, not by a
  test failing, which is what a claim about behaviour is: a test nothing runs.
- **Every conformance case now runs on every host.** The gap the entry above
  admits is closed, and closed the way it said: by giving the cases a program
  they can name anywhere rather than by dropping the key. `adash_test_emit`
  gained `--exit`, `--error`, `--sleep` and `--file`, so one shipped companion
  covers a program that fails, one that complains where nobody collects it, one
  that is still running, and one that shows what a file holds;
  `adash_test_upcase` covers pipelines and `run_from`. The runner expands
  `{emit}` and `{upcase}` -- in expectations as well as in scripts, which is
  what lets a job case assert the command line it reports -- and `{os}` and
  `{arch}`, which is what lets the two `--version` cases stop being Linux-only.
  Thirty-two cases lost their `platforms` key; no case carries one now. The key
  stays supported, because the next case that genuinely cannot hold on a host
  should say so.
- **The last three guides**: `user-guide.md`, `interactive-guide.md` and
  `scripting-guide.md`. The interactive one is why they waited: editing,
  completion, the prompt and the interrupt cannot be checked by running a
  script. They were written from a session driven through a pseudo-terminal, so
  what they say is what the shell did -- the `!` failure marker that comes
  before the directory so a narrow terminal keeps it, the `...` continuation
  prompt with no directory on it, Tab completing `ver` to `version` and listing
  the matches when there are several, Up recalling a whole multi-line
  submission, Ctrl-D exiting 0. `docs/README.md` owes nothing now.
- **`docs/grammar-reference.md`**, and a repository check that keeps it true.
  Every production names the syntax node it builds, and `adash_check` compares
  the document against `Adash.Language.Syntax`'s enumeration in both
  directions: a construct the parser can build with no production fails, and so
  does a production for a node that no longer exists. The check was proved by
  removing one name and watching it fail. This is the answer to a grammar
  written beside a parser drifting the day the parser changes -- the prose is
  still written by hand, but what it must *cover* is not a matter of memory.
- **Six more reference documents**: `execution-model.md`, `job-control.md`,
  `configuration-reference.md`, `persistence-formats.md`,
  `conformance-guide.md`, and `diagnostics-catalog.md` -- the last generated
  from the catalog, all 409 messages by identifier. Two entries in the index
  turned out not to be owed at all: `release-guide.md` is `RELEASE.md` under
  another name, and `ai-package-map.md` would be a third copy of what `AI.md`
  and `package-map.md` already carry. Four remain, and the index says why each
  is still absent rather than listing it as scheduled.
- **A call to a predefined entity or an internal command may name its
  arguments**, as a call to a program's own subprogram always could:
  `Index (Piece => "b", Whole => Line)`, `Put_Line (Item => Text)`,
  `cd (Directory => "/tmp")`. What pushes an argument travels by position, so
  the lowering asks the callee's own parameter names -- through
  `Adash.Predefined`, which answers for a command as well, because the language
  may not reach up to `Adash.Commands`. A name that is not a parameter, or one
  given twice, is now reported as that rather than reaching the lowering and
  being called an expression this build cannot run.
- **`docs/predefined-functions.md`** — the twenty-eight names a program has
  before it declares anything: six types, two constants, three procedures and
  seventeen functions, read out of the registry in `Adash.Predefined`. Writing
  it found that **a call to a predefined entity or an internal command cannot
  name its arguments**, though a call to a program's own subprogram can, and the
  refusal arrives from the lowering rather than the analyser. That is now a
  conformance case as well as a sentence.
- **`docs/internal-commands.md`** — every internal command, what it takes, what
  it does and what it reports, with the arity and parameter names read out of
  the registry in `Adash.Commands` rather than from the help text. Written after
  reading `help` like a stranger to answer a question about this shell, which is
  what an absent reference costs.
- **`docs/language-reference.md`**, the first of the fourteen reference
  documents the index has owed since the phases finished. It says what is in the
  Ada subset, what each construct means here, and where the subset ends --
  written from the conformance cases rather than from memory, because those are
  the only description of the subset that is verified. Every claim in it was run
  before it was written down, which caught one: a literal brace in an
  interpolated string is escaped, not doubled.
- **Nine internal commands had no conformance case**: `unset`, `env`,
  `run_into`, `run_from`, `run_append`, `run_new`, `pipe`, `pipe_run` and
  `save_settings`. Some were covered by AUnit cases, but none was exercised
  through a submission -- the suite that runs the shell as a user meets it did
  not touch redirection or pipelines at all. Seven cases now do, and each of
  them had to solve the same problem: an assertion that is the same on every
  machine. `env` clears the sandbox's own variables first so the list is what
  the script asked for; the redirection cases name files through `{store}`;
  `save_settings` prints a path that differs per machine, so its case checks the
  file and carries the assertion in the exit status instead.
- The sweep reached `docs/`. `package-map.md` opened with "every package that
  exists today" and named 18 of 54, closing with a list of subsystems that "do
  not exist yet" -- the language, the machine, execution, the interactive
  session, all of which have existed for a long time. It is rewritten from the
  sources: every package, its subsystem, and which crate it reaches outside
  Adash for, with the two essays that were still true kept. `test-guide.md`
  described two tools where there are four, and listed a coverage that predated
  the conformance suite; it now says what each of the four covers, and that
  `alr test` runs only the AUnit suite. `docs/README.md` framed fourteen
  reference documents as scheduled by phase when all sixteen phases are
  complete: they are owed, not pending, and it says so. `benchmark-guide.md`
  and `RELEASE.md` were checked against what the tools actually print and do,
  and needed nothing.
- The sweep reached the shell-facing examples. Every claim in them was run:
  standard error is not collected, only the trailing newline is dropped, an
  argument with a space in it is one argument, an unset variable reads empty, an
  unreachable path answers False rather than failing, appending makes the file,
  an empty line is told apart from the end of the input, and 126, 127 and
  128 + n are what they say. One had drifted:
  `examples/internal-command.adash` still said a submission is either commands
  or program statements and called joining them "the largest thing this
  language still owes its users", two files away from the example that shows it
  done. It now shows a command mixed with statements instead of denying it.
- `docs/command-calls.md` read as current design for work that landed long ago,
  and described the instruction set of a machine this build no longer runs. It
  said at the top what it was: history, kept for the reasoning rather than the
  mechanism, because the expensive finding was that there were *two* gaps and
  that one mechanism had to close both. Its "what this will make possible" is
  written as what it
  made possible, with each claim in it run before saying so.
  `docs/README.md` lists it as history.
- **`X'Range`** stands wherever a range stands -- a loop, forwards or
  backwards, a membership, a case choice, an aggregate's index -- built where it
  is read as the two ends Ada defines it to be, so nothing downstream learned a
  new shape. The one attribute whose name is a reserved word needed the
  attribute reader to accept a word where it wanted an identifier.
- **A run of parts may be named at once**: `(1 .. 2 => 7, others => 0)`, and
  `(X'Range => 0)` for all of them. Every part still gets exactly one value, so
  overlapping runs and a run reaching past the end are refused by name.
- **Overload resolution reaches both open ends.** `F = G` where each name
  belongs to two subprograms sharing one result, `Red = Amber` where two
  enumerations name a `Red` but only one an `Amber`, and `Show (F)` where the
  call and its argument are each several things -- all settled by asking which
  single type both ends could have, without choosing and without reporting. Two
  combinations fitting is still ambiguous, which is Ada's answer as well.
- **An attribute is a value known before the program runs.** `Integer'Last`,
  `Verdict'First`, `Colour'Succ (Red)`, `Integer'Pos (7)` and `Integer'Size`
  may now stand where a case choice, a subtype bound or an aggregate's index
  stands. One function answers that question for the whole front end, so it
  paid three times over. An array's `'First`, `'Last` and `'Length` answer
  about its index range; a String's are not static.
- **A case naming the whole of `Integer` ended the analyser rather than the
  program.** Counting how many values the choices covered overflowed on a span
  one wider than the largest number there is. The count saturates now. Nothing
  could write that program until attributes became static, which is why it had
  not been seen.
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
  mechanism that gives it, and explained the hand-back's design by what an
  interpreter this build no longer runs did not offer. Both corrected, and what
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
  say how far it goes. Lowered to the element, slice and length instructions,
  so an index past the end raises there rather than reading what was next.
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
  emitted as one instruction per type so the text is Ada's.
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
- **An aggregate is an argument at a call.** `Total ((1, 2, 3))` builds the
  value in a run of the caller's own slots and hands the call where that run
  starts, which is what a composite argument is; it was refused before, so the
  value needed a declaration one line above its only reader.
- **An anonymous array type**, `A : array (1 .. 3) of Integer;`. Every symbol
  carries a name, so the parser makes one from the object's — with an
  apostrophe, which no name a user can write has — while the type is *called*
  what it was written as, which is what carrying the variable into the next
  submission writes out again.
- **Conditional expressions**: `(if A then B else C)` and `(case X is when 1 =>
  A, when others => B)`, in the parentheses Ada requires and without them where
  Ada allows it — a call's only argument. The `else` is always written, because
  a reader of `(if Ready then Done)` should not have to know the type to know
  what it yields; a case expression's alternatives are the case statement's,
  analysed and emitted by the same code.
- **A record component's default**: `type Line is record Number : Integer := 0;
  ... end record;`, written into the object where the object is declared. The
  default is a literal, as a parameter's is and for the same reason.
- **Explicit conversion between the numeric types**, `Integer (F)` and
  `Float (I)`, and to a subtype of either, where it is the constraint check
  written where it applies. To an integer type it rounds to the nearest and
  away from zero at a half, which is Ada's rule. The language reference had
  claimed a conversion for some time; there had never been one.
- **A named number**, `Max : constant := 100;` — no type mark, and the value
  says what it is. Ada's is universal and mixes with an Integer and a Float
  alike; here nothing converts implicitly, so it is whichever its value is.
- **A qualified expression qualifies an aggregate**: `Row'(1, 2)`, which is
  what one is most often written for, an aggregate having no type of its own.
- **Overload resolution narrows from three directions.** What the context
  requires reaches a call's arguments through the candidates it rules out, as
  far down as the calls nest; an argument that can only be one thing rules
  candidates out for the arguments beside it, whether written positionally or
  by name; and an operator's settled operand rules out what its open one can
  be, so `put_line (F & "x")` reads F as the String.

- **A script reads in what it sources.** `source ("helpers");` at the top of a
  script is read into the script's text where it stands, so the names the
  module declares are in scope for the rest of the file. A script is one
  submission and a submission is analysed as a whole before any of it runs, so
  a call that only *ran* the other file came too late for the analysis -- which
  is why a script could not be factored into modules at all. Only a literal
  name, and only at the top of a submission; a computed name stays a command
  that runs a file when it is reached, and a file that would read itself back
  is left as one, so running it reports the cycle. Diagnostics about what was
  read in name the file it was written in.

- **A diagnostic about a file says where, and shows the line.**
  `report.adash:12:7: Total is not declared here`, then the line itself with a
  caret under what it is about, in the form every compiler writes: the position
  was in the data all along and nothing printed it, so a script with a mistake
  on line forty said what was wrong and left the reader to find it. The caret
  is placed in terminal *cells*, so a line holding an accented or a wide
  character still carries one that points at the right place. A file a script
  read in names itself and its own line. A line typed at a prompt gets no
  position -- it is on the screen already -- and neither does something with no
  place in the text: a file that could not be read, or a program that raised,
  which is a run rather than a place.

- **A diagnostic that is about more than one place says all of them.** "X is
  already declared" prints `declared here` under it, pointing at the first one;
  an aggregate that gives a component twice and a case choice that covers a
  value twice each print `the first one is here`; and an ambiguous name prints
  every declaration it could have meant, which is the diagnostic a reader can
  do least with on its own — including
  when the two are in different files, which reading a module in makes
  possible. The place travels as a related location: the scope chain keeps the
  span it has, the analyser attaches it, and the engine gives it a line from
  the buffer. `Adash.Diagnostics.Related_Location` had been declared and
  carried since the diagnostics subsystem was written and nothing had ever put
  one on a diagnostic or rendered one.

- **A line typed with a space in front of it is not remembered.** The mark
  other shells use, and the only one that can be typed in front of a command
  without changing what the command means, since the lexer skips it. The line
  runs; what is missing is the entry, in the session and in the file both, and
  not even a placeholder -- a record of *when* a secret was typed is still a
  record. `Adash.Interactive.History.Record_Line` had taken a `Sensitive` flag
  since it was written and nothing at the prompt had ever set it, which is a
  mechanism with no way to reach it. What is marked is the submission and not
  each line of one, so an indented continuation decides nothing and a
  multi-line construct is forgotten whole. On by default -- a protection that
  has to be switched on first is off in the session where it was needed --
  and `history.ignore-space` turns it off.

- **`forget` takes back a line already recorded.** The mark above has to be
  typed before the line, and this is the other half: `forget;` removes the last
  entry, `forget (3);` the last three, from the session and from the history
  file both. It takes itself with it and does not count itself -- a history
  whose last entry is the command that emptied it has kept a record of the act.
  A count below one is refused rather than read as "all of it", which is what
  `history (0)` means: a command that destroys more than it was asked to must
  not be reachable by a typing mistake. Removal is **by text, last occurrence
  first**, because a shared history file holds what several shells wrote
  interleaved and a position in it is not a line; it reaches what the session's
  log holds, which includes what was read from the file at start-up, so a line
  typed yesterday can be forgotten today. `Adash.Persistence.Update` is new
  underneath it: read, change and write under the one lock Write and Append
  already take, so a line another session appends meanwhile is not lost. It is
  the only operation that rewrites a history file rather than appending to it.

- **The recorded benchmark figures are current again.** `benchmarks/README.md`
  now carries a run of this build beside the first one, and the finding is that
  a month of work moved nothing: the analyser's fastest run is 780.9 us against
  779.6 us recorded before. Diagnostics that carry a position cost nothing on a
  submission that has none, source inclusion happens once per script rather
  than per line, and the history work is in the frontend. The one gap in the
  report -- analysis, whose fastest run sits a tenth below its median -- was
  checked at 200, 2000 and 5000 repetitions: the fastest stays at 765-795 us
  and the median near 890, so it is scheduling noise on the largest figure and
  not an operation that degrades as it repeats.

- **Windows asserts more of what it does.** A gate keeps a case off a host that
  cannot hold it; what nobody was checking on that host at all is the harder
  question, and five things now are. A script whose every line ends CR LF runs,
  and a diagnostic about one gives the right line and column and quotes the
  line without the carriage return that ended it -- the two fixtures are pinned
  to CR LF in `.gitattributes`, which holds the rest of the repository to LF,
  so all three hosts assert it. A backslash in an ordinary string is a
  backslash, which is how a Windows path is written, and needs doubling only in
  an interpolated string. The shell runs the shell through `{shell}`, which
  carries whatever suffix the host puts on an executable. A job is listed as
  running by a host that cannot signal it, which is the half of `jobs` that the
  signal-gated cases could not reach. And where hostkit reports no signals, a
  unit case asserts the shell does not believe it armed a disposition:
  installing succeeds, being installed does not, nothing is ever pending, and
  sending refuses.

  Three case requirements said "what Windows does instead is not asserted at
  all yet" and described `stop` there as terminating the process. Both had
  stopped being true: the Windows case asserts that `stop` refuses. Prose in a
  test is a claim like any other.

  Two cases still started `sleep`, a POSIX utility, where the rule this suite
  states is that a case needing a program names a companion. They name
  `{emit} --sleep=5` now.

- **The shell is driven through a terminal on Windows too.** hostkit grew a
  pseudo-console body -- `CreatePseudoConsole` and two ordinary pipes, attached
  to a child through a process-thread attribute -- and `Hostkit.Pty.Attach` is
  the one call that knows whether this host hands a child a device or a
  console, so the harness is one program rather than two. The six cases that
  drive the shell through a terminal now run on all three hosts rather than
  two: a whole session, Tab completion, Up recalling a line, Up not recalling a
  marked one, and backspace. Reads ask `Hostkit.Descriptors.Wait_Readable`
  first, because a Windows pipe has no non-blocking mode and a read of an empty
  terminal waits; the AUnit step gained a watchdog for when that is not enough.

  **Ctrl-C at the prompt** is asserted everywhere too: it abandons the line
  being typed, the next line runs, and the abandoned one never does. That is
  the editor's half of an interrupt and needs no signal.

  Ctrl-C *while a program is running* stays off Windows, and what is known is
  now measured. A companion that sits on a terminal and writes down what
  reaches it recorded three things there: a Ctrl-C typed as the byte arrives; an
  accented character arrives in the console's code page, which is what raw mode
  now asks to be UTF-8; and a program that is not reading, on a terminal asked
  to report an interrupt key, *is* told about a Ctrl-C -- which is the shell's
  own situation while a submission runs.

  The shell still does not stop, with the recording armed, the terminal asked
  before every submission, and the machine looking between instructions. What
  differs between the probe that works and the shell that does not is a
  terminal the shell has already read a line from, and that is where the next
  attempt starts.

  The accented half of the backspace case stays off as well, after three ways
  of typing that character at a console: the UTF-8 as it stands, the key event
  the console asks for with virtual key and scan code left at nothing, and the
  same with `VK_PACKET`. None reached the shell. A key event for a key that
  *exists* does -- Ctrl-C is sent that way and the editor sees it -- so the
  remaining guess is that the path wants a virtual key it can map. The shell
  was asked, and goes on answering afterwards, so what is missing is the
  keystroke rather than the editor.

- **An argument that is an expression settles the call it is in.** `Show (F, F
  & "z")` reads the concatenation as the String it can only be, and the call
  with it; before, only a literal or a name with one meaning counted as saying
  anything, so an operator expression left every candidate standing and the
  call was reported ambiguous with the answer written in front of it. The same
  for what an arithmetic operator, a comparison, a logical connective, a
  membership test and a qualified expression yield.

  And in the other direction: **`not` requires a Boolean of what it negates**,
  which is what makes `not F` the F that yields one -- the code passed nothing
  down, on the reading that "`not` is Boolean either way" was a statement about
  its result rather than about its operand. `and`, `or` and `xor` require
  Boolean of both sides, there being nothing else they apply to here. A sign
  requires a number, so `-F` and `abs F` are the F that yields one where
  exactly one reading does.

- **`forget ("...")` takes a line by its text**, every copy of it, from the
  session and from the file. It reaches what a count cannot: a count can only
  remove what the session's log holds -- the last `history.limit` entries --
  and a line older than that is in the file and was never read back. One
  command rather than two, the parameter taking whatever it is given, because
  a number and a line of text are two ways of saying which entry. The `forget`
  line goes with them, which matters more here than for a count: the line that
  names a secret contains it. What is reported is what was asked for, counted
  once whether it was in the log, the file, or both.

- **The cache store's promise is tested rather than assumed.** Nothing in this
  build caches anything -- a cache is a second copy of the truth and every one
  is a chance to serve a stale answer, so there will be none until something is
  worth caching. What the three stores exist for is that a system emptying the
  cache directory, which it may do unasked, costs a user nothing they would
  miss; that now has a case behind it, asserting the three directories are
  distinct and that neither the history nor the settings is inside the cache.
  An unused mechanism is one nobody would notice going wrong.
  `persistence-formats.md` says what would use it first.

- **Tab completes the name of a program to run.** Inside the string that says
  which program -- `run ("gi`, `start (`, `pipe (`, `Output_Of (`, and the
  file-taking forms at their second argument -- the search path is walked and
  what could be run is offered. Nothing else is offered there: a command name
  or a keyword inside a string is not something anybody could have meant, and
  until now that is exactly what a Tab there produced.

  The path is the session's own, threaded from the engine rather than read from
  this process's environment: `set ("PATH=...")` changes what a child is
  started with, so it changes what Tab offers.

  The host does the matching. Listing every directory on the path and filtering
  the names here cost 58 milliseconds a Tab -- a pause a user feels -- and
  handing the prefix over as the search pattern brought it to about three, with
  the question "can this be run" asked only of the names that already matched.
  `adash_bench` has a row for it, because it is the one completion that leaves
  this process's memory.

  What is offered is what a user would type: where the host supplies a suffix
  for a name written without one -- Windows appends `.exe` -- the offer leaves
  it off, `git` being the program's name there as much as anywhere.
  `Hostkit.Fs.Executable_Suffix` is new for that, and is deliberately not the
  whole of PATHEXT.

  And only what this shell could start. Windows calls a `.ps1` and an `.msi`
  executables and starts neither from a name, so offering one would be offering
  a name that fails when it is run -- and the failure would read as being about
  the program. `Hostkit.Fs.Starts_When_Named` is that narrower question, the
  same answer as `Is_Executable` on POSIX where the kernel starts what has the
  bit set.

  A `.bat` is offered, because that host does start one: it runs the command
  interpreter for it itself. This was written down the other way round first,
  from reading how process creation works rather than from watching it, and a
  conformance case gated to that host reported the shell running a batch file
  perfectly well. Both sides of the boundary are cases now: a batch file named
  in full runs, and a `.ps1` named in full is refused while the session goes
  on. Which diagnostic Windows produces for a failed process creation is left
  unasserted -- that is the host's word rather than this shell's behaviour.

  Case is folded, as it is everywhere else in the list: the prefix is handed
  over as the class of each letter's two cases, so `GI` completes to `git` on a
  host whose file names are case-sensitive too. What is inserted is the
  program's own spelling, which is what runs. A prefix carrying a character the
  pattern language reads specially is handed over as "*" and filtered here
  instead -- slower and unable to be wrong, where guessing at an escape would
  be fast and differ between the hosts.

- **`Read_File` is `write_file`'s other half.** A shell that can put text in a
  file and cannot get it back is one whose scripts run `cat` to read what they
  just wrote -- a program start for something the shell can do itself, and a
  program only two of the three hosts have. It is a question, so it is a
  function with no consequences: a file that is not there reads as nothing,
  which is what a script appending to a log wants on its first turn, and
  `Exists` is how "nothing there" is told from "nothing in it". A file that is
  not UTF-8 reads as nothing too, because a String in this language is text.
  `examples/writing.adash` uses it instead of `cat`.

- **`Current_Directory`, and two examples that no longer need a program.**
  Where the session is is something the shell knows, since `cd` moved it; a
  script that asked `pwd` for it paid a process start for an answer already in
  hand and only ran on hosts that ship the program. With it and `Read_File`,
  `examples/paths.adash` and `examples/writing.adash` run on every host rather
  than being skipped on Windows -- and the conformance runner now gives each
  example a directory of its own to run in, which is where a writing example
  puts its files instead of asking `mktemp` for somewhere.

- **`make_directory`, and every example now runs on every host.** `write_file`
  into a directory that is not there is refused, and a script had no way to make
  one — so a shell that could save a file could not decide where to put it, and
  reached for a program to make the place. It makes every missing directory in
  the path, is not a failure when the directory is already there, and refuses
  what is not a directory in the way. With it, and with `Read_File` and
  `Current_Directory`, the four examples that were skipped on Windows are
  skipped nowhere: the two that read a POSIX utility ask the host which programs
  it has and say the same thing either way, which is a lesson the examples were
  quietly avoiding.

- **`Output_Of` will not collect more than the limit either, and the limit is a
  setting.** A program that never stops writing had the same ending a huge file
  did: the shell grew until the host ended the session. Past `read.limit` the
  pipe is closed, which ends the program by its next write rather than by a
  signal -- the mechanism that works on the host with no signals -- and the
  capture is refused whole. The shell's own `Read_Line` is bounded too, but
  differently: input that has been read cannot be asked for again, so a line
  longer than the limit arrives in pieces rather than being dropped.

- **All three readers' line-ending rule is asserted, and writing's is written
  down.** `Read_Line` had only its own comment for the carriage return it drops;
  a case supplies input spelled the Windows way and asserts it, and asserts that
  a lone carriage return stays where it is. Nothing puts a carriage return back
  on the way out, which is deliberate -- a shell that added them on one host
  would make `write_file (Read_File (P), Q)` change the file it copied -- and
  was written nowhere until now.

- **`Read_File` hands back text as well.** It kept the carriage returns a
  Windows file has while the shell's other two readers dropped them, so a script
  comparing what it read against text it wrote itself failed on that host and
  nowhere else -- the same defect the capture had, one reader along. Three
  readers of one language disagreeing about what a line ends with is worse than
  any of the three answers. A lone carriage return is still left where it is.

- **`Output_Of` hands back text, not the host's line endings.** A program on
  Windows ends a line with a carriage return and a line feed, so a capture with
  two lines in it carried a stray carriage return inside -- invisible, and
  enough to make every comparison against text the script wrote itself fail on
  that host and nowhere else. Found by asking why one conformance case failed
  there and passed on the other two, which is the only way anybody was going to
  find it.

- **A store file past the limit says it is too large**, rather than saying it is
  not text. Telling a user their configuration file is not valid UTF-8 when it
  is sends them looking for a broken byte that is not there; nothing is wrong
  with the file except its size.

- **The shell's own reads are bounded too.** The setting covers what a script
  reads; a script file itself, a module read into one, and the configuration and
  history files were still read whole, so `adash some-disk-image` was a session
  that grew until the host ended it rather than a refusal. They are bounded by
  the same default -- not by the setting, since three of the four are read
  before there is a setting to consult -- and a script too large is refused by
  name with `error.source_too_large`.

- **`read.limit` is a setting**, in mebibytes, default 16, alongside
  `history.limit`. How much of a file is too much is a judgement about the work
  rather than a fact about shells, and somebody whose work is a
  large-but-legitimate file should be able to say so instead of reaching for
  another shell.

- **`Read_File` will not read more than 16 MiB.** A shell holds what it reads in
  one String, so a script that named a disk image or an unrotated log by mistake
  had the session grow until the host stopped it, taking everything in it. The
  file is refused whole rather than truncated -- half a file is not a shorter
  file, and a script cannot tell which half it got -- and this refusal is said
  out loud, unlike the ordinary ones: silence would tell a user their file was
  empty and send them looking for a reason it is not.

- **A job waited for gets the terminal.** `wait` puts a job in the foreground in
  the only sense a user means by the word, and it waited through the same call
  `run` does without the handover `run` had just been given -- so a job that
  asked a question was stopped where it asked. (`resume` needs nothing: it
  resumes into the background, and there is no foreground resume to fix.)

- **A directory name the host will not form is refused, not failed.** Every host
  has a limit on how long one part of a path may be, and `make_directory` called
  a name past it a write that did not finish -- sending a user looking for what
  was half done. A directory is made or it is not. Every complaint the host
  makes is answered the same way, deliberately: the same over-long name is one
  exception on one host and another elsewhere, and sorting by which arrived
  would report the compiler's mapping rather than what happened.

- **`Read_File` of a directory reads as nothing**, and now says so where it is
  documented and asserts it where it is tested. The same answer as a file that
  is not there, for the same reason; `Exists` and `Is_Directory` tell them
  apart.

- **Saying where a pipeline's streams go is no longer the same thing as running
  it, and `Last_Job` says what was started.** The nine placement forms ran the
  pipeline as well as placing it, so a pipeline could be given a file to read or
  a file to write and never both -- and `pipe_start` took no file, which meant
  "run this in the background with its output in a log", the commonest reason to
  background anything, could not be said at all. They record now, as `pipe_from`
  does, and `pipe_run` or `pipe_start` runs. `Last_Job` is the number the shell
  just gave a job: `start` and `pipe_start` print it, which is where a person
  reads it and nowhere a script could.

- **The scripting guide and an example teach the three families.** Twenty-odd
  commands and six functions had existed only as rows in a reference table:
  `examples/pipelines.adash` runs a pipeline into a file, into a value, into a
  log of both streams, and into the background, and the guide says where what a
  program wrote goes and how a pipeline is built. Writing the example found two
  things worth knowing, and both are in it: a running form empties the pipeline,
  so a script wanting two of them builds it twice, and the job number is the
  shell's -- it counts every job it has run, foreground ones included.

- **`pipe_start`.** `start` put one program in the background and nothing put a
  pipeline there, so a script that built one had to wait for it -- the last
  direction this family left open. It is a job like any other afterwards, and it
  takes the background input rule with it: nothing to read rather than the
  keyboard the shell is holding, unless `pipe_from` said otherwise.

- **`pipe_from`, and `Output_Of_Pipe` with its two companions.** The nine forms
  below cover where a pipeline's output goes and neither where it comes from nor
  how a script reads it. `pipe_from` attaches a file to the first stage and runs
  nothing -- a pipeline reading one file and writing another would otherwise be
  two commands each insisting on running -- and the three functions run the
  pipeline built so far for what it wrote rather than for where it wrote it.

- **A pipeline's streams have somewhere to go.** Everything a single program
  gained -- three files for output, three for complaints, three for both --
  stopped at the moment a script used more than one program: a pipeline could
  only run, and its output went wherever the shell's went. The nine `pipe_*`
  forms are the nine `run_*` forms, and they redirect the last stage, which is
  the one whose output is the pipeline's.

- **A pipeline waited for gets the terminal**, which `run` and `wait` were
  given and `pipe_run` was not: a stage that asked a question was stopped where
  it asked.

- **`All_Of`.** The reading half of `run_all_into`: everything a program wrote,
  in the order it wrote it. A script could send both streams to one file and
  could not read both back as one answer, so anything that wanted to look at
  what a program did rather than store it had to write a file and read it again.

- **`run_all_into`, `run_all_append` and `run_all_new`.** Each stream could be
  placed on its own and nothing joined them, so a build log -- one file with
  what a program said and what it complained about in the order it wrote them --
  was not something a script could ask for. Pointing both at one name gave two
  open files with two positions writing over each other. The error stream
  follows the output stream into the same open file now, which is the only
  arrangement in which the order survives.

- **`Error_Of`, `run_errors_into`, `run_errors_append` and `run_errors_new`.** A shell that could put a program's
  output anywhere and its complaints nowhere left a script two things it could
  not do: keep a program's noise out of its own error stream, and read what a
  program said about a failure in order to act on it. `Error_Of` is `Output_Of`
  for the other stream and `run_errors_into` is `run_into` for it -- two names
  rather than a flag on each of the existing pair, because what a program says
  and what it complains about are two streams for the reason that they are two
  things. Each leaves the other stream alone. The three redirecting forms are
  the three the output side has -- a log of what went wrong is the thing a
  script most often adds to rather than replaces -- and `Error_Of` is bounded
  by `read.limit` exactly as `Output_Of` is, which a case now runs past the end
  to show.

- **Analysing a submission is three times faster than this morning, and faster
  than it was before any of today's work.** `Adash.Predefined.Install` declared
  all eighty-seven of the shell's names into the chain before every analysis,
  and declaring asks whether the name is there already -- a scan of what has
  been declared so far, for each of the eighty-seven. The answers cannot change
  between submissions, so they are worked out once and adopted wholesale: 1620
  us to 493, where a fresh chain costs one append per name and no questions.

  The table is built while the package is elaborated rather than on first use.
  Lazily was the obvious way and it carried an assumption nobody had written
  down -- that no two things analyse at once -- which is true of the engine
  today but is a property of a caller, held in a package that cannot see its
  callers. Elaboration has no such question in it.

  The suspicion recorded this morning -- that the per-name registry lookups had
  grown -- was wrong, and one measurement said so: analysing one, five and
  twenty lines cost 1578, 2514 and 6518 us, which is 250 us a line and 1.3
  milliseconds that does not depend on the program. A per-name cost does not
  look like that.

- **The benchmark record was re-run.** It described a build from before the
  stream families, the readers' bounds and the write handling. Three rows moved
  and they are the three that scan the command and predefined registries --
  analysis 910 to 1620 us, highlighting 12.8 to 18.5, completing a command
  prefix 24.3 to 34.4 -- while lexing, parsing, lowering, running and opening a
  session did not move at all. Those registries grew from 61 entries to 87 in
  the same period, and both lookups are a linear scan. The record says so, and
  says it is an inference from which rows moved rather than a measurement.

- **`Stage_Count` and `Stage_Status`** say what each stage of the last pipeline
  reported. `Status` is the pipeline's own, which is its last stage's, and that
  rule hides a failure in the middle; other shells answer this with an array
  nobody remembers the name of, and this answers it in the shape the directory
  listing already has.

- **`trace.commands` announces each command before it runs**, which is `set -x`
  elsewhere -- on standard error and as a note, because tracing that wrote into
  a pipeline's data is a thing every shell user has been bitten by once.

- **A script can take things away again.** `remove_file`, `remove_directory`,
  `rename` and `copy_file`. Removing a directory takes an **empty** one, and
  that is the point: a recursive removal is one typo away from the most
  destructive thing a shell can do, and a script that means it says so in three
  lines that name what they destroy. `rename` and `copy_file` refuse to replace
  what is already there.

- **`on_exit` is `trap`.** A script that made a temporary directory had no way
  to take it away when it was interrupted. It names a subprogram the session
  declared and runs it when the session ends however it ends -- off the end,
  through `quit`, or because an interrupt stopped what was running -- most
  recently registered first, with the name resolved when it runs so cleanup can
  be asked for at the top and declared below.

- **`Program_Path` answers where a program is**, which `Is_Executable` could not:
  it needs a path, and every program a user names is on the search path. The
  host resolves it, because on Windows a name matches with any of the PATHEXT
  suffixes.

- **A script can see what is in a directory.** `File_Count` and `File_At` are
  the loop every other shell writes as `for f in *`, which had no equivalent
  here at all: a script had to run a program to find out what existed, which is
  what `Exists` and its neighbours were added to stop. They answer from one
  reading of the directory, sorted, without `.` and `..`.

- **`foreground` brings a stopped job back.** `suspend` stopped a job and
  `resume` let it carry on without the terminal, so a job stopped with Ctrl-Z
  could never be brought back to the keyboard -- the half of job control every
  other shell calls `fg`. It resumes the job and waits for it, with the
  terminal, because from where a user stands those are one act.

### Fixed

- **A script had the host's signal defaults, so Ctrl-C killed it outright.** The
  shell's policy was taken by the interactive session and by nothing else,
  which looked harmless until something depended on the shell surviving long
  enough to notice: `on_exit` is exactly that, and a script that is killed runs
  no cleanup at all. The machine stops a loop between instructions because the
  interrupt is *recorded*, and nothing was recording it for a script. Found by
  writing the case for the thing `on_exit` exists for.

- **A script's output no longer waits for the script to end.** Ada's `Text_IO`
  buffers by block, so on a pseudo-console a script that printed a line and
  then worked for a minute showed nothing until it finished -- and for a script
  that never finishes, nothing at all. A line written to a terminal is pushed
  out as it is written now; into a file or a pipe the buffering stays, because
  that is what makes writing a great deal cheap and nobody is watching it go.

  Found by the third probe of its kind: the interrupted-script case could not
  run on Windows because nothing arrived on the terminal, and rather than guess
  the probe printed every byte -- which showed the same script *did* say
  everything, at the moment it exited.

  It **did** fix that host, which took one more run to see: the probe now
  watches a script that keeps running, and on a pseudo-console it speaks as it
  goes. The interrupted-script case asks its question there again. macOS is
  where it stops now, for a different reason -- the child is gone by the time
  the interrupt is typed -- and that is written in the case with the probe
  beside it.

- **Ending after a failed write no longer runs a finalizer over it.** The
  machine reports a failed write to the program that made it and lets the
  session carry on, which is right -- and that left the process ending
  *normally*, into finalization, which closes the standard files, which
  flushes them, which fails again: `PROGRAM_ERROR` inside a finalizer and a
  stack trace on the stream that has been refusing everything. Windows showed
  this first and the fix there was too narrow; every exit point asks now.

- **The two statuses the shell exits with on its own are written down**, in the
  table and in the two pages that repeat the model: 2 for a usage error, 74 for
  having nowhere left to write. Neither ever reaches `Status` -- one happens
  before a session and the other ends it -- and a status nobody can look up is a
  status nobody can act on.

- **How to background a program with its output placed is written down.**
  `start` takes no file, and the answer is a one-stage pipeline: `pipe`,
  `pipe_all_into`, `pipe_start`. That is the whole reason placing and running
  became separate commands, and why `start` was left alone rather than growing
  nine file forms of its own.

- **Nor does anything else the shell writes.** The machine's `put_line` was
  guarded and every other line the shell prints for itself was not -- a listing,
  a prompt, a diagnostic, the usage text -- so `adash --help | head -1` could
  still end in a stack trace from a different line of the same program. A
  shell that cannot write ends with status 74, the convention for an
  input/output error, and says nothing: the place it would say it is the place
  that just failed. A test asserts the absence of the trace on every host,
  which is the part that is true everywhere -- what the shell says instead
  differs, since a signal takes it on two of the three before it can say
  anything.

  The two failures are not the same failure, which writing the tests made
  plain: a script whose `put_line` fails is a script that failed, and the shell
  exits as it does for any of those; 74 is for the shell's own lines having
  nowhere to go, where nothing is running and there is nobody to report to.

  Ending is `Hostkit.Process.End_Now` rather than a return, and that is not
  fussiness: returning runs finalization, finalization closes the standard
  files, closing them flushes them, the flush fails for the same reason, and an
  exception in a finalizer is `PROGRAM_ERROR` and a stack trace -- printed on
  the stream that has been refusing everything. The first version of this fix
  reported the failure properly and then traced anyway, and the new test is
  what caught it.

- **Writing to a reader that has gone no longer prints a traceback.** On
  Windows `put_line` into a closed pipe raises where POSIX raises a signal the
  shell refuses, and unhandled it reached the last-chance handler: fifteen lines
  of addresses where a shell should say one sentence, on the standard error
  somebody else's diagnostic was already using. It is reported as a stream write
  failure now, and the run ends -- a program that cannot say anything has
  nothing further to do.

  This is the thing that had been mistaken for a blank line ahead of a
  diagnostic since yesterday. The traceback begins with the carriage return and
  line feed that end the child's unfinished line, and everything after it was
  what nobody could account for.

- **A program the shell runs can read the terminal.** A job is started in a
  process group of its own -- that is what makes it a job, and what lets a
  signal reach the job rather than the shell -- and a POSIX terminal stops any
  program in another group that reads it. So a program that asked a question
  was stopped where it asked, and a shell running `cat` looked like a shell
  that had hung. The shell hands the terminal to a foreground job for as long
  as it runs and takes it back afterwards, for a captured program as well as a
  waited-for one. Taking it back is the other half: a shell that forgot would
  leave the terminal owned by a group with nothing in it, and its own next read
  would stop it.

- **A background job does not share the keyboard.** Only where the shell
  watches its own terminal, which is the host with no job control: there the
  shell holds the terminal raw and reads it between instructions, so a
  background program given that same terminal would race it for keystrokes and
  read them in a mode nobody chose for it. It is given hostkit's null device
  instead, so it sees end of input rather than a stream that never answers. A
  job whose input was redirected keeps what it was given. On POSIX the host
  settles this itself, by stopping a background program that reads the
  terminal, and nothing here takes that decision away from it.

- **A runaway loop in a script can be stopped on Windows too, and a program
  the shell runs still gets a usable console.** The watching was armed by the
  interactive session alone, so `adash script.adash` ran with nobody looking;
  it is armed around a script's submission as well now, and only when standard
  input is a terminal -- a script reading a pipe has no keyboard to watch, and
  a shell reading that pipe would be eating the script's own input. `Output_Of`
  hands the terminal back for the duration of the program it captures, as a
  foreground program already did: their output is a pipe, but their input is
  still the terminal. So does the shell's own `Read_Line`, which on a raw
  terminal would otherwise echo nothing and wait for a line feed that a raw
  return never sends. Type-ahead read by the watcher is written back with its
  return as a line feed, for the same reason.

- **A runaway loop can be stopped on Windows.** The shell waited for the host
  to say Ctrl-C had been typed, and there it never does: a probe spinning on a
  console is not told, and is still not told half a second after it stops
  spinning. The keystroke itself does arrive, as the byte three, at a terminal
  that is raw when the key is pressed -- so where hostkit says an interrupt
  does not reach a busy program, the shell holds its terminal raw for the
  duration of a submission and reads it between instructions, at most twenty
  times a second. A three is an interrupt; everything else goes back to the
  shared input buffer, so type-ahead survives. Anything the submission runs
  gets the terminal back for its own duration, because a program handed a raw
  console is one nobody can type a line into.

- **The history file stopped being written once the log was full.** The session
  decided whether a line had been recorded by asking whether the in-memory
  log's *count* had grown -- and a log at its limit drops its oldest entry as
  it takes a new one, so from the thousandth line of a session onwards nothing
  reached the file at all. `Record_Line` says whether it took the line now, and
  the count is nobody's answer to that question.

- **`already declared` named a line that was a byte offset.** The message said
  "on line {line}" and was handed `Extent.First` — a number that looked like a
  line and only sometimes was one. What a scope chain has is a span, and what
  turns a span into a line is the buffer it came from; the message no longer
  claims what the chain cannot know, and the place is a related location the
  engine gives a real line to.

### Removed

- `alias`, which had been registered and unavailable since Phase 9. Within a
  submission a subprogram is already a checked, composable short name for
  something longer -- what its own documentation said alias was for -- and the
  three ways to build it each cost something the shell will not spend: textual
  expansion is a second command language, a dynamic name makes the analyser
  depend on session state, and a binding invoked by another command buys nothing
  the language does not already give. `ROADMAP.md` carries the reasoning.

### Changed

- **Adash runs its own virtual machine.** The lowering emits `Adash.Machine`
  instructions, and the manifest no longer names an outside interpreter. The
  front end had grown to rival the compiler that interpreter came from, and
  reached it by building that compiler's own identifier and block tables -- a
  seam that produced defects rather than preventing them. `ROADMAP.md` records
  what the dependency gave, what it cost, and why it ended.
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

- **Reading a variable that had never been assigned killed the shell.** Any
  such read popped a machine cell of the wrong kind and the process died with
  an Ada discriminant check and a traceback; `X : Integer;` on its own was
  enough, because carrying the variable into the next submission reads it. It
  is `Program_Error` with `error.machine.no_value` now, and what carries a
  variable out of a submission asks first: one with no value is carried as its
  declaration, and a composite filled in part as the declaration plus the
  assignments it has, so a prompt where an array is filled an element at a time
  keeps what it filled.
- An anonymous array type whose definition ran past 31 characters was carried
  into the next submission under a name cut to fit, which read back as a type
  nobody had declared. The definition is kept beside the type's parts, where
  nothing truncates it.
- The pseudo-terminal test waited for the shell to exit without reading the
  terminal, so on a host whose buffer filled first the shell was still waiting
  to write and never reached its own exit. It drains while it waits now.
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
  directly above the code that emits it. It described a defect in the machine
  of the day that no longer reproduces.
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
  command sink on the way out rather than restoring it; and the lowering stub
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

Where the subset ends -- access types, derived types, a composite inside a
composite, a function returning one, generic packages, child packages, a
`private` part, `goto` and labels, `renames`, loop names, user-defined
operators, `for ... of`, and attributes beyond the seventeen listed -- is
written down in `ROADMAP.md` with a reason for each. None of it is pending
work. Generics, tasks, protected objects, user-declared exceptions and `raise`,
and aggregates were once on that list and are in the language; the list here
had not been re-read since. What follows is what is inside the subset and
imperfect.

- **Overload resolution asks narrower questions than Ada's.** What the context
  requires flows down -- into a call and, through the candidates it rules out,
  into the call's arguments as far down as they nest -- an argument that can
  only be one thing rules candidates out for the arguments beside it, an
  argument that is an expression says what it yields, `not` and the logical
  connectives require Booleans of their operands, a sign requires a number, and
  a comparison settles one operand from the other. What it does not do is
  enumerate a whole statement's interpretations, so a call where *every* end is
  open and more than one reading survives is ambiguous here -- which Ada calls
  ambiguous as well.
- **A subprogram cannot be named after a predefined one or an internal
  command.** Those accept any type, so a user's version would fit every call the
  original does and every one would be ambiguous.
- **A command call carries at most four arguments** from a program, whatever
  the command itself accepts at the prompt. The activation record the machine
  builds has a fixed shape, decided when the stub is built rather than when a
  call is written; the fifth argument is refused where it stands rather than
  lost.
- **Subprograms nest nineteen deep.** Not a machine limit since the machine
  gained static links: what it bounds is the front end, where the analyser and
  the lowering each recurse once per level.
- **Everything is passed by reference**, where Ada passes elementary types by
  copy. Reading an `out` parameter before writing it, and aliasing two
  write-back arguments, are defined here and erroneous or unspecified in Ada. No
  *correct* Ada program can tell the difference.
- **`'Image` is refused for a `String`**: Ada 2022 defines that as the text in
  quotes with non-graphic characters bracketed, which is not the text itself.
  Seventeen attributes are written, and `docs/language-reference.md` lists
  them; this entry said `'Image` was the only one long after it was not.
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

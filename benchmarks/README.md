# Benchmarks

`adash_bench` measures the operations an interactive session repeats. Build the
test crate and run it:

    cd adash_tests && alr build && ./bin/adash_bench [repetitions]

## Ceilings

Every figure has a ceiling in [ceilings.toml](ceilings.toml), and a figure over
its ceiling makes `adash_bench` exit non-zero — which is what lets CI run the
benchmarks on all three hosts on every push. A figure with *no* ceiling fails
too: a measurement nothing bounds is a measurement no run can fail on.

The bounds are deliberately an order of magnitude above what the operations
take. A shared CI runner under an unknown load is not comparable with a
developer machine, and a bound tight enough to notice the difference would
report it as a defect on every run. What a bound this loose still catches is
the thing worth catching: an operation that became ten times slower because of
what it now does.

The **drift** rule in the same file gates the other signal this report has
always printed and never failed on: a median far above the fastest run means
the operation got slower while it was being measured, which no machine
explains. A median more than four times the fastest run fails, and only where
the median is at least 20 us — below that the ratio measures the clock rather
than the operation. On the three CI hosts the worst honest gap is 1.6.

The table below is what this project's machine measures. It is *not* what the
ceilings are, and the two should not be conflated — one is a measurement, the
other is a limit chosen so that only a real regression trips it.

## Methodology

Each figure is the **median and the fastest** of N consecutive in-process runs
of the named operation, timed with `Ada.Real_Time`. Both are reported on
purpose: a median alone hides the shape, and an operation that starts fast and
gets slower shows up as a fastest run far below its median. A mean is not
reported at all — it is moved by the one iteration during which the machine did
something else, and that iteration is always present.

No process is spawned, so these do not include the operating system's cost of
starting a shell. Comparisons between machines, or between builds at different
optimization levels, are not meaningful, and a figure quoted without its build
profile is not a measurement.

What is measured is chosen from what a session actually repeats — lexing and
parsing happen on every line, highlighting on every keystroke, completion on
every tab. Throughput on a large program is not measured, because Adash is not
a batch compiler and nobody waits on it.

There is deliberately **no comparison against another shell**. It would be
measuring two different languages doing two different things, and the number
would be quoted long after anybody remembered that.

## What this build does

On a development build (`-Og`), 200 repetitions, on a sixteen-core machine
carrying a load average of about 1.5 while the figures were taken, and at its
full clock -- which is the condition worth stating, because the same machine
under the `powersave` governor at 1.40 GHz of 5.13 produces every row about 3.4
times larger and nothing else changed. See `docs/benchmark-guide.md`. One run of
four, all of which agreed: analysis fell between 493 and 549 us across them and
every other row within about three percent, so a reader should take the
row-to-row *shape* from this and not the last digit.

| Operation | Median | Fastest |
|---|---:|---:|
| load and validate UTF-8 | 0.4 us | 0.4 us |
| lex | 20.6 us | 20.1 us |
| parse | 27.5 us | 26.0 us |
| **analyse** | **492.8 us** | **469.9 us** |
| lower and run | 5.9 us | 5.8 us |
| highlight (per keystroke) | 19.0 us | 18.7 us |
| complete a command prefix | 36.2 us | 35.4 us |
| complete a program name | 2757.3 us | 2668.3 us |
| encode a history entry | 0.7 us | 0.7 us |
| parse a configuration file | 11.6 us | 11.5 us |
| open an engine session | 109.8 us | 105.2 us |

**The address map does not need `Place_Of` changed, 2026-08-22.** The obvious
first move is to stop keying a slot on `Declared_At` -- a byte offset, which
moves for a carried variable every time the session puts something new in front
of it, so the same variable never matches itself twice. Tried, and it is wrong:
a `declare` block's variables live at level one as well, so two slots there can
share a name and the offset is what tells the block-local one from the outer
one it hides. `block.hides-and-then-restores` is the case that says so, and it
was the only family left failing once the change was written correctly.

The map should stamp instead. It holds a name and an address; at seeding time
each entry takes the offset the *current* tree gives that name, and `Place_Of`
matches unchanged. Shadowing keeps working because nothing about matching
changed.

Two wrong readings of the same failure are recorded here because each was
stated confidently before being checked: that level-one slots are shared by
compiler temporaries (they are not -- they are shared by blocks), and before
that, that a first version failing 99 cases proved the keying wrong (it proved
the *condition* wrong: it also stopped a global resolving from inside a body).

**Corrected 2026-08-22: `Install_Predefined` was never the blocker.** An
earlier note here said the eighty-seven provided names could not be installed
once because the call mixed scope population with per-analysis state, and
pointed at 171 failing cases as evidence. That was a wrong reading of my own
change. `Adash.Predefined.Install` adopts prepared symbols into a chain and
does nothing else; the 171 came from installing once *without* telling the
chain where the previous submission ended, so every replayed declaration met
itself and was refused as already declared. With `Settle` in place, installing
once is fine.

What is actually left is one thing, and it cannot be done in halves: **while
the session replays its declarations as text, persisting the analysed chain
buys nothing** -- the replay re-declares everything anyway, so the chain can
only agree with it or contradict it. The eleven cases that fail with a
persistent chain are all the second: a name the chain kept that the replay
would have dropped, resolving to a slot the machine never made.

So the order is forced. The replay has to stop first, and that needs the
lowering to give a name the same slot in every submission -- `Slots` in
`Adash.Language.Evaluation.Run` is built fresh each time and addressed in
declaration order, and the machine already keeps its frame between runs
(`Machine.Slot_Value` exists for exactly that). A session-level name-to-address
map handed into the lowering is the piece that is missing for *variables*, and
everything else -- the chain, the mark, the rewind, installing the provided
names once -- follows it.

But a map is not enough to stop the replay, and this is the constraint that
decides the size of the whole item. `Adash.Engine`'s `Keep_As_Text` carries a
subprogram, a type and a package as **source**, and the replay is how the
machine gets their *code*: a call to a function declared three submissions ago
runs instructions emitted from that text into this submission's program. A slot
map persists where a variable lives; it does not persist a body. Stop replaying
and the names resolve and there is nothing to call.

So going all the way means the machine keeping compiled code across submissions
-- instructions, entry points, and the frame layout they were compiled against.
That is an image and a linker rather than a map, and it is worth knowing before
starting rather than after.

**Attempted twice on 2026-08-22, and the second attempt was worse than the
first, which is the finding.** Making the two structures one was tried by
keying the chain the way `Kept` is keyed. `Kept`'s key is a name *and a
profile*, so redefining `LL` replaces it while a second `LL` of another profile
is an overload.

Keying replacement by **name alone** left 11 cases failing, all of them the
chain holding what `Kept` drops. Keying it by **name and profile** -- which is
what unification means -- left **17**, adding nine overloading cases and
`sub.overloads-accumulate`: the predefined names are installed into the chain
at the start of every analysis, so with a chain that persists they meet
entries from the previous submission and the two keying schemes disagree about
which entry an install replaces.

That is the same disagreement one level down. `Kept` is keyed for *what a
session carries between submissions*; a scope chain is keyed for *what a name
means while a program is analysed*, and the predefined names are in the second
and not the first. Unifying them is not a matter of picking one key: it needs a
decision about what the predefined names are in a session that holds its own
scope, and that decision has to be made before any code, because each guess
costs a full suite run to disprove.

**The first attempt, and what it found:** A session's names live in *two* places that do not agree,
and persisting one of them makes the disagreement visible.

`Adash.Engine`'s `Kept` decides what a session carries: it holds source text,
it is keyed by **name and profile together** so that redefining `LL` replaces
it and a second `LL` of another profile is an overload, and it deliberately
drops things -- a task object, a name a package body keeps to itself, anything
a submission declared before it failed. `Adash.Language.Scopes.Chain` is what
the analyser resolves against, and today it is rebuilt from the replayed text
every submission, so it inherits those rules for free.

Persist the chain and it stops inheriting them. The attempt reached: a chain
kept on the session; `Mark`, `Rewind` and `Settle` on it; replace-on-redeclare
for a name settled by an earlier submission; rewind on a refused submission.
The suite then failed **eleven** cases in three families, and every one is the
chain holding what `Kept` would have dropped:

  * a variable from a submission that failed was still in scope -- the analyser
    resolved it and the machine had no slot, so `Lost` raised `Program_Error`
    where it should have said "not declared";
  * a name a package body keeps to itself answered from a later line;
  * an overload from an earlier submission made an ambiguous call resolve.

Pruning the chain to match `Kept` after each submission is the obvious repair
and it does not work as stated: `Kept` is keyed by name *and profile*, so it
cannot be matched against a chain of names without taking that key apart.

So the redesign is not "keep the analysed chain". It is **make the two one
thing** -- one structure that answers what a session holds, that the analyser
resolves against and that the engine's carrying rules are written on. That is a
bigger change than this item has ever been described as, and it is the reason
to do it once rather than in pieces.

**What a session actually pays for carrying, measured 2026-08-22 — and it is
not mostly analysis.** `analyse a line beside 128 declarations` is 14.5 ms, and
the *submission* it belongs to costs **35 ms**: measured by differencing two
sessions, one with 128 declarations and one further line, one with 128 and
twenty-one, so the figure is the marginal cost of a submission with 128 already
carried rather than a whole session's.

The other 20 ms is the carried text being lexed, parsed, lowered and run again,
because a session replays what it holds in front of every submission. Which
means the redesign this benchmark was written for — keeping an analysed symbol
table across submissions — removes **14.5 of 35 ms**, not all of it. Removing
the rest means not replaying the text at all, and that needs the machine's
variables to persist too, not only the analyser's names.

One thing the replay does *not* do, worth knowing before touching it: a
declaration's initial value does not run again. `Z : Integer := Noisy;` prints
once however many submissions follow it — what is replayed is a declaration and
an assignment of the value it ended with.

**Where the rest of carrying a session goes, and three things that did not
help (2026-08-22).** After the scope-lookup fix below, a line beside 128
carried declarations costs about 14.5 ms, and the next attempt should start
from these rather than from where the last one ended:

  * **It is the declaring, not the analysing.** 128 declarations cost 13.9 ms;
    128 *assignments* to an already-declared variable, which resolve a name and
    analyse an expression exactly as a declaration does, cost 2.7 ms.
  * **Declaring the name is about 4 ms of that** -- `Chain.Declare_Symbol`,
    timed with clocks put in by hand. The other 10 ms is the rest of the
    declaration branch: the type, the value, and the name-building around them.

Three targeted changes were tried against those numbers and **none of them
moved the total**, measured back to back on one machine under one load:

  * noting the symbol just built instead of looking it up again in the chain
    (a full scope walk and a whole-symbol copy per declaration);
  * growing the annotation table in one step instead of appending to it;
  * asking whether a scope already holds a name before fetching what it holds,
    so the duplicate check does not copy a symbol it will not use.

The second and third *look* like the fix that worked before, which is why they
were tried and why they are recorded: the vector was already growing
geometrically, and the copy the third removes is real but does not show. The
first is a plain redundancy and is worth doing for clarity, not for time.

Between them they say the remaining cost is **distributed rather than
concentrated**, which is the argument for the redesign this has been waiting
for -- keeping an analysed symbol table across submissions rather than
re-analysing carried text -- because that removes all 14.5 ms rather than a
piece of it.

A caution for whoever measures next: timers put inside the region they measure
inflate it. `Declare_Symbol` appeared to drop from 31 us to 15 us per call with
the third change, and the end-to-end figure did not move at all, which is what
says the isolated reading was measuring its own clock calls.

**Carrying a session got about three times cheaper (2026-08-22).** Analysing a
line beside 128 carried declarations measured 51.6 ms and now measures 14.9 ms
(medians, back to back on one machine under one load, which is the only way to
compare anything here). The cause was not the re-analysis being inherently
expensive: `Ada.Containers.Vectors.Element` returns by **value**, and a
`Symbol` holds thirty-seven `Unbounded_String` components -- name, key, within,
kept, origin, and sixteen parameter names beside sixteen defaults. Every scan
of a scope copied all of that for each entry it looked at, to read one field
and throw the rest away. Comparing through `Constant_Reference` instead is the
whole change.

Worth keeping for the next one: the phase split said where to look. `Analyse`
has five phases, and at 128 declarations it was 18.0 ms in `Analyse_Sequence`
against 0.17 in `Install_Predefined` and 0.25 in the rest together. Per
declaration the cost barely grew with how many were already declared -- 342 us
each at 16 and 437 at 256 -- so it was a fixed cost per declaration rather than
a scan that got longer, which is what pointed at the copy rather than at the
lookup.

**Checked again for 0.1.0 (2026-08-22), and the table stands.** The figures
above could not be re-taken: this machine was under the `powersave` governor at
1.40 GHz of 5.13 and carrying a load average of about 4.5 from a virtual
machine and somebody else's proofs, which is the condition this file already
says makes rows about 3.4 times larger and comparisons meaningless.

What *can* be measured under those conditions is a comparison, so the build
before this release's language work was built and measured back to back with
it, same machine, same load: `parse` 41.3 against 41.1 us, `lex` 52.4 against
53.4, `analyse` 2273 against 2218 (the mean of three runs). Nothing moved --
which is the question the release had to answer, because a lookahead was added
that runs at the start of every statement.

Two readings worth keeping from that. Repeated runs of one binary gave `lex`
41.0, 53.4 and 54.8 us and `parse` 31.3, 42.8 and 42.5 -- **a third of the
value, run to run**, on the small rows; `analyse` held to 3%. And a single
first reading of `analyse` came out at 1242 us, half of what the next three
runs of the same binary said. One reading on a loaded machine is not a
measurement, and this one would have been reported as a doubling in speed.


**Analysis had nearly doubled, and the cause was not where it looked.** Three
rows moved together -- analysis 910 to 1620 us, highlighting 12.8 to 18.5,
completing a command prefix 24.3 to 34.4 -- while lexing, parsing, lowering and
running, encoding a history entry and opening a session did not move at all. In
the same period the tables those three consult grew from 61 entries to 87, as
the stream families, the pipeline forms and their functions were added, and the
obvious suspicion was the linear scan each lookup does.

The obvious suspicion was wrong, and one measurement said so. Analysing programs
of one, five and twenty lines cost 1578, 2514 and 6518 us: about 250 us a line,
and **1.3 milliseconds that did not depend on the program at all**. A per-name
scan does not look like that. What does is `Adash.Predefined.Install`, which
declared all eighty-seven names into the chain before every analysis -- and
declaring asks whether the name is there already, which scans what has been
declared so far. Eighty-seven of those is the fixed cost, and it grows with the
square of the table.

The answers cannot change between one submission and the next, so they are
worked out once now and adopted wholesale. Analysis is **493 us**, which is
below where it was before any of this was added. The check that two entities do
not share a name is exactly as it was: it runs once, against a chain of that
package's own, and a table defect is still a failure to install.

Highlighting and completing a command prefix did *not* come back down, which is
the other half of the same measurement: those two really do scan the registries
per word, and their growth is proportional to the tables. At 19 and 36 us they
are far below anything a person notices, and a lookup that does not scan is
where to start if that ever stops being true.

Nothing else added since the last record touches these paths: the bounds checks
are one comparison per chunk read, the write handler costs nothing until a write
fails, and the terminal look between instructions returns on a descriptor test
where the shell is not watching, which is every host but one.

**The cost had already inverted before that.** Lowering and running a
submission was 1.7 ms and is 6 us; analysis was 14 us and is the dominant cost
by two orders of magnitude. Both follow from the same change: the machine is
Adash's own now, so nothing rebuilds a compiler's tables per submission, and
the analyser has grown every rule the language gained -- scope chains,
overload resolution that narrows from the context, the arguments and the
operands, composite shapes, and the checks each of those needs.

At under a millisecond nobody typing will notice, and a script pays it once per
submission rather than once per line. It is the obvious first thing to look at
if the pipeline ever needs to be faster, and the obvious first place to look
inside it is resolution, which asks each candidate about each argument.

### The one that walks the search path

Completing a *program* name is the only thing here that leaves the process's own
memory for anything but a single file, and it is worth the row it takes. The
first version listed every directory on the path and matched the names itself:
58 milliseconds, which is a pause a user feels on every Tab. Handing the prefix
to the host as the search pattern -- so the directory is filtered where it is
read -- brought it to about 3, and asking whether a file can be run only for the
names that already matched keeps the calls to a handful rather than thousands.

Three milliseconds is not nothing, and it is the figure to watch if the path
ever grows a directory on a network filesystem. It is also the number that says
a cache is not needed yet, which is the useful thing to have measured.

### What the last refresh found

**Nothing moved.** The figures above are the previous record within its own
noise, and the analyser's *fastest* run is 780.9 us against 779.6 us recorded
before -- a microsecond apart after a month of work on diagnostics that carry a
position, a quoted line, a caret and related locations; on a script that reads
in what it sources; and on the history mark and `forget`.

That is the expected answer rather than a surprising one, and it is worth
writing down why: a diagnostic's position costs nothing on a submission that
has no diagnostic, source inclusion happens once per script rather than per
line, and the history work is in the frontend, which this does not measure. A
refresh that had shown a change would have been the interesting one.

Four rows came out slightly *faster* than the previous record -- highlight,
completion, the configuration parse, opening a session. Between-run noise on
this machine covers the difference, and none of them is a claim.

### The one gap worth watching

Analysis is the only row where the fastest run sits meaningfully below the
median, about a tenth below. The report says such a gap is a defect signal
rather than noise, so it was checked: if the operation got slower as it
repeated, raising the repetition count would drag the median up and leave the
fastest where it was. At 200, 2000 and 5000 repetitions the fastest stayed at
765-795 us and the median stayed near 890 us. It is the largest figure on a
machine doing other things, which is where scheduling noise lands, and not an
operation that degrades.

## What the first run found

**This is history**, from the build that ran on an outside interpreter. It is
kept because the shape it describes is the one the section above inverted.

On a development build (`-Og`), 200 repetitions:

| Operation | Median | Fastest |
|---|---:|---:|
| load and validate UTF-8 | 0.4 us | 0.3 us |
| lex | 16.7 us | 16.3 us |
| parse | 10.2 us | 9.8 us |
| analyse | 14.0 us | 13.8 us |
| **lower and run** | **1784.7 us** | **1690.7 us** |
| highlight (per keystroke) | 6.5 us | 6.4 us |
| complete a command prefix | 9.1 us | 9.1 us |
| encode a history entry | 0.5 us | 0.5 us |
| parse a configuration file | 8.1 us | 8.1 us |
| open an engine session | 65.6 us | 63.4 us |

**Lowering and running costs about forty times everything else combined**, and
the median and the fastest are close, so it is a constant cost rather than
something that degrades. That is not a surprise once stated: the lowering
rebuilt an outside compiler's tables from scratch for every submission in order
to emit a handful of instructions. The per-line pipeline that a user feels —
lex, parse, analyse, highlight — is around 50 us, and the 1.7 ms sits on top of
it.

At 1.7 ms nobody typing will notice. It matters for a script of many
submissions, and it is the obvious first thing to look at if evaluation ever
needs to be faster: reusing the build across submissions in one session, rather
than making anything in Adash's own pipeline quicker.

This is recorded here rather than fixed because Phase 16 is about
characterizing performance, not tuning it. Optimizing before the behaviour is
pinned down produces a fast implementation of the wrong thing, and the
benchmark then defends it.

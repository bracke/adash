# Benchmarks

`adash_bench` measures the operations an interactive session repeats. Build the
test crate and run it:

    cd adash_tests && alr build && ./bin/adash_bench [repetitions]

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
carrying a load average of about 1.5 while the figures were taken. One run of
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

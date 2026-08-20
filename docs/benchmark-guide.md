# Benchmarks

`adash_bench` measures how long the things an interactive session does most
often take. Run it from the `adash_tests` directory:

```
alr build && ./bin/adash_bench
```

An optional argument sets the repetition count; the default is 200.

## What the numbers are

Each figure is the **median** of repeated in-process runs, in microseconds,
beside the **fastest** of the same runs.

The median rather than the mean, because a mean is moved by the one iteration
during which the machine did something else, and that iteration is always
present. The fastest beside it because a median alone hides the shape: an
operation that starts fast and slows down as it repeats shows up as a fastest
run far below the median, and that gap is a defect rather than noise. When the
two are close, the cost is uniform.

No process is spawned, so none of these include the operating system's cost of
starting a shell. What they measure is Adash's own work.

## What is measured, and why those things

Chosen from what a session actually repeats:

| Measured | Happens |
|---|---|
| load and validate UTF-8, lex, parse, analyse, lower and run | on every line |
| highlight | on every keystroke |
| complete a command prefix | on every tab |
| encode a history entry | on every accepted line |
| parse a configuration file, open an engine session | once per session |

The language pipeline is split by stage on purpose. A single "how long does a
line take" number cannot tell you which stage to look at when it moves.

Throughput of a large program is deliberately absent: Adash is not a batch
compiler and nobody waits on it.

A comparison against another shell is deliberately absent too. It would be
measuring two different languages doing two different things, and the number
would be quoted long after anybody remembered that.

## What the numbers are not

**Comparable between machines.** These are wall-clock times on whatever ran
them.

**Comparable between build profiles.** The development profile carries every
check GNAT offers; the release profile does not. A figure from one says nothing
about the other, which is why the report prints which profile it came from.

**A budget.** A figure that moves inside its bound fails nothing, and the report
is for noticing that it moved. Three things do fail the run, and `adash_bench`
exits non-zero for each: a figure over its ceiling in `benchmarks/ceilings.toml`,
a median more than four times the operation's own fastest run (above 20 us),
and a figure with no rule recorded for it at all. The ceilings are set an order
of magnitude above what the operations take and from the *slowest* CI host, so
one of them being reached is a change in what the operation does rather than a
busy machine. Watch it fail before believing it: set a ceiling to 1 and run.

**Comparable across the same machine on a different day.** The clock matters
more than the load does. A laptop under the `powersave` governor sat at 1.40
GHz of a 5.13 GHz maximum while these lines were written, and *every* row --
including `load and validate UTF-8`, which is a memcpy and a scan -- came out
about 3.4 times the figure recorded below, which is the clock ratio and nothing
else. Before reading a uniform slowdown as a regression, read
`/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` and the running MHz in
`/proc/cpuinfo`. A regression in one pass moves one row; a slower clock moves
all of them by the same factor.

## When a figure moves

Analysis is the largest figure and the one most likely to move, because it is
the pass that carries the most state. It grew by about a fifth when
`Adash.Language.Types.Type_Kind` stopped being a one-byte enumeration and
became a record carrying a shape, an identity, a name and a constraint — the
change that let a program declare its own types. That cost is paid on every
symbol lookup, because a type travels inside every symbol and every parameter
profile, and it was accepted deliberately: an open type model is worth a fifth
of a pass that takes a fraction of a millisecond.

Packages, tasking and the rendezvous each added to it again, in smaller steps:
a scope chain that carries dotted names, a statement kind that was not there
before, a formal list read for entries as well as for subprograms. The
rendezvous work also *removed* a duplicate — a second reading of what a formal
list means — and one implementation asked twice is cheaper than two that can
disagree.

A month of work on diagnostics -- a position, a quoted line, a caret, related
locations -- moved none of them, and that is the other thing these numbers are
for. The cost of a diagnostic falls on a submission that has one; the measured
pipeline analyses a program that is correct. Being able to say *this did not
cost anything* needs the same measurement as being able to say what a change
cost, and a figure nobody re-runs says neither.

That is the shape of the judgement these numbers are for. They are not a gate;
they are a way to be able to say what a change cost. `benchmarks/README.md`
carries the current figures and the previous ones beside them.

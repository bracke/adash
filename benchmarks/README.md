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

## What the first run found

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
something that degrades. That is not a surprise once stated: `Adash.Language.
Evaluation` calls HAC's `Init_for_new_Build` for every submission, which builds
the compiler's tables from scratch to emit a handful of instructions. The
per-line pipeline that a user feels — lex, parse, analyse, highlight — is around
50 us, and the 1.7 ms sits on top of it.

At 1.7 ms nobody typing will notice. It matters for a script of many
submissions, and it is the obvious first thing to look at if evaluation ever
needs to be faster: reusing the build across submissions in one session, rather
than making anything in Adash's own pipeline quicker.

This is recorded here rather than fixed because Phase 16 is about
characterizing performance, not tuning it. Optimizing before the behaviour is
pinned down produces a fast implementation of the wrong thing, and the
benchmark then defends it.

# Security

## Reporting

Report suspected vulnerabilities privately to <bent@bracke.dk>. Do not open a
public issue.

Include what you did, what happened, what you expected, and the output of
`adash --version`. A proof of concept helps; a proof of concept that destroys
data does not.

## Supported versions

`0.1.0`, the first release, made on 2026-08-22. It is the only version there
is, so it is the one that gets fixes; when there is a second, this section says
how long the first keeps getting them.

A release of Adash is reproducible together with the sibling commits it was
built against -- every dependency is a path pin -- and the tag records them.

## A shell's risk model

A shell is a privilege boundary in a way most programs are not. It runs what a
user tells it to, with that user's authority, and its ordinary correct behaviour
is to execute arbitrary code. That makes some usual advice inapplicable and some
unusual advice essential.

The risks Adash's design takes seriously:

**Text a user did not intend as a command.** Filenames, environment values,
command output, history entries and completion candidates are all data that
originated elsewhere. None of it may become executable by accident. Adash's
command language is parsed once, from source with known identity and extent;
values are not re-parsed as source at any point. There is no `eval` of an
arbitrary string that arrived as data.

**Argument vectors, never command lines.** Programs are started with an argument
vector, so a filename containing a space, a quote, a semicolon or a newline is
just a filename. Building a command line and handing it to a shell to re-split
is how a filename becomes an injection, and Adash does not do it.

**Terminal escape sequences in untrusted output.** A child process's output can
contain escape sequences that move the cursor, retitle the window or, on some
terminals, inject input. Adash never writes escape sequences itself, styles only
through `terminal_styles`, and remains semantically complete with styling off —
so nothing depends on escapes surviving.

**Secrets in persisted state.** History is durable, and a shell's history is one
of the more sensitive files on a system. Four things bear on it. A **line typed
with a space in front of it is not recorded at all** — not in the session, not
in the file, and not as a placeholder saying a line was here, since a record of
*when* a secret was typed is still a record. It is the convention the other
shells have, it is on by default (`history.ignore-space`), and it is read at the
submission rather than at each line of one, so a multi-line construct is marked
or not as a whole. `history.enabled` off turns recording off for a session
entirely. And `Adash.Interactive.History.Record_Line` takes the `Sensitive` flag
the frontend sets, so the policy has one implementation rather than one per
caller.

**`forget` takes back a line already recorded** — the last one, or the last
several — out of the session and out of the file, for the user who did not think
of the space in time. It takes itself with it: a history whose last entry is the
command that emptied it has kept a record of the act. Removal is by text and
takes the last occurrence, because a shared history file holds what several
shells wrote, interleaved, and a position there is not a line. The file is read
and rewritten under one lock, so a line another session appends meanwhile is not
lost.

A count reaches what the session's log holds, which includes what was loaded
from the file at start-up. Naming the line instead — `forget ("…")` — reaches
the **file**, whether or not this session ever read that line back, and takes
every copy of it; the line older than `history.limit` is exactly the one a
count cannot get to. The `forget` line goes with them, which matters most in
the naming form, because the line that names a secret contains it.

**Confident wrong answers about the host.** A permission check that silently
becomes a no-op reports that all is well for as long as it exists. Adash asks
hostkit, which answers from a body per operating system and returns False where
a host cannot express the question rather than guessing — and Adash treats
"cannot tell" as "cannot tell", never as "fine".

## Secure defaults

- Styling is off when the destination is not a terminal, and `NO_COLOR` is
  honoured.
- Persistence writes are atomic, so an interrupted write cannot truncate
  authoritative state.
- The store distinguishes what can be rebuilt from what cannot, so that a
  system emptying the cache — which it is entitled to do, unasked and on a
  schedule — never costs a user their history or their settings. Nothing is
  cached today; the distinction is in `Adash.Persistence` for the first thing
  that is, and the guarantee is under test rather than assumed: the three
  directories are distinct and neither the history nor the settings is inside
  the cache. An unused mechanism is one nobody would notice going wrong.
- Configuration that is invalid in a way that would materially change behaviour
  is reported, never silently ignored.
- Job control degrades explicitly on platforms where hostkit reports the
  capability as absent, rather than silently doing something different.
- A line typed with a space in front of it is kept out of the history without
  the user having to turn anything on first, and `forget` takes back one that
  was.

## Status

The above describes behaviour that is in force, not intentions: the language is
parsed once from source with known identity, programs are started with argument
vectors, styling goes through `terminal_styles` and is off where the
destination is not a terminal, history and settings are written atomically
under a lock, job control declines where hostkit reports the capability absent,
and a line typed with a space in front of it is left out of the history in the
session and on disk while `forget` takes back one that was. Each has conformance
cases behind it.

Two exceptions are named where they stand: `forget` reaches only what this
session's log still holds, and nothing is cached yet. Both are stated as limits
in the sections above rather than left to be inferred.

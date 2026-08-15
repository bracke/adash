# Security

## Reporting

Report suspected vulnerabilities privately to <bent@bracke.dk>. Do not open a
public issue.

Include what you did, what happened, what you expected, and the output of
`adash --version`. A proof of concept helps; a proof of concept that destroys
data does not.

## Supported versions

None yet. Adash is at `0.1.0-dev` and has made no release, so there is nothing
in anyone's hands to support. This section is filled in at the first release.

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
of the more sensitive files on a system. `history.enabled` turns recording off
for a session, and `Adash.Interactive.History.Record_Line` takes a `Sensitive`
flag that records nothing at all — but **nothing at the prompt sets it yet**:
there is no way for a user to mark one line as unrecorded, the way a leading
space does in other shells. The mechanism is there and the way to reach it is
not, which is a gap rather than a protection.

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
  corrupt cache never costs a user their history or their settings. Nothing is
  cached today; the distinction is in `Adash.Persistence` for the first thing
  that is.
- Configuration that is invalid in a way that would materially change behaviour
  is reported, never silently ignored.
- Job control degrades explicitly on platforms where hostkit reports the
  capability as absent, rather than silently doing something different.

## Status

The above describes behaviour that is in force, not intentions: the language is
parsed once from source with known identity, programs are started with argument
vectors, styling goes through `terminal_styles` and is off where the
destination is not a terminal, history and settings are written atomically
under a lock, and job control declines where hostkit reports the capability
absent. Each has conformance cases behind it.

Two exceptions are named where they stand: no way to mark a single line
unrecorded, and nothing cached yet. Both are stated as gaps in the sections
above rather than left to be inferred.

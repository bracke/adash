# The interactive session

What the shell does while somebody is typing at it: the prompt, editing,
completion, history and the interrupt.

## The prompt

    adash > 

Three parts, in this order: a failure marker, the working directory, and the
prompt itself.

    ! ~/work > put_line ("x");

The **failure marker `!`** appears when the last submission failed, and it comes
first so that it survives a narrow terminal — the directory is what gets
truncated, not the thing that says something went wrong. It is text, never
colour alone: a prompt that says something only in red says nothing to a reader
who cannot see it. `prompt.failure` turns it off.

The **directory** is dimmed rather than coloured, and `prompt.directory` turns
it off.

A submission that is not finished continues on the next line:

    adash > if X > 1 then
    ...     put_line ("bigger");
    ... end if;

The continuation prompt is `...` and carries **no directory**: the line
continues one already shown, and repeating the context would make the two look
unrelated. Input that ends in the middle of a construct is reported — `expected
end here` — rather than run as though it were finished.

## Editing

The line is edited in place: the shell takes the terminal into raw mode, redraws
what changed, and keeps the cursor where the text says it should be.

Editing is by **character, not byte**. A line holding an accented character
counts it once, the cursor steps over the whole of it, and a backspace deletes
the character rather than half of it. That is the property the unit cases are
written around, because it is the one that breaks quietly: a shell that steps by
bytes looks correct until somebody types a name with an umlaut in it.

`editing.enabled` turned off gives whole-line input — what a terminal that
misbehaves, or a screen reader that prefers to see the line once, needs.

## Completion

**Tab** completes what is being typed. `ver` and Tab becomes `version`. Where
several things match, they are listed and the line is left as it was, so nothing
is chosen on the user's behalf.

What it offers, in this order, is the internal commands, the predefined
entities, the language's reserved words, and — when the prefix looks like a
path, meaning it starts with `.` or `/` — the files and directories under it.
Ordering is by source and then by name, never by what was used recently: a
ranking that depends on history is one nobody can learn and no test can pin.

Paths only on that prefix, because listing the working directory for every empty
prefix would bury the shell's own vocabulary under whatever happens to be in the
directory. What the *session* has declared is not offered: completion reads the
registries and the filesystem and never the analyser's scope, since a line under
construction is exactly the input that must not be evaluated to find out what
could follow it.

## History

**Up** and **Down** walk what was typed this session, most recent first. What is
recalled is the whole submission, including a multi-line one: the history file
holds each as one JSON string, so a submission written across three lines comes
back as three lines rather than as a fragment.

`history;` lists it. In a session with no log — a script — the command says it
has nothing to report, which is a different thing from a missing feature.

`history.enabled` off writes nothing to disk while recall still works for the
session, which is what somebody on a shared machine wants.
`history.per-session` gives each session its own file, merged into the shared
one when it ends, so two shells running at once do not interleave their lines
there.

## Interrupting and ending

**Ctrl-C** interrupts the foreground work. A running program is signalled; a
loop of the shell's own is stopped between two instructions, which is why a
runaway loop is interruptible without any statement being left half-done.

**Ctrl-D** at an empty prompt ends the session, exiting 0. `quit;` does the
same, and `quit (N)` with a status.

## What the session keeps

What a submission declares is there on the next line — variables with the values
they ended with, types, subprograms, packages, task types, protected objects
with their state. `language-reference.md` says exactly what is carried and what
is not.

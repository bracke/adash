# Job control

A job is a program the shell started and did not wait for.

    start ("sleep", "30");     -- recorded as job 1
    jobs;                      -- what is running
    suspend (1);               -- stopped, able to be resumed
    resume (1);                -- running again, in the background
    stop (1);                  -- asked to stop
    wait (1);                  -- wait for it and report how it ended

Jobs are numbered from one in the order they were started, and the number is
what every other command takes. `start` reports the number it gave; `wait`
reports how the job ended, which is the same status model a program that ran in
the foreground reports.

## What each reports

`jobs` lists what the shell is running, one line per job, each carrying the
number, what was started, and the state — running, stopped, or finished.

`stop` asks a job to stop and says nothing when the host took the request:
what arrives is a termination signal, a program that traps it may still be
running afterwards, and how the job actually ended is what `wait` reports. It
speaks when it could not ask — a host without job control, or a table that
refused — because that is the case a reader cannot infer from silence.

`suspend` and `resume` do report, each naming the job's new state: they leave
the job in the table, so that line is the only word a user would otherwise
get.

`wait` on a job that has already finished answers with what it ended as rather
than waiting for something that will not happen again, and `wait` on a number
nothing was started with says that number is not a job.

## Foreground and background

A program run with `run` holds the session until it finishes; one started with
`start` does not. There is no `fg`: a suspended job is resumed **in the
background**, because bringing one to the foreground means handing it the
terminal, and that is the part of job control a host may not be able to do.

## Where a host cannot answer

Windows has no process groups and no pseudo-terminals. `Hostkit.Pty` and
`Supports_Foreground_Group` are False there, and the commands that depend on
them decline rather than pretending: a "cannot tell" is a deliberate refusal,
never an optimistic default. The one thing that host *can* do is report Ctrl-C,
which `Can_Record` answers for.

This is why the job commands report what they *asked for* rather than what they
achieved. A shell that said "stopped" when it had only signalled would be
telling the user something the host never confirmed.

## Signals

Ctrl-C interrupts the foreground work: a running program is signalled, and a
program of the shell's own — a loop in a submission — is stopped between two
instructions. The machine asks for the interrupt between instructions rather
than inside one, so a runaway loop is interruptible without any statement being
half-done.

How the shell learns that Ctrl-C was typed depends on the host, and only one of
the two is a signal. Where a signal reaches a program that is not waiting for
one, that is the whole arrangement. Where it does not — Windows, where a
spinning program is never told, not even half a second after it stops spinning —
the shell holds its terminal raw for as long as a submission runs and reads the
keystroke itself between instructions, at most twenty times a second. Anything
the submission runs gets the terminal back for its own duration, since a program
handed a raw console is one nobody can type a line into, and what stops a
foreground program there is the program's own interrupt.

Bytes that are not the interrupt key go back to the shell's input buffer, so
typing ahead during a long loop works the same way on every host. A script is
watched the same way as an interactive session, and only when standard input is
a terminal: a script reading a pipe has no keyboard, and a shell reading that
pipe would be taking the script's own input.

Anything that needs the terminal for itself is given it back for that
duration — a program in the foreground, a program whose output is being
captured, and the shell's own `Read_Line`.

A job started into the background is a different case: there is no "for that
duration" to give it back for, since the shell carries on while it runs. Where
the shell is watching, a background job is given the null device as its input
rather than the terminal it cannot safely share, so it reads end of input
instead of racing the shell for keystrokes. A job whose input was redirected
keeps what it was given.

A job killed by a signal reports 128 + n, which is the convention every shell
follows and what `Adash.Execution` documents as the one status model.

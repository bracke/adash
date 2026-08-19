# Configuration

Nine settings, held in one TOML file, changed with `settings` and written with
`save_settings`.

    settings;                              -- list them all
    settings ("color", "never");           -- change one
    save_settings;                         -- write them to the file

`settings` takes nothing or two arguments; a query form taking one is not
written. A value a setting does not accept is refused rather than clamped, and
the setting keeps what it had.

## The settings

| Key | Holds | Default | Read by |
|---|---|---|---|
| `color` | `auto`, `always` or `never` | `auto` | `Adash.Terminal` |
| `history.enabled` | true or false | `true` | `Adash.Interactive.History` |
| `history.limit` | 1 .. 1 000 000 | `1000` | `Adash.Interactive.History` |
| `read.limit` | 1 .. 4 096 (MiB) | `16` | `Adash.Filesystem`, `Adash.Execution.Pipelines`, `Adash.Execution.Streams` |
| `trace.commands` | true or false | `false` | `Adash.Commands.Builtins` |
| `history.per-session` | true or false | `false` | `Adash.Persistence.History` |
| `history.ignore-space` | true or false | `true` | `Adash.Interactive.Session` |
| `prompt.directory` | true or false | `true` | `Adash.Interactive.Prompt` |
| `prompt.failure` | true or false | `true` | `Adash.Interactive.Prompt` |
| `editing.enabled` | true or false | `true` | `Adash.Interactive.Editing` |
| `startup.session` | true or false | `true` | `Adash.Scripting.Startup` |

`trace.commands` announces each internal command before it runs — what `set -x`
is for elsewhere. On **standard error** and as a note, so what a script writes is
still what a script writes: tracing that wrote into a pipeline's data is a thing
every shell user has been bitten by once. The command that turns it on is not
traced, because it was not on when it ran.

`read.limit` is in **mebibytes**, and is the most any one read will hold: a file
for `Read_File`, a program's output for `Output_Of`, a line for `Read_Line`. The
shell's own reads — a script file, a module read into one, a configuration file,
a history log — are bounded by the same default but not by the setting, because
three of the four are read before there is a setting to consult. A
shell keeps what it reads in one String, so without a limit a script that names
a disk image, or captures a program that never stops writing, grows the session
until the host ends it — and a session that dies takes everything in it, while a
read that is refused takes nothing. It stops at 4 096 because past that the
limit would be promising more than a String can hold on a 32-bit host, and the
first two refuse whole rather than truncating; `Read_Line` hands a long line over
in pieces instead, because input that has been read cannot be asked for again.

`history.limit` starts at **1** rather than 0: zero would mean a history that
remembers nothing, which is what `history.enabled` is for. It stops at a million
because the history is held in memory for the session and a limit read out of a
file should not be able to exhaust it.

`prompt.failure` marks a failed submission **as text, never as colour alone** —
a prompt that says something only in red says nothing to a reader who cannot see
it.

`editing.enabled` turned off gives whole-line input, which is what a terminal
that misbehaves, or a screen reader that prefers to see the line once, needs.

`history.per-session` on gives each session a file of its own, merged into the
shared history when it ends: two shells writing the common file a line at a time
interleave their commands there, and this makes the shared history read as runs
rather than as fragments.

`history.ignore-space` is what makes a leading space mean *do not remember this
line*: a submission typed with a space in front of it runs, and is recorded
neither in the session nor in the file. It is the one thing a user can type
before a command without changing what the command means, since the lexer skips
it -- and it is on by default, because a protection that has to be switched on
first is off in the session where it was needed. Turning it off records every
line as typed, leading space and all.

The mark is read at the **submission**, not at each line of one: a multi-line
construct is one entry, and Ada continuation lines are indented. What decides is
the first character of the first line.

## The file

`$XDG_CONFIG_HOME/adash/config.toml`, or `~/.config/adash/config.toml` when that
variable is unset. Only what was changed from the default is written:

    schema = 1

    [history]
    limit = 42

The `schema` key says which layout the file was written for. There has been one
schema, so nothing is renamed yet; the key exists so that a setting *can* be
renamed later without a file written today becoming unreadable. A file with no
`schema` key is treated as current, because a hand-written file is the case the
rule is for.

A file that cannot be read leaves the defaults in place and says so once. An
unknown key warns and the rest of the file is still read — a setting this build
does not know is likely to be one a later build does.

## The prompt

`prompt.directory` and `prompt.failure` shape the built-in prompt. `prompt.format`
replaces it: whatever you write is the prompt, with four placeholders filled in.

| Placeholder | What it becomes |
|---|---|
| `{directory}` | the working directory's last component |
| `{path}` | the whole working directory, with your home written `~` |
| `{status}` | the number the last submission ended with |
| `{failed}` | the failure marker, and nothing at all when the last submission succeeded |

Anything else is literal, including a `{word}` that names no placeholder — what a
prompt does wrong is on the screen the moment it is set, which is why free text
is allowed here and nowhere else in the settings.

Spacing is yours: the built-in prompt puts a blank between its parts, and a
format is used exactly as written. Control characters are refused, so a prompt
cannot carry escape sequences of its own — colour comes from the style package,
by the role of each part.

Setting `prompt.format` back to the empty string brings the built-in prompt back.

## What the shell reads at startup

The configuration file, then `$XDG_CONFIG_HOME/adash/startup.adash` if it is
there, then the per-session startup file when `startup.session` is on. Each is
an ordinary submission: what it declares is carried into the session the way any
submission's declarations are.

# Configuration

Eight settings, held in one TOML file, changed with `settings` and written with
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
| `history.per-session` | true or false | `false` | `Adash.Persistence.History` |
| `prompt.directory` | true or false | `true` | `Adash.Interactive.Prompt` |
| `prompt.failure` | true or false | `true` | `Adash.Interactive.Prompt` |
| `editing.enabled` | true or false | `true` | `Adash.Interactive.Editing` |
| `startup.session` | true or false | `true` | `Adash.Scripting.Startup` |

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

## What the shell reads at startup

The configuration file, then `$XDG_CONFIG_HOME/adash/startup.adash` if it is
there, then the per-session startup file when `startup.session` is on. Each is
an ordinary submission: what it declares is carried into the session the way any
submission's declarations are.

# On-disk formats

Two files, both under the user's own directories, both written the same careful
way.

| File | Holds | Written by |
|---|---|---|
| `$XDG_CONFIG_HOME/adash/config.toml` | the settings that differ from the default | `save_settings` |
| `$XDG_DATA_HOME/adash/history.jsonl` | what was typed, one submission per line | the session, as it goes |

`~/.config` and `~/.local/share` are the fallbacks when those variables are
unset. A store that cannot be reached is a session with no history — that is a
perfectly good thing for a session to be, and it is not an error.

## The settings file

TOML, read and written by `tomllib`, which is the exclusive provider of that
format here.

    schema = 1

    [history]
    limit = 42

Only what was changed is written; a setting at its default is absent, so a file
says what a user decided rather than what the build's defaults happened to be
when it was written. `configuration-reference.md` lists the settings.

The `schema` key says which layout the file was written for. There has been one
schema, so nothing is renamed yet — the key exists so that a setting *can* be
renamed later without a file written today becoming unreadable. A file with no
`schema` key is treated as current, because a hand-written file is the case that
rule is for.

An unknown key warns and the rest of the file is still read: a key this build
does not know is likely to be one a later build does.

## The history file

JSON Lines, written through `jsonlib`, which is the exclusive provider of that
format here. One JSON string per line, one line per submission:

    "version;"
    "pwd;"

A submission with a newline in it is one line here, because JSON escapes it —
that is the whole reason the format is JSON rather than raw text. A history file
of raw lines cannot say whether two lines were one submission or two, and a
shell that guesses gets it wrong on exactly the multi-line submissions a user
most wants back.

A line typed with a space in front of it never reaches the file: the session
does not record it, and what the file gets is what the session recorded. See
`interactive-guide.md`.

`forget` is the one operation that **rewrites** this file rather than appending
to it, and `forget ("…")` is the one that reads it looking for something the
session never held — a line older than `history.limit`, which the session's own
log no longer holds, still goes out of the file.

Lines are matched by text rather than by position, because a shared file holds
what several shells wrote, interleaved. A count forgets the last occurrence of
each line it is taking out; a line named by its **text** takes out *every* copy,
because a caller who names a line wants it gone and last week's copy is the same
secret as this morning's. The read and the write happen under one lock, so a
line another session appends meanwhile is not lost.

`history.limit` bounds what a **session** holds and can recall, not what the
file keeps. The file goes on holding what was written to it: that is what lets
`forget ("…")` reach a line older than the limit, which the paragraph above
depends on, and it is why loading is written to drop the excess in one move
rather than a line at a time. Nothing trims the file — `forget` is what takes
something out of it.

`history.enabled` off means nothing is written at all, which is what somebody
on a shared machine wants.

With `history.per-session` on, a session writes its own file and merges it into
the shared one when it ends. Two shells appending to a common file a line at a
time interleave their commands there; this makes the shared history read as runs
rather than as fragments.

## How both are written

**Atomically, through `hostkit`**: the new content is written beside the target
and moved into place, so a reader never sees half a file and a crash leaves the
previous version intact. A `.lock` file beside each is how two sessions avoid
writing at the same moment.

Neither file is a format anything else is expected to read, and neither is an
interface this project promises to keep: they are how *this* shell remembers
between sessions. What is promised is that a file this build wrote, this build
reads — and that a file it cannot read leaves the defaults in place and says so
once, rather than refusing to start.

## The cache

`Adash.Persistence` knows three stores and this build writes to two of them.
The third — the cache — is where anything that can be *rebuilt* would go, and
it is kept separate because a system is entitled to empty a cache directory
without asking: what is in there has to be something whose loss costs nothing.

Nothing is cached today, and nothing will be until something is worth caching;
a cache is a second copy of the truth, and every one of them is a chance to
serve a stale answer. The likeliest first user is an index of the programs on
`PATH`, for completing a command name without walking every directory on every
Tab — which is a feature this shell does not have yet.

What is tested is the promise rather than the mechanism: the three directories
are distinct, and neither the history file nor the configuration file is inside
the cache. The first thing to put a file there should find that already
guaranteed instead of having to establish it.

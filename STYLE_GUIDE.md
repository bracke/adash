# Style guide

## Language and compiler

Ada 2022. Built with `-gnat2022 -gnata -gnatwa -gnatw.X -gnatyM120`. Warnings
are not decoration; a change that adds one is a change that is not finished.

Line limit is 120 columns.

## Naming

- Packages, types and subprograms in `Mixed_Case_With_Underscores`.
- Constants and enumeration literals the same. No `SHOUTING_CASE`.
- Enumeration literals carry their type's sense as a prefix where the bare word
  would be ambiguous in a `use`-free context: `Role_Error`, `Color_Never`,
  `Msg_Version_Line`.
- Say what a thing is, not what it is made of. `Catalog`, not `String_Map`.

## Comments

Comment density here is high on purpose, and the convention is specific: a
comment says **why**, not what. The code already says what.

The comments worth writing are the ones that record a decision someone would
otherwise undo:

```ada
--  Read back from terminal_styles rather than from a copy kept here.
--  A cached copy is a second source of truth, and the two disagree the
--  first time anything else in the process sets the policy.
```

A comment restating the next line is worse than none — it is another thing that
can drift out of date, and it trains readers to skip comments.

Package specs open with a paragraph on what the package owns and, where it is
not obvious, what it deliberately does not. Where a rule exists because of a
specific failure, say so; a rule whose reason is recorded survives, and one
whose reason is not gets optimized away by the next person.

## GNATdoc

Every public declaration. `@param` for each parameter, `@return` for each
function. Private declarations are documented where the reason for them is not
obvious.

## Structure

- One responsibility per package. Split by responsibility and dependency
  boundary, never to reduce line count.
- Implementation detail goes in `Adash.<Subsystem>.Internal.*`, not in a
  repository-wide utility package.
- Bodies declare subprograms before use, with a one-line comment on each
  forward declaration.
- Section banners (`----`/`-- Name --`/`----`) before each subprogram body, as
  GNAT's own sources do.

## Errors

Expected operational failures are structured results. Exceptions are for
defects: violated contracts, impossible states, broken invariants. Never swallow
an exception silently.

A `case` on an enumeration that drives behaviour has no `others`. That is the
point: adding a literal should fail to compile at every place that has to think
about it, which is the only moment anyone is still thinking about it.

## Strings

No string a user reads may appear in Ada source. Layout — an indent, a
separator — is presentation and may; a sentence may not. When in doubt, ask
whether a translator would want to change it.

## Tests

An AUnit case per package or per coherent behaviour. Test names read as
statements about the code: `"Color_Never emits no escapes"`, not `"test_3"`.

Assert with a message that says what went wrong and includes the offending
value. `Assert (X = Y, "mismatch")` sends the reader back to the debugger;
naming the value saves the trip.

Every suite includes at least one test that would fail if the thing under test
did nothing at all. A test that passes vacuously is worse than no test, because
it is believed.

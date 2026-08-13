--  Root of the adash test and tooling crate.
--
--  Everything that checks, measures, documents or releases the repository
--  lives under here, and nothing under here is reachable from the adash
--  binary. That separation is the point of the crate: AUnit and project_tools
--  are development dependencies, and a user installing a shell should not be
--  installing a test framework with it.
--
--  The other half of the rule is that tooling is Ada. There are no shell
--  scripts, no Makefiles and no Python in this repository, and adding one is
--  not a shortcut but a second toolchain that has to be installed, learned
--  and kept working on every host the shell is built on.
--
--  Tooling output obeys the same rule as the shell's own: a string a
--  maintainer reads comes from the message catalog, not from an Ada literal.
--  See Adash_Tests.Reporting.
package Adash_Tests is
   pragma Pure;
end Adash_Tests;

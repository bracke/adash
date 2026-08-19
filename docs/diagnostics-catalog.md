# Diagnostics

Every message this build can produce, by identifier. A diagnostic is an
**identity and typed arguments**, never a sentence: what a subsystem reports is
`error.name_undeclared` with a `name`, and the catalog turns that into English
at the boundary. That is what lets a conformance case assert which diagnostic
was produced rather than how it was worded, a log record one structurally, and a
translation replace all of it without touching Ada.

A diagnostic may point at **other places** — the earlier declaration behind
"already declared", the first of a component given twice, every declaration an
ambiguous name could have meant — and carries each as a related location with
its own message: `note.declared_here` or `note.first_here`. Four at most, which
is what a diagnostic holds; a name with five meanings is already past what a
reader will work through. Where the place is comes from the subsystem that found it,
as a span; what line that is comes from the engine, which has the buffer. A
subsystem that knew a line would be a subsystem that had read the file.

Placeholders are written `{name}` and are declared by the identifier itself:
`Adash.Messages.Placeholders` says which each takes, and a unit test renders
every identifier with its own declared placeholders, so an entry that exists but
does not substitute what it promises fails the suite rather than a user's line.

This document is the catalog, grouped. The catalog file
`resources/messages/catalog.txt` is the source; if the two disagree, the file is
right and this is stale.

There are 584 messages in 22 groups.

Two of them are defensive and no program reaches them in this build:
`error.machine.too_many_alternatives`, because the parser refuses a
thirty-third alternative and both limits are thirty-two, and
`error.command.unavailable`, because every registered command is implemented
and every predefined entity is runnable. They stay because the mechanisms they
belong to are real: a limit with no message is a limit that fails silently, and
a registry that can name something it cannot yet run needs a way to say so.

## Errors — what a program or a session did wrong

| Identifier | Says |
|---|---|
| `error.none` | no error |
| `error.command_not_found` | command not found: {command} |
| `error.command_not_executable` | not executable: {command} |
| `error.command_denied` | permission denied: {command} |
| `error.command_start_failed` | could not start {command}: {reason} |
| `error.redirection_open_failed` | could not open {path} for redirection |
| `error.input_text_not_held` | the text could not be put where the program could read it ({reason}); this host has no temporary space this process may write in |
| `error.redirection_conflict` | more than one redirection targets {stream} |
| `error.pipe_creation_failed` | could not create a pipe for the pipeline |
| `error.machine.stack_full` | the expression stack is full |
| `error.machine.stack_empty` | the expression stack is empty |
| `error.machine.no_place` | a by-reference slot holds no place |
| `error.machine.no_value` | a variable was read before it was given a value |
| `error.machine.no_store_place` | a store with no place to store into |
| `error.machine.swap_empty` | a swap with nothing to swap |
| `error.machine.not_a_number` | arithmetic on a non-number |
| `error.machine.arithmetic` | the arithmetic does not hold |
| `error.machine.too_many_calls` | too many calls without returning |
| `error.machine.no_frame_room` | no room for another frame |
| `error.machine.no_return_to` | a return with nothing to return to |
| `error.machine.no_shell` | a command with no shell to run it |
| `error.machine.index_outside` | position {position} is outside a String of {length} |
| `error.machine.slice_outside` | the slice {first} .. {last} is outside a String of {length} |
| `error.machine.slice_lengths` | a slice of {wanted} cannot be assigned a String of {given} |
| `error.machine.bad_value_text` | {text} does not hold a value of that type |
| `error.machine.too_many_handlers` | too many handlers at once |
| `error.machine.no_return_value` | a function ended without returning a value |
| `error.machine.not_a_raise` | a re-raise of something that was not raised |
| `error.machine.position_outside` | position {position} is outside {type} |
| `error.machine.outside_bounds` | {position} is outside the range of {type} |
| `error.machine.outside_array` | index {position} is outside {type} |
| `error.machine.too_many_tasks` | more tasks at once than this build runs |
| `error.machine.too_many_alternatives` | more alternatives in one select than this build offers at once |
| `error.machine.queue_too_long` | more callers at one entry than this program allowed |
| `error.machine.task_ran_out` | a task ran out where this program said none would |
| `error.machine.too_many_allowed` | more tasks at once than this program allowed itself |
| `error.machine.blocking_in_protected` | an operation that may wait was run inside a protected operation, which would hold its lock against everybody |
| `error.machine.above_ceiling` | a task of higher priority than a protected object's ceiling called one of its operations |
| `error.machine.no_caller` | a rendezvous was moved on with nobody in it |
| `error.machine.tasks_stuck` | every task is waiting for something no task will do |
| `error.machine.task_finished` | the task whose entry was called has ended |
| `error.subtype.not_discrete` | a range can only narrow a discrete type; {found} is not one |
| `error.subtype.bound_not_static` | a subtype bound must be a value this build knows before it runs |
| `error.subtype.range_is_empty` | this range runs backwards, so the subtype admits nothing |
| `error.part_not_simple` | {name} holds a {found}, and a record or an array can only hold a simple value |
| `error.part_given_twice` | this record has two components called {name} |
| `error.record_is_empty` | {name} has no components, and a record with none holds nothing |
| `error.array_bound_not_static` | an array bound must be a value this build knows before it runs |
| `error.array_is_empty` | {name} runs backwards, so it holds nothing |
| `error.array_too_long` | {name} has more elements than this build carries, which is {limit} |
| `error.not_a_record` | {found} has no components, so {name} does not name one |
| `error.no_such_component` | {found} has no component called {name} |
| `error.not_an_array` | {found} is not an array, so it cannot be indexed |
| `error.aggregate_wrong_count` | {name} takes {expected} values, not {found} |
| `error.aggregate_not_expected` | a list of values in parentheses builds a record or an array, and {found} is neither |
| `error.not_a_package` | {name} is not a package |
| `error.package_not_declared` | there is no package called {name} for this body to complete |
| `error.not_a_generic` | {name} is not a generic, so there is nothing to make a new one from |
| `error.generic_wrong_actuals` | {name} takes {expected} types, not {found} |
| `error.not_a_task` | {name} is not a task, so there is nothing to abort |
| `error.not_an_entry` | {name} is not an entry |
| `error.accept_differs` | accept {name} must take what the entry was declared with |
| `error.protected_entry_parameters` | a protected entry takes no parameters; {name} was given some |
| `error.entry_parameter_not_simple` | {name} cannot take a {found}: an entry's parameters are simple values |
| `error.select_alternative` | a select alternative is an accept or a delay |
| `error.select_trigger` | what a select abandons work for is an entry call or a delay |
| `error.select_waits_twice` | a select says once what to do when nothing can be accepted, and this says it more than once |
| `error.discriminants_need_a_type` | {name} is a single declaration and has nowhere to be given discriminants; declare a type and an object of it |
| `error.discriminants_wrong_count` | {name} takes {expected} discriminants, not {found} |
| `error.nothing_to_constrain` | {name} takes nothing in parentheses |
| `error.count_outside_its_unit` | {name}'Count is asked inside the task or protected body that declares the entry, where the answer keeps |
| `error.generic_not_callable` | {name} is a generic; make one from it before calling it |
| `error.cannot_write` | {name} cannot write a {found}: a record or an array is its parts, and each of those has a text form where the whole has none |
| `error.result_not_simple` | {name} returns a {found}; a function here returns a simple value, and an out parameter is how a program hands back a record or an array |
| `error.file_not_writable` | nothing can be written at {path} |
| `error.file_write_failed` | writing to {path} did not finish |
| `error.file_too_large` | {path} holds more than this shell will read at once |
| `error.output_too_large` | {program} wrote more than this shell will hold at once |
| `error.stream_write_failed` | could not write to {stream} |
| `error.stream_read_failed` | could not read from {stream} |
| `error.mask_not_octal` | {text} is not a mask: a mask is octal digits, as every shell writes one |
| `error.unknown_signal` | no signal here is called {signal}; the names are the host's own in lower case |
| `error.signal_not_catchable` | {signal} cannot be caught: kill and stop are refused by every host by design, and this host may report fewer still |
| `error.signal_refused` | this host would not send {signal} to process {process}: it may have ended already, or it may not be yours to signal |
| `error.unknown_stream` | no stream here is called {stream}; the streams are output, errors and both |
| `error.stream_not_redirected` | {stream} was not redirected, so there is nowhere to put it back |
| `error.no_previous_directory` | there is nowhere to go back to: this session has not changed directory yet |
| `error.no_matching_files` | nothing is called {pattern} here, and a pattern that names nothing is not passed along as a word |
| `error.too_many_matches` | {pattern} names more than {limit} paths, which is more than one command carries; name fewer, or loop over Match_At |
| `error.no_creation_mask` | this host has no creation mask: permissions here come from the directory a file is made in, not from a per-process mask |
| `error.no_resource_limits` | this host has no resource limits: what it has instead is attached to a set of processes rather than inherited by them, and a process cannot lower its own |
| `error.unknown_resource` | no limit here is called {resource}; resource_limit with no argument lists the ones there are |
| `error.limit_not_a_number` | {text} is not a limit: a limit is digits -- bytes for the sizes, seconds for processor_time, a count for the rest -- or the word unlimited |
| `error.limit_refused` | this host would not set the limit on {resource}: a limit cannot go above its ceiling, and raising a ceiling needs privilege |
| `error.process_would_not_stop` | process {process} would not take the request to stop: it may have ended already, or it may not be yours to signal |
| `error.job_unknown` | no such job: {job} |
| `error.job_is_suspended` | job {job} is suspended; resume it before waiting for it |
| `error.execution_cancelled` | cancelled |
| `error.capability_unavailable` | this system does not support {capability} |
| `error.directory_not_found` | no such directory: {path} |
| `error.directory_denied` | permission denied for directory: {path} |
| `error.module_not_found` | no script called {name}: {where} |
| `error.source_unreadable` | could not read source: {source} |
| `error.source_too_large` | {source} holds more source than this shell will read at once |
| `error.source_invalid_encoding` | {source} is not valid UTF-8; the first bad byte is at offset {offset} |
| `error.type_mismatch` | expected {expected}, found {found} |
| `error.name_undeclared` | {name} is not declared here |
| `error.name_already_declared` | {name} is already declared in this scope |
| `error.lexical.stray_character` | {character} does not begin anything the language recognises |
| `error.lexical.unterminated_string` | this string literal is not closed before the end of the line |
| `error.lexical.unterminated_character` | this character literal is not closed |
| `error.lexical.malformed_number` | {text} is not a well formed numeric literal |
| `error.lexical.malformed_identifier` | {text} is not a well formed identifier |
| `error.lexical.bad_escape` | {text} is not an escape this build defines |
| `error.lexical.quote_in_interpolation` | a quotation mark in an interpolated string is written \" and never doubled |
| `error.lexical.brace_unescaped` | a closing brace in an interpolated string must be escaped |
| `error.syntax.unexpected` | expected {expected}, found {found} |
| `error.syntax.missing` | expected {expected} here |
| `error.syntax.mixed_logical` | {first} and {second} cannot be mixed without parentheses |
| `error.not_assignable` | {name} cannot be assigned to |
| `error.not_a_type` | {name} is not a type |
| `error.requeue_not_an_entry` | {name} is not an entry of this task or protected object, and a requeue moves a caller to one of its own |
| `error.family_index_not_discrete` | an entry family is indexed by a discrete type of at most 256 values, and {found} is not one |
| `error.aggregate.others_covers_nothing` | others answers for the parts nothing else named, and every part here was named |
| `error.raise_outside_a_handler` | raise on its own raises again what was caught, so it belongs inside a handler that caught something |
| `error.terminate_outside_select` | terminate says a task may end instead of waiting for a caller, so it belongs to a select that is waiting for one |
| `error.queuing_twice` | {name} says how callers are taken off a queue and this program already said otherwise, and a program has one queuing policy |
| `error.dispatching_twice` | {name} gives a dispatching policy to priorities that already have another one, and a priority runs under one policy |
| `error.empty_priority_range` | the priorities from{first} to{last} are none of them, because the range runs backwards |
| `error.unknown_profile` | {name} is not a profile this language has; the ones it has are Ravenscar and Jorvik |
| `error.unknown_policy` | {name} is not a policy this machine implements; a policy accepted and not implemented would say something untrue about how a program runs |
| `error.unknown_restriction` | {name} is not a restriction this language knows |
| `error.restriction_broken` | this program said {name}, and this is one |
| `error.unknown_pragma` | {name} is not a pragma this language has; the ones it has are Priority, Detect_Blocking, Restrictions, Task_Dispatching_Policy, Priority_Specific_Dispatching, Queuing_Policy, Locking_Policy and Profile |
| `error.priority_not_static` | a priority is a number written where it stands, because what a task runs at is decided when it starts |
| `error.identity_needs_a_task` | {name} is a Task_Id with nothing in it, and an identity that names no task is not one; declare it with the task it means |
| `error.cannot_be_copied` | a {name} cannot be copied: what one is is the thing that runs or the state that is shared, and A'Identity is how a program keeps which one it meant |
| `error.not_a_family` | {name} is one entry rather than a family, so there is no member to name |
| `error.family_needs_a_member` | {name} is an entry family, and which member is what the parentheses say |
| `error.family_takes_nothing` | {name} is an entry family, and a member of one takes nothing |
| `error.requeue_takes_nothing` | {name} takes parameters, and a requeue moves a caller without moving what it gave |
| `error.is_a_type` | {name} is a type, and a type is not a value; an object of it is what has operations |
| `error.not_an_exception` | {name} is not an exception anything raises |
| `error.not_callable` | {name} cannot be called |
| `error.function_as_statement` | {name} yields a value, so a call to it is an expression and not a statement |
| `error.exit_outside_loop` | an exit statement outside any loop |
| `error.program_raised` | the program raised {exception} |
| `error.program_raised_detail` | the program raised {exception}: {detail} |
| `error.body_missing` | {name} was declared and never given a body |
| `error.name_is_predefined` | {name} is provided by the shell and cannot be redeclared |
| `error.no_matching_subprogram` | no {name} among the {count} declared takes these arguments |
| `error.ambiguous_literal` | {name} is a value of {count} types here, and nothing says which of them is meant |
| `error.ambiguous_call` | this call to {name} fits {count} of the declarations |
| `error.attribute_not_defined` | {found} does not have a {attribute} attribute |
| `error.actual_not_variable` | argument {position} is {mode}, so it must be a variable |
| `error.nested_subprogram` | {name} is nested more deeply than this build can analyse |
| `error.return_without_value` | a function must return a value |
| `error.return_with_value` | a procedure cannot return a value |
| `error.condition_not_boolean` | a condition must be Boolean, not {found} |
| `error.procedure_has_no_value` | {name} is a procedure and yields no value |
| `error.operand_has_no_value` | {operator} was given something that yields no value |
| `error.operator_not_defined` | operator {operator} is not defined for {left} and {right} |
| `error.statement_among_declarations` | only declarations may appear before begin |
| `error.string_index_malformed` | a String is taken apart by one position or one range of them |
| `error.too_many_parameters` | {name} takes more parameters than this build carries, which is {limit} |
| `error.too_many_at_once` | at most {limit} {what} in one of these, and this has more |
| `list.alternatives` | alternatives |
| `list.parameters` | parameters |
| `list.components` | components |
| `list.values` | values |
| `list.names` | names |
| `list.statements` | statements |
| `list.arguments` | arguments |
| `list.choices` | choices |
| `list.handlers` | handlers |
| `error.open_by_element` | {name} is as long as what was passed to it, so the whole of it is not replaced: assign a slice of it, or one element at a time |
| `error.needs_bounds` | a variable of {name} says how long it is, as {name} (1 .. 4), and its first index is one |
| `error.no_such_slice` | {name} has no elements {first} .. {last} |
| `error.not_taken_apart` | a {found} is not taken apart that way; a String takes a position or a range, an array a position |
| `error.case.not_discrete` | a case examines a discrete value; {found} is not one |
| `error.case.choice_not_static` | a case choice must be a literal value, a range of them, or others |
| `error.case.choice_covered_twice` | this choice covers a value an earlier one already covers |
| `error.case.range_is_empty` | this range runs backwards, so it covers nothing |
| `error.number_not_a_literal` | {name} is a named number, whose value is a literal |
| `error.number_not_numeric` | {name} is a named number and {found} is not a number |
| `error.case.others_not_last` | others covers what is left, so it must be the last choice of the last alternative |
| `error.case.incomplete` | this case does not cover every value of {found}; add an others alternative |
| `error.not_lowerable` | this build cannot yet run {construct} |
| `error.wrong_argument_count` | {name} takes {expected} arguments, not {found} |
| `error.no_such_parameter` | {name} has no parameter called {parameter} |
| `error.parameter_given_twice` | {name} was given {parameter} twice |
| `error.positional_after_named` | an argument without a name comes after one with a name, in a call to {name} |
| `error.parameter_not_given` | {name} was not given {parameter}, which has no default |
| `error.default_not_literal` | the default for {name} is not a literal |
| `error.default_not_in_mode` | {name} is written to rather than given, so it cannot have a default |
| `error.not_runnable_yet` | {name} exists but cannot be run in this build |
| `error.command.wrong_arguments` | {name} was given the wrong number of arguments: {found} |
| `error.too_many_kept` | this session already carries {limit} definitions, so {name} will not be remembered |
| `error.empty_pipeline` | nothing has been added to the pipeline |
| `error.no_history_here` | this session is not keeping a history |
| `error.history_not_forgotten` | the history file could not be rewritten; the lines are gone from this session only |
| `error.command.unavailable` | {name} is not available in this build |
| `error.command.bad_assignment` | {text} is not of the form NAME=VALUE |
| `error.script_cycle` | {source} is already being loaded; scripts may not load each other in a cycle |
| `error.setting_unknown` | no setting is called {key} |

## Lines — what a command reports when it worked

| Identifier | Says |
|---|---|
| `line.traced` | + {command} |
| `line.history_entry` | {number}  {line} |
| `line.forgotten` | {count} forgotten |
| `line.diagnostic_at` | {path}:{line}:{column}: {text} |
| `note.declared_here` | declared here |
| `note.first_here` | the first one is here |
| `line.creation_mask` | umask {mask} |
| `line.took` | {what} took {seconds} seconds |
| `line.search` | search back for |
| `line.search_empty` | nothing holds |
| `line.limit` | {resource} is {value} |
| `line.limit_unbounded` | {resource} is unlimited |
| `line.limit_ceiling` | {resource} may be raised to {value} |
| `line.limit_ceiling_unbounded` | {resource} may be raised without limit |
| `line.job_started` | [{id}] started {what} |
| `line.job_finished` | [{id}] finished with status {status} |
| `line.job_signalled` | [{id}] was ended by {signal} |
| `line.directory` | {path} |
| `line.setting` | {key} = {value}  {summary} |
| `line.settings_saved` | settings written to {path} |
| `line.variable` | {name}={value} |
| `line.job` | [{job}] {state}  {description} |
| `line.command_entry` | {name}  {summary} |
| `line.version` | {name} {version} |

## Commands — the help text for each

| Identifier | Says |
|---|---|
| `command.cd.doc` | Change the directory the shell is in. With no argument, go to the home directory. |
| `command.pwd.doc` | Report the directory the shell is in. |
| `command.exit.doc` | End the session, optionally with a status. Written quit, because exit is a keyword of the language. |
| `command.set.doc` | Set a variable children will inherit, written NAME=VALUE. |
| `command.unset.doc` | Remove a variable children would inherit. |
| `command.env.doc` | List the variables children will inherit. |
| `command.jobs.doc` | List what the shell is running. |
| `command.help.doc` | List the internal commands, or describe one. |
| `command.version.doc` | Report which build this is. |
| `command.history.doc` | List what has been typed this session. |
| `command.run.doc` | Run a program and wait for it to finish. |
| `command.run_into.doc` | Run a program with its output written to a file, replacing what was there. |
| `command.run_from.doc` | Run a program with its input read from a file. |
| `command.complete_with.doc` | Name a subprogram that says what may follow a program, one candidate per line, for Tab to offer. |
| `command.on_signal.doc` | Run a subprogram when a signal arrives: terminate, hangup, quit, continue and the rest, by the host's own name in lower case. kill and stop cannot be caught anywhere and are refused. |
| `command.signal_process.doc` | Send a signal to a process by id, naming the signal rather than numbering it. |
| `command.redirect.doc` | Point the shell own stream at a file for the rest of the session, replacing what is there: output, errors, or both. What the programs it starts write goes there too. |
| `command.redirect_append.doc` | As redirect, adding to the end of the file rather than replacing what is in it. |
| `command.redirect_back.doc` | Put a stream back where it was before redirect moved it. |
| `command.run_instead.doc` | Become a program: run it instead of this shell, keeping the process, its files and its place in the terminal. Nothing comes after it, and what on_exit asked for does not run. Windows has no such call. |
| `command.run_matching.doc` | Run a program, expanding the arguments that hold a pattern into the paths they name. An argument with no * ? or [ is passed along untouched, and a pattern that names nothing refuses the command. |
| `command.umask.doc` | Show the permissions this host takes away from a new file, or set them, in octal. Windows has none. |
| `command.time.doc` | Run a program and report how long it took, in wall-clock seconds. |
| `command.resource_limit.doc` | Show what this host will let this shell use, or set one of the limits. Sizes are bytes; unlimited is a value. Windows has none. |
| `command.resource_ceiling.doc` | Show or set how far a limit may be raised. Anybody may lower a ceiling and only privilege raises it again. |
| `command.run_with.doc` | Run a program with variables set for it alone, each written NAME=VALUE as set writes one. The assignments come first; the program is the first argument that is not one. |
| `command.start_with.doc` | As run_with, without waiting: the job is named and the shell goes on. |
| `command.run_from_text.doc` | Run a program with its input read from text this script computed. The text comes first; what follows is the program and its arguments. |
| `command.run_append.doc` | Run a program with its output added to the end of a file. |
| `command.run_new.doc` | Run a program with its output written to a file that must not already exist. |
| `command.run_errors_into.doc` | Run a program with what it complains about written to a file, replacing what was there. |
| `command.run_errors_append.doc` | Run a program with what it complains about added to the end of a file. |
| `command.run_errors_new.doc` | Run a program with what it complains about written to a file that must not already exist. |
| `command.run_all_into.doc` | Run a program with everything it writes, output and complaints, in one file. |
| `command.run_all_append.doc` | Run a program with everything it writes added to the end of one file. |
| `command.run_all_new.doc` | Run a program with everything it writes in one file that must not already exist. |
| `command.pipe.doc` | Add a program to the pipeline being built. |
| `command.pipe_start.doc` | Run the pipeline in the background, without waiting for it. |
| `command.pipe_from_text.doc` | Take the pipeline's input from text this script computed. Does not run it. |
| `command.pipe_from.doc` | Take the pipeline's input from a file, which must exist. Does not run it. |
| `command.pipe_into.doc` | Say that the pipeline's output goes to a file, replacing what was there. |
| `command.pipe_append.doc` | Say that the pipeline's output is added to the end of a file. |
| `command.pipe_new.doc` | Say that the pipeline's output goes to a file that must not already exist. |
| `command.pipe_errors_into.doc` | Say that what the pipeline's last stage complains about goes to a file. |
| `command.pipe_errors_append.doc` | Say that what it complains about is added to the end of a file. |
| `command.pipe_errors_new.doc` | Say that what it complains about goes to a file that must not already exist. |
| `command.pipe_all_into.doc` | Say that everything the pipeline's last stage writes goes to one file. |
| `command.pipe_all_append.doc` | Say that everything it writes is added to the end of one file. |
| `command.pipe_all_new.doc` | Say that everything it writes goes to one file that must not already exist. |
| `command.pipe_run.doc` | Run the pipeline that pipe has built, and wait for it. |
| `command.start.doc` | Start a program in the background and record it as a job. |
| `command.wait.doc` | Wait for a job to finish and report how it ended. |
| `command.stop_process.doc` | Ask a process this session did not start to stop, by its id. POSIX sends SIGTERM; Windows terminates it. |
| `command.stop.doc` | Ask a job to stop. |
| `command.suspend.doc` | Suspend a running job, leaving it able to be resumed. |
| `command.resume.doc` | Resume a suspended job, in the background. |
| `command.foreground.doc` | Resume a stopped job in front and wait for it: foreground (JOB). |
| `command.write_file.doc` | Write text to a file, replacing what was there: write_file (TEXT, FILE). |
| `command.make_directory.doc` | Make a directory, and any above it that is missing: make_directory (DIRECTORY). |
| `command.remove_file.doc` | Take a file away: remove_file (FILE). A file that is not there is not an error. |
| `command.remove_directory.doc` | Take an empty directory away: remove_directory (DIRECTORY). |
| `command.rename.doc` | Give something another name or place: rename (FROM, TO). Refuses to replace what is there. |
| `command.copy_file.doc` | Copy a file: copy_file (FROM, TO). Refuses to replace what is there. |
| `command.on_interrupt.doc` | Name a subprogram to run when the user interrupts. It stays registered; on_exit cleanups still run afterwards. |
| `command.on_exit.doc` | Run a subprogram before this session ends: on_exit (SUBPROGRAM). |
| `command.append_file.doc` | Add text to the end of a file: append_file (TEXT, FILE). |
| `command.forget.doc` | Forget history, in this session and in the file: forget (COUNT) or forget ("LINE"). |
| `command.settings.doc` | List the settings, or change one: settings (NAME, VALUE). |
| `command.save_settings.doc` | Write the current settings to the configuration file. |
| `command.source.doc` | Read and run a script in this session. |
| `command.hint` | shell command |

## Predefined entities — the help text for each

| Identifier | Says |
|---|---|
| `predefined.type.doc` | A predefined type. It can be written where a type is expected, and nowhere else. |
| `predefined.clock.doc` | The seconds on the session's own clock, which is monotonic: a program that measures an interval measures one whatever somebody does to the system time. What `delay until` takes. |
| `predefined.clock.hint` | seconds on the session's clock |
| `predefined.true.doc` | The Boolean value True. |
| `predefined.false.doc` | The Boolean value False. |
| `predefined.put_line.doc` | Write a value to standard output, followed by a line ending. |
| `predefined.put.doc` | Write a value to standard output without a line ending. |
| `predefined.env_value.doc` | The value of an environment variable, or the empty string when it is not set. |
| `predefined.env_value.hint` | read an environment variable |
| `predefined.status.doc` | What the last command did: zero when it succeeded, and otherwise the shell's one number for what became of it. |
| `predefined.status.hint` | the last command's status |
| `predefined.exists.doc` | Whether anything at all is at this path, of whatever kind. |
| `predefined.exists.hint` | whether anything is at a path |
| `predefined.is_directory.doc` | Whether a directory is at this path. |
| `predefined.is_directory.hint` | whether a path is a directory |
| `predefined.read_file.doc` | Read_File (PATH) is what a file holds, or nothing when there is no such file. |
| `predefined.read_file.hint` | what a file holds |
| `predefined.current_directory.doc` | Current_Directory is where the session is, which cd moves. |
| `predefined.current_directory.hint` | where the session is |
| `predefined.file_count.doc` | File_Count (DIRECTORY) is how many names a directory holds, or 0 where there is no such directory. |
| `predefined.file_count.hint` | how many names a directory holds |
| `predefined.file_at.doc` | File_At (DIRECTORY, POSITION) is one of the names in a directory, sorted, counting from one. |
| `predefined.file_at.hint` | one name in a directory |
| `predefined.previous_directory.doc` | Previous_Directory is where the shell was before the last cd, which is where cd ("-") goes back to. Empty in a session that has not moved. |
| `predefined.previous_directory.hint` | where the last cd came from |
| `predefined.job_process.doc` | Job_Process (JOB) is the process id of a job this session started, for handing to a program or to signal_process. Zero for a job that is not there, one that has been reaped, or a host with no process ids. |
| `predefined.job_process.hint` | the process id of a job |
| `predefined.left_aligned.doc` | Left_Aligned (TEXT, WIDTH) is the text padded on the right with spaces to that width. Text already longer comes back whole rather than cut. |
| `predefined.left_aligned.hint` | text padded on the right |
| `predefined.right_aligned.doc` | Right_Aligned (TEXT, WIDTH) is the text padded on the left with spaces to that width. Text already longer comes back whole rather than cut. |
| `predefined.right_aligned.hint` | text padded on the left |
| `predefined.zero_padded.doc` | Zero_Padded (TEXT, WIDTH) is the text padded on the left with zeros to that width, for a number in a name or a time. |
| `predefined.zero_padded.hint` | text padded on the left with zeros |
| `predefined.decimals.doc` | Decimals (VALUE, PLACES) is a number written with that many decimal places, between none and twenty. Empty for a number of places nobody could mean. |
| `predefined.decimals.hint` | a number with that many decimals |
| `predefined.braces_count.doc` | Braces_Count (TEXT) is how many strings a text with brace groups stands for: a group of two alternatives is two, a range counts, and two groups multiply. Text with no group stands for itself. |
| `predefined.braces_count.hint` | how many strings braces stand for |
| `predefined.braces_at.doc` | Braces_At (TEXT, POSITION) is one of the strings a text with brace groups stands for, counting from one, in the order they are written. |
| `predefined.braces_at.hint` | one string braces stand for |
| `predefined.match_count.doc` | Match_Count (PATTERN) is how many paths a pattern names, with * ? and [class] in the last segment. Nothing is expanded unless a script asks for it. |
| `predefined.match_count.hint` | how many paths a pattern names |
| `predefined.match_at.doc` | Match_At (PATTERN, POSITION) is one of the paths a pattern names, sorted, counting from one. |
| `predefined.match_at.hint` | one path a pattern names |
| `predefined.program_path.doc` | Program_Path (PROGRAM) is where the host would find that program, or nothing when it would not. |
| `predefined.program_path.hint` | where a program is |
| `predefined.stage_count.doc` | Stage_Count is how many stages the last pipeline had. |
| `predefined.stage_count.hint` | how many stages the last pipeline had |
| `predefined.stage_status.doc` | Stage_Status (POSITION) is what that stage of the last pipeline reported. |
| `predefined.stage_status.hint` | what one stage of a pipeline reported |
| `predefined.is_executable.doc` | Whether a program at this path could be run, as this host judges it. |
| `predefined.is_executable.hint` | whether a path is something to run |
| `predefined.index.doc` | Where one text starts inside another, counting from one, or zero when it is not there at all. |
| `predefined.index.hint` | where a piece of text starts inside another |
| `predefined.trim.doc` | The text without the blanks at either end of it. |
| `predefined.trim.hint` | the text without the blanks around it |
| `predefined.to_upper.doc` | The text with every letter in upper case. |
| `predefined.to_upper.hint` | the text in capitals |
| `predefined.to_lower.doc` | The text with every letter in lower case. |
| `predefined.to_lower.hint` | the text in small letters |
| `predefined.starts_with.doc` | Whether the text begins with that piece. |
| `predefined.starts_with.hint` | whether text begins with a piece |
| `predefined.matches.doc` | Whether the text matches the pattern: * for any run of characters, ? for one, [abc] or [a-z] for one of a set, [!abc] for one outside it. Nothing is read from the filesystem and no argument is expanded; a script asks about a name it already has. |
| `predefined.matches.hint` | whether text matches a pattern |
| `predefined.ends_with.doc` | Whether the text ends with that piece. |
| `predefined.ends_with.hint` | whether text ends with a piece |
| `predefined.output_of.doc` | Run a program and answer with what it wrote to standard output, without the newline it ended with. What it writes to standard error is not collected and reaches the user. |
| `predefined.read_line.doc` | Read one line from the shell's own input, without the newline that ended it. Answers with nothing at the end of the input; Input_Ended says which. |
| `predefined.read_line.hint` | read a line of input |
| `predefined.input_ended.doc` | Whether the last Read_Line found the end of the input rather than a line. An empty line is a line a file may contain, so the two are asked separately. |
| `predefined.input_ended.hint` | whether the input has run out |
| `predefined.output_of.hint` | run a program and read what it wrote |
| `predefined.error_of.doc` | Error_Of (PROGRAM, ...) runs a program and answers with what it complained about. |
| `predefined.error_of.hint` | what a program complained about |
| `predefined.all_of.doc` | All_Of (PROGRAM, ...) runs a program and answers with everything it wrote, in the order it wrote it. |
| `predefined.all_of.hint` | everything a program wrote |
| `predefined.last_job.doc` | Last_Job is the number of the job this session started most recently, or 0. |
| `predefined.last_job.hint` | the job most recently started |
| `predefined.output_of_pipe.doc` | Output_Of_Pipe runs the pipeline built so far and answers with what it wrote. |
| `predefined.output_of_pipe.hint` | what a pipeline wrote |
| `predefined.error_of_pipe.doc` | Error_Of_Pipe runs the pipeline built so far and answers with what its last stage complained about. |
| `predefined.error_of_pipe.hint` | what a pipeline complained about |
| `predefined.all_of_pipe.doc` | All_Of_Pipe runs the pipeline built so far and answers with everything its last stage wrote. |
| `predefined.all_of_pipe.hint` | everything a pipeline wrote |
| `predefined.argument_count.doc` | How many arguments the script was given, after its own path. Zero in an interactive session. |
| `predefined.argument_count.hint` | how many arguments the script was given |
| `predefined.argument.doc` | One of the arguments the script was given, counting from one, or the empty string when it was not given that many. |
| `predefined.argument.hint` | one of the script's arguments |
| `predefined.new_line.doc` | Write a line ending to standard output. |
| `predefined.type.hint` | type |
| `predefined.constant.hint` | constant |
| `predefined.put_line.hint` | write a line |
| `predefined.put.hint` | write without a line ending |
| `predefined.new_line.hint` | end the line |

## Configuration — what a settings file or a value was refused for

| Identifier | Says |
|---|---|
| `config.wants.truth` | true or false |
| `config.wants.whole` | a whole number |
| `config.wants.range` | between {low} and {high} |
| `config.wants.choice` | one of {choices} |
| `config.wants.text` | text of at most {limit} characters, with nothing in it a terminal would read as an instruction |
| `config.unknown-key` | {path}: no setting is called {key}; it was ignored. |
| `config.wrong-type` | {key} expects {detail}. |
| `config.out-of-range` | {key} must be {detail}. |
| `config.bad-choice` | {key} must be one of {detail}. |
| `config.syntax` | {path}: line {line}, column {column}: {detail} |
| `config.unreadable` | {path} could not be read; the defaults are in force. |
| `config.not-text` | {path} is not valid UTF-8; the defaults are in force. |
| `config.too-large` | {path} holds more than this shell will read at once; the defaults are in force. |
| `config.newer-schema` | {path} was written by a newer Adash (schema {detail}); unknown settings were ignored. |
| `config.migrated` | {path} was written for schema {detail} and has been brought forward. |

## Settings — the one-line summary of each

| Identifier | Says |
|---|---|
| `setting.color` | When coloured output is produced: auto, always or never. |
| `setting.history-enabled` | Whether commands are recorded in the history file. |
| `setting.history-limit` | How many history entries are kept. |
| `setting.read-limit` | The most one read will hold, in mebibytes. |
| `setting.trace` | Whether each command is announced before it runs. |
| `setting.prompt-directory` | Whether the prompt shows the working directory. |
| `setting.prompt-failure` | Whether the prompt marks that the last command failed. |
| `setting.editing` | Whether lines are edited in place rather than read whole. |
| `setting.history-per-session` | keep this session's history in a file of its own and merge it in when the session ends |
| `setting.history-ignore-space` | Whether a line typed with a space in front of it is left out of the history. |
| `setting.stop-on-failure` | Whether a submission stops at the first command that fails, rather than carrying on to the next statement. |
| `setting.prompt.format` | What the prompt looks like: your own text, with the words directory, path, status and failed in braces standing for the parts the shell fills in. Empty means the built-in prompt. |
| `setting.session-file` | Whether the per-session startup file runs. |

## Expectations — what the parser wanted where it stopped

| Identifier | Says |
|---|---|
| `expected.expression` | an expression |
| `expected.statement` | a statement |
| `expected.type_name` | a type name |
| `expected.literal_name` | the name of a value |
| `expected.component_name` | the name of a component |
| `expected.package_name` | the name of a package |
| `expected.task_name` | the name of a task |
| `expected.parameter_name` | a parameter name |
| `expected.loop_variable` | a loop variable |
| `expected.subprogram_name` | a subprogram name |
| `expected.exception_name` | an exception name |
| `expected.attribute_name` | an attribute name |
| `expected.interpolation_rest` | the rest of an interpolated string |
| `expected.end_of_input` | end of input |

## Lowering — constructs this build does not yet run

| Identifier | Says |
|---|---|
| `lower.call_wrong_count` | a call with the wrong number of arguments |
| `lower.write_back_not_variable` | a write-back argument that is not a variable |
| `lower.float_literal` | a Float literal this build cannot hold |
| `lower.unresolved_name` | an unresolved name |
| `lower.variable_of_type` | a variable of type {type} |
| `lower.call_to` | a call to {name} |
| `lower.this_operator` | this operator |
| `lower.arithmetic_on` | arithmetic on {type} |
| `lower.float_operation` | that operation on a Float |
| `lower.joining_letters` | joining two Characters |
| `lower.string_operation` | that operation on a String |
| `lower.string_concatenation` | string concatenation |
| `lower.value_of` | reading a {type} back from text |
| `lower.image_of` | the image of a {type} |
| `lower.procedure_as_value` | a procedure call used as a value |
| `lower.this_expression` | this expression |
| `lower.call_in_context` | a call to {name} in this context |
| `lower.command_arguments` | a command call with more than {count} arguments |
| `lower.argument_of_type` | an argument of type {type} |
| `lower.declaration_unresolved` | a declaration of an unresolved name |
| `lower.string_no_value` | a String declared with no initial value |
| `lower.assignment_unresolved` | an assignment to an unresolved name |
| `lower.case_choice` | a case choice |
| `lower.exit_outside_loop` | an exit outside a loop |
| `lower.return_with_value` | a return statement with a value |
| `lower.this_statement` | this statement |
| `lower.writing_type` | writing a value of type {type} |

## Signals — how a program ended

| Identifier | Says |
|---|---|
| `signal.interrupt` | an interrupt |
| `signal.quit` | a quit request |
| `signal.terminate` | a request to end |
| `signal.kill` | a kill |
| `signal.hangup` | a hangup |
| `signal.stop` | a stop that cannot be caught |
| `signal.terminal_stop` | the terminal's stop |
| `signal.continue` | a request to continue |
| `signal.pipe` | writing to a closed pipe |
| `signal.background_read` | reading the terminal from the background |
| `signal.background_write` | writing to the terminal from the background |
| `signal.window_change` | the terminal changing size |
| `signal.child` | a child changing state |

## job

| Identifier | Says |
|---|---|
| `job.state.running` | running |
| `job.state.stopped` | stopped |
| `job.state.completed` | finished |

## Usage — the command line

| Identifier | Says |
|---|---|
| `usage.line` | Usage: adash [options] [FILE [ARGUMENT...]] |
| `usage.options_header` | Options: |
| `usage.option.help` | --help, -h       show this help and exit |
| `usage.option.version` | --version, -V    show version information and exit |
| `usage.script` | FILE             run a script and exit; anything after it is the script's own |
| `usage.more` | Run adash with no options to start an interactive session. |

## Startup — what happened before the first prompt

| Identifier | Says |
|---|---|
| `startup.unknown_option` | Unknown option: {option} |
| `startup.catalog_unavailable` | Could not load the message catalog from {path}. Adash will report messages by identifier instead of by text. |

## Capabilities — what the host can and cannot do

| Identifier | Says |
|---|---|
| `capability.signals` | sending signals |
| `capability.job_control` | job control |
| `capability.pseudo_terminal` | pseudo-terminals |
| `capability.becoming_a_program` | replacing this program with another |
| `capability.advisory_locks` | advisory file locks |

## application

| Identifier | Says |
|---|---|
| `application.name` | adash |
| `application.summary` | A shell whose command language is Ada. Interactive input and scripts pass through one language pipeline and one execution engine. |

## version

| Identifier | Says |
|---|---|
| `version.line` | adash {version} |
| `version.build` | build profile {profile}, built for {os} {arch} |
| `version.prerelease_notice` | This is a pre-release build. Interfaces and behaviour may still change. |

## Tooling — the repository checks and the release tools

| Identifier | Says |
|---|---|
| `tooling.conformance.no_id` | the case has no id |
| `tooling.conformance.other_host` | not for this host |
| `tooling.conformance.no_cases` | no case directory at {path} |
| `tooling.conformance.no_expected` | no expected-output file beside it |
| `tooling.conformance.no_binary` | the binary could not be started |
| `tooling.conformance.no_status` | the case has no integer exit status |
| `tooling.conformance.unreadable_expected` | the expected-output file could not be read |
| `tooling.conformance.no_entries` | the file holds no case entries |
| `tooling.conformance.unknown_key` | unknown key: {key} |
| `tooling.conformance.unreadable` | could not be read: {reason} |
| `tooling.conformance.wrong_status` | exit status: expected {expected} got {found} |
| `tooling.conformance.malformed_toml` | line {line}: {reason} |
| `tooling.bench.header` | adash benchmarks |
| `tooling.bench.repetitions` | median and fastest of {count} runs, in microseconds |
| `tooling.bench.profile` | build profile: {profile} |
| `tooling.bench.column.median` | median |
| `tooling.bench.column.fastest` | fastest |
| `tooling.bench.group.pipeline` | language pipeline, one typed line |
| `tooling.bench.group.frontend` | interactive frontend |
| `tooling.bench.group.startup` | start-up work, once per session |
| `tooling.bench.no_sample` | the sample line did not load; nothing measured |
| `tooling.bench.drift` | A fastest run far below the median means the operation gets slower as it repeats, which is a defect rather than noise. See docs/benchmark-guide.md. |
| `tooling.bench.methodology` | Methodology: each figure is the median of {count} consecutive in-process runs of the named operation, timed with Ada.Real_Time on the machine this was run on. No process is spawned, so these do not include the operating system cost of starting a shell. Comparisons between machines, or between builds at different optimization levels, are not meaningful. |
| `tooling.bench.usage` | usage: adash_bench [repetitions], run from the adash_tests directory, where repetitions is between 1 and {most} |
| `tooling.bench.bad_count` | "{given}" is not a number of repetitions |
| `tooling.bench.ceilings_unreadable` | the ceilings could not be read from {path} ({reason}); this tool is run from the adash_tests directory |
| `tooling.bench.ceilings_malformed` | the ceilings in {path} are not readable TOML: line {line}, {reason} |
| `tooling.bench.no_ceiling` | ^ {what} has no ceiling in {path}. A figure nothing bounds is a figure no run can fail on |
| `tooling.bench.over_ceiling` | ^ {what} took {measured} us, over its ceiling of {ceiling} us |
| `tooling.bench.drifted` | ^ {what} has a median of {measured} us against a fastest run of {fastest} us, more than {ratio} times: it gets slower as it repeats |
| `tooling.bench.no_drift_rule` | {path} records no drift rule, and a report the tool calls a defect that nothing can fail on is a report |
| `tooling.bench.some_drift` | An operation got slower while it was being measured. A loaded machine moves every figure together; this moves one figure away from its own fastest run, so look for what accumulates -- a cache nothing evicts, a list rescanned from the start, a handle opened per call. |
| `tooling.bench.over_some_ceiling` | Over a ceiling. A bound in {path} is an order of magnitude above what the operation takes, so this is a change in what the operation does rather than a slow machine. Find what it now does that it did not, or say in that file why the bound moved. |
| `tooling.bench.within_ceilings` | Every figure is within its ceiling, as recorded in {path}. |
| `tooling.bench.what.utf8` | load and validate UTF-8 |
| `tooling.bench.what.lex` | lex |
| `tooling.bench.what.parse` | parse |
| `tooling.bench.what.analyse` | analyse |
| `tooling.bench.what.run` | lower and run |
| `tooling.bench.what.highlight` | highlight (per keystroke) |
| `tooling.bench.what.complete` | complete a command prefix |
| `tooling.bench.what.complete_program` | complete a program name |
| `tooling.bench.what.history` | encode a history entry |
| `tooling.bench.what.config` | parse a configuration file |
| `tooling.bench.what.session` | open an engine session |
| `tooling.check.header` | Adash repository check |
| `tooling.check.passed` | {count, plural, =0 {no checks ran} one {# check passed} other {# checks passed}} |
| `tooling.check.failed` | {count, plural, =0 {no failures} one {# check failed} other {# checks failed}} |
| `tooling.check.missing_file` | required file is missing: {path} |
| `tooling.check.missing_directory` | required directory is missing: {path} |
| `tooling.check.catalogued_message_missing` | docs/diagnostics-catalog.md has no row for {key}, and says it is the catalog |
| `tooling.check.catalogued_message_differs` | docs/diagnostics-catalog.md words {key} differently from the catalog |
| `tooling.check.catalogued_message_unknown` | docs/diagnostics-catalog.md has a row for {key}, which the catalog does not have |
| `tooling.check.catalog_key_unused` | the catalog carries {key} and no source names it, so nothing can ever show it |
| `tooling.check.catalog_key_absent` | a tool names {key} and the catalog does not carry it, so a user gets the fallback form |
| `tooling.check.version_unreadable` | the version could not be read from {path}; two files that both read as nothing compare equal, which is how this check passed for years |
| `tooling.check.inventory_unreadable` | repository.toml has a spec entry at character {position} whose path could not be read |
| `tooling.check.version_mismatch` | version disagreement: {first} says {first_value}, {second} says {second_value} |
| `tooling.check.catalog_missing_key` | message identifier {id} names key {key}, which the catalog does not carry |
| `tooling.check.inventory_missing` | repository.toml lists {path}, which does not exist |
| `tooling.check.inventory_unlisted` | {path} exists but repository.toml does not list it, so the package has no recorded owner |
| `tooling.check.catalog_unreadable` | could not read the message catalog at {path} |
| `tooling.check.prose_as_text` | {path} writes a sentence in Ada source: {text} |
| `tooling.check.identifier_as_text` | {path} passes an identifier where a message argument must be text: {text} |
| `tooling.check.pin_not_cloned` | the CI workflow does not check out {name}, which the manifests pin; a pin Alire cannot follow stops the build before anything is checked |
| `tooling.check.silent_truncation` | {path} stops collecting at the end of a fixed-size list without saying so; a construct that does not fit is refused where it is written |
| `tooling.check.escape_sequence` | {path} contains a literal terminal escape sequence; styling belongs to terminal_styles by way of Adash.Terminal |
| `tooling.check.grammar_missing` | the grammar reference has no production naming {name}, which the parser can build |
| `tooling.check.grammar_unknown` | the grammar reference names {name}, which the syntax has no such node for |
| `tooling.check.forbidden_dependency` | {path} depends on {unit}, which Adash may not use directly; see AI.md |
| `tooling.check.result_pass` | PASS |
| `tooling.check.result_fail` | FAIL |

## module

| Identifier | Says |
|---|---|
| `module.looked.as_written` | it names a path, and there is nothing there |
| `module.looked.beside` | nothing of that name beside the script that asked for it |
| `module.looked.in_modules` | nothing of that name beside the script that asked for it, nor in your module directory |

## start

| Identifier | Says |
|---|---|
| `start.reason.host_refused` | the host refused |
| `start.reason.stream_setup` | its streams could not be prepared |

## completion

| Identifier | Says |
|---|---|
| `completion.keyword` | keyword |
| `completion.program` | a program on the search path |
| `completion.path` | file |

## prompt

| Identifier | Says |
|---|---|
| `prompt.primary` | > |
| `prompt.continuation` | ... |
| `prompt.failed` | ! |

## interactive

| Identifier | Says |
|---|---|
| `interactive.line-editing-unavailable` | This terminal does not support line editing; lines are read whole. |
| `interactive.read-failed` | The terminal stopped responding; ending the session. |

## history

| Identifier | Says |
|---|---|
| `history.unreadable` | {path} could not be read; this session starts with no history. |
| `history.damaged-lines` | {path}: {detail} entries could not be read and were skipped. |
| `history.not-written` | {path} could not be written; this session was not recorded. |

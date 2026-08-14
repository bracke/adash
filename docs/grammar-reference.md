# The grammar

What the parser accepts, as productions. Each names the syntax node it builds,
in `Adash.Language.Syntax`, and `adash_check` verifies in both directions that
this document and that enumeration agree — a construct added to the parser
without a production here fails the repository checks.

The notation: `|` alternatives, `[…]` optional, `{…}` zero or more, `'x'` a
literal token. Reserved words are written lower case as Ada writes them; they
are matched case-insensitively, as all names here are.

## A submission

    submission  ::= { declaration | statement }              -- Node_Sequence

A submission is a program. Declarations and statements mix freely, and a
declaration may stand wherever a statement may — which is what lets a task or a
package be written at a prompt.

## Declarations

    declaration ::= object_declaration
                  | type_declaration | subtype_declaration
                  | subprogram_declaration | subprogram_body
                  | package_declaration | package_body
                  | generic_declaration | instantiation
                  | task_declaration | task_body
                  | protected_declaration | protected_body
                  | exception_declaration
                  | use_clause | pragma

    object_declaration ::=
        name ':' [ 'constant' ] type_mark [ '(' actual { ',' actual } ')' ]
                 [ ':=' expression ] ';'                     -- Node_Object_Declaration

    exception_declaration ::= name ':' 'exception' ';'       -- Node_Exception_Declaration

    type_declaration ::=
        'type' name 'is' ( '(' name { ',' name } ')'
                         | 'record' { component } 'end' 'record'
                         | 'array' '(' ( range | name 'range' '<>' )
                           ')' 'of' type_mark ) ';'
                                                             -- Node_Type_Declaration
                                                             -- Node_Record_Declaration
                                                             -- Node_Array_Declaration

`array (Integer range <>)` is the unconstrained form: its middle child is the
index type's name where the constrained form has a `Node_Range`, which is how
the analyser tells them apart without the parser deciding what the text means.
An object of such a type carries its length in the actual list of
`object_declaration` — `X : Line (1 .. 4)` — which is the same production a
task's discriminants use.

    subtype_declaration ::=
        'subtype' name 'is' type_mark [ 'range' range ] ';'  -- Node_Subtype_Declaration

    component ::= name ':' type_mark ';'                     -- Node_Parameter

    use_clause ::= 'use' name ';'                            -- Node_Use
    pragma     ::= 'pragma' name [ '(' argument { ',' argument } ')' ] ';'
                                                             -- Node_Pragma

## Subprograms, packages and generics

    subprogram_declaration ::=
        ( 'procedure' name [ formals ]
        | 'function' name [ formals ] 'return' type_mark ) ';'
                                                             -- Node_Subprogram_Declaration

    subprogram_body ::=
        ( 'procedure' name [ formals ]
        | 'function' name [ formals ] 'return' type_mark )
        'is' { declaration } 'begin' { statement }
        [ 'exception' { handler } ] 'end' [ name ] ';'

    formals ::= '(' formal { ';' formal } ')'
    formal  ::= name { ',' name } ':' [ 'in' ] [ 'out' ] type_mark
                [ ':=' literal ]                             -- Node_Parameter

    package_declaration ::=
        'package' name 'is' { declaration } 'end' [ name ] ';'
                                                             -- Node_Package_Declaration
    package_body ::=
        'package' 'body' name 'is' { declaration }
        [ 'begin' { statement } ] 'end' [ name ] ';'         -- Node_Package_Body

    generic_declaration ::=
        'generic' { generic_formal } subprogram_declaration   -- Node_Generic_Declaration
    generic_formal ::= 'type' name 'is' 'private' ';'         -- Node_Generic_Formal
    instantiation  ::=
        ( 'procedure' | 'function' ) name 'is' 'new' name
        '(' type_mark { ',' type_mark } ')' ';'               -- Node_Instantiation

## Tasks and protected objects

    task_declaration ::=
        'task' [ 'type' ] name [ discriminants ] [ 'is' { entry | pragma }
        'end' [ name ] ] ';'                                 -- Node_Task_Declaration
    task_body ::=
        'task' 'body' name 'is' { declaration } 'begin' { statement }
        [ 'exception' { handler } ] 'end' [ name ] ';'       -- Node_Task_Body

    protected_declaration ::=
        'protected' [ 'type' ] name [ discriminants ] 'is'
        { entry | subprogram_declaration | component | pragma }
        'end' [ name ] ';'                                   -- Node_Protected_Declaration
    protected_body ::=
        'protected' 'body' name 'is'
        { entry_body | subprogram_body | component }
        'end' [ name ] ';'                                   -- Node_Protected_Body

    entry      ::= 'entry' name [ '(' type_mark ')' ] [ formals ] ';'
                                                             -- Node_Entry
    entry_body ::= 'entry' name [ '(' 'for' name 'in' type_mark ')' ]
                   [ formals ] [ 'when' expression ] 'is'
                   { declaration } 'begin' { statement } 'end' [ name ] ';'

    discriminants ::= '(' formal { ';' formal } ')'

## Statements

    statement ::= assignment | procedure_call | if | case
                | loop | while_loop | for_loop | exit | return
                | block | null | raise | delay
                | accept | selective_accept | select | requeue
                | abort | terminate

    assignment     ::= name ':=' expression ';'              -- Node_Assignment
    procedure_call ::= name [ '(' argument { ',' argument } ')' ] ';'
                                                             -- Node_Procedure_Call
    null           ::= 'null' ';'                            -- Node_Null_Statement
    raise          ::= 'raise' [ name ] ';'                  -- Node_Raise
    exit           ::= 'exit' [ 'when' expression ] ';'      -- Node_Exit
    return         ::= 'return' [ expression ] ';'           -- Node_Return
    abort          ::= 'abort' name { ',' name } ';'         -- Node_Abort
    terminate      ::= 'terminate' ';'                       -- Node_Terminate
    delay          ::= 'delay' [ 'until' ] expression ';'    -- Node_Delay
    requeue        ::= 'requeue' name [ '(' expression ')' ]
                       [ 'with' 'abort' ] ';'                -- Node_Requeue

    if   ::= 'if' expression 'then' { statement }
             { 'elsif' expression 'then' { statement } }
             [ 'else' { statement } ] 'end' 'if' ';'         -- Node_If

    case ::= 'case' expression 'is' { alternative } 'end' 'case' ';'
                                                             -- Node_Case
    alternative ::= 'when' choice { '|' choice } '=>' { statement }
                                                             -- Node_Case_Alternative
    choice      ::= expression [ '..' expression ] | 'others'
                                                             -- Node_Range, Node_Others

    loop       ::= 'loop' { statement } 'end' 'loop' ';'     -- Node_Loop
    while_loop ::= 'while' expression loop                   -- Node_While_Loop
    for_loop   ::= 'for' name 'in' [ 'reverse' ]
                   ( expression '..' expression | type_mark | name ''' 'range' )
                   loop                                      -- Node_For_Loop
                                                             -- Node_For_Reverse_Loop

    block   ::= [ 'declare' { declaration } ] 'begin' { statement }
                [ 'exception' { handler } ] 'end' ';'        -- Node_Block
    handler ::= 'when' ( name { '|' name } | 'others' ) '=>' { statement }
                                                             -- Node_Handler

## Selecting and accepting

    accept ::= 'accept' name [ '(' expression ')' ] [ formals ]
               [ 'do' { statement } 'end' [ name ] ] ';'     -- Node_Accept

    selective_accept ::=
        'select' select_alternative { 'or' select_alternative }
        [ 'else' { statement } ] 'end' 'select' ';'          -- Node_Selective_Accept
    select_alternative ::=
        [ 'when' expression '=>' ] ( accept | delay | terminate ) { statement }
                                                             -- Node_Select_Alternative

    select ::= 'select' procedure_call { statement }
               ( 'or' 'delay' expression ';' { statement }
               | 'else' { statement }
               | 'then' 'abort' { statement } )
               'end' 'select' ';'                            -- Node_Select
                                                             -- Node_Then_Abort

Two constructs share the word `select`, and which one is being read is settled
by the first word after it — an `accept` or a `when` begins a task choosing what
to serve, anything else begins a caller deciding how long to wait. That is where
Ada settles it too.

## Expressions

    expression ::= relation { ( 'and' | 'and' 'then' | 'or' | 'or' 'else'
                              | 'xor' ) relation }           -- Node_Binary_Operation
    relation   ::= simple [ ( '=' | '/=' | '<' | '<=' | '>' | '>=' ) simple ]
                 | simple [ 'not' ] 'in'
                   ( simple '..' simple | type_mark
                   | name ''' 'range' )                      -- Node_Membership
    simple     ::= [ '+' | '-' ] term { ( '+' | '-' | '&' ) term }
    term       ::= factor { ( '*' | '/' | 'mod' | 'rem' ) factor }
    factor     ::= primary [ '**' primary ]                  -- Node_Unary_Operation

    primary ::= literal
              | name { '.' name | ''' attribute | '(' arguments ')' }
              | '(' expression ')'                           -- Node_Parenthesized
              | '(' aggregate ')'                            -- Node_Aggregate

    name      ::= identifier                                 -- Node_Name
                | name '.' identifier                        -- Node_Selected
    attribute ::= identifier | 'range'                       -- Node_Attribute
    literal   ::= integer | real | character | string
                                                             -- Node_Integer_Literal
                                                             -- Node_Real_Literal
                                                             -- Node_Character_Literal
                                                             -- Node_String_Literal

    arguments ::= argument { ',' argument }
    argument  ::= [ name '=>' ] expression                   -- Node_Named_Argument
                | expression [ '..' expression ]             -- Node_Range

    aggregate ::= argument { ',' argument }
                | 'others' '=>' expression

`Node_Call` is what `name '(' arguments ')'` builds in an expression — whether it
denotes a call, an array index, an array slice or a part of a String is a
question about what the name means, and the parser records the shape rather than
guessing — the range inside it is a `Node_Range` either way. A `Node_Call`
whose prefix is itself a `Node_Call` can only be the last of those: what a call
yields is a value, and a value is not called. `Node_Sequence` holds every
list of statements or declarations. `Node_None` and `Node_Error` are not written
by any program: the first is the absence of a node, the second is what a failed
parse leaves so that the rest of a submission can still be read.

## Where the grammar is not Ada's

The subset is defined by `language-reference.md`; this document describes what
*parses*. The two differ in one direction only: some things parse and are then
refused by the analyser, with a diagnostic naming what is wrong. `terminate`
outside a select, `raise` outside a handler, a case choice that is not static,
and a named argument to a subprogram that has no such parameter are all of that
kind. Nothing that the analyser accepts fails to parse.

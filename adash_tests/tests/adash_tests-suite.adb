with Adash_Tests.Command_Cases;
with Adash_Tests.Conformance_Cases;
with Adash_Tests.Configuration_Cases;
with Adash_Tests.Engine_Cases;
with Adash_Tests.Evaluation_Cases;
with Adash_Tests.Execution_Cases;
with Adash_Tests.Interactive_Cases;
with Adash_Tests.Language_Cases;
with Adash_Tests.Lexer_Cases;
with Adash_Tests.Pattern_Cases;
with Adash_Tests.Prompt_Cases;
with Adash_Tests.Message_Cases;
with Adash_Tests.Parser_Cases;
with Adash_Tests.Persistence_Cases;
with Adash_Tests.Filesystem_Cases;
with Adash_Tests.Machine_Cases;
with Adash_Tests.Predefined_Cases;
with Adash_Tests.Scripting_Cases;
with Adash_Tests.Semantics_Cases;
with Adash_Tests.Repository_Cases;
with Adash_Tests.Source_Cases;
with Adash_Tests.Terminal_Cases;
with Adash_Tests.Version_Cases;

package body Adash_Tests.Suite is

   Result : aliased AUnit.Test_Suites.Test_Suite;

   Version_Case    : aliased Adash_Tests.Version_Cases.Case_Type;
   Message_Case    : aliased Adash_Tests.Message_Cases.Case_Type;
   Terminal_Case   : aliased Adash_Tests.Terminal_Cases.Case_Type;
   Repository_Case : aliased Adash_Tests.Repository_Cases.Case_Type;
   Execution_Case  : aliased Adash_Tests.Execution_Cases.Case_Type;
   Source_Case     : aliased Adash_Tests.Source_Cases.Case_Type;
   Language_Case   : aliased Adash_Tests.Language_Cases.Case_Type;
   Lexer_Case      : aliased Adash_Tests.Lexer_Cases.Case_Type;
   Pattern_Case    : aliased Adash_Tests.Pattern_Cases.Case_Type;
   Prompt_Case     : aliased Adash_Tests.Prompt_Cases.Case_Type;
   Parser_Case     : aliased Adash_Tests.Parser_Cases.Case_Type;
   Semantics_Case  : aliased Adash_Tests.Semantics_Cases.Case_Type;
   Evaluation_Case : aliased Adash_Tests.Evaluation_Cases.Case_Type;
   Filesystem_Case : aliased Adash_Tests.Filesystem_Cases.Case_Type;
   Machine_Case    : aliased Adash_Tests.Machine_Cases.Case_Type;
   Predefined_Case : aliased Adash_Tests.Predefined_Cases.Case_Type;
   Command_Case    : aliased Adash_Tests.Command_Cases.Case_Type;
   Engine_Case     : aliased Adash_Tests.Engine_Cases.Case_Type;
   Scripting_Case  : aliased Adash_Tests.Scripting_Cases.Case_Type;
   Interactive_Case : aliased Adash_Tests.Interactive_Cases.Case_Type;
   Persistence_Case : aliased Adash_Tests.Persistence_Cases.Case_Type;
   Configuration_Case : aliased Adash_Tests.Configuration_Cases.Case_Type;
   Conformance_Case : aliased Adash_Tests.Conformance_Cases.Case_Type;

   -----------
   -- Suite --
   -----------

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
   begin
      --  Registered in dependency order, lowest first. AUnit does not require
      --  it, but a failure list that reads bottom-up tells you which layer
      --  broke rather than only that something did.
      AUnit.Test_Suites.Add_Test (Result'Access, Version_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Message_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Terminal_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Source_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Persistence_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Configuration_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Language_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Lexer_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Pattern_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Prompt_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Parser_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Semantics_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Evaluation_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Predefined_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Filesystem_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Machine_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Command_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Engine_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Scripting_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Interactive_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Execution_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Repository_Case'Access);

      --  Last, and deliberately: it runs the built binary from the outside,
      --  so a failure here after everything else passed says the parts are
      --  right and the whole is not.
      AUnit.Test_Suites.Add_Test (Result'Access, Conformance_Case'Access);
      return Result'Access;
   end Suite;

end Adash_Tests.Suite;

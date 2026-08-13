with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Adash.Terminal;

with Adash_Tests.Conformance;

--  adash_conformance: does the built shell still behave as it is documented to?
--
--  Thin, like every main in this project. It resolves a root, runs the suite
--  and the examples, prints what came back and turns the failures into an exit
--  status. The suite itself lives in a package so that an AUnit case can run
--  exactly the same code -- a checker reachable only from a main is one nobody
--  runs.
--
--  Run from the adash_tests directory, which is where Alire puts you:
--
--     alr build && ./bin/adash_conformance
--
--  The root defaults to `..` for that reason. The binary under test is
--  `<root>/bin/adash`, so build the shell first: this checks what was built,
--  not what is in the sources.
--
--  Its output is deliberately plain text and not a message catalog lookup. It
--  is a developer tool reporting on the message catalog, and rendering its own
--  report through the thing it is testing would make a broken catalog look
--  like a broken shell.
procedure Adash_Conformance_Main is

   package CLI renames Ada.Command_Line;
   package IO renames Ada.Text_IO;
   package Conf renames Adash_Tests.Conformance;

   use Ada.Strings.Unbounded;
   use type Conf.Verdict;

   Exit_Success : constant := 0;
   Exit_Failure : constant := 1;

   Root : constant String :=
     (if CLI.Argument_Count >= 1 then CLI.Argument (1) else "..");

   Stdout_Is_Terminal : constant Boolean :=
     Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Output);

   Results : Conf.Report;

   procedure Put_Styled (Item : String; Role : Adash.Terminal.Style_Role);

   procedure Put_Styled (Item : String; Role : Adash.Terminal.Style_Role) is
   begin
      IO.Put_Line (Adash.Terminal.Styled (Item, Role, Stdout_Is_Terminal));
   end Put_Styled;

begin
   Conf.Run (Root, Results);
   Conf.Run_Examples (Root, Results);

   for Index in 1 .. Conf.Count (Results) loop
      declare
         Item : constant Conf.Result := Conf.Element (Results, Index);
         Name : constant String := To_String (Item.Identity);
         Note : constant String := To_String (Item.Detail);
      begin
         case Item.Outcome is
            when Conf.Passed =>
               Put_Styled ("pass  " & Name, Adash.Terminal.Role_Success);

            when Conf.Skipped =>
               Put_Styled ("skip  " & Name & "  (" & Note & ")",
                           Adash.Terminal.Role_Muted);

            when Conf.Failed =>
               Put_Styled ("FAIL  " & Name, Adash.Terminal.Role_Error);
               Put_Styled ("      " & Note, Adash.Terminal.Role_Muted);

            when Conf.Malformed =>
               Put_Styled ("BAD   " & Name, Adash.Terminal.Role_Warning);
               Put_Styled ("      " & Note, Adash.Terminal.Role_Muted);
         end case;
      end;
   end loop;

   IO.New_Line;
   Put_Styled
     (Natural'Image (Conf.Count_Of (Results, Conf.Passed)) & " passed,"
      & Natural'Image (Conf.Count_Of (Results, Conf.Failed)) & " failed,"
      & Natural'Image (Conf.Count_Of (Results, Conf.Skipped)) & " skipped,"
      & Natural'Image (Conf.Count_Of (Results, Conf.Malformed)) & " malformed",
      (if Conf.Passed (Results) then Adash.Terminal.Role_Success
       else Adash.Terminal.Role_Error));

   CLI.Set_Exit_Status
     (CLI.Exit_Status
        (if Conf.Passed (Results) then Exit_Success else Exit_Failure));
end Adash_Conformance_Main;

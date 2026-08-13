with Ada.Command_Line;
with Ada.Text_IO;

with Adash.Messages;
with Adash.Messages.Rendering;
with Adash.Terminal;

with Adash_Tests.Repository;

--  adash_check: does the repository still obey its own rules?
--
--  Thin, like every main in this project. It resolves a root, calls
--  Adash_Tests.Repository, renders what came back and turns the count into an
--  exit status. The checks themselves live in a package so that
--  Adash_Tests.Repository_Cases can run exactly the same code -- a checker
--  reachable only from a main is a checker that is never itself tested.
--
--  Run from the adash_tests directory, which is where Alire puts you:
--
--     alr build && ./bin/adash_check
--
--  The root defaults to `..` for that reason. Pass one to check elsewhere.
procedure Adash_Check_Main is

   package CLI renames Ada.Command_Line;
   package IO renames Ada.Text_IO;
   package Msg renames Adash.Messages;
   package Render renames Adash.Messages.Rendering;

   Exit_Success : constant := 0;
   Exit_Failed  : constant := 1;

   Root : constant String :=
     (if CLI.Argument_Count >= 1 then CLI.Argument (1) else "..");

   Catalog : Render.Catalog;
   Report  : Adash_Tests.Repository.Report;

   Stdout_Is_Terminal : constant Boolean :=
     Adash.Terminal.Is_Terminal (Adash.Terminal.Standard_Output);

   procedure Put (Item : String; Role : Adash.Terminal.Style_Role);
   --  Write one styled line to standard output.

   function Count_Image (Value : Natural) return String;
   --  Decimal digits with no leading blank. Natural'Image supplies one for
   --  the sign, and an ICU plural selector reading " 3" does not see a
   --  number -- it falls through to `other` and the message is wrong in
   --  exactly the singular case nobody tests.

   -----------------
   -- Count_Image --
   -----------------

   function Count_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Count_Image;

   ---------
   -- Put --
   ---------

   procedure Put (Item : String; Role : Adash.Terminal.Style_Role) is
   begin
      IO.Put_Line (Adash.Terminal.Styled (Item, Role, Stdout_Is_Terminal));
   end Put;

begin
   Adash.Terminal.Set_Color_Policy (Adash.Terminal.Color_Auto);

   --  The catalog under test is the one in the root being checked, not one
   --  found beside this binary. Checking one repository while rendering from
   --  another is the kind of confusion that makes a green run meaningless.
   Catalog.Open (Catalog_Path => Root & "/resources/messages/catalog.txt");

   Put (Catalog.Text (Msg.Msg_Application_Name) & " -- "
        & Catalog.Text ("tooling.check.header"),
        Adash.Terminal.Role_Header);

   Adash_Tests.Repository.Check (Root, Report);

   for Finding of Report.Findings loop
      Put (Catalog.Text ("tooling.check.result_fail") & "  "
           & Catalog.Text (Adash_Tests.Repository.Key (Finding),
                           Adash_Tests.Repository.Arguments (Finding)),
           Adash.Terminal.Role_Error);
   end loop;

   IO.New_Line;

   Put (Catalog.Text
          ("tooling.check.passed",
           [1 => Msg.Named
                   ("count",
                    Count_Image
                      (Report.Checks_Run
                       - Adash_Tests.Repository.Failure_Count (Report)))]),
        Adash.Terminal.Role_Muted);

   if Adash_Tests.Repository.Passed (Report) then
      Put (Catalog.Text ("tooling.check.result_pass"), Adash.Terminal.Role_Success);
      Catalog.Close;
      CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Success));
   else
      Put (Catalog.Text
             ("tooling.check.failed",
              [1 => Msg.Named
                      ("count",
                       Count_Image
                         (Adash_Tests.Repository.Failure_Count (Report)))]),
           Adash.Terminal.Role_Error);
      Catalog.Close;
      CLI.Set_Exit_Status (CLI.Exit_Status (Exit_Failed));
   end if;
end Adash_Check_Main;

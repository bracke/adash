with AUnit.Assertions;

with Adash.Terminal;

package body Adash_Tests.Terminal_Cases is

   use AUnit.Assertions;

   package Term renames Adash.Terminal;

   use type Term.Color_Policy;
   use type Term.Style_Role;

   Sample : constant String := "the quick brown fox";

   procedure Policy_Round_Trips (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Never_Emits_Nothing (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Non_Terminal_Emits_Nothing (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Plain_Is_Never_Decorated (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Always_Decorates_Every_Other_Role
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   --------------------------
   -- Policy_Round_Trips --
   --------------------------

   procedure Policy_Round_Trips (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
   begin
      for Policy in Term.Color_Policy loop
         Term.Set_Color_Policy (Policy);
         Assert (Term.Current_Color_Policy = Policy,
                 "colour policy did not round-trip: "
                 & Term.Color_Policy'Image (Policy));
      end loop;

      Term.Set_Color_Policy (Term.Color_Auto);
   end Policy_Round_Trips;

   ----------------------------
   -- Never_Emits_Nothing --
   ----------------------------

   procedure Never_Emits_Nothing (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
   begin
      Term.Set_Color_Policy (Term.Color_Never);

      --  Every role, including with the destination claiming to be a
      --  terminal. Color_Never has to win over that, or NO_COLOR and a user's
      --  configured preference mean nothing.
      for Role in Term.Style_Role loop
         Assert (Term.Styled (Sample, Role, Destination_Is_Terminal => True) = Sample,
                 "Color_Never decorated " & Term.Style_Role'Image (Role));
      end loop;

      Assert (not Term.Color_Enabled (Destination_Is_Terminal => True),
              "Color_Never reported colour as enabled");

      Term.Set_Color_Policy (Term.Color_Auto);
   end Never_Emits_Nothing;

   ------------------------------------
   -- Non_Terminal_Emits_Nothing --
   ------------------------------------

   procedure Non_Terminal_Emits_Nothing (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
   begin
      Term.Set_Color_Policy (Term.Color_Auto);

      --  This is the case that matters for a shell: output going down a pipe
      --  into another program. Bytes out must equal bytes in.
      for Role in Term.Style_Role loop
         Assert (Term.Styled (Sample, Role, Destination_Is_Terminal => False) = Sample,
                 "output to a non-terminal was decorated for "
                 & Term.Style_Role'Image (Role));
      end loop;
   end Non_Terminal_Emits_Nothing;

   --------------------------------
   -- Plain_Is_Never_Decorated --
   --------------------------------

   procedure Plain_Is_Never_Decorated (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
   begin
      --  Role_Plain means no decoration at all, not "the default colour".
      --  Under Color_Always everything else gains bytes; this must not.
      Term.Set_Color_Policy (Term.Color_Always);

      Assert (Term.Styled (Sample, Term.Role_Plain, Destination_Is_Terminal => True) = Sample,
              "Role_Plain was decorated under Color_Always");
      Assert (Term.Styled (Sample, Term.Role_Plain, Destination_Is_Terminal => False) = Sample,
              "Role_Plain was decorated for a non-terminal");

      Term.Set_Color_Policy (Term.Color_Auto);
   end Plain_Is_Never_Decorated;

   ------------------------------------------
   -- Always_Decorates_Every_Other_Role --
   ------------------------------------------

   procedure Always_Decorates_Every_Other_Role
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Term.Set_Color_Policy (Term.Color_Always);

      --  The complement of the tests above: if styling never happened, they
      --  would all pass and mean nothing. Length rather than content, because
      --  the escape bytes belong to terminal_styles and this is not the place
      --  that decides what they are.
      for Role in Term.Style_Role loop
         if Role /= Term.Role_Plain then
            Assert (Term.Styled (Sample, Role, Destination_Is_Terminal => True)'Length
                    > Sample'Length,
                    "Color_Always did not decorate " & Term.Style_Role'Image (Role));
         end if;
      end loop;

      Term.Set_Color_Policy (Term.Color_Auto);
   end Always_Decorates_Every_Other_Role;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Adash.Terminal");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Policy_Round_Trips'Access, "colour policy round-trips");
      Register_Routine (T, Never_Emits_Nothing'Access, "Color_Never emits no escapes");
      Register_Routine (T, Non_Terminal_Emits_Nothing'Access,
                        "a non-terminal destination gets plain bytes");
      Register_Routine (T, Plain_Is_Never_Decorated'Access, "Role_Plain is never decorated");
      Register_Routine (T, Always_Decorates_Every_Other_Role'Access,
                        "Color_Always decorates every other role");
   end Register_Tests;

end Adash_Tests.Terminal_Cases;

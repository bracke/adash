with Hostkit.Host;
with Terminal_Styles;

package body Adash.Terminal is

   --  Adash's roles are not terminal_styles' roles, and are not required to
   --  stay in step with them: this table is the whole of the mapping, and the
   --  place to change how Adash looks.
   function To_Underlying (Role : Style_Role) return Terminal_Styles.Style_Role;

   -------------------
   -- To_Underlying --
   -------------------

   function To_Underlying (Role : Style_Role) return Terminal_Styles.Style_Role is
   begin
      case Role is
         when Role_Plain   => return Terminal_Styles.Role_Info;
         when Role_Header  => return Terminal_Styles.Role_Header;
         when Role_Info    => return Terminal_Styles.Role_Info;
         when Role_Success => return Terminal_Styles.Role_Success;
         when Role_Warning => return Terminal_Styles.Role_Warning;
         when Role_Error   => return Terminal_Styles.Role_Error;
         when Role_Muted   => return Terminal_Styles.Role_Muted;

         --  The syntax roles map onto the same six semantic roles rather than
         --  onto colours: terminal_styles owns what a role looks like, and a
         --  highlighter that picked colours would be deciding for it.
         when Role_Keyword    => return Terminal_Styles.Role_Header;
         when Role_Literal    => return Terminal_Styles.Role_Success;
         when Role_Comment    => return Terminal_Styles.Role_Muted;
         when Role_Known_Name => return Terminal_Styles.Role_Info;
         when Role_Operator   => return Terminal_Styles.Role_Muted;
      end case;
   end To_Underlying;

   ----------------------
   -- Set_Color_Policy --
   ----------------------

   procedure Set_Color_Policy (Policy : Color_Policy) is
   begin
      case Policy is
         when Color_Auto =>
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Auto);
         when Color_Always =>
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Always);
         when Color_Never =>
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      end case;
   end Set_Color_Policy;

   --------------------------
   -- Current_Color_Policy --
   --------------------------

   function Current_Color_Policy return Color_Policy is
   begin
      --  Read back from terminal_styles rather than from a copy kept here.
      --  A cached copy is a second source of truth, and the two disagree the
      --  first time anything else in the process sets the policy.
      case Terminal_Styles.Current_Color_Policy is
         when Terminal_Styles.Color_Auto   => return Color_Auto;
         when Terminal_Styles.Color_Always => return Color_Always;
         when Terminal_Styles.Color_Never  => return Color_Never;
      end case;
   end Current_Color_Policy;

   -------------------
   -- Color_Enabled --
   -------------------

   function Color_Enabled (Destination_Is_Terminal : Boolean) return Boolean is
   begin
      return Terminal_Styles.Color_Enabled (Destination_Is_Terminal);
   end Color_Enabled;

   ------------
   -- Styled --
   ------------

   function Styled
     (Item                    : String;
      Role                    : Style_Role;
      Destination_Is_Terminal : Boolean) return String
   is
   begin
      --  Role_Plain is not "the default colour"; it is "no decoration at
      --  all". Passing it through the table would wrap ordinary output in
      --  escape sequences that do nothing, which shows up as stray bytes in
      --  anything comparing output byte for byte.
      if Role = Role_Plain then
         return Item;
      end if;

      return Terminal_Styles.Decorate (Item, To_Underlying (Role), Destination_Is_Terminal);
   end Styled;

   -----------------
   -- Is_Terminal --
   -----------------

   function Is_Terminal (Stream : Stream_Kind) return Boolean is
   begin
      case Stream is
         when Standard_Input =>
            return Hostkit.Host.Is_Terminal (Hostkit.Host.Standard_Input);
         when Standard_Output =>
            return Hostkit.Host.Is_Terminal (Hostkit.Host.Standard_Output);
         when Standard_Error =>
            return Hostkit.Host.Is_Terminal (Hostkit.Host.Standard_Error);
      end case;
   end Is_Terminal;

end Adash.Terminal;

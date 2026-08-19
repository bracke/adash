with Hostkit.Descriptors;

with Adash.Filesystem;
with Adash.Messages;

package body Adash.Execution.Redirection is

   use Ada.Strings.Unbounded;
   use type Adash.Execution.Streams.Stream_Role;

   package D renames Hostkit.Descriptors;
   package S renames Adash.Execution.Streams;

   function Open_Mode_For (Kind : Redirection_Kind) return D.Open_Mode
   is (case Kind is
          when Redirect_From_File   => D.Open_Read,
          when Redirect_To_File     => D.Open_Write_Truncate,
          when Redirect_Append_File => D.Open_Write_Append,
          when Redirect_To_New_File => D.Open_Write_Exclusive,

          --  Never asked: a joined stream opens nothing. The mode is here so
          --  that the case is complete rather than because anybody uses it.
          when Redirect_Join_Output => D.Open_Read);

   ---------
   -- Add --
   ---------

   function Add
     (Item         : in out Plan;
      Entry_To_Add : Redirection;
      Error        : out Adash.Errors.Error_Info) return Boolean
   is
   begin
      Error := Adash.Errors.Success;

      for Index in 1 .. Item.Count loop
         if Item.Entries (Index).Role = Entry_To_Add.Role then
            --  Two redirections on one stream. Refused rather than resolved:
            --  picking one would silently not write the file that lost, and
            --  the user finds that out later, from its absence.
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Redirection_Conflict,
               [1 => Adash.Messages.Named ("stream", S.Name (Entry_To_Add.Role))]);
            return False;
         end if;
      end loop;

      if Item.Count = Max_Redirections then
         --  Unreachable while there are three roles and duplicates are
         --  refused above, which is why this is a conflict rather than a
         --  capacity error: if it ever fires, two entries share a role.
         Error := Adash.Errors.Failure
           (Adash.Errors.Error_Redirection_Conflict,
            [1 => Adash.Messages.Named ("stream", S.Name (Entry_To_Add.Role))]);
         return False;
      end if;

      Item.Count := Item.Count + 1;
      Item.Entries (Item.Count) := Entry_To_Add;
      return True;
   end Add;

   ------------
   -- Length --
   ------------

   function Length (Item : Plan) return Natural is
   begin
      return Item.Count;
   end Length;

   -----------
   -- Apply --
   -----------

   function Apply
     (Item   : Plan;
      Target : in out Adash.Execution.Commands.Invocation;
      Error  : out Adash.Errors.Error_Info) return Boolean
   is
      --  Opened here first, and only attached to the invocation once every one
      --  of them succeeded. Attaching as we go would leave a half-redirected
      --  invocation behind on failure, and the caller could not tell which
      --  streams were already the shell's own.
      Opened : array (1 .. Max_Redirections) of S.Endpoint;
      Ready  : Natural := 0;

      procedure Unwind;

      procedure Unwind is
      begin
         for Index in 1 .. Ready loop
            S.Release (Opened (Index));
         end loop;
      end Unwind;

   begin
      Error := Adash.Errors.Success;

      for Index in 1 .. Item.Count loop
         declare
            Current : constant Redirection := Item.Entries (Index);
            --  Expanded here, where the file is opened, so `run_into
            --  ("~/log.txt", ...)` writes where a user meant. The plan holds
            --  the path as it was written, which is what a diagnostic quotes
            --  back: naming the expansion in an error about a file the user
            --  called `~/log.txt` would be answering a question nobody asked.
            Path    : constant String :=
              Adash.Filesystem.Expanded (To_String (Current.Path));
            Handle  : D.Descriptor;
         begin
            if Current.Kind = Redirect_Join_Output then
               --  Nothing to open: this one follows whatever the output
               --  redirection opened, and the loop below hands it a copy.
               Ready := Ready + 1;
               Opened (Ready) := S.Inherited (S.Role_Error);
               goto Continue;
            end if;

            if not D.Open_File (Path, Open_Mode_For (Current.Kind), Handle) then
               Error := Adash.Errors.Failure
                 (Adash.Errors.Error_Redirection_Open_Failed,
                  [1 => Adash.Messages.Named ("path", Path)]);
               Unwind;
               return False;
            end if;

            Ready := Ready + 1;
            Opened (Ready) := S.Owned (Handle);

            <<Continue>>
         end;
      end loop;

      --  Every file is open; now the invocation can be changed. Whatever was on
      --  a stream before is released first -- if a caller applied two plans, the
      --  first plan's descriptors would otherwise leak.
      --  Everything that opens a file first, and the stream that follows one
      --  afterwards. A plan holds its redirections in the order they were
      --  added, and a join added before the output redirection it follows
      --  would otherwise copy whatever the stream was before -- which is the
      --  shell's own terminal, and looks exactly like the join not happening.
      for Index in 1 .. Item.Count loop
         if Item.Entries (Index).Kind /= Redirect_Join_Output then
            case Item.Entries (Index).Role is
               when S.Role_Input =>
                  S.Release (Target.Input);
                  Target.Input := Opened (Index);
               when S.Role_Output =>
                  S.Release (Target.Output);
                  Target.Output := Opened (Index);
               when S.Role_Error =>
                  S.Release (Target.Error_Output);
                  Target.Error_Output := Opened (Index);
            end case;
         end if;
      end loop;

      for Index in 1 .. Item.Count loop
         if Item.Entries (Index).Kind = Redirect_Join_Output then
            S.Release (Target.Error_Output);

            --  A copy of the descriptor output is going to, so that closing
            --  one does not take the other with it. One file, one position,
            --  and the two streams in the order the program wrote them.
            Target.Error_Output :=
              S.Owned (D.Duplicate (S.Handle (Target.Output)));
         end if;
      end loop;

      return True;
   end Apply;

end Adash.Execution.Redirection;

package body Adash.Interactive.Notifications is

   ----------
   -- Post --
   ----------

   procedure Post
     (Item      : in out Queue;
      Kind      : Notice_Kind;
      Message   : Adash.Messages.Message_Id;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Role      : Adash.Terminal.Style_Role := Adash.Terminal.Role_Info)
   is
      Fresh : Notice;
   begin
      Fresh.Kind := Kind;
      Fresh.Message := Message;
      Fresh.Role := Role;
      Fresh.Count := Natural'Min (Arguments'Length, Fresh.Arguments'Length);

      for Index in 1 .. Fresh.Count loop
         Fresh.Arguments (Index) := Arguments (Arguments'First + Index - 1);
      end loop;

      if Natural (Item.Items.Length) >= Max_Pending then
         --  Full. Drop the oldest notice that is *not* a job change: the user
         --  asked for the job and is owed the news, whereas an advisory that
         --  has already been superseded by sixty-three others is not worth the
         --  line it would take.
         declare
            Dropped : Boolean := False;
         begin
            for Index in 1 .. Natural (Item.Items.Length) loop
               if Item.Items.Element (Index).Kind /= Job_Change then
                  Item.Items.Delete (Index);
                  Dropped := True;
                  exit;
               end if;
            end loop;

            --  All of them are job changes. Then the oldest goes, because the
            --  alternative is refusing the newest -- and the newest is the one
            --  describing the state a job is actually in now.
            if not Dropped then
               Item.Items.Delete_First;
            end if;
         end;
      end if;

      Item.Items.Append (Fresh);
   end Post;

   -------------
   -- Pending --
   -------------

   function Pending (Item : Queue) return Natural is
   begin
      return Natural (Item.Items.Length);
   end Pending;

   -----------
   -- Ready --
   -----------

   function Ready (Item : Queue; Editing : Boolean) return Boolean is
   begin
      return not Editing and then not Item.Items.Is_Empty;
   end Ready;

   ----------
   -- Take --
   ----------

   function Take (Item : in out Queue; Into : out Notice) return Boolean is
   begin
      if Item.Items.Is_Empty then
         Into := (others => <>);
         return False;
      end if;

      Into := Item.Items.First_Element;
      Item.Items.Delete_First;
      return True;
   end Take;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Queue) is
   begin
      Item.Items.Clear;
   end Clear;

end Adash.Interactive.Notifications;

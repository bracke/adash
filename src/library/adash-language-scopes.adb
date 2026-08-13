with Adash.Language.Types;
with Adash.Messages;

package body Adash.Language.Scopes is

   procedure Ensure_Started (Item : in out Chain);
   --  Open the outermost scope on first use.

   function Level_Count (Item : Chain) return Natural
   is (Natural (Item.Levels.Length));

   -------------------
   -- Ensure_Started --
   -------------------

   procedure Ensure_Started (Item : in out Chain) is
   begin
      if Item.Started then
         return;
      end if;

      --  Lazily, so that a default-initialized Chain is usable without a
      --  separate call the caller has to remember. A chain that had to be
      --  opened before use would be one more thing to get wrong at every site.
      Item.Levels.Append (Scope'(First => 1, Last => 0));
      Item.Started := True;
   end Ensure_Started;

   -----------
   -- Depth --
   -----------

   function Depth (Item : Chain) return Positive is
   begin
      if not Item.Started then
         return 1;
      end if;

      return Positive (Level_Count (Item));
   end Depth;

   -----------
   -- Enter --
   -----------

   procedure Enter (Item : in out Chain) is
   begin
      Ensure_Started (Item);
      Item.Levels.Append
        (Scope'(First => Natural (Item.Entries.Length) + 1,
                Last  => Natural (Item.Entries.Length)));
   end Enter;

   -----------
   -- Leave --
   -----------

   procedure Leave (Item : in out Chain) is
   begin
      Ensure_Started (Item);

      --  The outermost scope is never closed. A chain always has one, which is
      --  what lets every lookup assume there is somewhere to look.
      if Level_Count (Item) <= 1 then
         return;
      end if;

      declare
         Innermost : constant Scope := Item.Levels.Last_Element;
      begin
         --  Truncation rather than a walk: the scope's symbols are the tail of
         --  the vector, because a nested scope can only have been entered after
         --  everything enclosing it was declared.
         while Natural (Item.Entries.Length) >= Innermost.First
           and then not Item.Entries.Is_Empty
         loop
            Item.Entries.Delete_Last;
         end loop;

         Item.Levels.Delete_Last;
      end;
   end Leave;

   ----------------------
   -- Declare_Symbol --
   ----------------------

   function Declare_Symbol
     (Item         : in out Chain;
      Entry_To_Add : Symbols.Symbol;
      Error        : out Adash.Errors.Error_Info) return Boolean
   is
   begin
      Ensure_Started (Item);
      Error := Adash.Errors.Success;

      declare
         Existing : constant Symbols.Symbol :=
           Lookup_Local (Item, Symbols.Name (Entry_To_Add));

         --  A second subprogram of the same name is an overload, and legal, as
         --  long as a call could tell the two apart. Anything else -- a second
         --  variable, or a subprogram over a variable -- is a redeclaration
         --  whatever its shape, because only subprograms overload.
         Overloadable : constant Boolean :=
           (Symbols.Is_Callable (Entry_To_Add)
              and then Symbols.Is_Callable (Existing)
              and then not Symbols.Same_Profile (Existing, Entry_To_Add))

           --  The other overload Ada has. An enumeration literal is a
           --  parameterless function returning its own type, so two types may
           --  each name a Red and a use of the name is settled by what the
           --  context expects -- the same rule, applied to the same shape.
           --
           --  Two of one type is still a redeclaration: `type T is (Red,
           --  Red)` names one value twice, and nothing could tell them apart.
           --  Neither may shadow a name the shell provides, which is the rule
           --  for everything at submission level.
           or else (Symbols."=" (Symbols.Kind (Entry_To_Add),
                                  Symbols.Symbol_Literal)
                    and then Symbols."=" (Symbols.Kind (Existing),
                                          Symbols.Symbol_Literal)
                    and then not Symbols.Is_Provided (Existing)
                    and then Adash.Language.Types."/="
                               (Symbols.Of_Type (Entry_To_Add),
                                Symbols.Of_Type (Existing)));
      begin
         if not Symbols.Is_Nothing (Existing) and then not Overloadable then
            --  Refused, not replaced. A second declaration of one name in one
            --  scope is almost always a typo or a paste, and replacing the
            --  first silently makes the program mean something nobody wrote.
            if Symbols.Is_Provided (Existing) then
               --  Nothing declared this one, so there is no line to send the
               --  reader to. It used to be told "already declared, on line 1",
               --  which named a line that had nothing to do with it and, in a
               --  one-line submission, was the line being complained about.
               Error := Adash.Errors.Failure
                 (Adash.Errors.Error_Name_Is_Predefined,
                  [1 => Adash.Messages.Named
                          ("name", Symbols.Name (Entry_To_Add))]);
               return False;
            end if;

            --  The position of the first declaration goes into the failure:
            --  "already declared" is only actionable if the user is told where.
            Error := Adash.Errors.Failure
              (Adash.Errors.Error_Name_Already_Declared,
               [Adash.Messages.Named ("name", Symbols.Name (Entry_To_Add)),
                Adash.Messages.Named
                  ("line", Natural'Image (Symbols.Extent (Existing).First))]);
            return False;
         end if;
      end;

      Item.Entries.Append (Entry_To_Add);

      declare
         Innermost : Scope := Item.Levels.Last_Element;
      begin
         Innermost.Last := Natural (Item.Entries.Length);
         Item.Levels.Replace_Element (Level_Count (Item), Innermost);
      end;

      return True;
   end Declare_Symbol;

   --------------------
   -- Lookup_Local --
   --------------------

   function Lookup_Local (Item : Chain; Name : String) return Symbols.Symbol is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      if not Item.Started or else Item.Levels.Is_Empty then
         return Symbols.Nothing;
      end if;

      declare
         Innermost : constant Scope := Item.Levels.Last_Element;
      begin
         --  Backwards, so that the most recent declaration of a name wins if
         --  one ever gets in. Declare_Symbol prevents that, but a lookup that
         --  depended on it would be relying on another package's check.
         for Index in reverse Innermost.First .. Innermost.Last loop
            if Symbols.Key (Item.Entries.Element (Index)) = Wanted then
               return Item.Entries.Element (Index);
            end if;
         end loop;
      end;

      return Symbols.Nothing;
   end Lookup_Local;

   ------------
   -- Lookup --
   ------------

   ----------------
   -- Candidates --
   ----------------

   procedure Candidates
     (Item  : Chain;
      Name  : String;
      Found : out Symbol_List;
      Count : out Natural)
   is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      Found := [others => Symbols.Nothing];
      Count := 0;

      if not Item.Started then
         return;
      end if;

      for Level in reverse 1 .. Level_Count (Item) loop
         declare
            Current : constant Scope := Item.Levels.Element (Level);
         begin
            for Index in reverse Current.First .. Current.Last loop
               declare
                  Candidate : constant Symbols.Symbol :=
                    Item.Entries.Element (Index);
                  Hidden : Boolean := False;
               begin
                  if Symbols.Key (Candidate) = Wanted then
                     if not Symbols.Is_Callable (Candidate)
                       and then Symbols."/=" (Symbols.Kind (Candidate),
                                              Symbols.Symbol_Literal)
                     then
                        --  A variable, a constant or a type name. It hides
                        --  every subprogram of the same name outright, so
                        --  there is nothing to choose between and the answer
                        --  is this one alone.
                        --
                        --  An enumeration literal is not one of those: it
                        --  overloads like the parameterless function it is,
                        --  so it is collected rather than answered with.
                        if Count = 0 then
                           Count := 1;
                           Found (1) := Candidate;
                        end if;

                        return;
                     end if;

                     for Taken in 1 .. Count loop
                        if Symbols.Same_Profile (Found (Taken), Candidate) then
                           --  An inner declaration of the same profile already
                           --  took this call's meaning.
                           Hidden := True;
                        end if;
                     end loop;

                     if not Hidden and then Count < Max_Overloads then
                        Count := Count + 1;
                        Found (Count) := Candidate;
                     end if;
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Candidates;

   function Lookup (Item : Chain; Name : String) return Symbols.Symbol is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      if not Item.Started then
         return Symbols.Nothing;
      end if;

      --  Outwards from the innermost scope, so an inner declaration hides an
      --  outer one for as long as its scope lasts.
      for Level in reverse 1 .. Level_Count (Item) loop
         declare
            Current : constant Scope := Item.Levels.Element (Level);
         begin
            for Index in reverse Current.First .. Current.Last loop
               if Symbols.Key (Item.Entries.Element (Index)) = Wanted then
                  return Item.Entries.Element (Index);
               end if;
            end loop;
         end;
      end loop;

      return Symbols.Nothing;
   end Lookup;

   -----------------
   -- Is_Visible --
   -----------------

   function Is_Visible (Item : Chain; Name : String) return Boolean is
   begin
      return not Symbols.Is_Nothing (Lookup (Item, Name));
   end Is_Visible;

   ------------------
   -- Would_Hide --
   ------------------

   function Would_Hide (Item : Chain; Name : String) return Boolean is
      Wanted : constant String := Symbols.Fold (Name);
   begin
      if not Item.Started or else Level_Count (Item) <= 1 then
         return False;
      end if;

      --  Every scope but the innermost. Declaring a name the innermost scope
      --  already has is a duplicate, which is an error rather than hiding, and
      --  Declare_Symbol reports that instead.
      for Level in reverse 1 .. Level_Count (Item) - 1 loop
         declare
            Current : constant Scope := Item.Levels.Element (Level);
         begin
            for Index in Current.First .. Current.Last loop
               if Symbols.Key (Item.Entries.Element (Index)) = Wanted then
                  return True;
               end if;
            end loop;
         end;
      end loop;

      return False;
   end Would_Hide;

   -------------------
   -- Local_Count --
   -------------------

   function Local_Count (Item : Chain) return Natural is
   begin
      if not Item.Started or else Item.Levels.Is_Empty then
         return 0;
      end if;

      declare
         Innermost : constant Scope := Item.Levels.Last_Element;
      begin
         if Innermost.Last < Innermost.First then
            return 0;
         end if;

         return Innermost.Last - Innermost.First + 1;
      end;
   end Local_Count;

end Adash.Language.Scopes;

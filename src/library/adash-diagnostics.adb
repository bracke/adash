with Adash.Display_Width;

package body Adash.Diagnostics is

   use type Adash.Messages.Message_Id;

   function Precedes (Left, Right : Diagnostic) return Boolean;
   --  The canonical order documented for Sort.

   ---------------
   -- Precedes --
   ---------------

   function Precedes (Left, Right : Diagnostic) return Boolean is
      Left_Name  : constant String := Adash.Source.Name (Left.Origin);
      Right_Name : constant String := Adash.Source.Name (Right.Origin);
   begin
      --  Source name first, so a run over several files groups by file rather
      --  than interleaving them by position.
      if Left_Name /= Right_Name then
         return Left_Name < Right_Name;
      end if;

      if Left.Extent.First /= Right.Extent.First then
         return Left.Extent.First < Right.Extent.First;
      end if;

      --  Worst first at one position: an error and a note about the same token
      --  should lead with the error.
      if Left.Level /= Right.Level then
         return Left.Level > Right.Level;
      end if;

      if Left.Message /= Right.Message then
         return Adash.Messages.Message_Id'Pos (Left.Message)
           < Adash.Messages.Message_Id'Pos (Right.Message);
      end if;

      --  Insertion order last, which is what makes the sort stable without the
      --  algorithm having to be.
      return Left.Sequence < Right.Sequence;
   end Precedes;

   ----------
   -- Make --
   ----------

   function Make
     (Message   : Adash.Messages.Message_Id;
      Level     : Severity;
      Of_Kind   : Category;
      Raised_By : Owner;
      Origin    : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent    : Adash.Source.Span := Adash.Source.Nowhere;
      Arguments : Adash.Messages.Argument_List := Adash.Messages.No_Arguments;
      Guidance  : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Quoted    : Adash.Messages.Message_Id := Adash.Messages.Msg_Error_None;
      Fills     : String := "";
      Quoted_Arguments : Adash.Messages.Argument_List :=
        Adash.Messages.No_Arguments)
      return Diagnostic
   is
      Result : Diagnostic;
   begin
      Result.Message   := Message;
      Result.Level     := Level;
      Result.Of_Kind   := Of_Kind;
      Result.Raised_By := Raised_By;
      Result.Origin    := Origin;
      Result.Extent    := Extent;
      Result.Guidance  := Guidance;

      --  Guidance that repeats the message is not guidance. Saying so here
      --  means a renderer does not have to compare them and decide.
      Result.Has_Guidance :=
        Guidance /= Adash.Messages.Msg_Error_None and then Guidance /= Message;

      Result.Argument_Count := Natural'Min (Arguments'Length, Max_Arguments);

      for Index in 1 .. Result.Argument_Count loop
         Result.Arguments (Index) := Arguments (Arguments'First + Index - 1);
      end loop;

      Result.Detail := Quoted;
      Result.Fills  := Adash.Messages.To_Placeholder (Fills);
      Result.Detail_Count :=
        Natural'Min (Quoted_Arguments'Length, Max_Arguments);

      for Index in 1 .. Result.Detail_Count loop
         Result.Detail_Args (Index) :=
           Quoted_Arguments (Quoted_Arguments'First + Index - 1);
      end loop;

      return Result;
   end Make;

   -----------------
   -- From_Error --
   -----------------

   function From_Error
     (Failure   : Adash.Errors.Error_Info;
      Level     : Severity := Severity_Error;
      Of_Kind   : Category := Category_Execution;
      Raised_By : Owner := Owner_Execution;
      Origin    : Adash.Source.Origin := Adash.Source.Unknown_Origin;
      Extent    : Adash.Source.Span := Adash.Source.Nowhere)
      return Diagnostic
   is
   begin
      --  The code's own message and its arguments come across unchanged. A
      --  second table here would be a second thing to keep in step, and the two
      --  would disagree about one code for a release.
      return Result : Diagnostic :=
        Make
          (Message   => Adash.Errors.Message (Failure.Code),
           Level     => Level,
           Of_Kind   => Of_Kind,
           Raised_By => Raised_By,
           Origin    => Origin,
           Extent    => Extent,
           Arguments => Adash.Errors.Arguments (Failure))
      do
         --  And what it quotes, for the same reason: a failure that names a
         --  message and a diagnostic that dropped it would render the
         --  placeholder unfilled.
         Result.Detail := Failure.Detail;
         Result.Fills  := Failure.Fills;
      end return;
   end From_Error;

   -------------------
   -- Add_Related --
   -------------------

   procedure Add_Related (Item : in out Diagnostic; Location : Related_Location) is
   begin
      if Item.Related_Count = Max_Related then
         --  Dropped rather than refused. A diagnostic with five related places
         --  is already more than a user will read, and losing the fifth beats
         --  losing the diagnostic.
         return;
      end if;

      Item.Related_Count := Item.Related_Count + 1;
      Item.Related (Item.Related_Count) := Location;
   end Add_Related;

   -------------
   -- Message --
   -------------

   function Message (Item : Diagnostic) return Adash.Messages.Message_Id is
   begin
      return Item.Message;
   end Message;

   -----------
   -- Level --
   -----------

   function Level (Item : Diagnostic) return Severity is
   begin
      return Item.Level;
   end Level;

   -------------
   -- Of_Kind --
   -------------

   function Of_Kind (Item : Diagnostic) return Category is
   begin
      return Item.Of_Kind;
   end Of_Kind;

   ---------------
   -- Raised_By --
   ---------------

   function Raised_By (Item : Diagnostic) return Owner is
   begin
      return Item.Raised_By;
   end Raised_By;

   ------------
   -- Origin --
   ------------

   function Origin (Item : Diagnostic) return Adash.Source.Origin is
   begin
      return Item.Origin;
   end Origin;

   ------------
   -- Extent --
   ------------

   function Extent (Item : Diagnostic) return Adash.Source.Span is
   begin
      return Item.Extent;
   end Extent;

   ---------------
   -- Arguments --
   ---------------

   function Arguments (Item : Diagnostic) return Adash.Messages.Argument_List is
   begin
      return Item.Arguments (1 .. Item.Argument_Count);
   end Arguments;

   ------------
   -- Detail --
   ------------

   function Detail (Item : Diagnostic) return Adash.Messages.Message_Id is
   begin
      return Item.Detail;
   end Detail;

   -------------------------
   -- Detail_Placeholder --
   -------------------------

   function Detail_Placeholder (Item : Diagnostic) return String is
   begin
      return Adash.Messages.From_Placeholder (Item.Fills);
   end Detail_Placeholder;

   -----------------------
   -- Detail_Arguments --
   -----------------------

   function Detail_Arguments
     (Item : Diagnostic) return Adash.Messages.Argument_List is
   begin
      return Item.Detail_Args
        (Item.Detail_Args'First
         .. Item.Detail_Args'First + Item.Detail_Count - 1);
   end Detail_Arguments;

   -------------------
   -- Has_Guidance --
   -------------------

   function Has_Guidance (Item : Diagnostic) return Boolean is
   begin
      return Item.Has_Guidance;
   end Has_Guidance;

   --------------
   -- Guidance --
   --------------

   function Guidance (Item : Diagnostic) return Adash.Messages.Message_Id is
   begin
      return Item.Guidance;
   end Guidance;

   --------------------
   -- Related_Count --
   --------------------

   function Related_Count (Item : Diagnostic) return Natural is
   begin
      return Item.Related_Count;
   end Related_Count;

   -------------
   -- Related --
   -------------

   function Related (Item : Diagnostic; Index : Positive) return Related_Location is
   begin
      return Item.Related (Index);
   end Related;

   ----------
   -- Emit --
   ----------

   procedure Emit (Item : in out List; Entry_To_Add : Diagnostic) is
      Recorded : Diagnostic := Entry_To_Add;
   begin
      Item.Emitted := Item.Emitted + 1;
      Recorded.Sequence := Item.Emitted;
      Item.Entries.Append (Recorded);
   end Emit;

   -----------
   -- Count --
   -----------

   function Count (Item : List) return Natural is
   begin
      return Natural (Item.Entries.Length);
   end Count;

   -------------
   -- Element --
   -------------

   function Element (Item : List; Index : Positive) return Diagnostic is
   begin
      return Item.Entries.Element (Index);
   end Element;

   ------------------
   -- Quoted_Line --
   ------------------

   function Quoted_Line (Item : Diagnostic) return String is
   begin
      return Ada.Strings.Unbounded.To_String (Item.Quote);
   end Quoted_Line;

   -----------
   -- Caret --
   -----------

   function Caret (Item : Diagnostic) return String is
      Line : constant String :=
        Ada.Strings.Unbounded.To_String (Item.Quote);

      --  Where the diagnostic starts in the line, in bytes, found by walking
      --  the characters before it: a column counts characters and a slice
      --  counts bytes, and the two differ from the first accented letter on.
      Index  : Positive := Line'First;
      Indent : Natural := 0;
      Seen   : Positive := 1;
   begin
      if Line'Length = 0 then
         return "";
      end if;

      while Seen < Item.Place.Column and then Index <= Line'Last loop
         declare
            Code   : Natural;
            Length : Positive;
         begin
            Adash.Display_Width.Decode (Line, Index, Code, Length);
            Indent := Indent + Adash.Display_Width.Cells (Code);
            Index := Index + Length;
            Seen := Seen + 1;
         end;
      end loop;

      declare
         --  How far the diagnostic reaches on this line: its own extent,
         --  stopped at the end of the line, since a span may cross lines and
         --  a caret may not.
         Covers : constant Natural :=
           (if Adash.Source.Is_Empty (Item.Extent) then 1
            else Natural'Min
                   (Natural (Item.Extent.Last - Item.Extent.First) + 1,
                    Line'Last - Index + 1));

         Width : constant Natural :=
           (if Index > Line'Last or else Covers = 0 then 1
            else Adash.Display_Width.Cells
                   (Line (Index .. Index + Covers - 1)));

         Mark : String (1 .. Indent + Natural'Max (Width, 1)) :=
           [others => ' '];
      begin
         Mark (Indent + 1) := '^';

         for Cell in Indent + 2 .. Mark'Last loop
            Mark (Cell) := '~';
         end loop;

         return Mark;
      end;
   end Caret;

   --------------
   -- Position --
   --------------

   function Position (Item : Diagnostic) return Adash.Source.Location is
   begin
      return Item.Place;
   end Position;

   ------------
   -- Locate --
   ------------

   procedure Locate
     (Item   : in out List;
      Index  : Positive;
      Origin : Adash.Source.Origin;
      Extent : Adash.Source.Span;
      Place  : Adash.Source.Location := (Line => 1, Column => 1);
      Quote  : String := "")
   is
      Moved : Diagnostic := Item.Entries.Element (Index);
   begin
      Moved.Origin := Origin;
      Moved.Place := Place;
      Moved.Quote := Ada.Strings.Unbounded.To_Unbounded_String (Quote);

      if not Adash.Source.Is_Empty (Extent) then
         Moved.Extent := Extent;
      end if;

      Item.Entries.Replace_Element (Index, Moved);
   end Locate;

   --------------
   -- Count_Of --
   --------------

   function Count_Of (Item : List; Level : Severity) return Natural is
      Result : Natural := 0;
   begin
      for Current of Item.Entries loop
         if Current.Level = Level then
            Result := Result + 1;
         end if;
      end loop;

      return Result;
   end Count_Of;

   -------------------
   -- Has_Blocking --
   -------------------

   function Has_Blocking (Item : List) return Boolean is
   begin
      for Current of Item.Entries loop
         if Current.Level = Severity_Error or else Current.Level = Severity_Fatal then
            return True;
         end if;
      end loop;

      return False;
   end Has_Blocking;

   ----------
   -- Sort --
   ----------

   procedure Sort (Item : in out List) is
      Count_Now : constant Natural := Natural (Item.Entries.Length);
   begin
      --  Insertion sort. The list is short -- a phase that produced hundreds of
      --  diagnostics has a bigger problem than the cost of ordering them -- and
      --  insertion sort is stable by construction, which is the property that
      --  matters here.
      for Outer in 2 .. Count_Now loop
         declare
            Current : constant Diagnostic := Item.Entries.Element (Outer);
            Inner   : Natural := Outer - 1;
         begin
            while Inner >= 1
              and then Precedes (Current, Item.Entries.Element (Inner))
            loop
               Item.Entries.Replace_Element (Inner + 1, Item.Entries.Element (Inner));
               Inner := Inner - 1;
            end loop;

            Item.Entries.Replace_Element (Inner + 1, Current);
         end;
      end loop;
   end Sort;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out List) is
   begin
      Item.Entries.Clear;

      --  The sequence counter is not reset. A list that is cleared and reused
      --  must not produce two diagnostics with the same tie-break key, or the
      --  stability Sort promises would depend on when Clear was called.
      null;
   end Clear;

end Adash.Diagnostics;

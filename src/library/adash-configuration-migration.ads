with Tomllib.Documents;

--  Bringing an older configuration file forward.
--
--  A configuration file records the schema it was written for, as a top-level
--  `schema` key. That number exists so that a setting can be renamed or moved
--  without silently ignoring what the user chose: without it, a rename means
--  every existing file quietly loses that setting, and the only sign is that
--  the shell behaves differently and nothing says why.
--
--  The rules are:
--
--    * **A file with no schema key is current.** Hand-written files are the
--      common case and nobody should have to write a version number to
--      configure a shell. This is a deliberate decision rather than an
--      oversight: it means a file written by hand can never be migrated, which
--      is correct, because there is nothing to bring it forward from.
--    * **An older file is migrated, then rewritten.** Migration happens in
--      memory on the parsed document; the file on disk is only rewritten when
--      the shell has reason to write it anyway, so reading a configuration
--      never modifies it as a side effect.
--    * **A newer file is read as far as it can be.** Settings this Adash knows
--      are honoured and the rest are reported as unknown. Refusing it outright
--      would mean a user with two versions of Adash on two machines cannot
--      share one file, which is exactly what they will try to do.
--
--  There has been one schema, so the rename table is empty. That is not a
--  reason to leave the mechanism out: the first rename is precisely when
--  nobody wants to be designing it.
package Adash.Configuration.Migration is

   --  The schema this build writes.
   Current_Schema : constant := 1;

   --  The oldest schema this build can bring forward. A file older than this
   --  is read as best it can be rather than refused, on the same reasoning as
   --  a newer one: the user's settings are worth more than our tidiness.
   Oldest_Supported : constant := 1;

   --  What a document says it was written for.
   --
   --  @param From The parsed document.
   --  @return Its schema number, or Current_Schema when it does not say. A
   --          `schema` key that is not a whole number is treated the same way:
   --          it is a mistake in a file somebody wrote by hand, and guessing
   --          low would migrate settings that never needed it.
   function Schema_Of (From : in out Tomllib.Documents.Document) return Natural;

   --  Whether a document needs bringing forward.
   --
   --  @param Schema What the document says.
   --  @return True when it is older than this build's.
   function Needs_Migration (Schema : Natural) return Boolean is
     (Schema in Oldest_Supported .. Current_Schema - 1);

   --  Whether a document was written by a newer Adash.
   --
   --  @param Schema What the document says.
   --  @return True when it is newer than this build's.
   function Is_Newer (Schema : Natural) return Boolean is
     (Schema > Current_Schema);

   --  Bring a document forward to the current schema.
   --
   --  Applied in memory, on the parsed document, before the settings are read
   --  out of it. Nothing is written to disk here.
   --
   --  @param Item The document, changed in place.
   --  @param From The schema it was written for.
   --  @return How many settings were moved or renamed. Zero is the ordinary
   --          answer while there has been only one schema, and a caller uses
   --          it to decide whether the file is worth rewriting.
   function Apply
     (Item : in out Tomllib.Documents.Document;
      From : Natural) return Natural;

   --  How many renames this build knows about.
   --
   --  Exposed so that a test can assert the table is what it is thought to be:
   --  a rename added without a schema bump, or a schema bumped with no rename,
   --  are both silent mistakes otherwise.
   --
   --  @return The count.
   function Rename_Count return Natural;

end Adash.Configuration.Migration;

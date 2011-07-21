-- Contributed by ITEC - NXP Semiconductors
-- June 2008
--
-- Change log:
-- ==========
-- 30-Mar-2010: GdM: Added Name function
-- 25-Feb-2010: GdM: Fixed major bottlenecks around Dir_entries
--                     -> 5x faster overall for 1000 files, 356x for 100'000 !
-- 17-Feb-2009: GdM: Added procedure Add_String
-- 10-Feb-2009: GdM: Create / Finish: if Info.Stream is to a file,
--                     the underling file is also created / closed in time
--  4-Feb-2009: GdM: Added procedure Add_File
--

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Zip.Headers; use Zip.Headers;
with Zip.Compress; use Zip.Compress;
with Zip_Streams; use Zip_Streams;

package Zip.Create is

   type Zip_Create_info is private;

   -- Create the Zip archive; create the file if the stream is a file

   procedure Create(Info        : out Zip_Create_info;
                    Z_Stream    : in Zipstream_Class;
                    Name        : String;
                    Compress    : Zip.Compress.Compression_Method:= Zip.Compress.Shrink);


   function Name(Info: Zip_Create_info) return String;

   -- Add a new entry to a Zip archive, from a general Zipstream

   procedure Add_Stream (Info   : in out Zip_Create_info;
                         Stream : Zipstream_Class);

   procedure Add_Stream (Info           : in out Zip_Create_info;
                         Stream         : Zipstream_Class;
                         Feedback       : in     Feedback_proc;
                         Compressed_Size:    out Zip.File_size_type;
                         Final_Method   :    out Natural);

   -- Add a new entry to a Zip archive, from a file

   procedure Add_File (Info              : in out Zip_Create_info;
                       Name              : String;
                       Name_in_archive   : String:= "";
                       -- default: add the file in the archive
                       -- under the same name
                       Delete_file_after : Boolean:= False;
                       -- practical to delete temporary file after
                       -- adding
                       Name_UTF_8_encoded: Boolean:= False
                       -- True if Name[_in_archive] is actually
                       -- UTF-8 encoded (Unicode)
   );

   -- Add new entries to a Zip archive, from a buffer stored in a string

   procedure Add_String (Info              : in out Zip_Create_info;
                         Contents          : String;
                         Name_in_archive   : String;
                         Name_UTF_8_encoded: Boolean:= False
                         -- True if Name is actually UTF-8 encoded (Unicode)
   );

   procedure Add_String (Info              : in out Zip_Create_info;
                         Contents          : Unbounded_String;
                         Name_in_archive   : String;
                         Name_UTF_8_encoded: Boolean:= False
                         -- True if Name is actually UTF-8 encoded (Unicode)
   );

   -- Complete the Zip archive; close the file if the stream is a file

   procedure Finish (Info       : in out Zip_Create_info);

private

   type Dir_entry is record
      head : Zip.Headers.Central_File_Header;
      name : p_String;
   end record;

   type Dir_entries is array (Positive range <>) of Dir_entry;
   type Pdir_entries is access Dir_entries;

   type Zip_Create_info is record
      Stream    : Zipstream_Class;
      Compress  : Zip.Compress.Compression_Method;
      Contains  : Pdir_entries:= null;
      Last_entry: Natural:= 0;
      -- 'Contains' has unused room, to avoid reallocating each time
   end record;

end Zip.Create;

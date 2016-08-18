with LZMA.Encoding;
with Zip.CRC_Crypto;

with Ada.Unchecked_Deallocation;
with Interfaces; use Interfaces;

procedure Zip.Compress.LZMA_E
 (input,
  output          : in out Zip_Streams.Root_Zipstream_Type'Class;
  input_size_known: Boolean;
  input_size      : File_size_type;
  feedback        : Feedback_proc;
  method          : LZMA_Method;
  CRC             : in out Interfaces.Unsigned_32; -- only updated here
  crypto          : in out Crypto_pack;
  output_size     : out File_size_type;
  compression_ok  : out Boolean -- indicates compressed < uncompressed
)
is

  ------------------
  -- Buffered I/O --
  ------------------

  --  Define data types needed to implement input and output file buffers

  procedure Dispose is
    new Ada.Unchecked_Deallocation(Byte_Buffer, p_Byte_Buffer);

  InBuf: p_Byte_Buffer;  --  I/O buffers
  OutBuf: p_Byte_Buffer;

  InBufIdx: Positive;  --  Points to next char in buffer to be read
  OutBufIdx: Positive; --  Points to next free space in output buffer

  MaxInBufIdx: Natural;  --  Count of valid chars in input buffer
  InputEoF: Boolean;     --  End of file indicator

  procedure Read_Block is
  begin
    Zip.BlockRead(
      stream        => input,
      buffer        => InBuf.all,
      actually_read => MaxInBufIdx
    );
    InputEoF:= MaxInBufIdx = 0;
    InBufIdx := 1;
  end Read_Block;

  -- Exception for the case where compression works but produces
  -- a bigger file than the file to be compressed (data is too "random").
  Compression_inefficient: exception;

  procedure Write_Block is
    amount: constant Integer:= OutBufIdx-1;
  begin
    output_size:= output_size + File_size_type(Integer'Max(0,amount));
    if input_size_known and then output_size >= input_size then
      -- The compression so far is obviously unefficient for that file.
      -- Useless to go further.
      -- Stop immediately before growing the file more than the
      -- uncompressed size.
      raise Compression_inefficient;
    end if;
    Encode(crypto, OutBuf(1 .. amount));
    Zip.BlockWrite(output, OutBuf(1 .. amount));
    OutBufIdx := 1;
  end Write_Block;

  procedure Put_byte(B : Unsigned_8) is
  begin
    OutBuf(OutBufIdx) := B;
    OutBufIdx:= OutBufIdx + 1;
    if OutBufIdx > OutBuf.all'Last then
      Write_Block;
    end if;
  end Put_byte;

  procedure Flush_output is
  begin
    if OutBufIdx > 1 then
      Write_Block;
    end if;
  end Flush_output;

  X_Percent: Natural;
  Bytes_in   : Natural;   --  Count of input file bytes processed
  user_aborting: Boolean;
  PctDone: Natural;

  function Read_byte return Byte is
    b: Byte;
  begin
    b:= InBuf(InBufIdx);
    InBufIdx:= InBufIdx + 1;
    Zip.CRC_Crypto.Update(CRC, (1=> b));
    Bytes_in:= Bytes_in + 1;
    if feedback /= null then
      if Bytes_in = 1 then
        feedback(0, False, user_aborting);
      end if;
      if X_Percent > 0 and then
         ((Bytes_in-1) mod X_Percent = 0
          or Bytes_in = Integer(input_size))
      then
        if input_size_known then
          PctDone := Integer( (100.0 * Float( Bytes_in)) / Float(input_size));
          feedback(PctDone, False, user_aborting);
        else
          feedback(0, False, user_aborting);
        end if;
        if user_aborting then
          raise User_abort;
        end if;
      end if;
    end if;
    return b;
  end Read_byte;

  function More_bytes return Boolean is
  begin
    if InBufIdx > MaxInBufIdx then
      Read_Block;
    end if;
    return not InputEoF;
  end More_bytes;

  use LZMA.Encoding;

  LZMA_choice: constant array(LZMA_Method) of LZMA_compression_level:=
    (LZMA_1  => Level_1,
     LZMA_2  => Level_2);

  procedure LZMA_Encode is
    new LZMA.Encoding.Encode(Read_byte, More_bytes, Put_byte);

begin
  --  Allocate input and output buffers.
  if input_size_known then
    InBuf:= new Byte_Buffer
      (1..Integer'Min(Integer'Max(8,Integer(input_size)), buffer_size));
  else
    InBuf:= new Byte_Buffer(1..buffer_size);
  end if;
  OutBuf:= new Byte_Buffer(1..buffer_size);
  OutBufIdx := 1;
  output_size:= 0;
  begin
    Read_Block;
    Bytes_in := 0;
    if input_size_known then
      X_Percent := Integer(input_size / 40);
    else
      X_Percent := 0;
    end if;
    Put_byte(16);  --  LZMA SDK major version
    Put_byte(02);  --  LZMA SDK minor version
    Put_byte(5);   --  LZMA properties size low byte
    Put_byte(0);   --  LZMA properties size high byte
    LZMA_Encode(
      level      => LZMA_choice(method),
      end_marker => True    --  In Appnote, the use of an EOS marker is "highly recommended".
    );
    Flush_output;
    compression_ok:= True;
  exception
    when Compression_inefficient =>
      compression_ok:= False;
  end;
  Dispose(InBuf);
  Dispose(OutBuf);
end Zip.Compress.LZMA_E;
unit PoisonMM;

{ Test-only memory manager. Every freed block is filled with $80 and never reused,
  so a use-after-free reads $80808080... and fails with an access violation instead
  of silently reading stale memory or a newer object that reused the address.
  Freeing a block twice reaches the real memory manager with an invalid pointer and
  raises EInvalidPointer.

  Must be the first unit in the program's uses clause. Blocks are never returned to
  the real memory manager, so this is only suitable for short test runs. }

interface

implementation

const
  cHeaderSize = 16;
  cMagic = Cardinal($C0DEF00D);
  cFreedMagic = Cardinal($DEADF00D);
  cPoison = $80;

var
  oldManager: TMemoryManagerEx;
  newManager: TMemoryManagerEx;

function HeaderOf(p: Pointer): PByte; inline;
begin
  result := PByte(p) - cHeaderSize;
end;

function IsOurs(p: Pointer): Boolean;
begin
  result := PCardinal(HeaderOf(p) + 8)^ = cMagic;
end;

function PoisonGetMem(size: NativeInt): Pointer;
var
  block: PByte;
begin
  block := oldManager.GetMem(size + cHeaderSize);
  if block = nil then
    Exit(nil);
  PNativeInt(block)^ := size;
  PCardinal(block + 8)^ := cMagic;
  result := block + cHeaderSize;
end;

function PoisonFreeMem(p: Pointer): Integer;
var
  block: PByte;
begin
  if p = nil then
    Exit(0);
  { Blocks allocated before this manager was installed have no header. }
  if not IsOurs(p) then
    Exit(oldManager.FreeMem(p));
  block := HeaderOf(p);
  FillChar(p^, PNativeInt(block)^, cPoison);
  PCardinal(block + 8)^ := cFreedMagic;
  result := 0; // quarantined: never handed out again
end;

function PoisonReallocMem(p: Pointer; size: NativeInt): Pointer;
var
  oldSize: NativeInt;
begin
  if (p = nil) or not IsOurs(p) then
    Exit(oldManager.ReallocMem(p, size));
  result := PoisonGetMem(size);
  if result = nil then
    Exit;
  oldSize := PNativeInt(HeaderOf(p))^;
  if oldSize < size then
    Move(p^, result^, oldSize)
  else
    Move(p^, result^, size);
  PoisonFreeMem(p);
end;

function PoisonAllocMem(size: NativeInt): Pointer;
begin
  result := PoisonGetMem(size);
  if result <> nil then
    FillChar(result^, size, 0);
end;

function PoisonRegisterLeak(p: Pointer): Boolean;
begin
  result := oldManager.RegisterExpectedMemoryLeak(p);
end;

function PoisonUnregisterLeak(p: Pointer): Boolean;
begin
  result := oldManager.UnregisterExpectedMemoryLeak(p);
end;

initialization
  GetMemoryManager(oldManager);
  newManager.GetMem := PoisonGetMem;
  newManager.FreeMem := PoisonFreeMem;
  newManager.ReallocMem := PoisonReallocMem;
  newManager.AllocMem := PoisonAllocMem;
  newManager.RegisterExpectedMemoryLeak := PoisonRegisterLeak;
  newManager.UnregisterExpectedMemoryLeak := PoisonUnregisterLeak;
  SetMemoryManager(newManager);

  { Deliberately not restored in finalization: blocks this manager handed out
    carry a header the real memory manager does not know about. }
end.

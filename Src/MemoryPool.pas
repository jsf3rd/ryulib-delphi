unit MemoryPool;

interface

uses
  DebugTools, Interlocked,
  Windows, SysUtils, Classes;

const
  /// 메모리 풀 크기가 상수를 넘으면 상수 단위로 페이징 한다.
  POOL_UNIT_SIZE = 1024 * 1024 * 64;

  { *
    경계 조건에서 실수가 있더라도 A.V. 에러가 나지 않도록 여유를 둔다.
    한 번에 할달 받을 수 있는 최대 크기이다.
  }
  SAFE_ZONE = 64 * 1024;

type
  TMemoryPool = class abstract
  private
  public
    function GetClone(ASrc: Pointer; ASize: Word): Pointer; virtual;
    procedure GetMem(var AData: Pointer; ASize: integer); overload; virtual; abstract;
    function GetMem(ASize: integer): Pointer; overload; virtual; abstract;
  end;

  TMemoryPool64 = class(TMemoryPool)
  private
    FPoolSize: int64;
    FIndex: int64;
    FUnitCount: int64;
    FPools: array of Pointer;

    // FIndex가 한계를 넘어서 마이너스로 가지 않도록 수정
    procedure do_ResetIndex;
  public
    constructor Create(APoolSize: int64); reintroduce;
    destructor Destroy; override;

    procedure GetMem(var AData: Pointer; ASize: integer); overload; override;
    function GetMem(ASize: integer): Pointer; overload; override;
  end;

  TMemoryPool32 = class(TMemoryPool)
  private
    FPoolSize: integer;
    FIndex: integer;
    FUnitCount: integer;
    FPools: array of Pointer;

    // FIndex가 한계를 넘어서 마이너스로 가지 않도록 수정
    procedure do_ResetIndex;
  public
    constructor Create(APoolSize: integer); reintroduce;
    destructor Destroy; override;

    procedure GetMem(var AData: Pointer; ASize: integer); overload; override;
    function GetMem(ASize: integer): Pointer; overload; override;
  end;

  /// 전역에서 사용 할 수 있는 메모리 풀 생성
procedure CreateMemoryPool(APoolSize: int64);

function GetMemory(ASize: integer): Pointer; overload;
procedure GetMemory(var AData: Pointer; ASize: integer); overload;

function CloneMemory(AData: Pointer; ASize: integer): Pointer;

implementation

var
  MemoryPoolObject: TMemoryPool = nil;

procedure CreateMemoryPool(APoolSize: int64);
begin
{$IFDEF CPUX86}
  MemoryPoolObject := TMemoryPool32.Create(APoolSize);
{$ENDIF}
{$IFDEF CPUX64}
  MemoryPoolObject := TMemoryPool64.Create(APoolSize);
{$ENDIF}
end;

function GetMemory(ASize: integer): Pointer; overload;
begin
  Result := MemoryPoolObject.GetMem(ASize);
end;

procedure GetMemory(var AData: Pointer; ASize: integer); overload;
begin
  MemoryPoolObject.GetMem(AData, ASize);
end;

function CloneMemory(AData: Pointer; ASize: integer): Pointer;
begin
  Result := MemoryPoolObject.GetMem(ASize);
  Move(AData^, Result^, ASize);
end;

{ TMemoryPool64 }

constructor TMemoryPool64.Create(APoolSize: int64);
var
  Loop: integer;
begin
  inherited Create;

  FPoolSize := APoolSize;
  if APoolSize < POOL_UNIT_SIZE then
    FPoolSize := POOL_UNIT_SIZE;

  SetLength(FPools, ((APoolSize - 1) div POOL_UNIT_SIZE) + 1);
  for Loop := Low(FPools) to High(FPools) do
    System.GetMem(FPools[Loop], POOL_UNIT_SIZE + SAFE_ZONE);

  FIndex := 0;
  FUnitCount := Length(FPools);
end;

destructor TMemoryPool64.Destroy;
var
  Loop: integer;
begin
  for Loop := Low(FPools) to High(FPools) do
    System.FreeMem(FPools[Loop]);

  inherited;
end;

procedure TMemoryPool64.do_ResetIndex;
var
  iIndex: int64;
begin
  iIndex := FIndex;

  if iIndex >= FPoolSize then
  begin
    InterlockedCompareExchange64(FIndex, iIndex - FPoolSize, iIndex);

{$IFDEF DEBUG}
    Trace(Format('TMemoryPool64.do_ResetIndex - FIndex: %d, iIndex: %d', [FIndex, iIndex]));
{$ENDIF}
  end;
end;

function TMemoryPool64.GetMem(ASize: integer): Pointer;
begin
  Self.GetMem(Result, ASize);
end;

procedure TMemoryPool64.GetMem(var AData: Pointer; ASize: integer);
var
  iIndex, iDiv, iMod: int64;
begin
  AData := nil;

  if ASize <= 0 then
    Exit;

  if ASize >= SAFE_ZONE then
    raise Exception.Create(Format('TMemoryPool64.GetMem - ASize >= %d KB', [SAFE_ZONE div 1024]));

  iIndex := InterlockedExchangeAdd64(FIndex, ASize);

  iDiv := iIndex div POOL_UNIT_SIZE;
  iMod := iIndex mod POOL_UNIT_SIZE;

  AData := FPools[iDiv mod FUnitCount];

  Inc(PByte(AData), iMod);

  do_ResetIndex;
end;

{ TMemoryPool32 }

constructor TMemoryPool32.Create(APoolSize: integer);
var
  Loop: integer;
begin
  inherited Create;

  FPoolSize := APoolSize;
  if APoolSize < POOL_UNIT_SIZE then
    FPoolSize := POOL_UNIT_SIZE;

  SetLength(FPools, ((APoolSize - 1) div POOL_UNIT_SIZE) + 1);
  for Loop := Low(FPools) to High(FPools) do
    System.GetMem(FPools[Loop], POOL_UNIT_SIZE + SAFE_ZONE);

  FIndex := 0;
  FUnitCount := Length(FPools);
end;

destructor TMemoryPool32.Destroy;
var
  Loop: integer;
begin
  for Loop := Low(FPools) to High(FPools) do
    System.FreeMem(FPools[Loop]);

  inherited;
end;

procedure TMemoryPool32.do_ResetIndex;
var
  iIndex: integer;
begin
  iIndex := FIndex;

  if iIndex >= FPoolSize then
  begin
    InterlockedCompareExchange(FIndex, iIndex - FPoolSize, iIndex);

{$IFDEF DEBUG}
    Trace(Format('TMemoryPool32.do_ResetIndex - FIndex: %d, iIndex: %d', [FIndex, iIndex]));
{$ENDIF}
  end;
end;

function TMemoryPool32.GetMem(ASize: integer): Pointer;
begin
  Self.GetMem(Result, ASize);
end;

procedure TMemoryPool32.GetMem(var AData: Pointer; ASize: integer);
var
  iIndex, iDiv, iMod: integer;
begin
  AData := nil;

  if ASize <= 0 then
    Exit;

  if ASize > SAFE_ZONE then
    raise Exception.Create(Format('TMemoryPool32.GetMem - ASize > %d KB', [SAFE_ZONE div 1024]));

  iIndex := InterlockedExchangeAdd(FIndex, ASize);

  iDiv := iIndex div POOL_UNIT_SIZE;
  iMod := iIndex mod POOL_UNIT_SIZE;

  AData := FPools[iDiv mod FUnitCount];

  Inc(PByte(AData), iMod);

  do_ResetIndex;
end;

{ TMemoryPool }

function TMemoryPool.GetClone(ASrc: Pointer; ASize: Word): Pointer;
begin
  if ASize = 0 then
  begin
    Result := nil;
    Exit;
  end;
  Self.GetMem(Result, ASize);
  CopyMemory(Result, ASrc, ASize);
end;

end.

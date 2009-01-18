(* Version: MPL 1.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is the nvfs main unit.
 *
 * The Initial Developer of the Original Code is
 * Noeska Software.
 * Portions created by the Initial Developer are Copyright (C) 2008
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *
 *  M van der Honing
 *
 *)

//TODO: when blocks are reused somehow filesize of / becomes to small?
//TODO: when reusing deleted block some blocks do not get reused.
//TODO: give more meaning to filemode. E.g. block write when in read mode
//look at real TFileStream ?
//do some error checking on reading a non existent file (fmcreate).
//TODO: Add Support for third party encryption via class
//TODO: investigate database capacities (dbexpress?); (low profile)
//TODO: investigate variable record length

unit nvfs;

interface

uses classes, sysutils;

{$R+}  //Range Check On

type

  TFileInfo = packed record //TODO: remove/add fields?
    id: int64; //unique id for directory entry
    filename: string[255]; //name instead of filename
    filesize: int64;       //size instead of filesize
    startblock: int64;
    deleted: boolean; //gives status for file can be used to not show deleted files and reuse directory entry
    offset: integer; //future use for storing more then one file in block
  end;
  PFileRecord = ^TFileInfo;

  TFileLabel = packed record
    labelid: int64; //is actualy also a fileid
    fileid: int64;
  end;
  PFileLabel = ^TFileLabel;

  TBlockList= array of int64;

  TVirtualFileStream = class(TStream)
  private
    FMode: Word;
    FSize: Integer;
    FOrigSize: Integer;
    FPosition: Int64;
    FFileRecord: TFileInfo; //name / begin block / stream (file) size
    FBlockList: TBlockList; //blocks used by stream in order
    FDataFileP: TObject; //pointer to virtual filesystem object
    FFirstBlock: int64;
  protected
    function GetSize: Int64; override;
    procedure SetSize(NewSize: LongInt); override;
  public
    constructor Create(aName: string; Mode: Word; aVFSFileSystem: TObject); overload;
    constructor Create(aLabelname: string; aName: string; Mode: Word; aVFSFileSystem: TObject); overload;
    destructor Destroy(); override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    property Position: Int64 read FPosition write FPosition;
  end;

  TVirtualFileSystem = class
  private
    FDataFile: TFileStream;
    FDataFileName: string;
    FBlockSize: integer;
    FUseableBlockSize: integer;
    FDir: TVirtualFileStream;
    FDeleted: TVirtualFileStream;
    FLabelIndex: TVirtualFileStream;
    FDeletedBlockList: TBlockList; //copy of list of deleted blocks in memory
    FNextFileId: int64;

    function ReadBlock(ablockid: int64; pBuf: pointer): int64; overload;
    function ReadBlock(ablockid: int64; pBuf: pointer; beginpos: integer; endpos: integer): int64; overload;
    function ReadBlock(ablockid: int64; var buffer; beginpos: integer; endpos: integer): int64; overload;

    procedure WriteBlock(ablockid, anextblockid, aprevblockid: int64; pBuf: pointer); overload;
    procedure WriteBlock(ablockid, anextblockid, aprevblockid: int64; pBuf: pointer; beginpos: integer; endpos: integer); overload;
    procedure WriteBlock(ablockid, anextblockid, aprevblockid: int64; const buffer; beginpos: integer; endpos: integer); overload;

    function NextFreeBlock(): int64;
    function SecondNextFreeBlock(): int64;
    function GetFreeBlockFromDeletedList(): int64;
    function RemoveBlockFromDeletedList(ablockid: int64): boolean;

    procedure WriteHeader();
    procedure WriteFirstDirectoryEntry();
    procedure WriteFirstDeletedFileEntry();
    procedure WriteFirstLabelIndexEntry();

    procedure GetBlockId(var existingblock: Boolean; endblockid: Integer; var blocklistsize: Integer; var BlockList: TBlockList; sequenceid: Integer; var blockid: Int64; var nextblockid: Int64);

    function AddFile(aname: string; astartblockid: int64; asize: int64): TFileInfo; //add file to directory
    procedure ChangeFile(aname: string; afilerecord: TFileInfo); //rename file and or change attributes
    function FindFile(aname: string; var afilerecord: TFileInfo): int64; //search file


    procedure DeleteBlock(ABlockId: int64);
    function GetDeletedBlockList(): TBlockList;
    function GetBlockList(afile: TFileInfo): TBlockList;
    function ReadVirtualFileStreamBuffer(var buffer; Position, Count: Integer; BlockList: TBlockList ): LongInt;
    function WriteVirtualFileStreamBuffer(const buffer; Position, Count: Integer; var BlockList: TBlockList ): LongInt;

  protected
  public
    constructor Create();
    destructor Destroy(); override;
    procedure New(); overload;
    procedure New(aBlockSize: integer); overload;
    procedure Open();
    procedure Close();

    //--------------------------------------------------------------------------
    //functions for file management

    procedure GetDeletedBlock(List: TStrings);

    procedure GetFileList(List: TStrings); overload; //read directory/filelist
    procedure GetFileList(aname: string; List: TStrings); overload; //read directory/filelist
    function DeleteFile(aname: string): boolean; //delete file
    procedure AddLabel(aname: string); //add a new label
    procedure AssignLabel(afileid: int64; alabelid: int64); overload;
    procedure AssignLabel(afileid: int64; alabelname: string); overload;



    //--------------------------------------------------------------------------
    //properties

    property FileName: string read FDataFileName write FDataFileName;
    property BlockSize: integer read FBlockSize;
  end;

implementation

type
  TBuffer = array of byte; //used for copying/addressing pointer/buffers

//TvfsFileStream ---------------------------------------------------------------

constructor TVirtualFileStream.Create(alabelname: string; aname: string; Mode: Word; aVFSFileSystem: TObject);
var
  NewFileRecord: TFileInfo;
begin
  inherited Create();

  FMode:= Mode;
  FBlockList:=nil;

  //determine if aVFSFileSystem is a TVirtualFileSystem
  if aVFSFileSystem <> nil then
    if aVFSFileSystem is TVirtualFileSystem then
    begin
      self.FDataFileP := aVFSFileSystem;

      //Does aname exist?
      TVirtualFileSystem(self.FDataFileP).FindFile(aname,FFileRecord);

      if FFileRecord.startblock > 0 then
      begin
        FOrigSize:=FFileRecord.filesize;
        FSize:=FFileRecord.filesize;
        FFirstBlock := FFileRecord.startblock;
      end
      else
      begin
        if fmode <> fmopenread then
        begin
        //new file
        FFirstBlock := TVirtualFileSystem(self.FDataFileP).NextFreeBlock();
        NewFileRecord := TVirtualFileSystem(self.FDataFileP).AddFile(aname,FFirstBlock , 0);
        FSize:=0;
        FOrigSize:=0;
        end
        else
          raise exception.Create('File '+aname+' does not exist');
      end;

      FPosition:=0; //go to start of virtual file

      //determine what blocks are used by virtual file (if any)
      FBlockList:=TVirtualFileSystem(self.FDataFileP).GetBlockList(FFileRecord);

      //some more for making a new virtual file
      if FFilerecord.filename = 'Not Found' then
      begin
        FFileRecord.id := NewFileRecord.id;  //read real id?
        FFileRecord.deleted :=false;
        FFileRecord.offset :=0;
        FFileRecord.filename := aname;
        FFileRecord.startblock :=TVirtualFileSystem(self.FDataFileP).NextFreeBlock();

        //Assign the label
        TVirtualFileSystem(self.FDataFileP).AssignLabel(FFileRecord.Id, alabelname);
      end;



      FPosition:=0; //go back to start of virtual file
    end
    else
      Raise Exception.Create('aVFSFileSystem must be a TVirtualFileSystem');

end;

constructor TVirtualFileStream.Create(aname: string; Mode: Word; aVFSFileSystem: TObject);
begin
  self.Create('/',aname, Mode, aVFSFileSystem);
end;

destructor TVirtualFileStream.Destroy();
var
  NewSize: integer;
begin
  //check size on closing the virtual file
  if (FMode = fmCreate) or (FMode = fmOpenWrite) then
  begin
    NewSize := FPosition; //could be tricky?
    self.SetSize(NewSize);
  end;
  (*
  if (FMode <> fmOpenRead) and (FSize=0) then
  begin
    //Delete the file if the size became 0
    TVirtualFileSystem(self.FDataFileP).DeleteFile(FFileRecord.filename);
  end;
  *)
  
  self.FDataFileP := nil; //unassign VirtualFileSystem...

  if self.FBlockList <> nil then
  begin
    SetLength(self.FBlockList,0);
    self.FBlockList := nil;
  end;

  inherited Destroy();
end;

function TVirtualFileStream.GetSize(): Int64;
begin
  result :=FSize;
end;

procedure TVirtualFileStream.SetSize(NewSize: LongInt);
var
  EndBlock: integer;
  i: integer;
begin

  //In readwrite mode every call to SetSize should be handled
  if FMode = fmOpenReadWrite then
  begin
    //Bij SetSize controle op verwijderen blokken.
    if FOrigSize> NewSize then
    begin
      //check for blocks to mark as deleted.
      EndBlock := FSize div ( TVirtualFileSystem(self.FDataFileP).FUseableBlockSize ) +1;

      //TODO: clear remaining space in last still used block (EndBlock-1)

      for i:=EndBlock to High(FBlockList) do
      begin
        TVirtualFileSystem(self.FDataFileP).DeleteBlock(FBlockList[i]);
      end;
    end;
  end;

  if (FMode = fmCreate) or (FMode = fmOpenWrite) then
  begin
    if FOrigSize> NewSize then
    begin
      //check for blocks to mark as deleted.
      EndBlock := newSize div ( TVirtualFileSystem(self.FDataFileP).FUseableBlockSize ) +1;

      //TODO: clear remaining space in last still used block (EndBlock-1)

      //Mark Remaining (not used anymore) Blocks as Deleted
      for i:=EndBlock to High(FBlockList) do
      begin
        TVirtualFileSystem(self.FDataFileP).DeleteBlock(FBlockList[i]);
      end;

    end;
  end;

  //TODO: this is a bugfix as sometimes the size of the directory is determined wrong?
  if (FFileRecord.filename = '/') and (NewSize<FSize)  then
  begin
    NewSize := FSize;
  end;

  // Set the size property of the wrapped stream
  FSize:= NewSize;
  FFileRecord.FileSize := FSize;

  TVirtualFileSystem(self.FDataFileP).ChangeFile(FFileRecord.filename, FFileRecord);
  FOrigSize:=FSize;

end;

function TVirtualFileStream.Read(var Buffer; Count: Integer): Longint;
begin
  if (fposition <= fsize) and (fposition+count <= fsize) then
  begin
  result := TVirtualFileSystem(FDataFileP).ReadVirtualFileStreamBuffer(Buffer, FPosition, Count, FBlockList);
  FPosition:=FPosition+result; //update fileposition
  end
  else
    raise exception.Create('Cannot read beyond filesize');
end;

function TVirtualFileStream.Write(const Buffer; Count: Integer): Longint;
var
  TempPosition: Int64;
begin
  if fmode<>fmopenread then
  begin
    //Determine if size has changed
    TempPosition:=FPosition; //save current fileposition
    if FPosition + Count > FSize then
    begin
      FSize := FPosition + Count;
      self.SetSize(FSize);
    end;
    FPosition:=TempPosition; //restore current filepostion

    //write the buffer
    result := TVirtualFileSystem(self.FDataFileP).WriteVirtualFileStreamBuffer(Buffer, FPosition, Count, FBlockList);

    //check if filerecord needs to be update due to changed startblock
    if FBlockList[0] <> FFirstBlock then
    begin
      ffilerecord.startblock:=FBlockList[0];
      TVirtualFileSystem(self.FDataFileP).ChangeFile(FFileRecord.filename,ffilerecord);
    end;

    if result = -1 then
    begin
      Raise Exception.Create('Write returned wrong size');
    end;
    FPosition:=FPosition+result; //update fileposition
  end
  else
    raise exception.Create('Cannot write when file is openend in open read mode');
end;

function TVirtualFileStream.Seek(Offset: Integer; Origin: Word): Longint;
var
  len : integer;
begin
  len := FFileRecord.filesize;
  case Origin of
    soFromBeginning: FPosition := Offset;
    soFromCurrent: FPosition := FPosition + Offset;
    soFromEnd: FPosition := len - Offset;
  end;

  if (FPosition > len) then
  begin
    FPosition := len;
  end
  else
  if (FPosition < 0) then
  begin
    FPosition := 0;
  end;
  Result := FPosition;
end;

//TvfsFileSystem ---------------------------------------------------------------

constructor TVirtualFileSystem.Create();
begin
  FNextFileId := 0;
  FDataFile := nil;
  FBlockSize := 512;//*1024;  //was 512
  FUseableBlockSize := FBlockSize - sizeof(int64);
end;

destructor TVirtualFileSystem.Destroy();
begin
  if FDataFile <> nil then self.Close();
  inherited Destroy();
end;

procedure TVirtualFileSystem.New();
begin
  FDataFile:= TFileStream.Create(FDataFileName, fmCreate);
  self.WriteHeader(); //header file with virtualfilesystem info
  self.WriteFirstDirectoryEntry(); //first directory entry /
  self.WriteFirstDeletedFileEntry(); //write file containing deleted block id's
  self.WriteFirstLabelIndexEntry(); //write label index for first files
  self.Close();
  self.Open();
end;

procedure TVirtualFileSystem.New(aBlockSize: integer);
begin
  FBlockSize:=aBlockSize;
  FUseableBlockSize:=FBlockSize-Sizeof(int64);
  self.New();
end;

procedure TVirtualFileSystem.Open();
begin
  FDataFile := TFileStream.Create(FDataFileName, fmOpenReadWrite);
  FDataFile.Position := 0;

  //open virtual directory filestream
  FDir := TVirtualFileStream.Create('/', fmOpenReadWrite, self);
  FNextFileId := (FDir.Size div SizeOf(TFileInfo));

  FDeleted := TVirtualFileStream.Create('/Deleted', fmOpenReadWrite, self);
  FLabelIndex := TVirtualFileStream.Create('/LabelIndex', fmOpenReadWrite, self);
  FDeletedBlockList := GetDeletedBlockList();
  FDataFile.Position := 0;


end;

procedure TVirtualFileSystem.Close();
begin
  if FLabelIndex <> nil then
  begin
    FLabelIndex.Free;
    FLabelIndex := nil;
  end;

  if FDeleted <> nil then
  begin
    FDeleted.Free;
    FDeleted := nil;
  end;

  if Fdir <> nil then
  begin
    FDir.Position := FDir.Size; //go to end of virtual file stream
    FDir.Free;
    FDir :=nil;
  end;

  FDataFile.Free;
  FDataFile := nil;
end;

function TVirtualFileSystem.ReadBlock(ablockid: int64; pBuf: pointer): int64;
var
  nextblockid: int64;
begin
  FDataFile.Position :=(ablockid * FBlockSize); //goto begin of block
  FDataFile.ReadBuffer(nextblockid, sizeof(nextblockid));
  FDataFile.ReadBuffer(pbuf^, FUseableBlockSize );
  result := nextblockid; //return the next block
end;

function TVirtualFileSystem.ReadBlock(ablockid: int64; pBuf: pointer; beginpos: integer; endpos: integer): int64;
var
  nextblockid: int64;
begin
  {$R+}
  FDataFile.Position :=(ablockid * FBlockSize); //goto begin of block
  FDataFile.ReadBuffer(nextblockid, sizeof(nextblockid));

  FDataFile.Position :=FDataFile.Position+beginpos; //advance to position within block
  FDataFile.ReadBuffer(pbuf^, (endpos-beginpos) ); //only read bytes needed

  result := nextblockid; //return the next block
end;

function TVirtualFileSystem.ReadBlock(ablockid: int64; var buffer; beginpos: integer; endpos: integer): int64;
var
  nextblockid: int64;
begin
  {$R+}
  FDataFile.Position :=(ablockid * FBlockSize); //goto begin of block
  FDataFile.ReadBuffer(nextblockid, sizeof(nextblockid));

  FDataFile.Position :=FDataFile.Position+beginpos; //advance to position within block
  FDataFile.ReadBuffer(buffer, (endpos-beginpos) ); //only read bytes needed

  result := nextblockid; //return the next block
end;

procedure TVirtualFileSystem.WriteBlock(ablockid, anextblockid, aprevblockid: int64; pBuf: Pointer);
begin
  {$R+}
  FDataFile.Position := (ablockid * FBlockSize); //goto begin of block
  FDataFile.WriteBuffer(anextblockid,sizeof(anextblockid));
  FDataFile.WriteBuffer(pbuf^,FUseAbleBlockSize );
end;

procedure TVirtualFileSystem.WriteBlock(ablockid, anextblockid, aprevblockid: int64; pBuf: Pointer; beginpos: integer; endpos: integer);
begin
  {$R+}
  FDataFile.Position := (ablockid * FBlockSize); //goto begin of block
  FDataFile.WriteBuffer(anextblockid,sizeof(anextblockid));

  FDataFile.Position := FDataFile.Position + beginpos; //advance to position within block
  FDataFile.WriteBuffer(pbuf^,(endpos-beginpos) ); //only write bytes needed
end;

procedure TVirtualFileSystem.WriteBlock(ablockid, anextblockid, aprevblockid: int64; const buffer; beginpos: integer; endpos: integer);
begin
  {$R+}
  FDataFile.Position := (ablockid * FBlockSize); //goto begin of block
  FDataFile.WriteBuffer(anextblockid,sizeof(anextblockid));

  FDataFile.Position := FDataFile.Position + beginpos; //advance to position within block
  FDataFile.WriteBuffer(buffer,(endpos-beginpos) ); //only write bytes needed
end;

//------------------------------------------------------------------------------

function TVirtualFileSystem.RemoveBlockFromDeletedList(ablockid: int64): boolean;
var
  dummy: int64;
begin
  result := true;
  //TODO: search for number and delete that instead of last one...
  //TODO: check if number is in list before removing it
  //TODO: compare DeletedBlockList
  dummy := 0;
  FDeleted.Position := FDeleted.Size-SizeOf(int64); //go to last entry
  FDeleted.Write(dummy, sizeof(int64)); //write 0
  //make FDeleted Smaller
  FDeleted.SetSize(FDeleted.FSize-SizeOf(int64));
end;

function TVirtualFileSystem.GetFreeBlockFromDeletedList(): int64;
begin
  //now the problem is that a requested block is not always used
  //TODO: how to detect how/if i should remove the block from the list
  //TODO: should also check if blockid has been given out already
  //TODO: compare DeletedBlockList
  Result:=0;
  if FDeleted <> nil then //special for the first time
  begin
    if Fdeleted.Size > 8 then //special for the first time
    begin
      FDeleted.Position := FDeleted.Size-SizeOf(int64); //go to last entry
      FDeleted.Read(result,SizeOf(int64));
    end;
  end;
end;

function TVirtualFileSystem.NextFreeBlock(): int64;
begin
  //Determine next free block (filesize / FBlockSize);
  result := (FDataFile.Size div FBlockSize);
end;

function TVirtualFileSystem.SecondNextFreeBlock(): int64;
begin
  //Determine the second next free block (filesize / FBlockSize);
  result := (FDataFile.Size div FBlockSize)+1;
end;

procedure TVirtualFileSystem.WriteFirstDeletedFileEntry();
var
  dummyid: int64;
begin
  dummyid := 0;
  FDeleted := TVirtualFileStream.Create('/Deleted', fmCreate, self);
  FDeleted.Position :=0;
  FDeleted.Write(dummyid,sizeof(int64));
  FDeleted.SetSize(FDeleted.Position); //TODO: is this line needed
end;

procedure TVirtualFileSystem.WriteFirstLabelIndexEntry();
var
  LabelIndex : TFileLabel;
begin
  FLabelIndex := TVirtualFileStream.Create('/LabelIndex',fmCreate, self);
  FLabelIndex.Position := 0;

  LabelIndex.labelid := 0;
  LabelIndex.fileid := 0;
  FLabelIndex.Write(LabelIndex,sizeof(TFileLabel));

  LabelIndex.labelid := 0;
  LabelIndex.fileid := 1;
  FLabelIndex.Write(LabelIndex,sizeof(TFileLabel));

  LabelIndex.labelid := 0;
  LabelIndex.fileid := 2;
  FLabelIndex.Write(LabelIndex,sizeof(TFileLabel));

  FLabelIndex.SetSize(FLabelIndex.Position); //TODO: is this line needed
end;

procedure TVirtualFileSystem.WriteFirstDirectoryEntry();
var
  FileRecord : TFileInfo;
  pBuf : pointer;
begin
  fillchar(filerecord, SizeOf(TFileInfo),0); //clean up memory

  FileRecord.id := FNextFileId;
  FNextFileId := FNextFileId + 1;
  FileRecord.deleted := false;
  FileRecord.offset := 0;

  FileRecord.filename := '/';
  FileRecord.startblock := self.NextFreeBlock();
  FileRecord.filesize := SizeOf(TFileInfo);

  //write an empty block first
  getMem(pBuf, FUseableBlockSize);
  FillChar(pBuf^, FUseableBlockSize , 0);
  self.WriteBlock(1,0,0,pbuf);
  freemem(pbuf);

  //writes first directory entry
  self.WriteBlock(1,0,0,@FileRecord, 0, SizeOf(TFileInfo));

  FDir := TVirtualFileStream.Create('/', fmCreate, self);
end;

procedure TVirtualFileSystem.WriteHeader();
var
  FileRecord : TFileInfo;
  pBuf: pointer;
begin
  //TODO: needs to write real header info
  fillchar(filerecord, SizeOf(TFileInfo),0); //clean up memory

  FileRecord.filename := 'Header Data';
  FileRecord.startblock := 0;

  //write an empty block first
  getMem(pBuf, FUseableBlockSize);
  FillChar(pBuf^, FUseableblockSize , 0);
  self.WriteBlock(0,0,0,pbuf);
  freemem(pbuf);

  //writes the header entry
  self.WriteBlock(0,0,0,@FileRecord, 0, SizeOf(TFileInfo));
end;

//------------------------------------------------------------------------------

procedure TVirtualFileSystem.GetFileList(List: TStrings);
var
  i,m: Integer;
  FileRecordEntry: TFileInfo;
  OrigFilePos : int64;
begin
  OrigFilePos:= FDir.FPosition;
  FDir.FPosition :=0;
  i:=0;
  m:= (FDir.Size div SizeOf(TFileInfo)) ;
  while i<=m-1 do
  begin
    FileRecordEntry.filename := 'Not Found';
    FileRecordEntry.filesize := 0;
    FileRecordEntry.startblock := 0;
    FDir.Read(FileRecordEntry, SizeOf(TFileInfo) );
    //TODO: clean up to only return filename
    if FileRecordEntry.deleted = false then
    begin
      List.Add(FileRecordEntry.filename+'-'+IntToStr(FileRecordEntry.filesize)+'-'+IntToStr(FileRecordEntry.startblock)+'- ID:'+IntToStr(FileRecordEntry.id) );
    end;
    i:=i+1;
  end;
  FDir.FPosition :=OrigFilePos;
end;

procedure TVirtualFileSystem.GetFileList(aname: string; List: TStrings);
var
  i,m: Integer;
  FileRecordEntry: TFileInfo;
  LabelEntry: TFileInfo;
  FileLabel: TFileLabel;
  OrigFilePos : int64;
  l,ml: integer;
  FoundEntries: TBlockList;
  NumFoundEntries: integer;
  FileRecordIdFound : boolean;
begin
  FileRecordIdFound := false;
  //find id for aname;
  self.FindFile(aname,LabelEntry);

  FLabelIndex.FPosition :=0;
  numfoundentries:=0;
  l:=0;
  ml:= (FLabelIndex.Size div SizeOf(TFileLabel) );
  while l <= ml-1 do
  begin
    FileLabel.labelid := 0;
    FileLabel.fileid := 0;
    FLabelIndex.Read(FileLabel,SizeOf(TFileLabel) );
    if FileLabel.labelid = LabelEntry.id then
    begin
      numfoundentries := numfoundentries +1;
      setlength(FoundEntries, numfoundentries);
      FoundEntries[numfoundentries-1]:=FileLabel.fileid;
    end;
    l:=l+1;
  end;

  OrigFilePos:= FDir.FPosition;
  FDir.FPosition :=0;
  i:=0;
  m:= (FDir.Size div SizeOf(TFileInfo)) ;
  while i<=m-1 do
  begin
    FileRecordIdFound:=false;
    FileRecordEntry.filename := 'Not Found';
    FileRecordEntry.filesize := 0;
    FileRecordEntry.startblock := 0;
    FDir.Read(FileRecordEntry, SizeOf(TFileInfo) );

    for l:=0 to numfoundentries-1 do
    begin
      if FoundEntries[l] = FileRecordEntry.id then
      begin
        FileRecordIdFound:=true;
        Break;
      end;
    end;

    if (FileRecordEntry.deleted = false) and (FileRecordIdFound) then
    begin
      //TODO: clean up to only return filename
      List.Add(FileRecordEntry.filename+'-'+IntToStr(FileRecordEntry.filesize)+'-'+IntToStr(FileRecordEntry.startblock)+'- ID:'+IntToStr(FileRecordEntry.id) );
    end;
    i:=i+1;
  end;
  FDir.FPosition :=OrigFilePos;

  setlength(FoundEntries, 0);
  FoundEntries :=nil;
end;

function TVirtualFileSystem.FindFile(aname: string; var afilerecord: TFileInfo): int64;
var
  FileRecordEntry: TFileInfo;
  i,m: integer;
  foundpos: integer;
  OrigFilePos: int64;
begin

  result :=0;

  FileRecordEntry.id := 0;
  FileRecordEntry.filename := 'Not Found';
  FileRecordEntry.filesize := 0;
  FileRecordEntry.startblock := 0;
  FileRecordEntry.deleted := true;
  FileRecordEntry.offset := 0;

  afilerecord :=FileRecordEntry;
  foundpos:=0;
  if aname = '/' then
  begin
    //read first dir entry
    //TODO: can this be simplified by assuming a fixed /
    self.ReadBlock(1,FileRecordEntry,0,SizeOf(TFileInfo));

    //compare ( is the first entry realy an / )
    if FileRecordEntry.filename = aname then
    begin
      result := foundpos * SizeOf(TFileInfo);
      afilerecord := FileRecordEntry;
    end;
  end
  else
  begin
    //browse through FileRecord(s) in virtual file stream
    OrigFilePos:=FDir.FPosition;
    FDir.FPosition :=0;
    i:=0;
    m:= (FDir.Size div SizeOf(TFileInfo));
    while i<=m-1 do
    begin
      FDir.Read(FileRecordEntry, SizeOf(TFileInfo) );
      //compare
      if FileRecordEntry.filename = aname then
      begin
        result := FDir.FPosition-SizeOf(TFileInfo) ;
        afilerecord := FileRecordEntry;
        FDir.FPosition :=OrigFilePos;
        break;
      end;
      i:=i+1;
    end;
    FDir.FPosition :=OrigFilePos;
  end;
end;


function TVirtualFileSystem.AddFile(aname: string; astartblockid: int64; aSize: int64): TFileInfo;
var
  FileRecord: TFileInfo;
begin
  FDir.Position := FDir.Size; //go to end of virtual file stream
  fillchar(filerecord, SizeOf(TFileInfo),0); //clean up memory
  FileRecord.filename := aname;
  FileRecord.startblock := astartblockid;
  FileRecord.filesize := aSize;

  FileRecord.id := FNextFileId;
  FileRecord.deleted := false;
  FileRecord.offset :=0;

  FDir.Write(FileRecord, SizeOf(TFileInfo));
  FDir.SetSize(FDir.Position); //make dirfile larger...

  FNextFileId := FNextFileId + 1;

  result := FileRecord;
end;

procedure TVirtualFileSystem.AddLabel(aname: string);
begin
  self.AddFile(aname, 0, 0);
end;

procedure TVirtualFileSystem.AssignLabel(afileid: int64; alabelid: int64);
var
  LabelIndex: TFileLabel;
begin
  if FLabelIndex <> nil then
  begin
    LabelIndex.labelid := alabelid;
    LabelIndex.fileid := afileid;
    FLabelIndex.Write(LabelIndex,sizeof(TFileLabel));
  end;
end;

procedure TVirtualFileSystem.AssignLabel(afileid: int64; alabelname: string);
var
  foundlabel: TFileInfo;
begin
  findfile(alabelname, foundlabel);
  self.AssignLabel(afileid, foundlabel.id);
end;

procedure TVirtualFileSystem.ChangeFile(aname: string; afilerecord: TFileInfo);
var
  OrigFileRecord: TFileInfo;
  NewFileRecord: TFileInfo;
  OrigFileRecordPos: int64;
begin
  FillChar(NewFileRecord, SizeOf(TFileInfo),0);

  NewFileRecord.id := aFileRecord.id;
  NewFileRecord.filename := aFileRecord.filename;
  NewFileRecord.filesize := aFileRecord.filesize;
  NewFileRecord.startblock := aFileRecord.startblock;
  NewFileRecord.deleted := aFileRecord.deleted;
  NewFileRecord.offset := 0;

  OrigFileRecordPos := self.FindFile(aname,OrigFileRecord);
  if OrigFileRecord.filename <> 'Not Found' then
  begin
    if OrigFileRecordPos > 0 then
      FDir.FPosition := OrigFileRecordPos
    else
      FDir.FPosition := 0;

    FDir.Write(NewFileRecord, SizeOf(TFileInfo) );
  end;
end;

procedure TVirtualFileSystem.DeleteBlock(ABlockId: int64);
var
  cleanbuffer: pointer;
begin
  FDeleted.Position := FDeleted.Size;
  FDeleted.Write(ABlockId, sizeof(int64) );

  //clean the deleted block ...
  getmem(cleanbuffer, FUseableBlockSize);
  fillchar(cleanbuffer^, FUseableBlockSize,'x');
  self.WriteBlock(ABlockId,0,0,cleanbuffer);
  freemem(cleanbuffer);
end;

function TVirtualFileSystem.DeleteFile(aname: string): boolean;
var
  OrigFileRecord: TFileInfo;
  NewRecord: TFileInfo;
  TempBlockList: TBLockList;
  i: integer;
  cleanbuffer: pointer;
begin
  //TODO: check if file is open
  result := false;
  self.FindFile(aname,OrigFileRecord);
  if OrigFileRecord.filename <> 'Not Found' then
  begin
    TempBlockList := self.GetBlockList(origfilerecord);
    for i:=High(TempBlockList) downto 0 do
    begin
      FDeleted.Position := FDeleted.Size;
      FDeleted.Write(TempBlockList[i], sizeof(int64) ); 
      //write empty block
      getmem(cleanbuffer, FUseableBlockSize);
      fillchar(cleanbuffer^, FUseableBlockSize,'x');
      self.WriteBlock(TempBlockList[i],0,0,cleanbuffer);
      freemem(cleanbuffer);
    end;
    //now clean or delete directory entry ...
    NewRecord.startblock := 0;
    NewRecord.filesize := 0;
    NewRecord.filename := '';  //need something better or empty
    NewRecord.deleted := true;
    self.ChangeFile(aname, NewRecord);

    setlength(tempblocklist,0);
    tempblocklist:=nil;

    result := true;
  end;
end;

function TVirtualFileSystem.GetDeletedBlockList(): TBlockList;
var
  test: int64;
  i: integer;
begin
  FDeleted.Position := 0;
  for i :=0 to (FDeleted.Size div sizeof(int64))-1 do
  begin
    FDeleted.Read(test, sizeof(int64) );
    setlength(result, i+1);
    result[i]:=test;
  end;
end;

//------------------------------------------------------------------------------

function TVirtualFileSystem.GetBlockList(afile: TFileInfo): TBlockList;
var
  i: integer;
  n: int64;
  SIZE: integer;
  FILESIZE: integer;
begin
  FILESIZE:=afile.filesize;
  //SIZE:= FBlockSize - (2*SizeOf(int64) );
  SIZE:= FUseableBlockSize;

  if afile.filename = 'Not Found' then
    result := nil
  else
  begin
    SetLength(result, 1);
    n:=afile.startblock;
    result[0] := n;
  end;

  i:=1;

  if FILESIZE > SIZE then
  begin
    while n <> 0 do
    begin

      FdataFile.Position := n * FBlockSize ;
      //FDataFile.ReadBuffer(p, sizeof(p)); //pff do not read previous anymore
      FDataFile.ReadBuffer(n, sizeof(n));
      //prevent adding a 0 as last element to the list
      if n <> 0 then
      begin
        SetLength(result, i+1);
        result[i] := n;
      end
      else
        break; //exit on 0
      i:=i+1;
    end;
  end;
end;

//------------------------------------------------------------------------------

function TVirtualFileSystem.ReadVirtualFileStreamBuffer(var buffer; Position, Count: Integer; BlockList: TBlockList): LongInt;
var
   ibegin, iend: integer;
   iBeginBlock, iEndBlock: integer;
   SIZE: integer;
   i: integer;
   mySize: integer;
   testteller: int64;
begin

  ibegin := Position; //beginposition in virtual filestream
  iEnd   := Position+count-1; //endposition in virtual filestream

  SIZE:= FUseableBlockSize; //blocksize corrected with prev next

  iBeginBlock := iBegin div Size; //block id for beginposition
  iEndBlock := iEnd div Size; //block id for endposition

  //if position is not in the first block of virtual file then correct ibegin and iend
  if iBeginBlock > 0 then
  begin
      iBegin := iBegin - (iBeginBlock*SIZE);
      iEnd := iEnd - (iBeginBlock*SIZE);
  end;

  testteller:=0; //read bytes
  mysize:=iEnd;

  //if we need to read from multiple blocks
  if iBeginBlock <> iEndBlock then
  begin

    for i:=iBeginBlock to iEndBlock do
    begin
      //first block
      if i=iBeginBlock then
      begin
      {$R-}
        self.ReadBlock(BlockList[i], Addr(TBuffer(@buffer)[0]), iBegin,  SIZE);
      {$R+}
        testteller := SIZE-iBegin;
        mysize := mysize - (SIZE-iBegin);
      end;

      //middle blocks read complete
      if (i>iBeginblock) and (i<iEndblock) then
      begin
      {$R-}
        self.ReadBlock(BlockList[i], Addr(TBuffer(@buffer)[testteller]) );
      {$F+}
        testteller := testteller+SIZE;
        MySize := MySize - SIZE;
      end;

      //last block
      if i=iEndBlock then
      begin
      {$R-}
        self.ReadBlock(BlockList[i], Addr(TBuffer(@buffer)[testteller]), 0, (mySize-iBegin)+1 );
      {$R+}
        testteller := testteller + (mysize-iBegin)+1 ;
      end;
    end;
  end
  else
  begin
    //smaller then count so read only first block
    self.ReadBlock(BlockList[iBeginBlock], buffer, ibegin, iend+1); 
    testteller := count;
 end;

 //check if we read the expected amount of bytes
 if testteller<> count then
  result := -1
 else
  result:=testteller;

end;

function TVirtualFileSystem.WriteVirtualFileStreamBuffer(const buffer; Position, Count: Integer; var BlockList: TBlockList ): LongInt;
var
  writebuffer: pointer;
  i: integer;
  ibegin, iend: integer;
  iBeginBlock, iEndBlock: integer;
  Size, mysize: integer;
  b,nb: int64;
  blocklistsize: integer;
  testteller: int64;
  existingblock: boolean;

begin
  existingblock:= false;

  ibegin := Position; //beginposition in virtual filestream
  iEnd   := Position+count-1; //beginposition in virtual filestream -1 or else disaster

  SIZE:= FUseableBlockSize; //blocksize corrected with prev next

  iBeginBlock := iBegin div Size; //blockid for first block
  iEndBlock := iEnd div Size; //blockid for last block

  blockListSize:=High(BlockList)+1; //get the number of blocks

  system.GetMem(writebuffer, SIZE); //make a writebuffer

  testteller := 0; //read bytes

  //if position is not in the first block of virtual file then correct ibegin and iend
  if iBeginBlock > 0 then
  begin
    iBegin := iBegin - (iBeginBlock*SIZE);
    iEnd := iEnd - (iBeginBlock*SIZE);
  end;

  mySize:=iEnd;

  //if we need to read from multiple blocks
  if iBeginBlock <> iEndBlock then
  begin
    //for each block from begin to endblock
    for i:=iBeginBlock to iEndBlock do
    begin
      existingblock := false;
      b:=0;
      nb:=0;
      self.GetBlockId(existingblock, iEndBlock, blocklistsize, BlockList, i, b, nb);

      if b <> 0 then
      begin

        //first block
        if i=iBeginBlock then
        begin
          if existingblock = false then
          begin
            fillchar(writebuffer^, SIZE, 0); //clean the write buffer
            self.WriteBlock(b,nb,0,writebuffer);
          end;
          {$R-}
          self.WriteBlock(b,nb,0, Addr(TBuffer(@buffer)[0]), iBegin,  SIZE);
          {$R+}
          testteller := SIZE-iBegin;
          mysize := mysize - (SIZE-iBegin);
        end;

        //middle blocks read complete
        if (i>iBeginblock) and (i<iEndblock) then
        begin
          {$R-}
          self.WriteBlock(b,nb,0, Addr(TBuffer(@buffer)[testteller]),0, SIZE );
          {$R+}
          testteller := testteller+SIZE;
          MySize := MySize - SIZE;
        end;

        //last block
        if i=iEndBlock then
        begin
          if existingblock = false then
          begin
            fillchar(writebuffer^, SIZE, 0); //clean the write buffer
            self.WriteBlock(b,nb,0,writebuffer);
          end;
          {$R-}
          self.WriteBlock(b,nb,0, Addr(TBuffer(@buffer)[testteller]), 0, (mySize-iBegin)+1 );
          {$R+}
          testteller := testteller + (mysize-iBegin)+1 ;
        end;

      end
      else
      begin
        raise Exception.Create('Block id cannot be 0');
      end;
    end;
  end
  else
  begin
    existingblock := false;
    //determine what block to use
    b:=0;
    nb:=0;
    GetBlockId(existingblock, iEndBlock, blocklistsize, BlockList, iBeginBlock, b, nb);
    if existingblock = false then
    begin
      fillchar(writebuffer^, SIZE, 0); //clean the write buffer
      self.WriteBlock(b,nb,0,writebuffer); //a new block needs to be written completely
    end;

    self.WriteBlock(b, nb, 0, buffer, ibegin, iend+1);
    testteller := count;
  end;

  system.FreeMem(writebuffer); //clean up the write buffer

  //check if we read the expected amount of bytes
  if testteller<> count then
    result := -1
  else
    result:=testteller;

end;

procedure TVirtualFileSystem.GetBlockId(var existingblock: Boolean; endblockid: Integer; var blocklistsize: Integer; var BlockList: TBlockList; sequenceid: Integer; var blockid: Int64; var nextblockid: Int64);
var
  tnb: Int64;
  inextfreeblock: int64;
  isecondnextfreeblock: int64;
begin
  isecondnextfreeblock :=0;
  //determine what block to use or create
  if sequenceid > High(BlockList) then
  begin
    inextfreeblock := self.GetFreeBlockFromDeletedList();
    if inextfreeblock = 0 then
    begin
      blockid := self.NextFreeBlock;
    end
    else
    begin
      blockid:=inextfreeblock;
      removeblockfromdeletedlist(inextfreeblock); //b is always used so it can be removed at once
    end;

    isecondnextfreeblock := self.GetFreeBlockFromDeletedList();
    if isecondnextfreeblock = 0 then
    begin
      if inextfreeblock = 0 then
        nextblockid:=self.SecondNextFreeBlock
      else
        nextblockid:=self.NextFreeBlock;
    end
    else
    begin
      nextblockid := isecondnextfreeblock;
      //we cannot yet delete it from blocklist here yet...
    end;
    if BlockList = nil then
    begin
      BlockListSize := 0;
      BlockListSize := BlockListSize + 1;
      SetLength(BlockList, BlockListSize);
    end
    else
    begin
      BlockListSize := BlockListSize + 1;
      SetLength(BlockList, BlockListSize);
    end;
    BlockList[sequenceid] := blockid;
  end
  else
  begin
    tnb := 0;
    blockid := BlockList[sequenceid];
    if (sequenceid + 1) > High(BlockList) then
    begin
      isecondnextfreeblock := self.GetFreeBlockFromDeletedList();
      if isecondnextfreeblock = 0 then
      begin
        tnb:=self.NextFreeBlock;
      end
      else
      begin
        tnb := isecondnextfreeblock;
        //we cannot yet delete it from blocklist here yet...
      end;

    end
    else
    begin
      if (sequenceid + 1 > High(BlockList)) then
        nextblockid := 0
      else
        nextblockid := BlockList[sequenceid + 1];
    end;

    existingblock := true;
    if tnb > 0 then
      nextblockid := tnb;
  end;

  if sequenceid >= High(BlockList) then
    //EndBlockId then correct nb to 0
    if sequenceid = endblockid then //do we need to determine this here?
      nextblockid := 0;

  //detect if nextfreeblocks are used
  //if so delete them from the FDeleted list
  if nextblockid = isecondnextfreeblock then
  begin
    if isecondnextfreeblock <> 0 then
    begin
      //if we realy used the block then remove it from the list
      self.RemoveBlockFromDeletedList(isecondnextfreeblock);
      //and add it to the blocklist?
      BlockListSize:=BlockListSize+1;
      setlength(BlockList,BlockListSize);
      BlockList[BlockListSize-1]:=isecondnextfreeblock;
    end;
  end;

end;

procedure TVirtualFileSystem.GetDeletedBlock(List: TStrings);
var
  blocklist : TBlockList;
  i: integer;
begin
  blocklist := self.GetDeletedBlockList;
  for i:=0 to high(blocklist) do
  begin
    List.Add(IntToStr(blocklist[i]));
  end;
end;

end.

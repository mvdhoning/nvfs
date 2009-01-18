unit DemoForm;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, nvfs, StdCtrls, StrUtils;

type
  TForm1 = class(TForm)
    bNew: TButton;
    bOpen: TButton;
    bClose: TButton;
    eFileName: TEdit;
    cbReadOnly: TCheckBox;
    lTest: TLabel;
    mTest: TMemo;
    eMemoName: TEdit;
    bFillMemo: TButton;
    Button1: TButton;
    bDynWrite: TButton;
    bDynChange: TButton;
    bClearMemo: TButton;
    bReadDirectory: TButton;
    bTestWriteDir: TButton;
    lbFiles: TListBox;
    bDelete: TButton;
    bDebugDeleted: TButton;
    procedure bDebugDeletedClick(Sender: TObject);
    procedure bDeleteClick(Sender: TObject);
    procedure lbFilesClick(Sender: TObject);
    procedure bTestWriteDirClick(Sender: TObject);
    procedure bReadDirectoryClick(Sender: TObject);
    procedure bClearMemoClick(Sender: TObject);
    procedure bDynChangeClick(Sender: TObject);
    procedure bDynWriteClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure bFillMemoClick(Sender: TObject);
    procedure bNewClick(Sender: TObject);
    procedure bCloseClick(Sender: TObject);
    procedure bOpenClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;
  TestDataFile : TVirtualFileSystem;

implementation

{$R *.dfm}

procedure TForm1.bOpenClick(Sender: TObject);
begin
  TestDataFile := TVirtualFileSystem.Create();
  TestDataFile.FileName := eFileName.Text;
  TestDataFile.Open;

  //lTest.Caption := TestDataFile.ReadTest();

  //TestDataFile.ReadDummyLarge();
  //lTest.Caption := TestDataFile.ReadDummyRecord();

  bClose.Enabled := true;
  bNew.Enabled := false;
  bOpen.Enabled := false;
  eFileName.Enabled := false;
end;

procedure TForm1.bCloseClick(Sender: TObject);
begin
  TestDataFile.Close();
  bClose.Enabled := false;
  bNew.Enabled := true;
  bOpen.Enabled := true;
  eFileName.Enabled := true;
  lbFiles.Items.Clear;
end;

procedure TForm1.bNewClick(Sender: TObject);
begin
  lTest.Caption := IntToStr(SizeOf(TFileInfo));
  TestDataFile := TVirtualFileSystem.Create();
  TestDataFile.FileName := eFileName.Text;
  TestDataFile.New();
  bClose.Enabled := true;
  bNew.Enabled := false;
  bOpen.Enabled := false;
  eFileName.Enabled := false;
end;

procedure TForm1.bFillMemoClick(Sender: TObject);
var
  i: integer;
begin
  for i:=0 to 1024 do
  begin
    mTest.Lines.Add('Dit is een test.'+IntToStr(i)+'!');
  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  MyStream: TVirtualFileStream;
begin
  MyStream := TVirtualFileStream.Create(eMemoName.Text, fmOpenRead, TestDataFile);

//  mTest.Lines.SaveToStream(MyStream);

  //

  mTest.Lines.LoadFromStream(MyStream);

  MyStream.Free;
end;



procedure TForm1.bDynWriteClick(Sender: TObject);
var
  MyStream: TVirtualFileStream;
begin
  MyStream:= TVirtualFileStream.Create(eMemoName.Text, fmCreate, TestDataFile);
  mTest.Lines.SaveToStream(MyStream);
  FreeAndNil(MyStream);
  lTest.Caption := 'OK';
end;

procedure TForm1.bDynChangeClick(Sender: TObject);
var
  MyStream: TVirtualFileStream;
  MyText: pchar;
begin
  MyStream:=TVirtualFileStream.Create(eMemoName.Text, fmOpenReadWrite, TestDataFile);

  GetMem(MyText, 10+512);
  FillChar(MyText^, 10+512, 'x');

  MyStream.Position := 200+512;
 // MyText:=pchar('hello world at pos 200');
  MyStream.Write(MyText^, 10+511 );

  MyStream.Free;
end;

procedure TForm1.bClearMemoClick(Sender: TObject);
begin
  mTest.Lines.Clear();
  mTest.Lines.Add('mTest');
end;

procedure TForm1.bReadDirectoryClick(Sender: TObject);
begin
  lbFiles.Items.Clear();
  TestDataFile.GetFileList('/',lbFiles.Items);
  //TestDataFile.GetFileList(lbFiles.Items);
end;

procedure TForm1.bTestWriteDirClick(Sender: TObject);
var
  MyRecord: TFileInfo;
  MyStream: TVirtualFileStream;
  MyFileStream: TFileStream;
  i: integer;
begin
//mFileList.Lines.Clear();
lbFiles.Items.Clear();


//Write en of Read gaat de fout in met posities....

  //Write
  MyStream:=TVirtualFileStream.Create('mytest.dat', fmCreate, TestDataFile);
  MyFileStream:=TFileStream.Create('mytest.dat',fmcreate);

//  TestDataFile.GetFileList(mFileList.Lines);
  TestDataFile.GetFileList(lbFiles.Items);

  for i:=0 to 3 do
  begin
    FillChar(MyRecord, 272, 0);
    MyRecord.filename:='mytest'+IntToStr(i)+'.txt';
    MyRecord.filesize:=7;
    MyRecord.startblock:=i;
    MyStream.Write(MyRecord, SizeOf(TFileInfo) );
    //MyFileStream.Write(MyRecord, SizeOf(TFileRecord) );
    //MyStream.Position := MyStream.Position + 1;
    //mFileList.Lines.Add(MyRecord.filename+' '+IntToStr(MyStream.Position) );
    lbFiles.Items.Add( MyRecord.filename+' '+IntToStr(MyStream.Position) )
  end;

  //MyFileStream.Free;
  MyStream.Free;


  //Read
  TestDataFile.GetFileList(lbFiles.Items);
  //mFileList.Refresh;

  MyStream:=TVirtualFileStream.Create('mytest.dat', fmOpenRead, TestDataFile);
  MyStream.Position :=0;
  for i:=0 to 3 do
  begin
    //MyStream.Position := i * SizeOf(MyRecord); //eigenlijk niet nodig?

    FillChar(MyRecord, 272, 0);
    MyRecord.filename:='';
    MyRecord.filesize:=0;
    MyRecord.startblock:=0;

//    MyStream.Position :=0;
    MyStream.Read(MyRecord, SizeOf(TFileInfo) );
    //MyStream.Position := MyStream.Position +1;
    lbFiles.Items.Add(MyRecord.filename +' '+IntToStr(MyStream.Position));
  end;

  MyStream.Free;


end;

procedure TForm1.lbFilesClick(Sender: TObject);
var
  test:string;
begin
test := lbFiles.items[lbFiles.itemindex];
eMemoName.Text := LeftStr(test,Pos('-',test)-1);

Button1Click(self);
end;

procedure TForm1.bDeleteClick(Sender: TObject);
begin
  TestDataFile.DeleteFile(eMemoName.Text);
end;

procedure TForm1.bDebugDeletedClick(Sender: TObject);
begin
  TestDataFile.GetDeletedBlock(lbFiles.Items);
end;

end.

program Test1;

uses
  Forms,
  DemoForm in 'DemoForm.pas' {Form1};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

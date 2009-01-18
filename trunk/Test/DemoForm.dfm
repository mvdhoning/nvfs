object Form1: TForm1
  Left = 0
  Top = 0
  Width = 756
  Height = 494
  Caption = 'Form1'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object lTest: TLabel
    Left = 96
    Top = 80
    Width = 23
    Height = 13
    Caption = 'lTest'
  end
  object bNew: TButton
    Left = 8
    Top = 16
    Width = 75
    Height = 25
    Caption = 'bNew'
    TabOrder = 0
    OnClick = bNewClick
  end
  object bOpen: TButton
    Left = 8
    Top = 48
    Width = 75
    Height = 25
    Caption = 'bOpen'
    TabOrder = 1
    OnClick = bOpenClick
  end
  object bClose: TButton
    Left = 8
    Top = 80
    Width = 75
    Height = 25
    Caption = 'bClose'
    Enabled = False
    TabOrder = 2
    OnClick = bCloseClick
  end
  object eFileName: TEdit
    Left = 96
    Top = 48
    Width = 121
    Height = 21
    TabOrder = 3
    Text = 'test.dat'
  end
  object cbReadOnly: TCheckBox
    Left = 232
    Top = 48
    Width = 97
    Height = 17
    Caption = 'cbReadOnly'
    TabOrder = 4
  end
  object mTest: TMemo
    Left = 8
    Top = 112
    Width = 529
    Height = 329
    Lines.Strings = (
      'mTest')
    TabOrder = 5
  end
  object eMemoName: TEdit
    Left = 184
    Top = 80
    Width = 121
    Height = 21
    TabOrder = 6
    Text = 'test.txt'
  end
  object bFillMemo: TButton
    Left = 392
    Top = 48
    Width = 75
    Height = 25
    Caption = 'bFillMemo'
    TabOrder = 7
    OnClick = bFillMemoClick
  end
  object Button1: TButton
    Left = 312
    Top = 16
    Width = 75
    Height = 25
    Caption = 'LoadMemo'
    TabOrder = 8
    OnClick = Button1Click
  end
  object bDynWrite: TButton
    Left = 392
    Top = 16
    Width = 75
    Height = 25
    Caption = 'SaveMemo'
    TabOrder = 9
    OnClick = bDynWriteClick
  end
  object bDynChange: TButton
    Left = 224
    Top = 16
    Width = 75
    Height = 25
    Caption = 'bDynChange'
    TabOrder = 10
    OnClick = bDynChangeClick
  end
  object bClearMemo: TButton
    Left = 144
    Top = 16
    Width = 75
    Height = 25
    Caption = 'bClearMemo'
    TabOrder = 11
    OnClick = bClearMemoClick
  end
  object bReadDirectory: TButton
    Left = 552
    Top = 48
    Width = 185
    Height = 25
    Caption = 'bReadDirectory'
    TabOrder = 12
    OnClick = bReadDirectoryClick
  end
  object bTestWriteDir: TButton
    Left = 552
    Top = 16
    Width = 185
    Height = 25
    Caption = 'bTestWriteDir'
    TabOrder = 13
    OnClick = bTestWriteDirClick
  end
  object lbFiles: TListBox
    Left = 552
    Top = 80
    Width = 185
    Height = 337
    ItemHeight = 13
    TabOrder = 14
    OnClick = lbFilesClick
  end
  object bDelete: TButton
    Left = 392
    Top = 80
    Width = 75
    Height = 25
    Caption = 'bDelete'
    TabOrder = 15
    OnClick = bDeleteClick
  end
  object bDebugDeleted: TButton
    Left = 472
    Top = 48
    Width = 75
    Height = 25
    Caption = 'bDebugDeleted'
    TabOrder = 16
    OnClick = bDebugDeletedClick
  end
end

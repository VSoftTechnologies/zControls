unit Testing.Inspector;

{ Shared code for the inspector tests: the base fixture, and helpers that drive the
  inspector as a user would. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Vcl.StdCtrls,
  DUnitX.TestFramework,
  zObjInspector;

type
  { Base for the fixtures. Each fixture gets a shown form, and each test a new
    inspector on it, so a test can't leave state behind for the next one.

    VCL catches exceptions raised inside message handlers and shows a modal dialog,
    which would block the run. While a test runs they are collected instead, and the
    test fails in TearDown. A test that expects them sets FExpectedExceptions, and
    checks it has gone back to 0. }
  TInspectorTestCase = class
  protected
    FForm: TForm;
    FInspector: TzObjectInspector;
    FExpectedExceptions: Integer;
    FUnexpectedExceptions: string;
    procedure HandleException(Sender: TObject; E: Exception);
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
  end;

function FindTopItem(insp: TzObjectInspector; const name: string): PPropItem;
function FindEdit(insp: TzObjectInspector): TzPropInspEdit;
procedure PaintInspector(insp: TzObjectInspector);

{ Selects a top-level row with the inspector focused, as a click would, and returns
  the editor. }
function SelectRow(insp: TzObjectInspector; const name: string): TzPropInspEdit;

{ Another control on the form, to move the focus to. }
function NewOtherEdit(form: TForm): TEdit;

procedure TypeText(edit: TzPropInspEdit; const text: string);

{ Types text into the row's editor and presses Enter, as a user would. }
procedure EnterText(insp: TzObjectInspector; const row, text: string);

{ Clicks the dropdown button of the selected row, as a user would. }
function OpenDropDown(insp: TzObjectInspector): TzPopupListBox;

{ Posted (not SendInput) so that nothing can reach another application; goes through
  TApplication.ProcessMessage like a real key, including the dialog-key handling. }
procedure PostKey(wnd: HWND; key: Word);

implementation

uses
  Winapi.Messages,
  Vcl.Graphics;

{ TInspectorTestCase }

procedure TInspectorTestCase.HandleException(Sender: TObject; E: Exception);
begin
  if FExpectedExceptions > 0 then
  begin
    Dec(FExpectedExceptions);
    Log(TLogLevel.Information, 'expected exception reported: ' + E.ClassName + ': ' + E.Message);
    Exit;
  end;
  if FUnexpectedExceptions <> '' then
    FUnexpectedExceptions := FUnexpectedExceptions + '; ';
  FUnexpectedExceptions := FUnexpectedExceptions + E.ClassName + ': ' + E.Message;
end;

procedure TInspectorTestCase.SetupFixture;
begin
  FForm := TForm.Create(nil);
  FForm.SetBounds(100, 100, 400, 500);
  FForm.Show;
end;

procedure TInspectorTestCase.TearDownFixture;
begin
  FreeAndNil(FForm);
end;

procedure TInspectorTestCase.Setup;
begin
  FExpectedExceptions := 0;
  FUnexpectedExceptions := '';
  Application.OnException := HandleException;
  FInspector := TzObjectInspector.Create(FForm);
  FInspector.Parent := FForm;
  FInspector.SetBounds(0, 0, 380, 460);
end;

procedure TInspectorTestCase.TearDown;
var
  unexpected: string;
begin
  try
    FreeAndNil(FInspector);
  finally
    Application.OnException := nil;
    unexpected := FUnexpectedExceptions;
    FUnexpectedExceptions := '';
    FExpectedExceptions := 0;
  end;
  if unexpected <> '' then
    Assert.Fail('exception inside a message handler: ' + unexpected);
end;

{ helpers }

function FindTopItem(insp: TzObjectInspector; const name: string): PPropItem;
var
  i: Integer;
  item: PPropItem;
begin
  result := nil;
  for i := 0 to insp.Items.Count - 1 do
  begin
    item := insp.Items.Items[i];
    if (item^.Parent = nil) and (not item^.IsCategory) and SameText(item^.Name, name) then
      Exit(item);
  end;
end;

function FindEdit(insp: TzObjectInspector): TzPropInspEdit;
var
  i: Integer;
begin
  result := nil;
  for i := 0 to insp.ControlCount - 1 do
    if insp.Controls[i] is TzPropInspEdit then
      Exit(TzPropInspEdit(insp.Controls[i]));
end;

procedure PaintInspector(insp: TzObjectInspector);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.SetSize(insp.Width, insp.Height);
    insp.PaintTo(bmp.Canvas.Handle, 0, 0);
  finally
    bmp.Free;
  end;
end;

function SelectRow(insp: TzObjectInspector; const name: string): TzPropInspEdit;
var
  item: PPropItem;
begin
  item := FindTopItem(insp, name);
  Assert.IsTrue(item <> nil, name + ' row exists');
  { as a user would: focus is in the inspector when a row is selected }
  if insp.CanFocus then
    insp.SetFocus;
  insp.SelectItem(insp.VisibleItems.IndexOf(item));
  result := FindEdit(insp);
  Assert.IsTrue(Assigned(result) and result.Visible, 'editor visible on ' + name);
end;

function NewOtherEdit(form: TForm): TEdit;
begin
  result := TEdit.Create(nil);
  result.Parent := form;
  result.SetBounds(0, 465, 100, 21);
end;

procedure TypeText(edit: TzPropInspEdit; const text: string);
var
  i: Integer;
begin
  for i := 1 to Length(text) do
    SendMessage(edit.Handle, WM_CHAR, Ord(text[i]), 0);
end;

procedure EnterText(insp: TzObjectInspector; const row, text: string);
var
  edit: TzPropInspEdit;
begin
  edit := SelectRow(insp, row);
  edit.SelectAll;
  TypeText(edit, text);
  SendMessage(edit.Handle, WM_CHAR, VK_RETURN, 0);
end;

function OpenDropDown(insp: TzObjectInspector): TzPopupListBox;
var
  i: Integer;
  button: TzPropInspButton;
begin
  result := nil;
  button := nil;
  for i := 0 to insp.ControlCount - 1 do
    if insp.Controls[i] is TzPropInspButton then
      button := TzPropInspButton(insp.Controls[i]);
  Assert.IsTrue(Assigned(button) and button.Visible, 'dropdown button visible');
  SendMessage(button.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(2, 2));
  SendMessage(button.Handle, WM_LBUTTONUP, 0, MakeLParam(2, 2));
  for i := 0 to insp.ControlCount - 1 do
    if insp.Controls[i] is TzPopupListBox then
      result := TzPopupListBox(insp.Controls[i]);
  Assert.IsTrue(Assigned(result) and IsWindowVisible(result.Handle), 'dropdown open');
end;

procedure PostKey(wnd: HWND; key: Word);
var
  scan: LPARAM;
begin
  scan := LPARAM(MapVirtualKey(key, 0)) shl 16;
  PostMessage(wnd, WM_KEYDOWN, key, scan or 1);
  PostMessage(wnd, WM_KEYUP, key, scan or 1 or (LPARAM(3) shl 30));
  Application.ProcessMessages;
end;

end.

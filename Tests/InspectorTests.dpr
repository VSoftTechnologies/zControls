program InspectorTests;

{ Tests for TzObjectInspector. A console program that drives a real form and
  inspector: it prints PASS or FAIL for each check, and its exit code is the number of
  failures. Run RunTests.bat from a RAD Studio command prompt to build and run it for
  Win32 and Win64. The fixes the tests cover are described in CODE_REVIEW.md. }

{$APPTYPE CONSOLE}

uses
  PoisonMM in 'PoisonMM.pas', // must be first: turns use-after-free into access violations
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.DateUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.ExtCtrls,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  FloatConv,
  System.StrUtils,
  zCanvasStack,
  zUtils,
  zObjInspDialogs,
  zObjInspector;

var
  failures: Integer;
  expectedExceptions: Integer; // reported exceptions a test expects, see TExceptionSink

type
  { VCL catches exceptions raised inside message handlers and shows a modal dialog,
    which would block the run. Log them as failures instead. }
  TExceptionSink = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;

procedure TExceptionSink.HandleException(Sender: TObject; E: Exception);
begin
  if expectedExceptions > 0 then
  begin
    Dec(expectedExceptions);
    Writeln('  info  expected exception reported: ', E.ClassName, ': ', E.Message);
    Exit;
  end;
  Writeln('  FAIL  exception inside a message handler ', E.ClassName, ': ', E.Message);
  Inc(failures);
end;

procedure Check(condition: Boolean; const msg: string);
begin
  if condition then
    Writeln('  PASS  ', msg)
  else
  begin
    Writeln('  FAIL  ', msg);
    Inc(failures);
  end;
end;

function ItemsReference(insp: TzObjectInspector; obj: Pointer): Boolean;
var
  i: Integer;
  item: PPropItem;
begin
  result := False;
  for i := 0 to insp.Items.Count - 1 do
  begin
    item := insp.Items.Items[i];
    if (Pointer(item^.Instance) = obj) or (Pointer(item^.Component) = obj) then
      Exit(True);
  end;
end;

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

{ True when p is nil or points at one of the inspector's current items. }
function PropInfoValid(insp: TzObjectInspector; p: PPropItem): Boolean;
begin
  result := (p = nil) or (insp.Items.IndexOf(p) >= 0);
end;

function SelectRow(insp: TzObjectInspector; const name: string): TzPropInspEdit;
var
  item: PPropItem;
begin
  result := nil;
  item := FindTopItem(insp, name);
  Check(item <> nil, name + ' row exists');
  if item = nil then
    Exit;
  { as a user would: focus is in the inspector when a row is selected }
  if insp.CanFocus then
    insp.SetFocus;
  insp.SelectItem(insp.VisibleItems.IndexOf(item));
  result := FindEdit(insp);
  Check(Assigned(result) and result.Visible, 'editor visible on ' + name);
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

type
  TTestHandlers = class
  public
    FInspector: TzObjectInspector;
    FPaintDuringEnum: Boolean;
    FRejectChildren: Boolean;
    function BeforeAddItem(Sender: TControl; PItem: PPropItem): Boolean;
  end;

function TTestHandlers.BeforeAddItem(Sender: TControl; PItem: PPropItem): Boolean;
begin
  result := True;
  if FRejectChildren and (PItem^.Parent <> nil) then
    Exit(False);
  if FPaintDuringEnum then
  begin
    { stands in for anything that pumps messages while the items are enumerated }
    FPaintDuringEnum := False;
    PaintInspector(FInspector);
  end;
end;

procedure TestRootFreedNoOwner(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  oldPtr: Pointer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  insp.Component := btn;
  Check(insp.Items.Count > 0, 'items populated');
  oldPtr := btn;
  btn.Free;
  Check(insp.Component = nil, 'Component cleared when root freed');
  Check(not ItemsReference(insp, oldPtr), 'no item references the freed root');
  PaintInspector(insp);
  Application.ProcessMessages;
  Check(insp.Component = nil, 'Component still nil after message pump');
end;

procedure TestRootFreedSameOwner(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  oldPtr: Pointer;
begin
  btn := TButton.Create(form);
  btn.Parent := form;
  insp.Component := btn;
  oldPtr := btn;
  btn.Free;
  Check(insp.Component = nil, 'Component cleared when root (same owner) freed');
  Check(not ItemsReference(insp, oldPtr), 'no item references the freed root');
  PaintInspector(insp);
end;

procedure TestNestedComponentFreed(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  menu: TPopupMenu;
  menuItem: TMenuItem;
  item: PPropItem;
  oldPtr: Pointer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  menu := TPopupMenu.Create(nil);
  menuItem := TMenuItem.Create(menu);
  menuItem.Caption := 'Test';
  menu.Items.Add(menuItem);
  btn.PopupMenu := menu;
  try
    insp.Component := btn;
    item := FindTopItem(insp, 'PopupMenu');
    Check(item <> nil, 'PopupMenu row exists');
    if item = nil then
      Exit;
    insp.ExpandItem(item);
    Check(ItemsReference(insp, menu), 'expanded rows reference the popup menu');
    PaintInspector(insp);
    oldPtr := menu;
    menu.Free;
    Check(not ItemsReference(insp, oldPtr), 'no item references the freed popup menu (synchronous)');
    PaintInspector(insp);
    Application.ProcessMessages;
    Check(insp.Component = btn, 'root still inspected');
    Check(btn.PopupMenu = nil, 'button released its popup menu');
    Check(insp.Items.Count > 0, 'items rebuilt after message pump');
    Check(not ItemsReference(insp, oldPtr), 'rebuilt items do not reference the freed popup menu');
    PaintInspector(insp);
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestHostMemberFreed(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
  host: TzObjectHost;
  oldPtr: Pointer;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  try
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'Btn1');
    host.AddObject(btn2, 'Btn2');
    insp.Component := host;
    Check(ItemsReference(insp, btn1) and ItemsReference(insp, btn2), 'both hosted objects listed');
    oldPtr := btn1;
    btn1.Free;
    btn1 := nil;
    Check(not ItemsReference(insp, oldPtr), 'no item references the freed hosted object (synchronous)');
    PaintInspector(insp);
    Application.ProcessMessages;
    Check(insp.Component = host, 'host still inspected');
    Check(ItemsReference(insp, btn2), 'remaining hosted object listed after rebuild');
    Check(not ItemsReference(insp, oldPtr), 'freed hosted object not listed after rebuild');
    PaintInspector(insp);
  finally
    insp.Component := nil; // frees the host
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TestRemovedFromOwnerNotFreed(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
begin
  btn := TButton.Create(form);
  btn.Parent := form;
  try
    insp.Component := btn;
    form.RemoveComponent(btn);
    Application.ProcessMessages;
    Check(insp.Component = btn, 'Component kept when only removed from owner');
    Check(insp.Items.Count > 0, 'items kept when only removed from owner');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestInspectorFreedFirst(form: TForm);
var
  btn: TButton;
  insp: TzObjectInspector;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  insp := TzObjectInspector.Create(nil);
  insp.Parent := form;
  insp.Component := btn;
  insp.Free;
  btn.Free; // must not notify the freed inspector
  Check(True, 'freeing inspector before component does not crash');
end;

procedure TestRootFreedWithPendingEdit(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  item: PPropItem;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  insp.Component := btn;
  item := FindTopItem(insp, 'Caption');
  Check(item <> nil, 'Caption row exists');
  if item = nil then
    Exit;
  insp.SetFocus;
  insp.SelectItem(insp.VisibleItems.IndexOf(item));
  edit := FindEdit(insp);
  Check(Assigned(edit) and edit.Visible, 'editor visible on selected row');
  if not Assigned(edit) then
    Exit;
  Writeln('  info  editor has focus: ', GetFocus = edit.Handle);
  SendMessage(edit.Handle, WM_CHAR, Ord('X'), 0); // leaves uncommitted text
  btn.Free;
  Check(insp.Component = nil, 'Component cleared');
  Check(not edit.Visible, 'editor hidden after root freed');
  Application.ProcessMessages;
  PaintInspector(insp);
end;

{ ---- crash #2: PPropItem pointers dangle after a rebuild ---- }

procedure TestUpdatePropertiesWithPendingEdit(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    Check(GetFocus = edit.Handle, 'editor has focus (needed for this test)');
    TypeText(edit, 'X');
    insp.UpdateProperties(True);
    Check(btn.Caption = 'X', 'pending text committed before the rebuild');
    Check(PropInfoValid(insp, edit.PropInfo), 'editor points at a current item');
    Check(edit.Visible and Assigned(edit.PropInfo), 'editor re-attached after the rebuild');
    Check(GetFocus = edit.Handle, 'editor keeps focus across the rebuild');
    PaintInspector(insp);
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestCollapseAllWithPendingEdit(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    TypeText(edit, 'Y');
    insp.CollapseAll;
    Check(btn.Caption = 'Y', 'pending text committed before collapsing');
    Check(PropInfoValid(insp, edit.PropInfo), 'editor points at a current item');
    PaintInspector(insp);
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestComponentChangeWithPendingEdit(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
  edit: TzPropInspEdit;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn1.Caption := 'One';
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  btn2.Caption := 'Two';
  try
    insp.Component := btn1;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    TypeText(edit, 'Z');
    insp.Component := btn2;
    Check(btn1.Caption = 'Z', 'pending text committed to the previous component');
    Check(btn2.Caption = 'Two', 'new component untouched');
    Check(PropInfoValid(insp, edit.PropInfo), 'editor points at a current item');
    PaintInspector(insp);
  finally
    insp.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TestRebuildWithInvalidPendingText(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Default'); // Boolean: only False/True are accepted
    if edit = nil then
      Exit;
    TypeText(edit, 'xyz');
    expectedExceptions := 1;
    insp.UpdateProperties(True);
    Check(expectedExceptions = 0, 'rejected text reported once');
    expectedExceptions := 0;
    Check(not btn.Default, 'value unchanged');
    Check(PropInfoValid(insp, edit.PropInfo) and Assigned(edit.PropInfo), 'rebuild still happened and editor re-attached');
    Check(edit.Text = 'False', 'editor shows the current value again');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestExpandClickRebuildKeepsEditor(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
  handlers: TTestHandlers;
  index: Integer;
  pt: TPoint;
begin
  { With every child rejected, a class row has HasChild = True but Count = 0, so
    clicking its +/- takes the MouseDown path that rebuilds with UpdateItems. }
  handlers := TTestHandlers.Create;
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    handlers.FRejectChildren := True;
    insp.OnBeforeAddItem := handlers.BeforeAddItem;
    insp.Component := btn;
    edit := SelectRow(insp, 'Font');
    if edit = nil then
      Exit;
    index := insp.VisibleItems.IndexOf(FindTopItem(insp, 'Font'));
    pt := insp.PlusMinBtnRect[index].CenterPoint;
    SendMessage(insp.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
    SendMessage(insp.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
    Check(PropInfoValid(insp, edit.PropInfo), 'editor does not point at a freed item');
    Check(edit.Visible and Assigned(edit.PropInfo), 'editor still attached to the selected row');
    PaintInspector(insp);
  finally
    insp.OnBeforeAddItem := nil;
    insp.Component := nil;
    btn.Free;
    handlers.Free;
  end;
end;

procedure TestPaintDuringEnumeration(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  handlers: TTestHandlers;
begin
  handlers := TTestHandlers.Create;
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    Check(insp.VisibleItems.Count > 0, 'rows visible before the rebuild');
    handlers.FInspector := insp;
    handlers.FPaintDuringEnum := True;
    insp.OnBeforeAddItem := handlers.BeforeAddItem;
    insp.UpdateProperties(True);
    Check(not handlers.FPaintDuringEnum, 'painted while the items were being enumerated');
    Check(insp.VisibleItems.Count > 0, 'rows visible after the rebuild');
  finally
    insp.OnBeforeAddItem := nil;
    insp.Component := nil;
    btn.Free;
    handlers.Free;
  end;
end;

{ ---- crash #8: UpdateEditControl always calls SetFocus ---- }

procedure TestProgrammaticChangesDoNotTakeFocus(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(form);
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  try
    insp.Component := btn1;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    other.SetFocus;
    Check(GetFocus = other.Handle, 'focus moved to another control');
    insp.Component := btn2; // same class: the selected row is kept
    Check(GetFocus = other.Handle, 'Component change does not take focus');
    Check(edit.Visible and Assigned(edit.PropInfo), 'editor still shown for the selected row');
    insp.UpdateProperties(True);
    Check(GetFocus = other.Handle, 'UpdateProperties does not take focus');
    insp.ExpandAll;
    Check(GetFocus = other.Handle, 'ExpandAll does not take focus');
  finally
    insp.Component := nil;
    btn1.Free;
    btn2.Free;
    other.Free;
  end;
end;

procedure TestDeferredRebuildDoesNotTakeFocus(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  menu: TPopupMenu;
  other: TEdit;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  menu := TPopupMenu.Create(nil);
  btn.PopupMenu := menu;
  try
    insp.Component := btn;
    if SelectRow(insp, 'Caption') = nil then
      Exit;
    other.SetFocus;
    menu.Free;
    menu := nil;
    Application.ProcessMessages; // runs the deferred rebuild
    Check(insp.Items.Count > 0, 'items rebuilt');
    Check(GetFocus = other.Handle, 'rebuild after a referenced component is freed does not take focus');
  finally
    insp.Component := nil;
    btn.Free;
    menu.Free;
    other.Free;
  end;
end;

procedure TestHiddenInspectorDoesNotRaise(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  try
    insp.Component := btn1;
    if SelectRow(insp, 'Caption') = nil then
      Exit;
    insp.Visible := False; // like an inspector on a tab that is not shown
    try
      insp.UpdateProperties(True);
      Check(True, 'UpdateProperties on a hidden inspector does not raise');
    except
      on e: Exception do
        Check(False, 'UpdateProperties on a hidden inspector raised ' + e.ClassName + ': ' + e.Message);
    end;
    try
      insp.Component := btn2;
      Check(True, 'Component change on a hidden inspector does not raise');
    except
      on e: Exception do
        Check(False, 'Component change on a hidden inspector raised ' + e.ClassName + ': ' + e.Message);
    end;
  finally
    insp.Visible := True;
    insp.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TestKeyboardNavigationKeepsFocus(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
  before: PPropItem;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    Check(GetFocus = edit.Handle, 'editor focused after selecting a row in a focused inspector');
    before := insp.SelectedItem;
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Check(insp.SelectedItem <> before, 'Down arrow selected the next row');
    Check(GetFocus = edit.Handle, 'editor keeps focus after the Down arrow');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestClickFocusesEditor(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
  index: Integer;
  pt: TPoint;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    other.SetFocus;
    index := insp.VisibleItems.IndexOf(FindTopItem(insp, 'Caption'));
    pt := insp.ValueRect[index].CenterPoint;
    SendMessage(insp.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
    SendMessage(insp.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
    edit := FindEdit(insp);
    Check(Assigned(edit) and edit.Visible, 'clicking a row shows the editor');
    Check(Assigned(edit) and (GetFocus = edit.Handle), 'clicking a row focuses the editor');
  finally
    insp.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

{ ---- crash #3: SetPropValue with no editor item ---- }

procedure TestSetPropValueWithNothingSelected(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  value: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    value := TValue.From<string>('Changed');
    Check(insp.SetPropValue(FindTopItem(insp, 'Caption'), value), 'SetPropValue returned True');
    Check(btn.Caption = 'Changed', 'value set');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestSetPropValueWithCategorySelected(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  value: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.SortByCategory := True;
    insp.Component := btn;
    Check(insp.VisibleItems[0]^.IsCategory, 'first row is a category');
    insp.SetFocus;
    insp.SelectItem(0);
    value := TValue.From<string>('Changed');
    Check(insp.SetPropValue(FindTopItem(insp, 'Caption'), value), 'SetPropValue returned True');
    Check(btn.Caption = 'Changed', 'value set');
  finally
    insp.SortByCategory := False;
    insp.Component := nil;
    btn.Free;
  end;
end;

{ ---- crash #5: TStackEx<T>.Get recursion, unbalanced canvas stack ---- }

type
  TRaisingObject = class(TPersistent)
  private
    FRaise: Boolean;
    FValue: Integer;
    function GetBoom: Integer;
  published
    property Boom: Integer read GetBoom;
    property Value: Integer read FValue write FValue;
  end;

function TRaisingObject.GetBoom: Integer;
begin
  if FRaise then
    raise Exception.Create('getter failed');
  result := 1;
end;

procedure TestCanvasStackIndexedAccess(form: TForm; insp: TzObjectInspector);
var
  stack: TzCanvasStack;
  bmp: TBitmap;
begin
  stack := TzCanvasStack.Create;
  bmp := TBitmap.Create;
  try
    stack.Push(bmp.Canvas);
    stack.Push(bmp.Canvas);
    try
      Check(stack.Peek(0) = bmp.Canvas, 'Peek(0) returns the bottom canvas');
    except
      on e: Exception do
        Check(False, 'Peek(0) raised ' + e.ClassName + ': ' + e.Message);
    end;
    try
      stack.Clear; // frees the saved brush/font/pen objects through indexed access
      Check(stack.Count = 0, 'Clear empties the stack');
    except
      on e: Exception do
        Check(False, 'Clear raised ' + e.ClassName + ': ' + e.Message);
    end;
  finally
    bmp.Free;
    stack.Free;
  end;
end;

procedure TestGetterRaisingDuringPaint(form: TForm; insp: TzObjectInspector);
var
  obj: TRaisingObject;
  raised: Boolean;
begin
  obj := TRaisingObject.Create;
  try
    insp.Component := obj;
    Check(insp.VisibleItems.Count = 2, 'both rows visible');
    PaintInspector(insp);
    obj.FRaise := True;
    raised := False;
    try
      PaintInspector(insp);
    except
      on e: Exception do
        raised := True;
    end;
    { not part of #5: whether a raising getter should break the whole paint }
    Writeln('  info  getter exception escaped the paint: ', raised);
    obj.FRaise := False;
    try
      insp.Invalidate; // TzObjInspectorBase.Invalidate clears the canvas stack
      Check(True, 'Invalidate after a failed paint does not raise');
    except
      on e: Exception do
        Check(False, 'Invalidate after a failed paint raised ' + e.ClassName + ': ' + e.Message);
    end;
    PaintInspector(insp);
    Check(True, 'paints again once the getter recovers');
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

{ ---- crash #6: Down arrow in an open dropdown ---- }

{ Clicks the dropdown button of the selected row, as a user would. }
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
  Check(Assigned(button) and button.Visible, 'dropdown button visible');
  if button = nil then
    Exit;
  SendMessage(button.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(2, 2));
  SendMessage(button.Handle, WM_LBUTTONUP, 0, MakeLParam(2, 2));
  for i := 0 to insp.ControlCount - 1 do
    if insp.Controls[i] is TzPopupListBox then
      result := TzPopupListBox(insp.Controls[i]);
  Check(Assigned(result) and IsWindowVisible(result.Handle), 'dropdown open');
end;

procedure TestDropDownDownArrowOnLastItem(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Default'); // Boolean: a two-item list
    if edit = nil then
      Exit;
    list := OpenDropDown(insp);
    if list = nil then
      Exit;
    Check(list.Items.Count = 2, 'False and True listed');
    list.ItemIndex := list.Items.Count - 1;
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Check(list.ItemIndex = list.Items.Count - 1, 'Down on the last item stays on it');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestDropDownDownArrowThroughLongList(form: TForm; insp: TzObjectInspector);
var
  panel: TPanel;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
  i, steps: Integer;
begin
  panel := TPanel.Create(nil);
  panel.Parent := form;
  try
    insp.Component := panel;
    edit := SelectRow(insp, 'Color');
    if edit = nil then
      Exit;
    list := OpenDropDown(insp);
    if list = nil then
      Exit;
    steps := insp.VisiblePropCount + 5;
    Check(list.Items.Count > steps, 'colour list is longer than the inspector has rows');
    list.ItemIndex := 0;
    for i := 1 to steps do
      SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Check(list.ItemIndex = steps, 'Down moves through the whole list');
  finally
    insp.Component := nil;
    panel.Free;
  end;
end;

{ ---- crash #10: destructor frees its lists before the editor goes ---- }

procedure TestFreeInspectorWhileEditing(form: TForm; insp: TzObjectInspector);
var
  own: TzObjectInspector;
  btn: TButton;
  edit: TzPropInspEdit;
begin
  { uses its own inspector so the test controls when it is freed }
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  own := TzObjectInspector.Create(nil);
  try
    own.Parent := form;
    own.SetBounds(0, 0, 380, 460);
    own.Component := btn;
    edit := SelectRow(own, 'Caption');
    if edit = nil then
      Exit;
    Check(GetFocus = edit.Handle, 'editor has focus');
    TypeText(edit, 'X'); // uncommitted
    try
      FreeAndNil(own);
      Check(True, 'freeing the inspector while editing does not raise');
    except
      on e: Exception do
        Check(False, 'freeing the inspector while editing raised ' + e.ClassName + ': ' + e.Message);
    end;
    Check(btn.Caption = 'Original', 'pending text discarded, not written during teardown');
    PaintInspector(insp); // the form carries on normally
  finally
    own.Free;
    btn.Free;
  end;
end;

{ ---- crash #9: font measured through a window handle ---- }

{ What the row height should be for a font: text height of 'WA' plus 4. }
function ExpectedItemHeight(font: TFont): Integer;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(font);
    result := bmp.Canvas.TextHeight('WA') + 4;
  finally
    bmp.Free;
  end;
end;

procedure TestFontChangeBeforeParent(form: TForm; insp: TzObjectInspector);
var
  own: TzObjectInspector;
  btn: TButton;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  own := TzObjectInspector.Create(nil);
  try
    try
      own.Font.Size := 14; // no parent yet
      Check(True, 'setting Font before Parent does not raise');
    except
      on e: Exception do
        Check(False, 'setting Font before Parent raised ' + e.ClassName + ': ' + e.Message);
    end;
    Check(not own.HandleAllocated, 'no window handle created early');
    own.Parent := form;
    own.SetBounds(0, 0, 380, 460);
    own.Component := btn;
    Check(own.ItemRect[0].Height = ExpectedItemHeight(own.Font), 'row height follows the font');
    PaintInspector(own);
  finally
    own.Free;
    btn.Free;
  end;
end;

procedure TestParentWithoutWindow(form: TForm; insp: TzObjectInspector);
var
  own: TzObjectInspector;
  panel: TPanel;
  btn: TButton;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  panel := TPanel.Create(nil);
  own := TzObjectInspector.Create(nil);
  try
    try
      own.Parent := panel; // the panel has no parent yet: built bottom-up
      Check(True, 'parenting to a control without a window does not raise');
    except
      on e: Exception do
        Check(False, 'parenting to a control without a window raised ' + e.ClassName + ': ' + e.Message);
    end;
    panel.Parent := form;
    panel.SetBounds(0, 0, 380, 460);
    own.SetBounds(0, 0, 380, 460);
    panel.Font.Size := 12; // reaches the inspector through ParentFont
    own.Component := btn;
    Check(own.ItemRect[0].Height = ExpectedItemHeight(own.Font), 'row height follows the parent font');
    PaintInspector(own);
  finally
    own.Free;
    panel.Free;
    btn.Free;
  end;
end;

{ ---- invalid numbers silently became 0 ---- }

type
  TNumbers = class(TPersistent)
  private
    FByte: Byte;
    FShortInt: ShortInt;
    FCardinal: Cardinal;
    FInteger: Integer;
    FInt64: Int64;
    FUInt64: UInt64;
    FSingle: Single;
    FDouble: Double;
    FColor: TColor;
  published
    property AByte: Byte read FByte write FByte;
    property AShortInt: ShortInt read FShortInt write FShortInt;
    property ACardinal: Cardinal read FCardinal write FCardinal;
    property AInteger: Integer read FInteger write FInteger;
    property AInt64: Int64 read FInt64 write FInt64;
    property AUInt64: UInt64 read FUInt64 write FUInt64;
    property ASingle: Single read FSingle write FSingle;
    property ADouble: Double read FDouble write FDouble;
    property AColor: TColor read FColor write FColor;
  end;

function NewNumbers: TNumbers;
begin
  result := TNumbers.Create;
  result.AByte := 7;
  result.AShortInt := 7;
  result.ACardinal := 7;
  result.AInteger := 7;
  result.AInt64 := 7;
  result.AUInt64 := 7;
  result.ASingle := 7;
  result.ADouble := 7;
  result.AColor := clRed;
end;

{ Types text into the row's editor and presses Enter, as a user would. }
procedure EnterText(insp: TzObjectInspector; const row, text: string);
var
  edit: TzPropInspEdit;
begin
  edit := SelectRow(insp, row);
  if edit = nil then
    Exit;
  edit.SelectAll;
  TypeText(edit, text);
  SendMessage(edit.Handle, WM_CHAR, VK_RETURN, 0);
end;

procedure TestInvalidNumbersRejected(form: TForm; insp: TzObjectInspector);
var
  obj: TNumbers;

  procedure Reject(const row, text: string);
  begin
    expectedExceptions := 1;
    EnterText(insp, row, text);
    Check(expectedExceptions = 0, Format('%s: "%s" rejected', [row, text]));
    expectedExceptions := 0;
  end;

begin
  obj := NewNumbers;
  try
    insp.Component := obj;
    Reject('AInteger', 'abc');
    Check(obj.AInteger = 7, 'AInteger unchanged (was set to 0)');
    Reject('ADouble', 'abc');
    Check(obj.ADouble = 7, 'ADouble unchanged (was set to 0)');
    Reject('ASingle', '1e50');
    Check(obj.ASingle = 7, 'ASingle unchanged by an overflowing value');
    Reject('AByte', '300');
    Check(obj.AByte = 7, 'AByte unchanged (300 was stored as 44)');
    Reject('AByte', '-1');
    Check(obj.AByte = 7, 'AByte unchanged by a negative value');
    Reject('AShortInt', '200');
    Check(obj.AShortInt = 7, 'AShortInt unchanged by an out-of-range value');
    Reject('ACardinal', '-1');
    Check(obj.ACardinal = 7, 'ACardinal unchanged by a negative value');
    Reject('AInt64', '99999999999999999999');
    Check(obj.AInt64 = 7, 'AInt64 unchanged by an out-of-range value');
    Reject('AUInt64', '-1');
    Check(obj.AUInt64 = 7, 'AUInt64 unchanged by a negative value');
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

procedure TestValidNumbersAccepted(form: TForm; insp: TzObjectInspector);
var
  obj: TNumbers;
begin
  obj := NewNumbers;
  try
    insp.Component := obj;
    EnterText(insp, 'AByte', '255');
    Check(obj.AByte = 255, 'AByte accepts 255');
    EnterText(insp, 'AShortInt', '-128');
    Check(obj.AShortInt = -128, 'AShortInt accepts -128');
    EnterText(insp, 'ACardinal', '4000000000');
    Check(obj.ACardinal = 4000000000, 'ACardinal accepts 4000000000');
    EnterText(insp, 'AInteger', '-5');
    Check(obj.AInteger = -5, 'AInteger accepts -5');
    EnterText(insp, 'AInteger', '$10');
    Check(obj.AInteger = 16, 'AInteger accepts hex $10');
    EnterText(insp, 'AInt64', '-9000000000');
    Check(obj.AInt64 = -9000000000, 'AInt64 accepts -9000000000');
    EnterText(insp, 'AUInt64', '18446744073709551615');
    Check(obj.AUInt64 = High(UInt64), 'AUInt64 accepts its maximum');
    EnterText(insp, 'ADouble', '2' + FormatSettings.DecimalSeparator + '5');
    Check(obj.ADouble = 2.5, 'ADouble accepts 2.5');
    EnterText(insp, 'AColor', '$00123456');
    Check(obj.AColor = $123456, 'AColor accepts $00123456');
    EnterText(insp, 'AColor', '$FF00000F'); // how unnamed system colours are shown
    Check(obj.AColor = clBtnFace, 'AColor accepts a system colour typed as hex');
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

{ ---- TDateTime, TDate, TTime, Currency and other float types became 0 ---- }

type
  TMeasure = type Double; // a distinct float type, like TDateTime

  TOtherFloats = class(TPersistent)
  private
    FWhen: TDateTime;
    FDay: TDate;
    FAtTime: TTime;
    FMoney: Currency;
    FMeasure: TMeasure;
  published
    property When: TDateTime read FWhen write FWhen;
    property Day: TDate read FDay write FDay;
    property AtTime: TTime read FAtTime write FAtTime;
    property Money: Currency read FMoney write FMoney;
    property Measure: TMeasure read FMeasure write FMeasure;
  end;

function NewOtherFloats: TOtherFloats;
begin
  result := TOtherFloats.Create;
  result.When := EncodeDate(2020, 6, 15);
  result.Day := EncodeDate(2020, 6, 15);
  result.AtTime := EncodeTime(9, 0, 0, 0);
  result.Money := 12.5;
  result.Measure := 3;
end;

procedure TestOtherFloatTypesAccepted(form: TForm; insp: TzObjectInspector);
var
  obj: TOtherFloats;
  expected: TDateTime;
  sep: string;
begin
  sep := FormatSettings.DecimalSeparator;
  obj := NewOtherFloats;
  try
    insp.Component := obj;
    expected := EncodeDateTime(2021, 3, 4, 10, 30, 0, 0);
    EnterText(insp, 'When', DateTimeToStr(expected));
    Check(SameDateTime(obj.When, expected), 'TDateTime accepts ' + DateTimeToStr(expected));
    expected := EncodeDate(2022, 12, 25);
    EnterText(insp, 'Day', DateToStr(expected));
    Check(SameDate(obj.Day, expected), 'TDate accepts ' + DateToStr(expected));
    expected := EncodeTime(13, 45, 0, 0);
    EnterText(insp, 'AtTime', TimeToStr(expected));
    Check(SameTime(obj.AtTime, expected), 'TTime accepts ' + TimeToStr(expected));
    EnterText(insp, 'Money', '99' + sep + '25');
    Check(obj.Money = 99.25, 'Currency accepts 99' + sep + '25');
    EnterText(insp, 'Measure', '1' + sep + '5');
    Check(obj.Measure = 1.5, 'a distinct Double type accepts 1' + sep + '5');
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

procedure TestOtherFloatTypesRejectInvalid(form: TForm; insp: TzObjectInspector);
var
  obj: TOtherFloats;

  procedure Reject(const row, text: string);
  begin
    expectedExceptions := 1;
    EnterText(insp, row, text);
    Check(expectedExceptions = 0, Format('%s: "%s" rejected', [row, text]));
    expectedExceptions := 0;
  end;

begin
  obj := NewOtherFloats;
  try
    insp.Component := obj;
    Reject('When', 'not a date');
    Check(SameDate(obj.When, EncodeDate(2020, 6, 15)), 'TDateTime unchanged');
    Reject('Money', 'abc');
    Check(obj.Money = 12.5, 'Currency unchanged');
    Reject('Measure', 'abc');
    Check(obj.Measure = 3, 'distinct Double type unchanged');
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

{ ---- leak: TzObjectHost not freed with the inspector ---- }

var
  trackedHostFreed: Boolean;

type
  TTrackedHost = class(TzObjectHost)
  public
    destructor Destroy; override;
  end;

destructor TTrackedHost.Destroy;
begin
  trackedHostFreed := True;
  inherited;
end;

procedure TestHostOwnership(form: TForm; insp: TzObjectInspector);
var
  own: TzObjectInspector;
  btn: TButton;
  host: TTrackedHost;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  own := TzObjectInspector.Create(nil);
  try
    own.Parent := form;
    own.SetBounds(0, 0, 380, 460);

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    own.Component := nil;
    Check(trackedHostFreed, 'host freed when Component is set to nil');

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    own.Component := btn;
    Check(trackedHostFreed, 'host freed when Component is replaced');

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    FreeAndNil(own);
    Check(trackedHostFreed, 'host freed with the inspector');
  finally
    own.Free;
    btn.Free;
  end;
end;

{ ---- batch: small fixes ---- }

procedure PostKey(wnd: HWND; key: Word); forward;

type
  TControlAccess = class(TControl); // Font is protected on TzPropInspEdit

  TDottedName = class(TPersistent)
  private
    FValue: Integer;
  public
    function ToString: string; override;
  published
    property Value: Integer read FValue write FValue;
  end;

  TPlainName = class(TPersistent)
  private
    FValue: Integer;
  published
    property Value: Integer read FValue write FValue;
  end;

  TBig = (e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11);
  TBigSet = set of TBig;

  TSetHolder = class(TPersistent)
  private
    FBig: TBigSet;
  published
    property Big: TBigSet read FBig write FBig;
  end;

  TEventForm = class(TForm)
  published
    function HelpHandler(Command: Word; Data: THelpEventData; var CallHelp: Boolean): Boolean;
    procedure ItemClick(Sender: TObject);
  end;

function TDottedName.ToString: string;
begin
  result := 'a.b.c';
end;

function TEventForm.HelpHandler(Command: Word; Data: THelpEventData; var CallHelp: Boolean): Boolean;
begin
  result := False;
end;

procedure TEventForm.ItemClick(Sender: TObject);
begin
end;

procedure TestEditorTextColour(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit <> nil then
      Check(TControlAccess(edit).Font.Color = clWindowText, 'editor text uses clWindowText (was 0, black)');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestSearchReachesLastRow(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    insp.SetFocus;
    insp.SelectItem(insp.VisibleItems.Count - 1);
    edit := FindEdit(insp);
    Check(Assigned(edit) and (GetFocus = edit.Handle), 'editor focused on the last row');
    PostKey(edit.Handle, VK_TAB);
    Check(GetFocus = insp.Handle, 'Tab on the last row starts searching');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestSplitterPosMovesEditor(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
  oldLeft: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    oldLeft := edit.Left;
    insp.SplitterPos := insp.SplitterPos + 40;
    Check(edit.Left = oldLeft + 40, 'editor follows SplitterPos set from code');
    insp.SplitterPos := insp.SplitterPos - 40;
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestWideCharValue(form: TForm; insp: TzObjectInspector);
var
  ed: TEdit;
begin
  ed := TEdit.Create(nil);
  ed.Parent := form;
  try
    insp.Component := ed;
    EnterText(insp, 'PasswordChar', #$25CF);
    Check(ed.PasswordChar = #$25CF, 'PasswordChar accepts U+25CF (was stored as U+00CF)');
  finally
    insp.Component := nil;
    ed.Free;
  end;
end;

procedure TestDropDownInsideWorkArea(form: TForm; insp: TzObjectInspector);
var
  panel: TPanel;
  list: TzPopupListBox;
  r: TRect;
begin
  { Only a sanity check on one monitor: the multi-monitor case can't be set up here. }
  panel := TPanel.Create(nil);
  panel.Parent := form;
  try
    insp.Component := panel;
    if SelectRow(insp, 'Color') = nil then
      Exit;
    list := OpenDropDown(insp);
    if list = nil then
      Exit;
    GetWindowRect(list.Handle, r);
    Check(r.Height > 0, 'dropdown has a height');
    Check(r.Bottom <= Screen.MonitorFromRect(r).WorkareaRect.Bottom, 'dropdown fits the monitor work area');
  finally
    insp.Component := nil;
    panel.Free;
  end;
end;

procedure TestIndentationIgnoresToString(form: TForm; insp: TzObjectInspector);
var
  dotted: TDottedName;
  plain: TPlainName;
  plainLeft: Integer;
begin
  dotted := TDottedName.Create;
  plain := TPlainName.Create;
  try
    insp.Component := plain;
    plainLeft := insp.PropTextRect[0].Left;
    insp.Component := dotted;
    Check(insp.PropTextRect[0].Left = plainLeft, 'indentation does not depend on ToString');
  finally
    insp.Component := nil;
    dotted.Free;
    plain.Free;
  end;
end;

procedure TestSetElementOrder(form: TForm; insp: TzObjectInspector);
var
  holder: TSetHolder;
  i, index: Integer;
  names: string;
begin
  holder := TSetHolder.Create;
  try
    insp.Component := holder;
    insp.ExpandItem(FindTopItem(insp, 'Big'));
    index := insp.VisibleItems.IndexOf(FindTopItem(insp, 'Big'));
    names := '';
    for i := index + 1 to insp.VisibleItems.Count - 1 do
      names := names + insp.VisibleItems[i]^.Name + ' ';
    Check(names = 'e0 e1 e2 e3 e4 e5 e6 e7 e8 e9 e10 e11 ', 'set elements in declaration order, got: ' + names);
  finally
    insp.Component := nil;
    holder.Free;
  end;
end;

procedure TestHostDoesNotForceCategories(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  host: TzObjectHost;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    Check(not insp.SortByCategory, 'starts without categories');
    host := TzObjectHost.Create;
    host.AddObject(btn, 'Btn');
    insp.Component := host;
    insp.Component := btn; // frees the host
    Check(not insp.SortByCategory, 'SortByCategory not switched on by a host');
    Check(not insp.VisibleItems[0]^.IsCategory, 'a normal component is not grouped');
  finally
    insp.SortByCategory := False;
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestInspDialogAlias(form: TForm; insp: TzObjectInspector);
begin
  Check(TClass(zObjInspDialogs.TzInspDialog) = TClass(zObjInspector.TzInspDialog),
    'zObjInspDialogs.TzInspDialog is the TzInspDialog that ShowModalDialog accepts');
end;

procedure TestFunctionEventHandlerListed(form: TForm; insp: TzObjectInspector);
var
  evForm: TEventForm;
  list: TzPopupListBox;
begin
  evForm := TEventForm.CreateNew(nil);
  try
    insp.Component := evForm;
    if SelectRow(insp, 'OnHelp') = nil then
      Exit;
    list := OpenDropDown(insp);
    Check(Assigned(list) and (list.Items.IndexOf('HelpHandler') >= 0), 'a function-type event lists its matching handler');
  finally
    insp.Component := nil;
    evForm.Free;
  end;
end;

procedure TestCanvasStackFromCollection(form: TForm; insp: TzObjectInspector);
var
  canvases: TList<TCanvas>;
  bmp1, bmp2: TBitmap;
  stack: TzCanvasStack;
begin
  canvases := TList<TCanvas>.Create;
  bmp1 := TBitmap.Create;
  bmp2 := TBitmap.Create;
  try
    canvases.Add(bmp1.Canvas);
    canvases.Add(bmp2.Canvas);
    stack := TzCanvasStack.Create(canvases);
    try
      try
        Check(stack.Peek(1) = bmp2.Canvas, 'Peek works on a stack created from a collection');
      except
        on e: Exception do
          Check(False, 'Peek on a stack created from a collection raised ' + e.ClassName + ': ' + e.Message);
      end;
    finally
      stack.Free;
    end;
  finally
    bmp2.Free;
    bmp1.Free;
    canvases.Free;
  end;
end;

procedure TestFloatConvBlankText(form: TForm; insp: TzObjectInspector);
var
  d: Double;
begin
  try
    Check(not MyTryStrToFloat('  ', d), 'MyTryStrToFloat rejects blank text');
  except
    on e: Exception do
      Check(False, 'MyTryStrToFloat on blank text raised ' + e.ClassName + ': ' + e.Message);
  end;
end;

procedure TestFloatPreferenceIsCopied(form: TForm; insp: TzObjectInspector);
var
  pref, saved: TzFloatPreference;
begin
  saved := TzFloatPreference.Create;
  try
    saved.Assign(insp.FloatPreference);
    pref := TzFloatPreference.Create;
    pref.MaxDigits := 5;
    pref.ExpPrecision := 9;
    insp.FloatPreference := pref;
    Check(insp.FloatPreference <> pref, 'FloatPreference keeps its own object');
    pref.Free;
    Check((insp.FloatPreference.MaxDigits = 5) and (insp.FloatPreference.ExpPrecision = 9),
      'settings copied, still readable after the caller frees its object');
    insp.FloatPreference := saved; // restore: the old code shared it between inspectors
  finally
    saved.Free;
  end;
end;

{ ---- batch 2 ---- }

type
  TEditAccess = class(TzPropInspEdit); // ReadOnly is protected

  TRaisingWithChild = class(TPersistent)
  private
    FRaise: Boolean;
    function GetBoom: Integer;
    function GetChild: TPersistent;
  published
    property Boom: Integer read GetBoom;
    property Child: TPersistent read GetChild;
  end;

function TRaisingWithChild.GetBoom: Integer;
begin
  if FRaise then
    raise Exception.Create('Boom getter failed');
  result := 1;
end;

function TRaisingWithChild.GetChild: TPersistent;
begin
  if FRaise then
    raise Exception.Create('Child getter failed');
  result := nil;
end;

procedure ClickListItem(list: TzPopupListBox; const name: string);
var
  index: Integer;
  r: TRect;
begin
  index := list.Items.IndexOf(name);
  Check(index >= 0, name + ' listed in the dropdown');
  if index < 0 then
    Exit;
  r := list.ItemRect(index);
  SendMessage(list.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(r.Left + 2, r.Top + 2));
  SendMessage(list.Handle, WM_LBUTTONUP, 0, MakeLParam(r.Left + 2, r.Top + 2));
  Application.ProcessMessages; // the click is applied from a posted message
end;

procedure TestComponentReferences(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  menu1, menu2: TPopupMenu;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
begin
  menu1 := TPopupMenu.Create(form);
  menu1.Name := 'RefMenu1';
  menu2 := TPopupMenu.Create(form);
  menu2.Name := 'RefMenu2';
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'PopupMenu');
    if edit = nil then
      Exit;
    Check(not TEditAccess(edit).ReadOnly, 'component reference editor is not read-only');

    list := OpenDropDown(insp);
    if list <> nil then
      ClickListItem(list, 'RefMenu2');
    Check(btn.PopupMenu = menu2, 'clicking RefMenu2 in the dropdown sets it');

    EnterText(insp, 'PopupMenu', 'RefMenu1');
    Check(btn.PopupMenu = menu1, 'typing RefMenu1 and Enter sets it');

    edit := SelectRow(insp, 'PopupMenu');
    edit.SelectAll;
    SendMessage(edit.Handle, WM_CLEAR, 0, 0);
    SendMessage(edit.Handle, WM_CHAR, VK_RETURN, 0);
    Check(btn.PopupMenu = nil, 'deleting the text and Enter clears it');

    edit := SelectRow(insp, 'PopupMenu');
    edit.SelectAll;
    TypeText(edit, 'RefMenu1'); // not committed
    list := OpenDropDown(insp);
    if list <> nil then
      ClickListItem(list, 'RefMenu2');
    Check(btn.PopupMenu = menu2, 'a dropdown choice wins over text typed before it');
  finally
    insp.Component := nil;
    btn.Free;
    menu1.Free;
    menu2.Free;
  end;
end;

procedure TestRaisingGettersDoNotBreakInspector(form: TForm; insp: TzObjectInspector);
var
  obj: TRaisingWithChild;
  index: Integer;
  pt: TPoint;
begin
  obj := TRaisingWithChild.Create;
  obj.FRaise := True;
  try
    try
      insp.Component := obj;
      Check(insp.VisibleItems.Count = 2, 'both rows listed although their getters raise');
      PaintInspector(insp);
      Check(True, 'paints although getters raise');
      index := insp.VisibleItems.IndexOf(FindTopItem(insp, 'Boom'));
      pt := insp.ValueRect[index].CenterPoint;
      SendMessage(insp.Handle, WM_MOUSEMOVE, 0, MakeLParam(pt.X, pt.Y));
      SendMessage(insp.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
      SendMessage(insp.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
      Check(not FindEdit(insp).Visible, 'no editor for a row whose value can''t be read');
      insp.UpdateProperties(True);
      Check(True, 'rebuilds although getters raise');
    except
      on e: Exception do
        Check(False, 'raised ' + e.ClassName + ': ' + e.Message);
    end;
  finally
    insp.Component := nil;
    obj.Free;
  end;
end;

procedure TestEditsWithoutWmCharCommitted(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    edit.SelStart := Length(edit.Text);
    edit.SelLength := 0;
    SendMessage(edit.Handle, WM_CHAR, VK_BACK, 0);
    other.SetFocus;
    Check(btn.Caption = 'Origina', 'a Backspace edit is committed when focus moves');

    edit := SelectRow(insp, 'Caption');
    edit.SetFocus; // the row was already selected, so SelectRow left focus on the inspector
    edit.SelectAll;
    SendMessage(edit.Handle, WM_CLEAR, 0, 0); // the context menu's Delete
    other.SetFocus;
    Check(btn.Caption = '', 'a context-menu Delete is committed when focus moves');
  finally
    insp.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TestNonVisualComponentEvents(form: TForm; insp: TzObjectInspector);
var
  evForm: TEventForm;
  item: TMenuItem;
  row: PPropItem;
  list: TzPopupListBox;
begin
  evForm := TEventForm.CreateNew(nil);
  try
    item := TMenuItem.Create(evForm);
    item.Name := 'Item1';
    item.OnClick := evForm.ItemClick;
    insp.Component := item;
    row := FindTopItem(insp, 'OnClick');
    Check(Assigned(row) and (row^.ValueName = 'ItemClick'), 'a TMenuItem shows its OnClick handler''s name');
    if SelectRow(insp, 'OnClick') <> nil then
    begin
      list := OpenDropDown(insp);
      Check(Assigned(list) and (list.Items.IndexOf('ItemClick') >= 0), 'its OnClick dropdown lists the form''s handlers');
    end;
  finally
    insp.Component := nil;
    evForm.Free;
  end;
end;

procedure TestExpandAllSticks(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  total: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    insp.ExpandAll;
    total := insp.Items.Count;
    Check(insp.VisibleItems.Count = total, 'ExpandAll shows every row');
    insp.UpdateProperties(True);
    Check(insp.VisibleItems.Count = total, 'still expanded after a rebuild');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

{ ---- performance batch: regression guards ---- }

type
  TPlainObj = class(TObject) // not a TPersistent: public properties count
  private
    FValue: Integer;
  public
    property Value: Integer read FValue write FValue;
  end;

  TPlainOwner = class(TPersistent)
  private
    FChild: TPlainObj;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Child: TPlainObj read FChild;
  end;

constructor TPlainOwner.Create;
begin
  inherited Create;
  FChild := TPlainObj.Create;
end;

destructor TPlainOwner.Destroy;
begin
  FChild.Free;
  inherited;
end;

procedure TestRowChangeCommitsTypedText(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    TypeText(edit, 'Moved');
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0); // to the next row, without Enter
    Check(btn.Caption = 'Moved', 'text typed for a row is committed when moving to another row');
    Check(GetFocus = edit.Handle, 'the editor keeps focus');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestDropDownButtonFollowsRow(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  button: TzPropInspButton;
  i: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    SelectRow(insp, 'Default'); // Boolean: has a dropdown
    button := nil;
    for i := 0 to insp.ControlCount - 1 do
      if insp.Controls[i] is TzPropInspButton then
        button := TzPropInspButton(insp.Controls[i]);
    Check(Assigned(button) and button.Visible, 'dropdown button shown for a Boolean row');
    SelectRow(insp, 'Caption'); // string: no dropdown
    Check(Assigned(button) and not button.Visible, 'dropdown button hidden for a string row');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestUsedPropertiesUnique(form: TForm; insp: TzObjectInspector);
var
  ctx: TRttiContext;
  props: TArray<TRttiProperty>;
  names: TStringList;
  prop: TRttiProperty;
begin
  ctx := TRttiContext.Create;
  names := TStringList.Create;
  try
    names.Sorted := True;
    names.Duplicates := dupError;
    props := TzRttiType(ctx.GetType(TButton)).GetUsedProperties;
    try
      for prop in props do
        names.Add(prop.Name);
      Check(True, 'GetUsedProperties returns each name once');
    except
      on e: Exception do
        Check(False, 'GetUsedProperties returned a name twice: ' + e.Message);
    end;
    Check((names.IndexOf('Caption') >= 0) and (names.IndexOf('Name') >= 0) and (names.IndexOf('Tag') >= 0),
      'GetUsedProperties includes declared and inherited properties');
  finally
    names.Free;
  end;
end;

procedure TestObjectVisibilityClearsCache(form: TForm; insp: TzObjectInspector);
var
  owner: TPlainOwner;
  row: PPropItem;
begin
  owner := TPlainOwner.Create;
  try
    insp.ObjectVisibility := mvPublic;
    insp.Component := owner;
    row := FindTopItem(insp, 'Child');
    Check(Assigned(row) and row^.HasChild, 'a plain object with a public property can be expanded');
    insp.ObjectVisibility := mvPublished;
    Check(Assigned(row) and not row^.HasChild, 'not after ObjectVisibility changes to mvPublished');
  finally
    insp.ObjectVisibility := mvPublic;
    insp.Component := nil;
    owner.Free;
  end;
end;

{ ---- batch 4 ---- }

{$WARN SYMBOL_DEPRECATED OFF} // IsValueNoDefault: these tests also compile against the old code

type
  TWide = 0..40;
  TWideSet = set of TWide; // 6 bytes
  TUpper = 40..50;
  TUpperSet = set of TUpper; // 2 bytes, starting at byte 5

  TSetsHolder = class(TObject) // a plain object, so its public properties are shown
  private
    FWide: TWideSet;
    FUpper: TUpperSet;
    FSmall: TBigSet;
  public
    property Wide: TWideSet read FWide write FWide;
    property Upper: TUpperSet read FUpper write FUpper;
    property Small: TBigSet read FSmall write FSmall;
  end;

  TNodeB = class;

  TNodeA = class(TObject)
  private
    FNext: TNodeB;
  public
    property Next: TNodeB read FNext;
  end;

  TNodeB = class(TObject)
  private
    FBack: TNodeA;
  public
    property Back: TNodeA read FBack;
  end;

  TCircRoot = class(TPersistent)
  private
    FNode: TNodeA;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Node: TNodeA read FNode;
  end;

  TFloatHolder = class(TPersistent)
  private
    FValue: Double;
  published
    property Value: Double read FValue write FValue;
  end;

  TValueManagerAccess = class(TzCustomValueManager); // GetValue is protected

  TPaddedBool = packed record
    Value: Boolean;
    Pad: array[0..6] of Byte;
  end;

constructor TCircRoot.Create;
begin
  inherited Create;
  FNode := TNodeA.Create;
  FNode.FNext := TNodeB.Create;
  FNode.FNext.FBack := FNode;
end;

destructor TCircRoot.Destroy;
begin
  FNode.FNext.Free;
  FNode.Free;
  inherited;
end;

function FindChild(insp: TzObjectInspector; parent: PPropItem; const name: string): PPropItem;
var
  i: Integer;
  item: PPropItem;
begin
  result := nil;
  if parent = nil then
    Exit;
  for i := 0 to insp.Items.Count - 1 do
  begin
    item := insp.Items.Items[i];
    if (item^.Parent = parent) and SameText(item^.Name, name) then
      Exit(item);
  end;
end;

function ElementValue(insp: TzObjectInspector; const setName, element: string): string;
var
  item: PPropItem;
begin
  item := FindChild(insp, FindTopItem(insp, setName), element);
  if item = nil then
    Exit('(no row)');
  result := item^.ValueName;
end;

{ Sets one element of a set through its row, as a user would: select it, type the
  value, press Enter. }
procedure SetElement(insp: TzObjectInspector; const setName, element, text: string);
var
  item: PPropItem;
  edit: TzPropInspEdit;
begin
  insp.ExpandItem(FindTopItem(insp, setName));
  item := FindChild(insp, FindTopItem(insp, setName), element);
  Check(item <> nil, setName + '.' + element + ' row exists');
  if item = nil then
    Exit;
  insp.SetFocus;
  insp.SelectItem(insp.VisibleItems.IndexOf(item));
  edit := FindEdit(insp);
  if not (Assigned(edit) and edit.Visible) then
  begin
    Check(False, 'editor visible on ' + setName + '.' + element);
    Exit;
  end;
  edit.SelectAll;
  TypeText(edit, text);
  SendMessage(edit.Handle, WM_CHAR, VK_RETURN, 0);
end;

function CategoryOf(insp: TzObjectInspector; const name: string): string;
var
  item: PPropItem;
begin
  { A grouped item's qualified name starts with its category name. }
  item := FindTopItem(insp, name);
  if item = nil then
    Exit('(no row)');
  result := Copy(item^.QualifiedName, 1, Pos('.', item^.QualifiedName) - 1);
end;

function HasCategoryRow(insp: TzObjectInspector; const name: string): Boolean;
var
  i: Integer;
begin
  result := False;
  for i := 0 to insp.Items.Count - 1 do
    if insp.Items.Items[i]^.IsCategory and (insp.Items.Items[i]^.Name = name) then
      Exit(True);
end;

procedure TestCategoryRegistrationsKept(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
  host: TzObjectHost;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  try
    insp.SortByCategory := True;
    insp.RegisterPropertyInCategory('Layout', 'Left');
    insp.Component := btn1;
    Check(CategoryOf(insp, 'Left') = 'Layout', 'registered before Component is set: Left is in Layout, got ' + CategoryOf(insp, 'Left'));
    Check(HasCategoryRow(insp, 'Layout'), 'a Layout category row');
    Check(CategoryOf(insp, 'Caption') = insp.DefaultCategoryName, 'an unregistered property is in the default category');
    insp.Component := btn2;
    Check(CategoryOf(insp, 'Left') = 'Layout', 'still in Layout after the component changes, got ' + CategoryOf(insp, 'Left'));
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'One');
    insp.Component := host;
    Check(HasCategoryRow(insp, 'One'), 'a host still groups by object');
    insp.Component := btn2; // frees the host
    Check(CategoryOf(insp, 'Left') = 'Layout', 'still in Layout after inspecting a TzObjectHost, got ' + CategoryOf(insp, 'Left'));
    insp.ClearRegisteredCategorys;
    Check(CategoryOf(insp, 'Left') = insp.DefaultCategoryName, 'ClearRegisteredCategorys removes the registration');
    Check(not HasCategoryRow(insp, 'Layout'), 'and the Layout row');
  finally
    insp.ClearRegisteredCategorys;
    insp.SortByCategory := False;
    insp.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TestLargeSets(form: TForm; insp: TzObjectInspector);
var
  holder: TSetsHolder;
begin
  holder := TSetsHolder.Create;
  try
    holder.Wide := [0, 35, 40];
    holder.Upper := [40, 50];
    insp.Component := holder;
    Check(ElementValue(insp, 'Wide', '35') = 'True', 'element 35 of a 41-element set shows True, got ' + ElementValue(insp, 'Wide', '35'));
    Check(ElementValue(insp, 'Wide', '34') = 'False', 'element 34 shows False');
    Check((ElementValue(insp, 'Wide', '0') = 'True') and (ElementValue(insp, 'Wide', '40') = 'True'),
      'the first and last elements show True');
    SetElement(insp, 'Wide', '34', 'True');
    Check(holder.Wide = [0, 34, 35, 40], 'element 34 included, the others kept');
    SetElement(insp, 'Wide', '0', 'False');
    Check(holder.Wide = [34, 35, 40], 'element 0 excluded, the others kept');
    Check(ElementValue(insp, 'Upper', '50') = 'True', 'set of 40..50: element 50 shows True, got ' + ElementValue(insp, 'Upper', '50'));
    Check(ElementValue(insp, 'Upper', '45') = 'False', 'set of 40..50: element 45 shows False');
    SetElement(insp, 'Upper', '45', 'True');
    Check(holder.Upper = [40, 45, 50], 'set of 40..50: element 45 included, the others kept');
    SetElement(insp, 'Small', 'e3', 'True');
    Check(holder.Small = [e3], 'a set of up to 32 elements still works');
    SetElement(insp, 'Small', 'e3', 'False');
    Check(holder.Small = [], 'and its element can be excluded again');
  finally
    insp.Component := nil;
    holder.Free;
  end;
end;

procedure TestItemHintLeavesControlHint(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  text: string;
  r: TRect;

  { What TApplication does: a mouse move, then CM_HINTSHOW once the pause is over.
    The message is sent directly, so no real hint window is involved. }
  function HintAt(row: Integer; out hintText: string): Boolean;
  var
    info: THintInfo;
    pt: TPoint;
  begin
    r := insp.PropTextRect[row];
    pt := Point(r.Left + 2, (r.Top + r.Bottom) div 2);
    insp.Perform(WM_MOUSEMOVE, 0, MakeLParam(pt.X, pt.Y));
    info := Default(THintInfo);
    info.HintControl := insp;
    info.CursorPos := pt;
    info.HintStr := GetShortHint(insp.Hint);
    result := insp.Perform(CM_HINTSHOW, 0, LPARAM(@info)) = 0;
    hintText := info.HintStr;
  end;

begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    Application.ShowHint := False; // no real hint window while the test moves the mouse
    form.ShowHint := False;
    TControlAccess(insp).ParentShowHint := True; // not published by the inspector
    insp.Hint := 'Developer hint';
    insp.Component := btn;
    insp.SplitterPos := 30; // the names no longer fit
    PaintInspector(insp);
    Check(HintAt(0, text) and (text = insp.VisibleItems[0]^.Name),
      'hint for a cut-off name on the first row, got: ' + text);
    Check(insp.ShowHint, 'ShowHint is on while a cut-off name is under the mouse');
    Check(HintAt(1, text) and (text = insp.VisibleItems[1]^.Name),
      'hint for a cut-off name on the second row, got: ' + text);
    Check(insp.Hint = 'Developer hint', 'the control''s Hint is not overwritten, got: ' + insp.Hint);
    insp.Perform(CM_MOUSELEAVE, 0, 0);
    Check(not insp.ShowHint and TControlAccess(insp).ParentShowHint, 'ShowHint and ParentShowHint restored when the mouse leaves');

    insp.SplitterPos := 200; // the names fit again
    insp.ShowHint := True;
    PaintInspector(insp);
    Check(HintAt(0, text) and (text = 'Developer hint'), 'a name that fits shows the control''s own hint, got: ' + text);
    insp.Perform(CM_MOUSELEAVE, 0, 0);
    Check(insp.ShowHint, 'ShowHint set by the application is left on');
  finally
    Application.ShowHint := True;
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestNonDefaultFollowsRtti(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  panel: TPanel;
  menu: TPopupMenu;
  handlers: TEventForm;

  function NonDefault(const name: string): Boolean;
  var
    item: PPropItem;
  begin
    item := FindTopItem(insp, name);
    Check(item <> nil, name + ' row exists');
    result := (item <> nil) and insp.IsValueNoDefault(item^.QualifiedName, item^.ValueName);
  end;

  function ElementNonDefault(const setName, element: string): Boolean;
  var
    item: PPropItem;
  begin
    insp.ExpandItem(FindTopItem(insp, setName));
    item := FindChild(insp, FindTopItem(insp, setName), element);
    Check(item <> nil, setName + '.' + element + ' row exists');
    result := (item <> nil) and insp.IsValueNoDefault(item^.QualifiedName, item^.ValueName);
  end;

begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  panel := TPanel.Create(nil);
  panel.Parent := form;
  menu := TPopupMenu.Create(nil);
  menu.Name := 'Menu1';
  handlers := TEventForm.CreateNew(nil);
  try
    insp.Component := btn;
    Check(not NonDefault('Anchors'), 'Anchors [akLeft,akTop] is the default');
    Check(not ElementNonDefault('Anchors', 'akLeft'), 'Anchors.akLeft True is the default');
    Check(not ElementNonDefault('Anchors', 'akRight'), 'Anchors.akRight False is the default');
    btn.Anchors := [akLeft, akTop, akRight];
    Check(NonDefault('Anchors'), 'Anchors [akLeft,akTop,akRight] is non-default');
    Check(ElementNonDefault('Anchors', 'akRight'), 'Anchors.akRight True is non-default');
    Check(not ElementNonDefault('Anchors', 'akBottom'), 'Anchors.akBottom False is still the default');
    btn.ParentFont := False;
    Check(not NonDefault('Font'), 'an owned object (Font) is not non-default itself');
    Check(not NonDefault('PopupMenu'), 'no PopupMenu is the default');
    btn.PopupMenu := menu;
    Check(NonDefault('PopupMenu'), 'a PopupMenu reference is non-default');
    Check(not NonDefault('OnClick'), 'no OnClick handler is the default');
    btn.OnClick := handlers.ItemClick;
    Check(NonDefault('OnClick'), 'an OnClick handler is non-default');
    insp.Component := nil;
    btn.Tag := 5;
    btn.Caption := '';
    insp.Component := btn;
    Check(NonDefault('Tag'), 'Tag 5 (default 0) is non-default before its row is ever selected');
    Check(not NonDefault('Cursor'), 'Cursor crDefault is the default');
    Check(not NonDefault('Default'), 'Default False is the default');
    Check(not NonDefault('Caption'), 'an empty Caption is the default');
    Check(NonDefault('Left'), 'Left has no default, so it is always stored');
    btn.Tag := 0;
    Check(not NonDefault('Tag'), 'Tag back to 0 is the default');
    EnterText(insp, 'Caption', 'X');
    Check(NonDefault('Caption'), 'a non-empty Caption is non-default');
    panel.ParentColor := True;
    insp.Component := panel;
    Check(not NonDefault('Color'), 'Color is not stored while ParentColor is True');
  finally
    insp.Component := nil;
    panel.Free;
    btn.Free;
    menu.Free;
    handlers.Free;
  end;
end;

procedure TestFloatPreferencePerInspector(form: TForm; insp: TzObjectInspector);
var
  other: TzObjectInspector;
  holder: TFloatHolder;
  saved: TzFloatPreference;
  mine, theirs: string;
begin
  saved := TzFloatPreference.Create;
  other := TzObjectInspector.Create(nil);
  holder := TFloatHolder.Create;
  try
    saved.Assign(insp.FloatPreference);
    other.Parent := form;
    other.SetBounds(0, 0, 380, 460);
    holder.Value := 1.23456789;
    insp.FloatPreference.ExpPrecision := 3;
    Check(other.FloatPreference.ExpPrecision <> 3, 'another inspector keeps its own FloatPreference');
    insp.Component := holder;
    other.Component := holder;
    mine := FindTopItem(insp, 'Value')^.ValueName;
    theirs := FindTopItem(other, 'Value')^.ValueName;
    Check(mine <> theirs, 'each inspector formats with its own settings: ' + mine + ' / ' + theirs);
  finally
    insp.FloatPreference := saved; // the old code shared it between inspectors
    insp.Component := nil;
    other.Free;
    holder.Free;
    saved.Free;
  end;
end;

procedure TestCircularLinkThroughPlainObjects(form: TForm; insp: TzObjectInspector);
var
  root: TCircRoot;
begin
  root := TCircRoot.Create;
  try
    insp.Component := root;
    Check(insp.Items.Count < 20, 'a reference cycle between plain objects is cut, items: ' + IntToStr(insp.Items.Count));
  finally
    insp.Component := nil;
    root.Free;
  end;
end;

procedure TestGetValueReadsOnlyTheValue(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  item: PPropItem;
  padded: TPaddedBool;
  v: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    item := FindTopItem(insp, 'Default');
    Check(item <> nil, 'Default row exists');
    if item = nil then
      Exit;
    padded.Value := True;
    FillChar(padded.Pad, SizeOf(padded.Pad), $AB);
    v := TValueManagerAccess.GetValue(item, padded.Value);
    Check(TValueData(v).FAsUInt64 = 1, 'GetValue reads the Boolean only, not the bytes after it: ' +
      IntToHex(TValueData(v).FAsUInt64, 16));
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

{$WARN SYMBOL_DEPRECATED ON}

{ ---- performance batch 2: regression guards ---- }

{ What TPropItem.Count and Items mean: the items whose Parent is the item, and for a
  category row the top-level items in that category, in list order. Found by
  scanning the whole list, as Count and Items themselves used to. }
function ScanChildren(insp: TzObjectInspector; item: PPropItem): TList<PPropItem>;
var
  i: Integer;
  child: PPropItem;
begin
  result := TList<PPropItem>.Create;
  for i := 0 to insp.Items.Count - 1 do
  begin
    child := insp.Items.Items[i];
    if item^.IsCategory then
    begin
      if (child^.Parent = nil) and not child^.IsCategory and (child^.CategoryIndex = item^.CategoryIndex) then
        result.Add(child);
    end
    else if child^.Parent = item then
      result.Add(child);
  end;
end;

procedure CheckChildLinks(insp: TzObjectInspector; const what: string);
var
  i, k: Integer;
  item: PPropItem;
  expected: TList<PPropItem>;
  wrong: string;
begin
  wrong := '';
  for i := 0 to insp.Items.Count - 1 do
  begin
    item := insp.Items.Items[i];
    expected := ScanChildren(insp, item);
    try
      if item^.Count <> expected.Count then
        wrong := wrong + item^.QualifiedName + ' '
      else
        for k := 0 to expected.Count - 1 do
          if item^.Items[k] <> expected[k] then
          begin
            wrong := wrong + item^.QualifiedName + ' ';
            Break;
          end;
    finally
      expected.Free;
    end;
  end;
  Check(wrong = '', what + ': Count and Items match the parent links' + IfThen(wrong <> '', ', wrong for: ' + wrong));
end;

procedure TestChildLinks(form: TForm; insp: TzObjectInspector);
var
  btn1, btn2: TButton;
  host: TzObjectHost;
  holder: TSetsHolder;
  font, past: PPropItem;
  raised: Boolean;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := form;
  btn2 := TButton.Create(nil);
  btn2.Parent := form;
  holder := TSetsHolder.Create;
  try
    insp.Component := btn1;
    CheckChildLinks(insp, 'a component');
    insp.ExpandAll;
    CheckChildLinks(insp, 'a component, expanded');
    insp.SortByCategory := True;
    insp.RegisterPropertyInCategory('Layout', 'Left');
    insp.UpdateProperties(True);
    CheckChildLinks(insp, 'grouped by category');
    insp.SortByCategory := False;
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'One');
    host.AddObject(btn2, 'Two');
    insp.Component := host;
    CheckChildLinks(insp, 'a TzObjectHost');
    insp.Component := holder;
    CheckChildLinks(insp, 'sets');

    insp.Component := btn1;
    font := FindTopItem(insp, 'Font');
    Check((font <> nil) and not font^.Expanded, 'Font starts collapsed');
    insp.ExpandItem(font);
    font := FindTopItem(insp, 'Font');
    Check((font <> nil) and font^.Expanded, 'Font expanded');
    Check((font <> nil) and (FindTopItem(insp, 'Caption')^.Count = 0) and (FindTopItem(insp, 'Caption')^.Items[0] = nil),
      'a string row has no children');
    raised := False;
    past := nil;
    try
      if font <> nil then
        past := font^.Items[font^.Count];
    except
      on EListError do
        raised := True;
    end;
    Check(raised and (past = nil), 'Items past the end raises EListError, as before');
  finally
    insp.ClearRegisteredCategorys;
    insp.SortByCategory := False;
    insp.Component := nil;
    holder.Free;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TestButtonFollowsEditor(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  edit: TzPropInspEdit;
  button: TzPropInspButton;
  i: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Default'); // Boolean: a dropdown list
    button := nil;
    for i := 0 to insp.ControlCount - 1 do
      if insp.Controls[i] is TzPropInspButton then
        button := TzPropInspButton(insp.Controls[i]);
    if (edit = nil) or (button = nil) then
    begin
      Check(False, 'editor and button exist');
      Exit;
    end;
    Check(button.Visible and button.DropDown, 'a list row shows the dropdown arrow');
    Check(button.Top = edit.Top - 3, 'the button is on the editor''s row');
    edit := SelectRow(insp, 'Font'); // an object with a dialog
    Check(button.Visible and not button.DropDown, 'a dialog row shows "..."');
    Check((edit <> nil) and (button.Top = edit.Top - 3), 'the button moved with the editor');
    edit := SelectRow(insp, 'Cursor'); // a list again, on another row
    Check(button.Visible and button.DropDown, 'back to the arrow');
    Check((edit <> nil) and (button.Top = edit.Top - 3), 'and moved again');
    Check((edit <> nil) and (button.Left = insp.ClientWidth - button.Width) and (edit.Left + edit.Width <= button.Left),
      'the button is at the right edge, after the editor');
    SelectRow(insp, 'Caption'); // no button
    Check(not button.Visible, 'hidden on a row without one');
  finally
    insp.Component := nil;
    btn.Free;
  end;
end;

procedure TestDrawHorzDotLinePixels(form: TForm; insp: TzObjectInspector);
var
  bmp: TBitmap;
  x, y, startX, endX: Integer;
  expected: Boolean;
  wrong: string;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(40, 3);
    for startX := 3 to 4 do
      for endX := 20 to 21 do
      begin
        bmp.Canvas.Brush.Color := clWhite;
        bmp.Canvas.FillRect(Rect(0, 0, 40, 3));
        bmp.Canvas.Pen.Color := clRed;
        DrawHorzDotLine(bmp.Canvas, startX, 1, endX);
        wrong := '';
        for y := 0 to 2 do
          for x := 0 to 39 do
          begin
            expected := (y = 1) and (x >= startX) and (x <= endX) and not Odd(x);
            if (bmp.Canvas.Pixels[x, y] = clRed) <> expected then
              wrong := wrong + Format('(%d,%d) ', [x, y]);
          end;
        Check(wrong = '', Format('dotted line from %d to %d sets every even x and nothing else', [startX, endX]) +
          IfThen(wrong <> '', ', wrong at: ' + wrong));
      end;
  finally
    bmp.Free;
  end;
end;

{ ---- crash #7: system-wide Tab hotkey ---- }

function GlobalTabHotkeyFree: Boolean;
const
  cTestId = $BEEF;
begin
  { RegisterHotKey fails while another window has plain Tab registered. }
  result := RegisterHotKey(0, cTestId, 0, VK_TAB);
  if result then
    UnregisterHotKey(0, cTestId);
end;

{ Posted (not SendInput) so that nothing can reach another application; goes through
  TApplication.ProcessMessage like a real key, including the dialog-key handling. }
procedure PostKey(wnd: HWND; key: Word);
var
  scan: LPARAM;
begin
  scan := LPARAM(MapVirtualKey(key, 0)) shl 16;
  PostMessage(wnd, WM_KEYDOWN, key, scan or 1);
  PostMessage(wnd, WM_KEYUP, key, scan or 1 or (LPARAM(3) shl 30));
  Application.ProcessMessages;
end;

function EditorWantsTab(edit: TzPropInspEdit; shiftDown: Boolean): Boolean;
var
  saved, state: TKeyboardState;
begin
  GetKeyboardState(saved);
  state := saved;
  if shiftDown then
    state[VK_SHIFT] := $80
  else
    state[VK_SHIFT] := 0;
  SetKeyboardState(state);
  try
    result := edit.Perform(CM_WANTSPECIALKEY, VK_TAB, 0) <> 0;
  finally
    SetKeyboardState(saved);
  end;
end;

procedure TestNoGlobalHotkeyWhileEditing(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    other.SetFocus;
    if not GlobalTabHotkeyFree then
    begin
      Writeln('  info  plain Tab is already registered by another application: skipped');
      Exit;
    end;
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    Check(GetFocus = edit.Handle, 'editor has focus');
    Check(GlobalTabHotkeyFree, 'Tab is not registered as a global hotkey while the editor has focus');
  finally
    insp.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TestRejectedTextOnFocusLossLeavesNoHotkey(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Default'); // Boolean: only False/True are accepted
    if edit = nil then
      Exit;
    TypeText(edit, 'xyz');
    expectedExceptions := 1;
    other.SetFocus; // WM_KILLFOCUS commits the text, which is rejected
    Check(expectedExceptions = 0, 'rejected text reported');
    expectedExceptions := 0;
    Check(GlobalTabHotkeyFree, 'no global Tab hotkey left registered');
  finally
    insp.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TestTabStartsSearch(form: TForm; insp: TzObjectInspector);
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(form);
  btn := TButton.Create(nil);
  btn.Parent := form;
  btn.Caption := 'Original';
  try
    insp.Component := btn;
    edit := SelectRow(insp, 'Caption');
    if edit = nil then
      Exit;
    Check(EditorWantsTab(edit, False), 'editor claims plain Tab');
    Check(not EditorWantsTab(edit, True), 'editor leaves Shift+Tab to dialog navigation');
    PostKey(edit.Handle, VK_TAB);
    Check(GetFocus = insp.Handle, 'Tab moved focus to the property names (search)');
    Check(Pos(#9, edit.Text) = 0, 'no tab character typed into the editor');
    Check(btn.Caption = 'Original', 'value unchanged');
    PostKey(insp.Handle, VK_TAB);
    Check(GetFocus = other.Handle, 'Tab while searching moves to the next control');
    insp.AllowSearch := False;
    Check(not EditorWantsTab(edit, False), 'with AllowSearch off, Tab is left to dialog navigation');
  finally
    insp.AllowSearch := True;
    insp.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

type
  TTestProc = reference to procedure(form: TForm; insp: TzObjectInspector);

procedure Run(const name: string; form: TForm; proc: TTestProc);
var
  insp: TzObjectInspector;
begin
  Writeln(name);
  try
    // fresh inspector per test so a failure cannot leak state into the next one
    insp := TzObjectInspector.Create(form);
    try
      insp.Parent := form;
      insp.SetBounds(0, 0, 380, 460);
      proc(form, insp);
    finally
      insp.Free;
    end;
  except
    on e: Exception do
    begin
      Writeln('  FAIL  exception ', e.ClassName, ': ', e.Message);
      Inc(failures);
    end;
  end;
end;

var
  form: TForm;
  sink: TExceptionSink;
begin
  ReportMemoryLeaksOnShutdown := False;
  failures := 0;
  Application.Initialize;
  sink := TExceptionSink.Create;
  Application.OnException := sink.HandleException;
  form := TForm.Create(nil);
  try
    form.SetBounds(100, 100, 400, 500);
    Run('Root component (no owner) freed', form, TestRootFreedNoOwner);
    Run('Root component (same owner) freed', form, TestRootFreedSameOwner);
    Run('Nested component reference freed', form, TestNestedComponentFreed);
    Run('Hosted object freed', form, TestHostMemberFreed);
    Run('Component removed from owner but not freed', form, TestRemovedFromOwnerNotFreed);
    Writeln('Inspector freed before component');
    TestInspectorFreedFirst(form);
    form.Show;
    Run('Root freed while editor has pending text', form, TestRootFreedWithPendingEdit);
    Writeln;
    Writeln('---- crash #2 ----');
    Run('UpdateProperties with pending editor text', form, TestUpdatePropertiesWithPendingEdit);
    Run('CollapseAll with pending editor text', form, TestCollapseAllWithPendingEdit);
    Run('Component change with pending editor text', form, TestComponentChangeWithPendingEdit);
    Run('Rebuild with rejected pending text', form, TestRebuildWithInvalidPendingText);
    Run('+/- click that rebuilds keeps the editor valid', form, TestExpandClickRebuildKeepsEditor);
    Run('Paint while items are being enumerated', form, TestPaintDuringEnumeration);
    Writeln;
    Writeln('---- crash #8 ----');
    Run('Programmatic changes do not take focus', form, TestProgrammaticChangesDoNotTakeFocus);
    Run('Deferred rebuild does not take focus', form, TestDeferredRebuildDoesNotTakeFocus);
    Run('Hidden inspector with a selected row', form, TestHiddenInspectorDoesNotRaise);
    Run('Keyboard navigation keeps focus in the editor', form, TestKeyboardNavigationKeepsFocus);
    Run('Clicking a row focuses the editor', form, TestClickFocusesEditor);
    Writeln;
    Writeln('---- crash #3 ----');
    Run('SetPropValue with nothing selected', form, TestSetPropValueWithNothingSelected);
    Run('SetPropValue with a category row selected', form, TestSetPropValueWithCategorySelected);
    Writeln;
    Writeln('---- crash #7 ----');
    Run('No global hotkey while editing', form, TestNoGlobalHotkeyWhileEditing);
    Run('Rejected text on focus loss leaves no hotkey', form, TestRejectedTextOnFocusLossLeavesNoHotkey);
    Run('Tab in the editor starts searching', form, TestTabStartsSearch);
    Writeln;
    Writeln('---- crash #5 ----');
    Run('Canvas stack indexed access', form, TestCanvasStackIndexedAccess);
    Run('Getter raising during paint, then Invalidate', form, TestGetterRaisingDuringPaint);
    Writeln;
    Writeln('---- crash #6 ----');
    Run('Down arrow on the last dropdown item', form, TestDropDownDownArrowOnLastItem);
    Run('Down arrow through a long dropdown', form, TestDropDownDownArrowThroughLongList);
    Writeln;
    Writeln('---- crash #10 ----');
    Run('Free the inspector while editing', form, TestFreeInspectorWhileEditing);
    Writeln;
    Writeln('---- crash #9 ----');
    Run('Font changed before Parent is set', form, TestFontChangeBeforeParent);
    Run('Parented to a control that has no window yet', form, TestParentWithoutWindow);
    Writeln;
    Writeln('---- invalid numbers ----');
    Run('Invalid and out-of-range numbers are rejected', form, TestInvalidNumbersRejected);
    Run('Valid numbers are accepted', form, TestValidNumbersAccepted);
    Writeln;
    Writeln('---- other float types ----');
    Run('TDateTime, TDate, TTime, Currency and distinct float types accept values', form, TestOtherFloatTypesAccepted);
    Run('Other float types reject invalid text', form, TestOtherFloatTypesRejectInvalid);
    Writeln;
    Writeln('---- TzObjectHost leak ----');
    Run('Inspector owns the TzObjectHost it is given', form, TestHostOwnership);
    Writeln;
    Writeln('---- batch: small fixes ----');
    Run('Editor text colour', form, TestEditorTextColour);
    Run('Search reaches the last row', form, TestSearchReachesLastRow);
    Run('SplitterPos set from code moves the editor', form, TestSplitterPosMovesEditor);
    Run('WideChar value above #255', form, TestWideCharValue);
    Run('Dropdown inside the monitor work area', form, TestDropDownInsideWorkArea);
    Run('Indentation ignores ToString', form, TestIndentationIgnoresToString);
    Run('Set elements in declaration order', form, TestSetElementOrder);
    Run('A host does not switch on SortByCategory', form, TestHostDoesNotForceCategories);
    Run('zObjInspDialogs.TzInspDialog is the real one', form, TestInspDialogAlias);
    Run('Function-type event lists its handler', form, TestFunctionEventHandlerListed);
    Run('Canvas stack created from a collection', form, TestCanvasStackFromCollection);
    Run('FloatConv blank text', form, TestFloatConvBlankText);
    Run('FloatPreference is copied, not stored', form, TestFloatPreferenceIsCopied);
    Writeln;
    Writeln('---- batch 2 ----');
    Run('Component references can be set and cleared', form, TestComponentReferences);
    Run('Raising getters do not break the inspector', form, TestRaisingGettersDoNotBreakInspector);
    Run('Edits without WM_CHAR are committed', form, TestEditsWithoutWmCharCommitted);
    Run('Non-visual component events', form, TestNonVisualComponentEvents);
    Run('ExpandAll survives a rebuild', form, TestExpandAllSticks);
    Writeln;
    Writeln('---- performance batch ----');
    Run('Moving to another row commits typed text', form, TestRowChangeCommitsTypedText);
    Run('Dropdown button follows the selected row', form, TestDropDownButtonFollowsRow);
    Run('GetUsedProperties returns each name once', form, TestUsedPropertiesUnique);
    Run('ObjectVisibility change clears the HasChild cache', form, TestObjectVisibilityClearsCache);
    Writeln;
    Writeln('---- batch 4 ----');
    Run('Category registrations survive component changes', form, TestCategoryRegistrationsKept);
    Run('Sets beyond element 31', form, TestLargeSets);
    Run('Item hints leave the control''s Hint alone', form, TestItemHintLeavesControlHint);
    Run('Non-default follows the RTTI default', form, TestNonDefaultFollowsRtti);
    Run('FloatPreference per inspector', form, TestFloatPreferencePerInspector);
    Run('GetValue reads only the value', form, TestGetValueReadsOnlyTheValue);
    Run('Reference cycle through plain objects', form, TestCircularLinkThroughPlainObjects);
    Writeln;
    Writeln('---- performance batch 2 ----');
    Run('Count and Items follow the parent links', form, TestChildLinks);
    Run('Dotted line pixels', form, TestDrawHorzDotLinePixels);
    Run('The dropdown button follows the editor', form, TestButtonFollowsEditor);
  finally
    form.Free;
    Application.OnException := nil;
    sink.Free;
  end;
  Writeln;
  if failures = 0 then
    Writeln('ALL PASSED')
  else
    Writeln(failures, ' FAILURE(S)');
  ExitCode := failures;
end.

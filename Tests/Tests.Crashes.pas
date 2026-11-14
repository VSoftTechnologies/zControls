unit Tests.Crashes;

{ Tests for the crashes and memory-safety bugs in CODE_REVIEW.md, one fixture
  per numbered item. }

interface

uses
  DUnitX.TestFramework,
  Testing.Inspector;

type
  { 1. No free notification on the inspected object }
  [TestFixture]
  TFreedComponentTests = class(TInspectorTestCase)
  public
    [Test] procedure RootFreedNoOwner;
    [Test] procedure RootFreedSameOwner;
    [Test] procedure NestedComponentFreed;
    [Test] procedure HostMemberFreed;
    [Test] procedure RemovedFromOwnerNotFreed;
    [Test] procedure InspectorFreedFirst;
    [Test] procedure RootFreedWithPendingEdit;
  end;

  { 2. PPropItem pointers dangle after every rebuild }
  [TestFixture]
  TRebuildTests = class(TInspectorTestCase)
  public
    [Test] procedure UpdatePropertiesWithPendingEdit;
    [Test] procedure CollapseAllWithPendingEdit;
    [Test] procedure ComponentChangeWithPendingEdit;
    [Test] procedure RebuildWithInvalidPendingText;
    [Test] procedure ExpandClickRebuildKeepsEditor;
    [Test] procedure PaintDuringEnumeration;
  end;

  { 3. SetPropValue with nothing selected always crashed }
  [TestFixture]
  TSetPropValueTests = class(TInspectorTestCase)
  public
    [Test] procedure SetPropValueWithNothingSelected;
    [Test] procedure SetPropValueWithCategorySelected;
  end;

  { 5. TStackEx<T>.Get always recursed until the stack overflowed }
  [TestFixture]
  TCanvasStackTests = class(TInspectorTestCase)
  public
    [Test] procedure CanvasStackIndexedAccess;
    [Test] procedure GetterRaisingDuringPaint;
  end;

  { 6. The Down arrow in an open dropdown raised EListError }
  [TestFixture]
  TDropDownTests = class(TInspectorTestCase)
  public
    [Test] procedure DropDownDownArrowOnLastItem;
    [Test] procedure DropDownDownArrowThroughLongList;
  end;

  { 7. The Tab key could be broken in every application }
  [TestFixture]
  TTabKeyTests = class(TInspectorTestCase)
  public
    [Test] procedure NoGlobalHotkeyWhileEditing;
    [Test] procedure RejectedTextOnFocusLossLeavesNoHotkey;
    [Test] procedure TabStartsSearch;
  end;

  { 8. UpdateEditControl always called SetFocus }
  [TestFixture]
  TFocusTests = class(TInspectorTestCase)
  public
    [Test] procedure ProgrammaticChangesDoNotTakeFocus;
    [Test] procedure DeferredRebuildDoesNotTakeFocus;
    [Test] procedure HiddenInspectorDoesNotRaise;
    [Test] procedure KeyboardNavigationKeepsFocus;
    [Test] procedure ClickFocusesEditor;
  end;

  { 9. Setting Font before Parent raised }
  [TestFixture]
  TFontTests = class(TInspectorTestCase)
  public
    [Test] procedure FontChangeBeforeParent;
    [Test] procedure ParentWithoutWindow;
  end;

  { 10. Wrong destructor order }
  [TestFixture]
  TDestructorTests = class(TInspectorTestCase)
  public
    [Test] procedure FreeInspectorWhileEditing;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Rtti,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.ExtCtrls,
  zCanvasStack,
  zObjInspector;

{ ---- crash #1: no free notification on the inspected object ---- }

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

procedure TFreedComponentTests.RootFreedNoOwner;
var
  btn: TButton;
  oldPtr: Pointer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  FInspector.Component := btn;
  Assert.IsTrue(FInspector.Items.Count > 0, 'items populated');
  oldPtr := btn;
  btn.Free;
  Assert.IsTrue(FInspector.Component = nil, 'Component cleared when root freed');
  Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'no item references the freed root');
  PaintInspector(FInspector);
  Application.ProcessMessages;
  Assert.IsTrue(FInspector.Component = nil, 'Component still nil after message pump');
end;

procedure TFreedComponentTests.RootFreedSameOwner;
var
  btn: TButton;
  oldPtr: Pointer;
begin
  btn := TButton.Create(FForm);
  btn.Parent := FForm;
  FInspector.Component := btn;
  oldPtr := btn;
  btn.Free;
  Assert.IsTrue(FInspector.Component = nil, 'Component cleared when root (same owner) freed');
  Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'no item references the freed root');
  PaintInspector(FInspector);
end;

procedure TFreedComponentTests.NestedComponentFreed;
var
  btn: TButton;
  menu: TPopupMenu;
  menuItem: TMenuItem;
  item: PPropItem;
  oldPtr: Pointer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  menu := TPopupMenu.Create(nil);
  menuItem := TMenuItem.Create(menu);
  menuItem.Caption := 'Test';
  menu.Items.Add(menuItem);
  btn.PopupMenu := menu;
  try
    FInspector.Component := btn;
    item := FindTopItem(FInspector, 'PopupMenu');
    Assert.IsTrue(item <> nil, 'PopupMenu row exists');
    FInspector.ExpandItem(item);
    Assert.IsTrue(ItemsReference(FInspector, menu), 'expanded rows reference the popup menu');
    PaintInspector(FInspector);
    oldPtr := menu;
    menu.Free;
    Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'no item references the freed popup menu (synchronous)');
    PaintInspector(FInspector);
    Application.ProcessMessages;
    Assert.IsTrue(FInspector.Component = btn, 'root still inspected');
    Assert.IsTrue(btn.PopupMenu = nil, 'button released its popup menu');
    Assert.IsTrue(FInspector.Items.Count > 0, 'items rebuilt after message pump');
    Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'rebuilt items do not reference the freed popup menu');
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TFreedComponentTests.HostMemberFreed;
var
  btn1, btn2: TButton;
  host: TzObjectHost;
  oldPtr: Pointer;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  try
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'Btn1');
    host.AddObject(btn2, 'Btn2');
    FInspector.Component := host;
    Assert.IsTrue(ItemsReference(FInspector, btn1) and ItemsReference(FInspector, btn2), 'both hosted objects listed');
    oldPtr := btn1;
    btn1.Free;
    btn1 := nil;
    Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'no item references the freed hosted object (synchronous)');
    PaintInspector(FInspector);
    Application.ProcessMessages;
    Assert.IsTrue(FInspector.Component = host, 'host still inspected');
    Assert.IsTrue(ItemsReference(FInspector, btn2), 'remaining hosted object listed after rebuild');
    Assert.IsTrue(not ItemsReference(FInspector, oldPtr), 'freed hosted object not listed after rebuild');
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil; // frees the host
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TFreedComponentTests.RemovedFromOwnerNotFreed;
var
  btn: TButton;
begin
  btn := TButton.Create(FForm);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    FForm.RemoveComponent(btn);
    Application.ProcessMessages;
    Assert.IsTrue(FInspector.Component = btn, 'Component kept when only removed from owner');
    Assert.IsTrue(FInspector.Items.Count > 0, 'items kept when only removed from owner');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TFreedComponentTests.InspectorFreedFirst;
var
  btn: TButton;
  own: TzObjectInspector;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  own := TzObjectInspector.Create(nil);
  own.Parent := FForm;
  own.Component := btn;
  own.Free;
  btn.Free; // must not notify the freed inspector
end;

procedure TFreedComponentTests.RootFreedWithPendingEdit;
var
  btn: TButton;
  item: PPropItem;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Caption := 'Original';
  FInspector.Component := btn;
  item := FindTopItem(FInspector, 'Caption');
  Assert.IsTrue(item <> nil, 'Caption row exists');
  FInspector.SetFocus;
  FInspector.SelectItem(FInspector.VisibleItems.IndexOf(item));
  edit := FindEdit(FInspector);
  Assert.IsTrue(Assigned(edit) and edit.Visible, 'editor visible on selected row');
  Log(TLogLevel.Information, 'editor has focus: ' + BoolToStr(GetFocus = edit.Handle, True));
  SendMessage(edit.Handle, WM_CHAR, Ord('X'), 0); // leaves uncommitted text
  btn.Free;
  Assert.IsTrue(FInspector.Component = nil, 'Component cleared');
  Assert.IsTrue(not edit.Visible, 'editor hidden after root freed');
  Application.ProcessMessages;
  PaintInspector(FInspector);
end;

{ ---- crash #2: PPropItem pointers dangle after a rebuild ---- }

{ True when p is nil or points at one of the inspector's current items. }
function PropInfoValid(insp: TzObjectInspector; p: PPropItem): Boolean;
begin
  result := (p = nil) or (insp.Items.IndexOf(p) >= 0);
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

procedure TRebuildTests.UpdatePropertiesWithPendingEdit;
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Caption := 'Original';
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor has focus (needed for this test)');
    TypeText(edit, 'X');
    FInspector.UpdateProperties(True);
    Assert.IsTrue(btn.Caption = 'X', 'pending text committed before the rebuild');
    Assert.IsTrue(PropInfoValid(FInspector, edit.PropInfo), 'editor points at a current item');
    Assert.IsTrue(edit.Visible and Assigned(edit.PropInfo), 'editor re-attached after the rebuild');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor keeps focus across the rebuild');
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TRebuildTests.CollapseAllWithPendingEdit;
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Caption := 'Original';
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    TypeText(edit, 'Y');
    FInspector.CollapseAll;
    Assert.IsTrue(btn.Caption = 'Y', 'pending text committed before collapsing');
    Assert.IsTrue(PropInfoValid(FInspector, edit.PropInfo), 'editor points at a current item');
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TRebuildTests.ComponentChangeWithPendingEdit;
var
  btn1, btn2: TButton;
  edit: TzPropInspEdit;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn1.Caption := 'One';
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  btn2.Caption := 'Two';
  try
    FInspector.Component := btn1;
    edit := SelectRow(FInspector, 'Caption');
    TypeText(edit, 'Z');
    FInspector.Component := btn2;
    Assert.IsTrue(btn1.Caption = 'Z', 'pending text committed to the previous component');
    Assert.IsTrue(btn2.Caption = 'Two', 'new component untouched');
    Assert.IsTrue(PropInfoValid(FInspector, edit.PropInfo), 'editor points at a current item');
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TRebuildTests.RebuildWithInvalidPendingText;
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Default'); // Boolean: only False/True are accepted
    TypeText(edit, 'xyz');
    FExpectedExceptions := 1;
    FInspector.UpdateProperties(True);
    Assert.IsTrue(FExpectedExceptions = 0, 'rejected text reported once');
    Assert.IsTrue(not btn.Default, 'value unchanged');
    Assert.IsTrue(PropInfoValid(FInspector, edit.PropInfo) and Assigned(edit.PropInfo), 'rebuild still happened and editor re-attached');
    Assert.IsTrue(edit.Text = 'False', 'editor shows the current value again');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TRebuildTests.ExpandClickRebuildKeepsEditor;
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
  btn.Parent := FForm;
  try
    handlers.FRejectChildren := True;
    FInspector.OnBeforeAddItem := handlers.BeforeAddItem;
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Font');
    index := FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Font'));
    pt := FInspector.PlusMinBtnRect[index].CenterPoint;
    SendMessage(FInspector.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
    SendMessage(FInspector.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
    Assert.IsTrue(PropInfoValid(FInspector, edit.PropInfo), 'editor does not point at a freed item');
    Assert.IsTrue(edit.Visible and Assigned(edit.PropInfo), 'editor still attached to the selected row');
    PaintInspector(FInspector);
  finally
    FInspector.OnBeforeAddItem := nil;
    FInspector.Component := nil;
    btn.Free;
    handlers.Free;
  end;
end;

procedure TRebuildTests.PaintDuringEnumeration;
var
  btn: TButton;
  handlers: TTestHandlers;
begin
  handlers := TTestHandlers.Create;
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    Assert.IsTrue(FInspector.VisibleItems.Count > 0, 'rows visible before the rebuild');
    handlers.FInspector := FInspector;
    handlers.FPaintDuringEnum := True;
    FInspector.OnBeforeAddItem := handlers.BeforeAddItem;
    FInspector.UpdateProperties(True);
    Assert.IsTrue(not handlers.FPaintDuringEnum, 'painted while the items were being enumerated');
    Assert.IsTrue(FInspector.VisibleItems.Count > 0, 'rows visible after the rebuild');
  finally
    FInspector.OnBeforeAddItem := nil;
    FInspector.Component := nil;
    btn.Free;
    handlers.Free;
  end;
end;

{ ---- crash #3: SetPropValue with no editor item ---- }

procedure TSetPropValueTests.SetPropValueWithNothingSelected;
var
  btn: TButton;
  value: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    value := TValue.From<string>('Changed');
    Assert.IsTrue(FInspector.SetPropValue(FindTopItem(FInspector, 'Caption'), value), 'SetPropValue returned True');
    Assert.IsTrue(btn.Caption = 'Changed', 'value set');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TSetPropValueTests.SetPropValueWithCategorySelected;
var
  btn: TButton;
  value: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.SortByCategory := True;
    FInspector.Component := btn;
    Assert.IsTrue(FInspector.VisibleItems[0]^.IsCategory, 'first row is a category');
    FInspector.SetFocus;
    FInspector.SelectItem(0);
    value := TValue.From<string>('Changed');
    Assert.IsTrue(FInspector.SetPropValue(FindTopItem(FInspector, 'Caption'), value), 'SetPropValue returned True');
    Assert.IsTrue(btn.Caption = 'Changed', 'value set');
  finally
    FInspector.SortByCategory := False;
    FInspector.Component := nil;
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

procedure TCanvasStackTests.CanvasStackIndexedAccess;
var
  stack: TzCanvasStack;
  bmp: TBitmap;
begin
  stack := TzCanvasStack.Create;
  bmp := TBitmap.Create;
  try
    stack.Push(bmp.Canvas);
    stack.Push(bmp.Canvas);
    Assert.IsTrue(stack.Peek(0) = bmp.Canvas, 'Peek(0) returns the bottom canvas');
    stack.Clear; // frees the saved brush/font/pen objects through indexed access
    Assert.IsTrue(stack.Count = 0, 'Clear empties the stack');
  finally
    bmp.Free;
    stack.Free;
  end;
end;

procedure TCanvasStackTests.GetterRaisingDuringPaint;
var
  obj: TRaisingObject;
  raised: Boolean;
begin
  obj := TRaisingObject.Create;
  try
    FInspector.Component := obj;
    Assert.IsTrue(FInspector.VisibleItems.Count = 2, 'both rows visible');
    PaintInspector(FInspector);
    obj.FRaise := True;
    raised := False;
    try
      PaintInspector(FInspector);
    except
      on e: Exception do
        raised := True;
    end;
    { not part of #5: whether a raising getter should break the whole paint }
    Log(TLogLevel.Information, 'getter exception escaped the paint: ' + BoolToStr(raised, True));
    obj.FRaise := False;
    try
      FInspector.Invalidate; // TzObjInspectorBase.Invalidate clears the canvas stack
    except
      on e: Exception do
        Assert.Fail('Invalidate after a failed paint raised ' + e.ClassName + ': ' + e.Message);
    end;
    PaintInspector(FInspector);
  finally
    FInspector.Component := nil;
    obj.Free;
  end;
end;

{ ---- crash #6: Down arrow in an open dropdown ---- }

procedure TDropDownTests.DropDownDownArrowOnLastItem;
var
  btn: TButton;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Default'); // Boolean: a two-item list
    list := OpenDropDown(FInspector);
    Assert.IsTrue(list.Items.Count = 2, 'False and True listed');
    list.ItemIndex := list.Items.Count - 1;
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Assert.IsTrue(list.ItemIndex = list.Items.Count - 1, 'Down on the last item stays on it');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TDropDownTests.DropDownDownArrowThroughLongList;
var
  panel: TPanel;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
  i, steps: Integer;
begin
  panel := TPanel.Create(nil);
  panel.Parent := FForm;
  try
    FInspector.Component := panel;
    edit := SelectRow(FInspector, 'Color');
    list := OpenDropDown(FInspector);
    steps := FInspector.VisiblePropCount + 5;
    Assert.IsTrue(list.Items.Count > steps, 'colour list is longer than the inspector has rows');
    list.ItemIndex := 0;
    for i := 1 to steps do
      SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Assert.IsTrue(list.ItemIndex = steps, 'Down moves through the whole list');
  finally
    FInspector.Component := nil;
    panel.Free;
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

procedure TTabKeyTests.NoGlobalHotkeyWhileEditing;
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(FForm);
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    other.SetFocus;
    if not GlobalTabHotkeyFree then
    begin
      Log(TLogLevel.Warning, 'skipped: plain Tab is already registered by another application');
      Exit;
    end;
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor has focus');
    Assert.IsTrue(GlobalTabHotkeyFree, 'Tab is not registered as a global hotkey while the editor has focus');
  finally
    FInspector.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TTabKeyTests.RejectedTextOnFocusLossLeavesNoHotkey;
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(FForm);
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Default'); // Boolean: only False/True are accepted
    TypeText(edit, 'xyz');
    FExpectedExceptions := 1;
    other.SetFocus; // WM_KILLFOCUS commits the text, which is rejected
    Assert.IsTrue(FExpectedExceptions = 0, 'rejected text reported');
    Assert.IsTrue(GlobalTabHotkeyFree, 'no global Tab hotkey left registered');
  finally
    FInspector.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TTabKeyTests.TabStartsSearch;
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(FForm);
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Caption := 'Original';
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    Assert.IsTrue(EditorWantsTab(edit, False), 'editor claims plain Tab');
    Assert.IsTrue(not EditorWantsTab(edit, True), 'editor leaves Shift+Tab to dialog navigation');
    PostKey(edit.Handle, VK_TAB);
    Assert.IsTrue(GetFocus = FInspector.Handle, 'Tab moved focus to the property names (search)');
    Assert.IsTrue(Pos(#9, edit.Text) = 0, 'no tab character typed into the editor');
    Assert.IsTrue(btn.Caption = 'Original', 'value unchanged');
    PostKey(FInspector.Handle, VK_TAB);
    Assert.IsTrue(GetFocus = other.Handle, 'Tab while searching moves to the next control');
    FInspector.AllowSearch := False;
    Assert.IsTrue(not EditorWantsTab(edit, False), 'with AllowSearch off, Tab is left to dialog navigation');
  finally
    FInspector.AllowSearch := True;
    FInspector.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

{ ---- crash #8: UpdateEditControl always calls SetFocus ---- }

procedure TFocusTests.ProgrammaticChangesDoNotTakeFocus;
var
  btn1, btn2: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
begin
  other := NewOtherEdit(FForm);
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  try
    FInspector.Component := btn1;
    edit := SelectRow(FInspector, 'Caption');
    other.SetFocus;
    Assert.IsTrue(GetFocus = other.Handle, 'focus moved to another control');
    FInspector.Component := btn2; // same class: the selected row is kept
    Assert.IsTrue(GetFocus = other.Handle, 'Component change does not take focus');
    Assert.IsTrue(edit.Visible and Assigned(edit.PropInfo), 'editor still shown for the selected row');
    FInspector.UpdateProperties(True);
    Assert.IsTrue(GetFocus = other.Handle, 'UpdateProperties does not take focus');
    FInspector.ExpandAll;
    Assert.IsTrue(GetFocus = other.Handle, 'ExpandAll does not take focus');
  finally
    FInspector.Component := nil;
    btn1.Free;
    btn2.Free;
    other.Free;
  end;
end;

procedure TFocusTests.DeferredRebuildDoesNotTakeFocus;
var
  btn: TButton;
  menu: TPopupMenu;
  other: TEdit;
begin
  other := NewOtherEdit(FForm);
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  menu := TPopupMenu.Create(nil);
  btn.PopupMenu := menu;
  try
    FInspector.Component := btn;
    SelectRow(FInspector, 'Caption');
    other.SetFocus;
    menu.Free;
    menu := nil;
    Application.ProcessMessages; // runs the deferred rebuild
    Assert.IsTrue(FInspector.Items.Count > 0, 'items rebuilt');
    Assert.IsTrue(GetFocus = other.Handle, 'rebuild after a referenced component is freed does not take focus');
  finally
    FInspector.Component := nil;
    btn.Free;
    menu.Free;
    other.Free;
  end;
end;

procedure TFocusTests.HiddenInspectorDoesNotRaise;
var
  btn1, btn2: TButton;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  try
    FInspector.Component := btn1;
    SelectRow(FInspector, 'Caption');
    FInspector.Visible := False; // like an inspector on a tab that is not shown
    try
      FInspector.UpdateProperties(True);
    except
      on e: Exception do
        Assert.Fail('UpdateProperties on a hidden inspector raised ' + e.ClassName + ': ' + e.Message);
    end;
    try
      FInspector.Component := btn2;
    except
      on e: Exception do
        Assert.Fail('Component change on a hidden inspector raised ' + e.ClassName + ': ' + e.Message);
    end;
  finally
    FInspector.Visible := True;
    FInspector.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TFocusTests.KeyboardNavigationKeepsFocus;
var
  btn: TButton;
  edit: TzPropInspEdit;
  before: PPropItem;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor focused after selecting a row in a focused inspector');
    before := FInspector.SelectedItem;
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0);
    Assert.IsTrue(FInspector.SelectedItem <> before, 'Down arrow selected the next row');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor keeps focus after the Down arrow');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TFocusTests.ClickFocusesEditor;
var
  btn: TButton;
  other: TEdit;
  edit: TzPropInspEdit;
  index: Integer;
  pt: TPoint;
begin
  other := NewOtherEdit(FForm);
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    other.SetFocus;
    index := FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Caption'));
    pt := FInspector.ValueRect[index].CenterPoint;
    SendMessage(FInspector.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
    SendMessage(FInspector.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
    edit := FindEdit(FInspector);
    Assert.IsTrue(Assigned(edit) and edit.Visible, 'clicking a row shows the editor');
    Assert.IsTrue(Assigned(edit) and (GetFocus = edit.Handle), 'clicking a row focuses the editor');
  finally
    FInspector.Component := nil;
    btn.Free;
    other.Free;
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

procedure TFontTests.FontChangeBeforeParent;
var
  own: TzObjectInspector;
  btn: TButton;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  own := TzObjectInspector.Create(nil);
  try
    try
      own.Font.Size := 14; // no parent yet
    except
      on e: Exception do
        Assert.Fail('setting Font before Parent raised ' + e.ClassName + ': ' + e.Message);
    end;
    Assert.IsTrue(not own.HandleAllocated, 'no window handle created early');
    own.Parent := FForm;
    own.SetBounds(0, 0, 380, 460);
    own.Component := btn;
    Assert.IsTrue(own.ItemRect[0].Height = ExpectedItemHeight(own.Font), 'row height follows the font');
    PaintInspector(own);
  finally
    own.Free;
    btn.Free;
  end;
end;

procedure TFontTests.ParentWithoutWindow;
var
  own: TzObjectInspector;
  panel: TPanel;
  btn: TButton;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  panel := TPanel.Create(nil);
  own := TzObjectInspector.Create(nil);
  try
    try
      own.Parent := panel; // the panel has no parent yet: built bottom-up
    except
      on e: Exception do
        Assert.Fail('parenting to a control without a window raised ' + e.ClassName + ': ' + e.Message);
    end;
    panel.Parent := FForm;
    panel.SetBounds(0, 0, 380, 460);
    own.SetBounds(0, 0, 380, 460);
    panel.Font.Size := 12; // reaches the inspector through ParentFont
    own.Component := btn;
    Assert.IsTrue(own.ItemRect[0].Height = ExpectedItemHeight(own.Font), 'row height follows the parent font');
    PaintInspector(own);
  finally
    own.Free;
    panel.Free;
    btn.Free;
  end;
end;

{ ---- crash #10: destructor frees its lists before the editor goes ---- }

procedure TDestructorTests.FreeInspectorWhileEditing;
var
  own: TzObjectInspector;
  btn: TButton;
  edit: TzPropInspEdit;
begin
  { uses its own inspector so the test controls when it is freed }
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Caption := 'Original';
  own := TzObjectInspector.Create(nil);
  try
    own.Parent := FForm;
    own.SetBounds(0, 0, 380, 460);
    own.Component := btn;
    edit := SelectRow(own, 'Caption');
    Assert.IsTrue(GetFocus = edit.Handle, 'editor has focus');
    TypeText(edit, 'X'); // uncommitted
    try
      FreeAndNil(own);
    except
      on e: Exception do
        Assert.Fail('freeing the inspector while editing raised ' + e.ClassName + ': ' + e.Message);
    end;
    Assert.IsTrue(btn.Caption = 'Original', 'pending text discarded, not written during teardown');
    PaintInspector(FInspector); // the form carries on normally
  finally
    own.Free;
    btn.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFreedComponentTests);
  TDUnitX.RegisterTestFixture(TRebuildTests);
  TDUnitX.RegisterTestFixture(TSetPropValueTests);
  TDUnitX.RegisterTestFixture(TCanvasStackTests);
  TDUnitX.RegisterTestFixture(TDropDownTests);
  TDUnitX.RegisterTestFixture(TTabKeyTests);
  TDUnitX.RegisterTestFixture(TFocusTests);
  TDUnitX.RegisterTestFixture(TFontTests);
  TDUnitX.RegisterTestFixture(TDestructorTests);

end.

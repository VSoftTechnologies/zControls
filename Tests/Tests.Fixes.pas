unit Tests.Fixes;

{ Tests for the smaller fixes in CODE_REVIEW.md, one fixture per batch. }

interface

uses
  DUnitX.TestFramework,
  Testing.Inspector;

type
  { The TzObjectHost given to the inspector leaked }
  [TestFixture]
  THostLeakTests = class(TInspectorTestCase)
  public
    [Test] procedure HostOwnership;
  end;

  { Batch 1: small fixes }
  [TestFixture]
  TBatch1Tests = class(TInspectorTestCase)
  public
    [Test] procedure EditorTextColour;
    [Test] procedure SearchReachesLastRow;
    [Test] procedure SplitterPosMovesEditor;
    [Test] procedure WideCharValue;
    [Test] procedure DropDownInsideWorkArea;
    [Test] procedure IndentationIgnoresToString;
    [Test] procedure SetElementOrder;
    [Test] procedure HostDoesNotForceCategories;
    [Test] procedure InspDialogAlias;
    [Test] procedure FunctionEventHandlerListed;
    [Test] procedure CanvasStackFromCollection;
    [Test] procedure FloatConvBlankText;
    [Test] procedure FloatPreferenceIsCopied;
  end;

  { Batch 2 }
  [TestFixture]
  TBatch2Tests = class(TInspectorTestCase)
  public
    [Test] procedure ComponentReferences;
    [Test] procedure RaisingGettersDoNotBreakInspector;
    [Test] procedure EditsWithoutWmCharCommitted;
    [Test] procedure NonVisualComponentEvents;
    [Test] procedure ExpandAllSticks;
  end;

  { Performance batch: regression guards }
  [TestFixture]
  TPerformanceTests = class(TInspectorTestCase)
  public
    [Test] procedure RowChangeCommitsTypedText;
    [Test] procedure DropDownButtonFollowsRow;
    [Test] procedure UsedPropertiesUnique;
    [Test] procedure ObjectVisibilityClearsCache;
  end;

  { Batch 4 }
  [TestFixture]
  TBatch4Tests = class(TInspectorTestCase)
  public
    [Test] procedure CategoryRegistrationsKept;
    [Test] procedure LargeSets;
    [Test] procedure ItemHintLeavesControlHint;
    [Test] procedure NonDefaultFollowsRtti;
    [Test] procedure FloatPreferencePerInspector;
    [Test] procedure CircularLinkThroughPlainObjects;
    [Test] procedure GetValueReadsOnlyTheValue;
  end;

  { Performance batch 2: regression guards }
  [TestFixture]
  TPerformance2Tests = class(TInspectorTestCase)
  public
    [Test] procedure ChildLinks;
    [Test] procedure ButtonFollowsEditor;
    [Test] procedure DrawHorzDotLinePixels;
  end;

  { Batch 5 }
  [TestFixture]
  TBatch5Tests = class(TInspectorTestCase)
  public
    [Test] procedure ReplacedObjectIsNotRead;
    [Test] procedure ReplacedObjectEditorText;
    [Test] procedure NewObjectOnEveryRead;
    [Test] procedure SelectHandlerThatRebuilds;
    [Test] procedure RejectedTextRevertsOnFocusLoss;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.ExtCtrls,
  FloatConv,
  zCanvasStack,
  zUtils,
  zObjInspDialogs,
  zObjInspector;

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

procedure THostLeakTests.HostOwnership;
var
  own: TzObjectInspector;
  btn: TButton;
  host: TTrackedHost;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  own := TzObjectInspector.Create(nil);
  try
    own.Parent := FForm;
    own.SetBounds(0, 0, 380, 460);

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    own.Component := nil;
    Assert.IsTrue(trackedHostFreed, 'host freed when Component is set to nil');

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    own.Component := btn;
    Assert.IsTrue(trackedHostFreed, 'host freed when Component is replaced');

    host := TTrackedHost.Create;
    host.AddObject(btn, 'Btn');
    trackedHostFreed := False;
    own.Component := host;
    FreeAndNil(own);
    Assert.IsTrue(trackedHostFreed, 'host freed with the inspector');
  finally
    own.Free;
    btn.Free;
  end;
end;

{ ---- batch: small fixes ---- }

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

procedure TBatch1Tests.EditorTextColour;
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    Assert.IsTrue(TControlAccess(edit).Font.Color = clWindowText, 'editor text uses clWindowText (was 0, black)');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TBatch1Tests.SearchReachesLastRow;
var
  btn: TButton;
  edit: TzPropInspEdit;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    FInspector.SetFocus;
    FInspector.SelectItem(FInspector.VisibleItems.Count - 1);
    edit := FindEdit(FInspector);
    Assert.IsTrue(Assigned(edit) and (GetFocus = edit.Handle), 'editor focused on the last row');
    PostKey(edit.Handle, VK_TAB);
    Assert.IsTrue(GetFocus = FInspector.Handle, 'Tab on the last row starts searching');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TBatch1Tests.SplitterPosMovesEditor;
var
  btn: TButton;
  edit: TzPropInspEdit;
  oldLeft: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Caption');
    oldLeft := edit.Left;
    FInspector.SplitterPos := FInspector.SplitterPos + 40;
    Assert.IsTrue(edit.Left = oldLeft + 40, 'editor follows SplitterPos set from code');
    FInspector.SplitterPos := FInspector.SplitterPos - 40;
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TBatch1Tests.WideCharValue;
var
  ed: TEdit;
begin
  ed := TEdit.Create(nil);
  ed.Parent := FForm;
  try
    FInspector.Component := ed;
    EnterText(FInspector, 'PasswordChar', #$25CF);
    Assert.IsTrue(ed.PasswordChar = #$25CF, 'PasswordChar accepts U+25CF (was stored as U+00CF)');
  finally
    FInspector.Component := nil;
    ed.Free;
  end;
end;

procedure TBatch1Tests.DropDownInsideWorkArea;
var
  panel: TPanel;
  list: TzPopupListBox;
  r: TRect;
begin
  { Only a sanity check on one monitor: the multi-monitor case can't be set up here. }
  panel := TPanel.Create(nil);
  panel.Parent := FForm;
  try
    FInspector.Component := panel;
    SelectRow(FInspector, 'Color');
    list := OpenDropDown(FInspector);
    GetWindowRect(list.Handle, r);
    Assert.IsTrue(r.Height > 0, 'dropdown has a height');
    Assert.IsTrue(r.Bottom <= Screen.MonitorFromRect(r).WorkareaRect.Bottom, 'dropdown fits the monitor work area');
  finally
    FInspector.Component := nil;
    panel.Free;
  end;
end;

procedure TBatch1Tests.IndentationIgnoresToString;
var
  dotted: TDottedName;
  plain: TPlainName;
  plainLeft: Integer;
begin
  dotted := TDottedName.Create;
  plain := TPlainName.Create;
  try
    FInspector.Component := plain;
    plainLeft := FInspector.PropTextRect[0].Left;
    FInspector.Component := dotted;
    Assert.IsTrue(FInspector.PropTextRect[0].Left = plainLeft, 'indentation does not depend on ToString');
  finally
    FInspector.Component := nil;
    dotted.Free;
    plain.Free;
  end;
end;

procedure TBatch1Tests.SetElementOrder;
var
  holder: TSetHolder;
  i, index: Integer;
  names: string;
begin
  holder := TSetHolder.Create;
  try
    FInspector.Component := holder;
    FInspector.ExpandItem(FindTopItem(FInspector, 'Big'));
    index := FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Big'));
    names := '';
    for i := index + 1 to FInspector.VisibleItems.Count - 1 do
      names := names + FInspector.VisibleItems[i]^.Name + ' ';
    Assert.IsTrue(names = 'e0 e1 e2 e3 e4 e5 e6 e7 e8 e9 e10 e11 ', 'set elements in declaration order, got: ' + names);
  finally
    FInspector.Component := nil;
    holder.Free;
  end;
end;

procedure TBatch1Tests.HostDoesNotForceCategories;
var
  btn: TButton;
  host: TzObjectHost;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    Assert.IsTrue(not FInspector.SortByCategory, 'starts without categories');
    host := TzObjectHost.Create;
    host.AddObject(btn, 'Btn');
    FInspector.Component := host;
    FInspector.Component := btn; // frees the host
    Assert.IsTrue(not FInspector.SortByCategory, 'SortByCategory not switched on by a host');
    Assert.IsTrue(not FInspector.VisibleItems[0]^.IsCategory, 'a normal component is not grouped');
  finally
    FInspector.SortByCategory := False;
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TBatch1Tests.InspDialogAlias;
begin
  Assert.IsTrue(TClass(zObjInspDialogs.TzInspDialog) = TClass(zObjInspector.TzInspDialog),
    'zObjInspDialogs.TzInspDialog is the TzInspDialog that ShowModalDialog accepts');
end;

procedure TBatch1Tests.FunctionEventHandlerListed;
var
  evForm: TEventForm;
  list: TzPopupListBox;
begin
  evForm := TEventForm.CreateNew(nil);
  try
    FInspector.Component := evForm;
    SelectRow(FInspector, 'OnHelp');
    list := OpenDropDown(FInspector);
    Assert.IsTrue(Assigned(list) and (list.Items.IndexOf('HelpHandler') >= 0), 'a function-type event lists its matching handler');
  finally
    FInspector.Component := nil;
    evForm.Free;
  end;
end;

procedure TBatch1Tests.CanvasStackFromCollection;
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
      Assert.IsTrue(stack.Peek(1) = bmp2.Canvas, 'Peek works on a stack created from a collection');
    finally
      stack.Free;
    end;
  finally
    bmp2.Free;
    bmp1.Free;
    canvases.Free;
  end;
end;

procedure TBatch1Tests.FloatConvBlankText;
var
  d: Double;
begin
  Assert.IsTrue(not MyTryStrToFloat('  ', d), 'MyTryStrToFloat rejects blank text');
end;

procedure TBatch1Tests.FloatPreferenceIsCopied;
var
  pref, saved: TzFloatPreference;
begin
  saved := TzFloatPreference.Create;
  try
    saved.Assign(FInspector.FloatPreference);
    pref := TzFloatPreference.Create;
    pref.MaxDigits := 5;
    pref.ExpPrecision := 9;
    FInspector.FloatPreference := pref;
    Assert.IsTrue(FInspector.FloatPreference <> pref, 'FloatPreference keeps its own object');
    pref.Free;
    Assert.IsTrue((FInspector.FloatPreference.MaxDigits = 5) and (FInspector.FloatPreference.ExpPrecision = 9),
      'settings copied, still readable after the caller frees its object');
    FInspector.FloatPreference := saved; // restore: the old code shared it between inspectors
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
  Assert.IsTrue(index >= 0, name + ' listed in the dropdown');
  r :=list.ItemRect(index);
  SendMessage(list.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(r.Left + 2, r.Top + 2));
  SendMessage(list.Handle, WM_LBUTTONUP, 0, MakeLParam(r.Left + 2, r.Top + 2));
  Application.ProcessMessages; // the click is applied from a posted message
end;

procedure TBatch2Tests.ComponentReferences;
var
  btn: TButton;
  menu1, menu2: TPopupMenu;
  edit: TzPropInspEdit;
  list: TzPopupListBox;
begin
  menu1 := TPopupMenu.Create(FForm);
  menu1.Name := 'RefMenu1';
  menu2 := TPopupMenu.Create(FForm);
  menu2.Name := 'RefMenu2';
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'PopupMenu');
    Assert.IsTrue(not TEditAccess(edit).ReadOnly, 'component reference editor is not read-only');

    list := OpenDropDown(FInspector);
    ClickListItem(list, 'RefMenu2');
    Assert.IsTrue(btn.PopupMenu = menu2, 'clicking RefMenu2 in the dropdown sets it');

    EnterText(FInspector, 'PopupMenu', 'RefMenu1');
    Assert.IsTrue(btn.PopupMenu = menu1, 'typing RefMenu1 and Enter sets it');

    edit := SelectRow(FInspector, 'PopupMenu');
    edit.SelectAll;
    SendMessage(edit.Handle, WM_CLEAR, 0, 0);
    SendMessage(edit.Handle, WM_CHAR, VK_RETURN, 0);
    Assert.IsTrue(btn.PopupMenu = nil, 'deleting the text and Enter clears it');

    edit := SelectRow(FInspector, 'PopupMenu');
    edit.SelectAll;
    TypeText(edit, 'RefMenu1'); // not committed
    list := OpenDropDown(FInspector);
    ClickListItem(list, 'RefMenu2');
    Assert.IsTrue(btn.PopupMenu = menu2, 'a dropdown choice wins over text typed before it');
  finally
    FInspector.Component := nil;
    btn.Free;
    menu1.Free;
    menu2.Free;
  end;
end;

procedure TBatch2Tests.RaisingGettersDoNotBreakInspector;
var
  obj: TRaisingWithChild;
  index: Integer;
  pt: TPoint;
begin
  obj := TRaisingWithChild.Create;
  obj.FRaise := True;
  try
    FInspector.Component := obj;
    Assert.IsTrue(FInspector.VisibleItems.Count = 2, 'both rows listed although their getters raise');
    PaintInspector(FInspector); // paints although the getters raise
    index := FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Boom'));
    pt := FInspector.ValueRect[index].CenterPoint;
    SendMessage(FInspector.Handle, WM_MOUSEMOVE, 0, MakeLParam(pt.X, pt.Y));
    SendMessage(FInspector.Handle, WM_LBUTTONDOWN, MK_LBUTTON, MakeLParam(pt.X, pt.Y));
    SendMessage(FInspector.Handle, WM_LBUTTONUP, 0, MakeLParam(pt.X, pt.Y));
    Assert.IsTrue(not FindEdit(FInspector).Visible, 'no editor for a row whose value can''t be read');
    FInspector.UpdateProperties(True); // rebuilds although the getters raise
  finally
    FInspector.Component := nil;
    obj.Free;
  end;
end;

procedure TBatch2Tests.EditsWithoutWmCharCommitted;
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
    edit.SelStart := Length(edit.Text);
    edit.SelLength := 0;
    SendMessage(edit.Handle, WM_CHAR, VK_BACK, 0);
    other.SetFocus;
    Assert.IsTrue(btn.Caption = 'Origina', 'a Backspace edit is committed when focus moves');

    edit := SelectRow(FInspector, 'Caption');
    edit.SetFocus; // the row was already selected, so SelectRow left focus on the inspector
    edit.SelectAll;
    SendMessage(edit.Handle, WM_CLEAR, 0, 0); // the context menu's Delete
    other.SetFocus;
    Assert.IsTrue(btn.Caption = '', 'a context-menu Delete is committed when focus moves');
  finally
    FInspector.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

procedure TBatch2Tests.NonVisualComponentEvents;
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
    FInspector.Component := item;
    row := FindTopItem(FInspector, 'OnClick');
    Assert.IsTrue(Assigned(row) and (row^.ValueName = 'ItemClick'), 'a TMenuItem shows its OnClick handler''s name');
    SelectRow(FInspector, 'OnClick');
    list := OpenDropDown(FInspector);
    Assert.IsTrue(list.Items.IndexOf('ItemClick') >= 0, 'its OnClick dropdown lists the form''s handlers');
  finally
    FInspector.Component := nil;
    evForm.Free;
  end;
end;

procedure TBatch2Tests.ExpandAllSticks;
var
  btn: TButton;
  total: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    FInspector.ExpandAll;
    total := FInspector.Items.Count;
    Assert.IsTrue(FInspector.VisibleItems.Count = total, 'ExpandAll shows every row');
    FInspector.UpdateProperties(True);
    Assert.IsTrue(FInspector.VisibleItems.Count = total, 'still expanded after a rebuild');
  finally
    FInspector.Component := nil;
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

procedure TPerformanceTests.RowChangeCommitsTypedText;
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
    TypeText(edit, 'Moved');
    SendMessage(edit.Handle, WM_KEYDOWN, VK_DOWN, 0); // to the next row, without Enter
    Assert.IsTrue(btn.Caption = 'Moved', 'text typed for a row is committed when moving to another row');
    Assert.IsTrue(GetFocus = edit.Handle, 'the editor keeps focus');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TPerformanceTests.DropDownButtonFollowsRow;
var
  btn: TButton;
  button: TzPropInspButton;
  i: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    SelectRow(FInspector, 'Default'); // Boolean: has a dropdown
    button := nil;
    for i := 0 to FInspector.ControlCount - 1 do
      if FInspector.Controls[i] is TzPropInspButton then
        button := TzPropInspButton(FInspector.Controls[i]);
    Assert.IsTrue(Assigned(button) and button.Visible, 'dropdown button shown for a Boolean row');
    SelectRow(FInspector, 'Caption'); // string: no dropdown
    Assert.IsTrue(Assigned(button) and not button.Visible, 'dropdown button hidden for a string row');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TPerformanceTests.UsedPropertiesUnique;
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
    except
      on e: Exception do
        Assert.Fail('GetUsedProperties returned a name twice: ' + e.Message);
    end;
    Assert.IsTrue((names.IndexOf('Caption') >= 0) and (names.IndexOf('Name') >= 0) and (names.IndexOf('Tag') >= 0),
      'GetUsedProperties includes declared and inherited properties');
  finally
    names.Free;
  end;
end;

procedure TPerformanceTests.ObjectVisibilityClearsCache;
var
  owner: TPlainOwner;
  row: PPropItem;
begin
  owner := TPlainOwner.Create;
  try
    FInspector.ObjectVisibility := mvPublic;
    FInspector.Component := owner;
    row := FindTopItem(FInspector, 'Child');
    Assert.IsTrue(Assigned(row) and row^.HasChild, 'a plain object with a public property can be expanded');
    FInspector.ObjectVisibility := mvPublished;
    Assert.IsTrue(Assigned(row) and not row^.HasChild, 'not after ObjectVisibility changes to mvPublished');
  finally
    FInspector.ObjectVisibility := mvPublic;
    FInspector.Component := nil;
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
  Assert.IsTrue(item <> nil, setName + '.' + element + ' row exists');
  insp.SetFocus;
  insp.SelectItem(insp.VisibleItems.IndexOf(item));
  edit := FindEdit(insp);
  Assert.IsTrue(Assigned(edit) and edit.Visible, 'editor visible on ' + setName + '.' + element);
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

procedure TBatch4Tests.CategoryRegistrationsKept;
var
  btn1, btn2: TButton;
  host: TzObjectHost;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  try
    FInspector.SortByCategory := True;
    FInspector.RegisterPropertyInCategory('Layout', 'Left');
    FInspector.Component := btn1;
    Assert.IsTrue(CategoryOf(FInspector, 'Left') = 'Layout', 'registered before Component is set: Left is in Layout, got ' + CategoryOf(FInspector, 'Left'));
    Assert.IsTrue(HasCategoryRow(FInspector, 'Layout'), 'a Layout category row');
    Assert.IsTrue(CategoryOf(FInspector, 'Caption') = FInspector.DefaultCategoryName, 'an unregistered property is in the default category');
    FInspector.Component := btn2;
    Assert.IsTrue(CategoryOf(FInspector, 'Left') = 'Layout', 'still in Layout after the component changes, got ' + CategoryOf(FInspector, 'Left'));
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'One');
    FInspector.Component := host;
    Assert.IsTrue(HasCategoryRow(FInspector, 'One'), 'a host still groups by object');
    FInspector.Component := btn2; // frees the host
    Assert.IsTrue(CategoryOf(FInspector, 'Left') = 'Layout', 'still in Layout after inspecting a TzObjectHost, got ' + CategoryOf(FInspector, 'Left'));
    FInspector.ClearRegisteredCategorys;
    Assert.IsTrue(CategoryOf(FInspector, 'Left') = FInspector.DefaultCategoryName, 'ClearRegisteredCategorys removes the registration');
    Assert.IsTrue(not HasCategoryRow(FInspector, 'Layout'), 'and the Layout row');
  finally
    FInspector.ClearRegisteredCategorys;
    FInspector.SortByCategory := False;
    FInspector.Component := nil;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TBatch4Tests.LargeSets;
var
  holder: TSetsHolder;
begin
  holder := TSetsHolder.Create;
  try
    holder.Wide := [0, 35, 40];
    holder.Upper := [40, 50];
    FInspector.Component := holder;
    Assert.IsTrue(ElementValue(FInspector, 'Wide', '35') = 'True', 'element 35 of a 41-element set shows True, got ' + ElementValue(FInspector, 'Wide', '35'));
    Assert.IsTrue(ElementValue(FInspector, 'Wide', '34') = 'False', 'element 34 shows False');
    Assert.IsTrue((ElementValue(FInspector, 'Wide', '0') = 'True') and (ElementValue(FInspector, 'Wide', '40') = 'True'),
      'the first and last elements show True');
    SetElement(FInspector, 'Wide', '34', 'True');
    Assert.IsTrue(holder.Wide = [0, 34, 35, 40], 'element 34 included, the others kept');
    SetElement(FInspector, 'Wide', '0', 'False');
    Assert.IsTrue(holder.Wide = [34, 35, 40], 'element 0 excluded, the others kept');
    Assert.IsTrue(ElementValue(FInspector, 'Upper', '50') = 'True', 'set of 40..50: element 50 shows True, got ' + ElementValue(FInspector, 'Upper', '50'));
    Assert.IsTrue(ElementValue(FInspector, 'Upper', '45') = 'False', 'set of 40..50: element 45 shows False');
    SetElement(FInspector, 'Upper', '45', 'True');
    Assert.IsTrue(holder.Upper = [40, 45, 50], 'set of 40..50: element 45 included, the others kept');
    SetElement(FInspector, 'Small', 'e3', 'True');
    Assert.IsTrue(holder.Small = [e3], 'a set of up to 32 elements still works');
    SetElement(FInspector, 'Small', 'e3', 'False');
    Assert.IsTrue(holder.Small = [], 'and its element can be excluded again');
  finally
    FInspector.Component := nil;
    holder.Free;
  end;
end;

procedure TBatch4Tests.ItemHintLeavesControlHint;
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
    r := FInspector.PropTextRect[row];
    pt := Point(r.Left + 2, (r.Top + r.Bottom) div 2);
    FInspector.Perform(WM_MOUSEMOVE, 0, MakeLParam(pt.X, pt.Y));
    info := Default(THintInfo);
    info.HintControl := FInspector;
    info.CursorPos := pt;
    info.HintStr := GetShortHint(FInspector.Hint);
    result := FInspector.Perform(CM_HINTSHOW, 0, LPARAM(@info)) = 0;
    hintText := info.HintStr;
  end;

begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    Application.ShowHint := False; // no real hint window while the test moves the mouse
    FForm.ShowHint := False;
    TControlAccess(FInspector).ParentShowHint := True; // not published by the inspector
    FInspector.Hint := 'Developer hint';
    FInspector.Component := btn;
    FInspector.SplitterPos := 30; // the names no longer fit
    PaintInspector(FInspector);
    Assert.IsTrue(HintAt(0, text) and (text = FInspector.VisibleItems[0]^.Name),
      'hint for a cut-off name on the first row, got: ' + text);
    Assert.IsTrue(FInspector.ShowHint, 'ShowHint is on while a cut-off name is under the mouse');
    Assert.IsTrue(HintAt(1, text) and (text = FInspector.VisibleItems[1]^.Name),
      'hint for a cut-off name on the second row, got: ' + text);
    Assert.IsTrue(FInspector.Hint = 'Developer hint', 'the control''s Hint is not overwritten, got: ' + FInspector.Hint);
    FInspector.Perform(CM_MOUSELEAVE, 0, 0);
    Assert.IsTrue(not FInspector.ShowHint and TControlAccess(FInspector).ParentShowHint, 'ShowHint and ParentShowHint restored when the mouse leaves');

    FInspector.SplitterPos := 200; // the names fit again
    FInspector.ShowHint := True;
    PaintInspector(FInspector);
    Assert.IsTrue(HintAt(0, text) and (text = 'Developer hint'), 'a name that fits shows the control''s own hint, got: ' + text);
    FInspector.Perform(CM_MOUSELEAVE, 0, 0);
    Assert.IsTrue(FInspector.ShowHint, 'ShowHint set by the application is left on');
  finally
    Application.ShowHint := True;
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TBatch4Tests.NonDefaultFollowsRtti;
var
  btn: TButton;
  panel: TPanel;
  menu: TPopupMenu;
  handlers: TEventForm;

  function NonDefault(const name: string): Boolean;
  var
    item: PPropItem;
  begin
    item := FindTopItem(FInspector, name);
    Assert.IsTrue(item <> nil, name + ' row exists');
    result := (item <> nil) and FInspector.IsValueNoDefault(item^.QualifiedName, item^.ValueName);
  end;

  function ElementNonDefault(const setName, element: string): Boolean;
  var
    item: PPropItem;
  begin
    FInspector.ExpandItem(FindTopItem(FInspector, setName));
    item := FindChild(FInspector, FindTopItem(FInspector, setName), element);
    Assert.IsTrue(item <> nil, setName + '.' + element + ' row exists');
    result := (item <> nil) and FInspector.IsValueNoDefault(item^.QualifiedName, item^.ValueName);
  end;

begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  panel := TPanel.Create(nil);
  panel.Parent := FForm;
  menu := TPopupMenu.Create(nil);
  menu.Name := 'Menu1';
  handlers := TEventForm.CreateNew(nil);
  try
    FInspector.Component := btn;
    Assert.IsTrue(not NonDefault('Anchors'), 'Anchors [akLeft,akTop] is the default');
    Assert.IsTrue(not ElementNonDefault('Anchors', 'akLeft'), 'Anchors.akLeft True is the default');
    Assert.IsTrue(not ElementNonDefault('Anchors', 'akRight'), 'Anchors.akRight False is the default');
    btn.Anchors := [akLeft, akTop, akRight];
    Assert.IsTrue(NonDefault('Anchors'), 'Anchors [akLeft,akTop,akRight] is non-default');
    Assert.IsTrue(ElementNonDefault('Anchors', 'akRight'), 'Anchors.akRight True is non-default');
    Assert.IsTrue(not ElementNonDefault('Anchors', 'akBottom'), 'Anchors.akBottom False is still the default');
    btn.ParentFont := False;
    Assert.IsTrue(not NonDefault('Font'), 'an owned object (Font) is not non-default itself');
    Assert.IsTrue(not NonDefault('PopupMenu'), 'no PopupMenu is the default');
    btn.PopupMenu := menu;
    Assert.IsTrue(NonDefault('PopupMenu'), 'a PopupMenu reference is non-default');
    Assert.IsTrue(not NonDefault('OnClick'), 'no OnClick handler is the default');
    btn.OnClick := handlers.ItemClick;
    Assert.IsTrue(NonDefault('OnClick'), 'an OnClick handler is non-default');
    FInspector.Component := nil;
    btn.Tag := 5;
    btn.Caption := '';
    FInspector.Component := btn;
    Assert.IsTrue(NonDefault('Tag'), 'Tag 5 (default 0) is non-default before its row is ever selected');
    Assert.IsTrue(not NonDefault('Cursor'), 'Cursor crDefault is the default');
    Assert.IsTrue(not NonDefault('Default'), 'Default False is the default');
    Assert.IsTrue(not NonDefault('Caption'), 'an empty Caption is the default');
    Assert.IsTrue(NonDefault('Left'), 'Left has no default, so it is always stored');
    btn.Tag := 0;
    Assert.IsTrue(not NonDefault('Tag'), 'Tag back to 0 is the default');
    EnterText(FInspector, 'Caption', 'X');
    Assert.IsTrue(NonDefault('Caption'), 'a non-empty Caption is non-default');
    panel.ParentColor := True;
    FInspector.Component := panel;
    Assert.IsTrue(not NonDefault('Color'), 'Color is not stored while ParentColor is True');
  finally
    FInspector.Component := nil;
    panel.Free;
    btn.Free;
    menu.Free;
    handlers.Free;
  end;
end;

procedure TBatch4Tests.FloatPreferencePerInspector;
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
    saved.Assign(FInspector.FloatPreference);
    other.Parent := FForm;
    other.SetBounds(0, 0, 380, 460);
    holder.Value := 1.23456789;
    FInspector.FloatPreference.ExpPrecision := 3;
    Assert.IsTrue(other.FloatPreference.ExpPrecision <> 3, 'another inspector keeps its own FloatPreference');
    FInspector.Component := holder;
    other.Component := holder;
    mine := FindTopItem(FInspector, 'Value')^.ValueName;
    theirs := FindTopItem(other, 'Value')^.ValueName;
    Assert.IsTrue(mine <> theirs, 'each inspector formats with its own settings: ' + mine + ' / ' + theirs);
  finally
    FInspector.FloatPreference := saved; // the old code shared it between inspectors
    FInspector.Component := nil;
    other.Free;
    holder.Free;
    saved.Free;
  end;
end;

procedure TBatch4Tests.CircularLinkThroughPlainObjects;
var
  root: TCircRoot;
begin
  root := TCircRoot.Create;
  try
    FInspector.Component := root;
    Assert.IsTrue(FInspector.Items.Count < 20, 'a reference cycle between plain objects is cut, items: ' + IntToStr(FInspector.Items.Count));
  finally
    FInspector.Component := nil;
    root.Free;
  end;
end;

procedure TBatch4Tests.GetValueReadsOnlyTheValue;
var
  btn: TButton;
  item: PPropItem;
  padded: TPaddedBool;
  v: TValue;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    item := FindTopItem(FInspector, 'Default');
    Assert.IsTrue(item <> nil, 'Default row exists');
    padded.Value := True;
    FillChar(padded.Pad, SizeOf(padded.Pad), $AB);
    v := TValueManagerAccess.GetValue(item, padded.Value);
    Assert.IsTrue(TValueData(v).FAsUInt64 = 1, 'GetValue reads the Boolean only, not the bytes after it: ' +
      IntToHex(TValueData(v).FAsUInt64, 16));
  finally
    FInspector.Component := nil;
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
  Assert.IsTrue(wrong = '', what + ': Count and Items match the parent links' + IfThen(wrong <> '', ', wrong for: ' + wrong));
end;

procedure TPerformance2Tests.ChildLinks;
var
  btn1, btn2: TButton;
  host: TzObjectHost;
  holder: TSetsHolder;
  font, past: PPropItem;
  raised: Boolean;
begin
  btn1 := TButton.Create(nil);
  btn1.Parent := FForm;
  btn2 := TButton.Create(nil);
  btn2.Parent := FForm;
  holder := TSetsHolder.Create;
  try
    FInspector.Component := btn1;
    CheckChildLinks(FInspector, 'a component');
    FInspector.ExpandAll;
    CheckChildLinks(FInspector, 'a component, expanded');
    FInspector.SortByCategory := True;
    FInspector.RegisterPropertyInCategory('Layout', 'Left');
    FInspector.UpdateProperties(True);
    CheckChildLinks(FInspector, 'grouped by category');
    FInspector.SortByCategory := False;
    host := TzObjectHost.Create;
    host.AddObject(btn1, 'One');
    host.AddObject(btn2, 'Two');
    FInspector.Component := host;
    CheckChildLinks(FInspector, 'a TzObjectHost');
    FInspector.Component := holder;
    CheckChildLinks(FInspector, 'sets');

    FInspector.Component := btn1;
    font := FindTopItem(FInspector, 'Font');
    Assert.IsTrue((font <> nil) and not font^.Expanded, 'Font starts collapsed');
    FInspector.ExpandItem(font);
    font := FindTopItem(FInspector, 'Font');
    Assert.IsTrue((font <> nil) and font^.Expanded, 'Font expanded');
    Assert.IsTrue((font <> nil) and (FindTopItem(FInspector, 'Caption')^.Count = 0) and (FindTopItem(FInspector, 'Caption')^.Items[0] = nil),
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
    Assert.IsTrue(raised and (past = nil), 'Items past the end raises EListError, as before');
  finally
    FInspector.ClearRegisteredCategorys;
    FInspector.SortByCategory := False;
    FInspector.Component := nil;
    holder.Free;
    btn1.Free;
    btn2.Free;
  end;
end;

procedure TPerformance2Tests.ButtonFollowsEditor;
var
  btn: TButton;
  edit: TzPropInspEdit;
  button: TzPropInspButton;
  i: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  try
    FInspector.Component := btn;
    edit := SelectRow(FInspector, 'Default'); // Boolean: a dropdown list
    button := nil;
    for i := 0 to FInspector.ControlCount - 1 do
      if FInspector.Controls[i] is TzPropInspButton then
        button := TzPropInspButton(FInspector.Controls[i]);
    Assert.IsTrue(button <> nil, 'the dropdown button exists');
    Assert.IsTrue(button.Visible and button.DropDown, 'a list row shows the dropdown arrow');
    Assert.IsTrue(button.Top = edit.Top - 3, 'the button is on the editor''s row');
    edit := SelectRow(FInspector, 'Font'); // an object with a dialog
    Assert.IsTrue(button.Visible and not button.DropDown, 'a dialog row shows "..."');
    Assert.IsTrue(button.Top = edit.Top - 3, 'the button moved with the editor');
    edit := SelectRow(FInspector, 'Cursor'); // a list again, on another row
    Assert.IsTrue(button.Visible and button.DropDown, 'back to the arrow');
    Assert.IsTrue(button.Top = edit.Top - 3, 'and moved again');
    Assert.IsTrue((button.Left = FInspector.ClientWidth - button.Width) and (edit.Left + edit.Width <= button.Left),
      'the button is at the right edge, after the editor');
    SelectRow(FInspector, 'Caption'); // no button
    Assert.IsTrue(not button.Visible, 'hidden on a row without one');
  finally
    FInspector.Component := nil;
    btn.Free;
  end;
end;

procedure TPerformance2Tests.DrawHorzDotLinePixels;
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
        Assert.IsTrue(wrong = '', Format('dotted line from %d to %d sets every even x and nothing else', [startX, endX]) +
          IfThen(wrong <> '', ', wrong at: ' + wrong));
      end;
  finally
    bmp.Free;
  end;
end;

{ ---- batch 5 ---- }

type
  TSwapLeaf = class(TPersistent)
  private
    FText: string;
  published
    property Text: string read FText write FText;
  end;

  TSwapChild = class(TPersistent)
  private
    FText: string;
    FLeaf: TSwapLeaf;
  public
    constructor Create(const text: string);
    destructor Destroy; override;
  published
    property Text: string read FText write FText;
    property Leaf: TSwapLeaf read FLeaf;
  end;

  { An object property whose object the program frees and replaces, as a setter that
    frees the old object does. }
  TSwapHolder = class(TPersistent)
  private
    FChild: TSwapChild;
  public
    constructor Create(const text: string);
    destructor Destroy; override;
    procedure Replace(const text: string);
  published
    property Child: TSwapChild read FChild;
  end;

  { A getter that returns a new object on every read. }
  TFreshHolder = class(TPersistent)
  private
    FMade: TObjectList<TSwapChild>;
    function GetFresh: TSwapChild;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Fresh: TSwapChild read GetFresh;
  end;

  TSelectHandlers = class
  public
    FInspector: TzObjectInspector;
    FCollapse: string; // a row to collapse from inside OnSelectItem, once
    function SelectItem(Sender: TControl; PItem: PPropItem): Boolean;
  end;

constructor TSwapChild.Create(const text: string);
begin
  inherited Create;
  FText := text;
  FLeaf := TSwapLeaf.Create;
  FLeaf.Text := text + ' leaf';
end;

destructor TSwapChild.Destroy;
begin
  FLeaf.Free;
  inherited;
end;

constructor TSwapHolder.Create(const text: string);
begin
  inherited Create;
  FChild := TSwapChild.Create(text);
end;

destructor TSwapHolder.Destroy;
begin
  FChild.Free;
  inherited;
end;

procedure TSwapHolder.Replace(const text: string);
begin
  FChild.Free;
  FChild := TSwapChild.Create(text);
end;

constructor TFreshHolder.Create;
begin
  inherited Create;
  FMade := TObjectList<TSwapChild>.Create;
end;

destructor TFreshHolder.Destroy;
begin
  FMade.Free;
  inherited;
end;

function TFreshHolder.GetFresh: TSwapChild;
begin
  result := TSwapChild.Create('fresh');
  FMade.Add(result);
end;

function TSelectHandlers.SelectItem(Sender: TControl; PItem: PPropItem): Boolean;
var
  item: PPropItem;
begin
  result := True;
  if FCollapse <> '' then
  begin
    item := FindTopItem(FInspector, FCollapse);
    FCollapse := '';
    FInspector.CollapseItem(item); // rebuilds the items, so PItem is freed
  end;
end;

function RebuildPosted(insp: TzObjectInspector): Boolean;
var
  msg: TMsg;
begin
  result := PeekMessage(msg, insp.Handle, ZCM_REBUILDITEMS, ZCM_REBUILDITEMS, PM_NOREMOVE);
end;

function SwapRow(insp: TzObjectInspector; const name: string): PPropItem;
var
  child: PPropItem;
begin
  child := FindTopItem(insp, 'Child');
  if name = 'Leaf.Text' then
    result := FindChild(insp, FindChild(insp, child, 'Leaf'), 'Text')
  else
    result := FindChild(insp, child, name);
end;

procedure ExpandSwapRows(insp: TzObjectInspector);
begin
  insp.ExpandItem(FindTopItem(insp, 'Child'));
  insp.ExpandItem(SwapRow(insp, 'Leaf'));
end;

procedure TBatch5Tests.ReplacedObjectIsNotRead;
var
  holder: TSwapHolder;
  text, leafText: PPropItem;
begin
  holder := TSwapHolder.Create('first');
  try
    FInspector.Component := holder;
    ExpandSwapRows(FInspector);
    text := SwapRow(FInspector, 'Text');
    leafText := SwapRow(FInspector, 'Leaf.Text');
    Assert.IsTrue((text <> nil) and (leafText <> nil), 'Child.Text and Child.Leaf.Text rows exist');
    Assert.IsTrue((text^.ValueName = 'first') and (leafText^.ValueName = 'first leaf'), 'the rows show the child''s values');
    holder.Replace('second');
    { Every read below used to go to the freed child: with PoisonMM, reading its
      string is an access violation. }
    PaintInspector(FInspector);
    Assert.IsTrue(text^.Instance = nil, 'a row of the replaced object reads nil');
    Assert.IsTrue(leafText^.Instance = nil, 'and so does a row of an object inside it, without reading the freed one');
    Assert.IsTrue((text^.ValueName = '') and (leafText^.ValueName = ''), 'neither shows a value');
    Assert.IsTrue(RebuildPosted(FInspector), 'a rebuild is posted');
    Application.ProcessMessages;
    text := SwapRow(FInspector, 'Text');
    leafText := SwapRow(FInspector, 'Leaf.Text');
    Assert.IsTrue((text <> nil) and (text^.ValueName = 'second'), 'the rebuild shows the new child');
    Assert.IsTrue((leafText <> nil) and (leafText^.ValueName = 'second leaf'), 'with its rows expanded as before');
  finally
    FInspector.Component := nil;
    holder.Free;
  end;
end;

procedure TBatch5Tests.ReplacedObjectEditorText;
var
  holder: TSwapHolder;
  text: PPropItem;
  edit: TzPropInspEdit;
  other: TEdit;
begin
  other := NewOtherEdit(FForm);
  holder := TSwapHolder.Create('first');
  try
    FInspector.Component := holder;
    ExpandSwapRows(FInspector);
    text := SwapRow(FInspector, 'Text');
    Assert.IsTrue(text <> nil, 'Child.Text row exists');
    FInspector.SetFocus;
    FInspector.SelectItem(FInspector.VisibleItems.IndexOf(text));
    edit := FindEdit(FInspector);
    Assert.IsTrue(Assigned(edit) and edit.Visible, 'editor on Child.Text');
    TypeText(edit, 'typed');
    holder.Replace('second');
    other.SetFocus; // WM_KILLFOCUS commits the typed text
    Assert.IsTrue(holder.Child.Text = 'second', 'text typed for the replaced child is dropped, not written to the new one');
    Application.ProcessMessages;
    text := SwapRow(FInspector, 'Text');
    Assert.IsTrue((text <> nil) and (text^.ValueName = 'second'), 'the rebuild shows the new child');
  finally
    FInspector.Component := nil;
    holder.Free;
    other.Free;
  end;
end;

procedure TBatch5Tests.NewObjectOnEveryRead;
var
  holder: TFreshHolder;
  i, posts: Integer;
  msg: TMsg;
begin
  holder := TFreshHolder.Create;
  try
    FInspector.Component := holder;
    FInspector.ExpandItem(FindTopItem(FInspector, 'Fresh'));
    Assert.IsTrue(FindChild(FInspector, FindTopItem(FInspector, 'Fresh'), 'Text') <> nil, 'Fresh expanded');
    { Only the rebuild message is dispatched, a fixed number of times: with
      ProcessMessages, a rebuild after every paint never ends and the run hangs. }
    posts := 0;
    for i := 1 to 3 do
    begin
      PaintInspector(FInspector);
      while PeekMessage(msg, FInspector.Handle, ZCM_REBUILDITEMS, ZCM_REBUILDITEMS, PM_REMOVE) do
      begin
        Inc(posts);
        DispatchMessage(msg);
      end;
    end;
    Assert.IsTrue(posts = 0, Format('no rebuild is posted for a getter that returns a new object on every read: ' +
      'it would repeat after every paint (%d posted)', [posts]));
  finally
    FInspector.Component := nil;
    holder.Free;
  end;
end;

procedure TBatch5Tests.SelectHandlerThatRebuilds;
var
  btn: TButton;
  handlers: TSelectHandlers;
  last: string;
  edit: TzPropInspEdit;
  caret: TPoint;
  index: Integer;
begin
  btn := TButton.Create(nil);
  btn.Parent := FForm;
  btn.Left := 17;
  handlers := TSelectHandlers.Create;
  try
    handlers.FInspector := FInspector;
    FInspector.Component := btn;
    FInspector.OnSelectItem := handlers.SelectItem;
    FInspector.SetFocus;

    { Left is below Font, so collapsing Font moves it up. }
    FInspector.ExpandItem(FindTopItem(FInspector, 'Font'));
    handlers.FCollapse := 'Font';
    FInspector.SelectItem(FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Left')));
    Assert.IsTrue((FInspector.SelectedItem <> nil) and (FInspector.SelectedItem^.Name = 'Left'),
      'the row asked for is selected after the handler collapsed a row above it');
    edit := FindEdit(FInspector);
    Assert.IsTrue(Assigned(edit) and (edit.Text = '17'), 'and the editor shows its value');

    { The last row: its index was past the end of the list after the collapse. }
    FInspector.ExpandItem(FindTopItem(FInspector, 'Font'));
    handlers.FCollapse := 'Font';
    last := FInspector.VisibleItems[FInspector.VisibleItems.Count - 1]^.QualifiedName;
    FInspector.SelectItem(FInspector.VisibleItems.Count - 1);
    Assert.IsTrue((FInspector.SelectedItem <> nil) and (FInspector.SelectedItem^.QualifiedName = last), 'the last row is selected');

    { Search: typing a name selects the row, and the caret goes on it. }
    FInspector.ExpandItem(FindTopItem(FInspector, 'Font'));
    edit := SelectRow(FInspector, 'Caption');
    PostKey(edit.Handle, VK_TAB);
    Assert.IsTrue(GetFocus = FInspector.Handle, 'searching');
    handlers.FCollapse := 'Font';
    PostKey(FInspector.Handle, Ord('L'));
    Assert.IsTrue((FInspector.SelectedItem <> nil) and (FInspector.SelectedItem^.Name = 'Left'), 'typing L selects Left');
    index := FInspector.VisibleItems.IndexOf(FindTopItem(FInspector, 'Left'));
    GetCaretPos(caret);
    Assert.IsTrue((index >= 0) and (caret.Y = FInspector.ItemRect[index].Top + 1), 'the caret is on that row');
  finally
    FInspector.OnSelectItem := nil;
    FInspector.Component := nil;
    handlers.Free;
    btn.Free;
  end;
end;

procedure TBatch5Tests.RejectedTextRevertsOnFocusLoss;
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
    Assert.IsTrue(not btn.Default, 'value unchanged');
    Assert.IsTrue(edit.Text = 'False', 'the editor shows the current value again, not the rejected text: ' + edit.Text);

    edit.SetFocus;
    edit.SelectAll;
    TypeText(edit, 'xyz');
    FExpectedExceptions := 1;
    PostKey(edit.Handle, VK_RETURN);
    Assert.IsTrue(FExpectedExceptions = 0, 'Enter reports rejected text too');
    Assert.IsTrue(edit.Text = 'xyz', 'and leaves it in the editor to be corrected');
  finally
    FInspector.Component := nil;
    btn.Free;
    other.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THostLeakTests);
  TDUnitX.RegisterTestFixture(TBatch1Tests);
  TDUnitX.RegisterTestFixture(TBatch2Tests);
  TDUnitX.RegisterTestFixture(TPerformanceTests);
  TDUnitX.RegisterTestFixture(TBatch4Tests);
  TDUnitX.RegisterTestFixture(TPerformance2Tests);
  TDUnitX.RegisterTestFixture(TBatch5Tests);

end.

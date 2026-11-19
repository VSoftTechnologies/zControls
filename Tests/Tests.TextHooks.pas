unit Tests.TextHooks;

{ The value manager's text hooks: EditsAsText lets a class-typed row take typed text,
  and TryTextToValue turns typed text into the value before the inspector's own
  parsing. }

interface

uses
  System.Rtti,
  Vcl.Controls,
  DUnitX.TestFramework,
  zObjInspector,
  Testing.Inspector;

type
  [TestFixture]
  TTextHookTests = class(TInspectorTestCase)
  private
    FCaptured: string;
    function CaptureSet(Sender: TControl; PItem: PPropItem; var NewValue: TValue): Boolean;
  public
    [Test] procedure TypedTextBecomesTheValueTheHookGives;
    [Test] procedure TextTheHookLeavesIsParsedAsBefore;
    [Test] procedure AClassRowTakesTextWhenTheManagerSaysSo;
    [Test] procedure AClassRowIsReadOnlyByDefault;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics;

type
  THookInner = class(TPersistent)
  private
    FTitle: string;
  published
    property Title: string read FTitle write FTitle;
  end;

  THookTarget = class(TPersistent)
  private
    FColour: TColor;
    FInner: THookInner;
    procedure SetInner(const Value: THookInner);
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Colour: TColor read FColour write FColour;
    property Inner: THookInner read FInner write SetInner;
  end;

  { '#RRGGBB' for Colour; any text for Inner, as a string value }
  THookManager = class(TzCustomValueManager)
  protected
    class function EditsAsText(const PItem: PPropItem): Boolean; override;
    class function TryTextToValue(const PItem: PPropItem; const Text: string;
      var Value: TValue): Boolean; override;
  end;

constructor THookTarget.Create;
begin
  inherited Create;
  FInner := THookInner.Create;
end;

destructor THookTarget.Destroy;
begin
  FInner.Free;
  inherited;
end;

procedure THookTarget.SetInner(const Value: THookInner);
begin
  FInner.Assign(Value);
end;

class function THookManager.EditsAsText(const PItem: PPropItem): Boolean;
begin
  Result := (PItem^.Prop <> nil) and SameText(PItem^.Prop.Name, 'Inner');
end;

class function THookManager.TryTextToValue(const PItem: PPropItem; const Text: string;
  var Value: TValue): Boolean;
var
  rgb: Integer;
begin
  Result := False;
  if PItem^.Prop = nil then
    Exit;
  if SameText(PItem^.Prop.Name, 'Colour') and Text.StartsWith('#') and
    TryStrToInt('$' + Copy(Text, 2, MaxInt), rgb) then
  begin
    Value := TValue.From<TColor>(TColor(((rgb and $FF) shl 16) or (rgb and $FF00) or
      ((rgb shr 16) and $FF)));
    Exit(True);
  end;
  if SameText(PItem^.Prop.Name, 'Inner') then
  begin
    Value := TValue.From<string>(Text);
    Exit(True);
  end;
end;

function TTextHookTests.CaptureSet(Sender: TControl; PItem: PPropItem; var NewValue: TValue): Boolean;
begin
  FCaptured := NewValue.AsString;
  Result := False;
end;

procedure TTextHookTests.TypedTextBecomesTheValueTheHookGives;
var
  target: THookTarget;
  saved: TzCustomValueManagerClass;
begin
  saved := DefaultValueManager;
  target := THookTarget.Create;
  try
    DefaultValueManager := THookManager;
    FInspector.Component := target;
    EnterText(FInspector, 'Colour', '#102030');
    Assert.AreEqual(Integer($00302010), Integer(target.Colour));
  finally
    FInspector.Component := nil;
    DefaultValueManager := saved;
    target.Free;
  end;
end;

procedure TTextHookTests.TextTheHookLeavesIsParsedAsBefore;
var
  target: THookTarget;
  saved: TzCustomValueManagerClass;
begin
  saved := DefaultValueManager;
  target := THookTarget.Create;
  try
    DefaultValueManager := THookManager;
    FInspector.Component := target;
    EnterText(FInspector, 'Colour', '$00102030');
    Assert.AreEqual(Integer($00102030), Integer(target.Colour));
  finally
    FInspector.Component := nil;
    DefaultValueManager := saved;
    target.Free;
  end;
end;

procedure TTextHookTests.AClassRowTakesTextWhenTheManagerSaysSo;
var
  target: THookTarget;
  saved: TzCustomValueManagerClass;
begin
  saved := DefaultValueManager;
  target := THookTarget.Create;
  try
    DefaultValueManager := THookManager;
    FInspector.OnItemSetValue := CaptureSet;
    FInspector.Component := target;
    Assert.IsFalse(SelectRow(FInspector, 'Inner').ReadOnly, 'the row takes text');
    FCaptured := '';
    EnterText(FInspector, 'Inner', 'abc');
    Assert.AreEqual('abc', FCaptured, 'the hook''s value reached OnItemSetValue');
  finally
    FInspector.Component := nil;
    DefaultValueManager := saved;
    target.Free;
  end;
end;

procedure TTextHookTests.AClassRowIsReadOnlyByDefault;
var
  target: THookTarget;
begin
  target := THookTarget.Create;
  try
    FInspector.Component := target;
    Assert.IsTrue(SelectRow(FInspector, 'Inner').ReadOnly);
  finally
    FInspector.Component := nil;
    target.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextHookTests);

end.

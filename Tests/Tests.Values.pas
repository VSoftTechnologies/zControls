unit Tests.Values;

{ Tests for values typed into the editor: numbers that were silently stored as 0
  or wrapped, and float types that were set to 0 by any text. }

interface

uses
  DUnitX.TestFramework,
  Testing.Inspector;

type
  { Invalid numbers were silently stored as 0 or wrapped }
  [TestFixture]
  TNumberTests = class(TInspectorTestCase)
  public
    [Test] procedure InvalidNumbersRejected;
    [Test] procedure ValidNumbersAccepted;
  end;

  { TDateTime, TDate, TTime, Currency and other float types were set to 0 }
  [TestFixture]
  TFloatTypeTests = class(TInspectorTestCase)
  public
    [Test] procedure OtherFloatTypesAccepted;
    [Test] procedure OtherFloatTypesRejectInvalid;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Classes,
  Vcl.Graphics;

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

procedure TNumberTests.InvalidNumbersRejected;
var
  obj: TNumbers;

  procedure Reject(const row, text: string);
  begin
    FExpectedExceptions := 1;
    EnterText(FInspector, row, text);
    Assert.IsTrue(FExpectedExceptions = 0, Format('%s: "%s" rejected', [row, text]));
  end;

begin
  obj := NewNumbers;
  try
    FInspector.Component := obj;
    Reject('AInteger', 'abc');
    Assert.IsTrue(obj.AInteger = 7, 'AInteger unchanged (was set to 0)');
    Reject('ADouble', 'abc');
    Assert.IsTrue(obj.ADouble = 7, 'ADouble unchanged (was set to 0)');
    Reject('ASingle', '1e50');
    Assert.IsTrue(obj.ASingle = 7, 'ASingle unchanged by an overflowing value');
    Reject('AByte', '300');
    Assert.IsTrue(obj.AByte = 7, 'AByte unchanged (300 was stored as 44)');
    Reject('AByte', '-1');
    Assert.IsTrue(obj.AByte = 7, 'AByte unchanged by a negative value');
    Reject('AShortInt', '200');
    Assert.IsTrue(obj.AShortInt = 7, 'AShortInt unchanged by an out-of-range value');
    Reject('ACardinal', '-1');
    Assert.IsTrue(obj.ACardinal = 7, 'ACardinal unchanged by a negative value');
    Reject('AInt64', '99999999999999999999');
    Assert.IsTrue(obj.AInt64 = 7, 'AInt64 unchanged by an out-of-range value');
    Reject('AUInt64', '-1');
    Assert.IsTrue(obj.AUInt64 = 7, 'AUInt64 unchanged by a negative value');
  finally
    FInspector.Component := nil;
    obj.Free;
  end;
end;

procedure TNumberTests.ValidNumbersAccepted;
var
  obj: TNumbers;
begin
  obj := NewNumbers;
  try
    FInspector.Component := obj;
    EnterText(FInspector, 'AByte', '255');
    Assert.IsTrue(obj.AByte = 255, 'AByte accepts 255');
    EnterText(FInspector, 'AShortInt', '-128');
    Assert.IsTrue(obj.AShortInt = -128, 'AShortInt accepts -128');
    EnterText(FInspector, 'ACardinal', '4000000000');
    Assert.IsTrue(obj.ACardinal = 4000000000, 'ACardinal accepts 4000000000');
    EnterText(FInspector, 'AInteger', '-5');
    Assert.IsTrue(obj.AInteger = -5, 'AInteger accepts -5');
    EnterText(FInspector, 'AInteger', '$10');
    Assert.IsTrue(obj.AInteger = 16, 'AInteger accepts hex $10');
    EnterText(FInspector, 'AInt64', '-9000000000');
    Assert.IsTrue(obj.AInt64 = -9000000000, 'AInt64 accepts -9000000000');
    EnterText(FInspector, 'AUInt64', '18446744073709551615');
    Assert.IsTrue(obj.AUInt64 = High(UInt64), 'AUInt64 accepts its maximum');
    EnterText(FInspector, 'ADouble', '2' + FormatSettings.DecimalSeparator + '5');
    Assert.IsTrue(obj.ADouble = 2.5, 'ADouble accepts 2.5');
    EnterText(FInspector, 'AColor', '$00123456');
    Assert.IsTrue(obj.AColor = $123456, 'AColor accepts $00123456');
    EnterText(FInspector, 'AColor', '$FF00000F'); // how unnamed system colours are shown
    Assert.IsTrue(obj.AColor = clBtnFace, 'AColor accepts a system colour typed as hex');
  finally
    FInspector.Component := nil;
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

procedure TFloatTypeTests.OtherFloatTypesAccepted;
var
  obj: TOtherFloats;
  expected: TDateTime;
  sep: string;
begin
  sep := FormatSettings.DecimalSeparator;
  obj := NewOtherFloats;
  try
    FInspector.Component := obj;
    expected := EncodeDateTime(2021, 3, 4, 10, 30, 0, 0);
    EnterText(FInspector, 'When', DateTimeToStr(expected));
    Assert.IsTrue(SameDateTime(obj.When, expected), 'TDateTime accepts ' + DateTimeToStr(expected));
    expected := EncodeDate(2022, 12, 25);
    EnterText(FInspector, 'Day', DateToStr(expected));
    Assert.IsTrue(SameDate(obj.Day, expected), 'TDate accepts ' + DateToStr(expected));
    expected := EncodeTime(13, 45, 0, 0);
    EnterText(FInspector, 'AtTime', TimeToStr(expected));
    Assert.IsTrue(SameTime(obj.AtTime, expected), 'TTime accepts ' + TimeToStr(expected));
    EnterText(FInspector, 'Money', '99' + sep + '25');
    Assert.IsTrue(obj.Money = 99.25, 'Currency accepts 99' + sep + '25');
    EnterText(FInspector, 'Measure', '1' + sep + '5');
    Assert.IsTrue(obj.Measure = 1.5, 'a distinct Double type accepts 1' + sep + '5');
  finally
    FInspector.Component := nil;
    obj.Free;
  end;
end;

procedure TFloatTypeTests.OtherFloatTypesRejectInvalid;
var
  obj: TOtherFloats;

  procedure Reject(const row, text: string);
  begin
    FExpectedExceptions := 1;
    EnterText(FInspector, row, text);
    Assert.IsTrue(FExpectedExceptions = 0, Format('%s: "%s" rejected', [row, text]));
  end;

begin
  obj := NewOtherFloats;
  try
    FInspector.Component := obj;
    Reject('When', 'not a date');
    Assert.IsTrue(SameDate(obj.When, EncodeDate(2020, 6, 15)), 'TDateTime unchanged');
    Reject('Money', 'abc');
    Assert.IsTrue(obj.Money = 12.5, 'Currency unchanged');
    Reject('Measure', 'abc');
    Assert.IsTrue(obj.Measure = 3, 'distinct Double type unchanged');
  finally
    FInspector.Component := nil;
    obj.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNumberTests);
  TDUnitX.RegisterTestFixture(TFloatTypeTests);

end.

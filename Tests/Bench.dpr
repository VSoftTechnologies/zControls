program Bench;

{ Timing for the inspector's hot paths. Not a test: prints milliseconds per operation.
  Build the Release configuration (optimisation on, no assertions). The results are
  noisy, paint in particular: compare several runs. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Diagnostics,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.ImgList,
  zObjInspector;

type
  TBenchProc = reference to procedure;

procedure Measure(const name: string; repeats: Integer; proc: TBenchProc);
var
  watch: TStopwatch;
  i: Integer;
begin
  proc(); // warm up
  watch := TStopwatch.StartNew;
  for i := 1 to repeats do
    proc();
  watch.Stop;
  Writeln(Format('%-46s %9.3f ms', [name, watch.Elapsed.TotalMilliseconds / repeats]));
end;

function FindRow(insp: TzObjectInspector; const name: string): PPropItem;
var
  i: Integer;
begin
  result := nil;
  for i := 0 to insp.Items.Count - 1 do
    if (insp.Items.Items[i]^.Parent = nil) and (not insp.Items.Items[i]^.IsCategory) and
      SameText(insp.Items.Items[i]^.Name, name) then
      Exit(insp.Items.Items[i]);
end;

function BuildSubject: TForm;
var
  images: TImageList;
  menu: TPopupMenu;
  i: Integer;
  item: TMenuItem;
  ctrl: TControl;
begin
  result := TForm.CreateNew(nil);
  result.Name := 'Subject';
  images := TImageList.Create(result);
  images.Name := 'Images';
  menu := TPopupMenu.Create(result);
  menu.Name := 'Menu';
  menu.Images := images;
  for i := 1 to 10 do
  begin
    item := TMenuItem.Create(result);
    item.Caption := 'Item' + IntToStr(i);
    menu.Items.Add(item);
  end;
  result.PopupMenu := menu;
  for i := 1 to 30 do
  begin
    case i mod 3 of
      0: ctrl := TButton.Create(result);
      1: ctrl := TEdit.Create(result);
    else
      ctrl := TPanel.Create(result);
    end;
    ctrl.Name := 'Ctrl' + IntToStr(i);
    ctrl.Parent := result;
    ctrl.SetBounds(10, i * 22, 100, 20);
    TButton(ctrl).PopupMenu := menu; // PopupMenu is declared on TControl
  end;
end;

var
  host, subject: TForm;
  insp: TzObjectInspector;
  bmp: TBitmap;
  btn: TButton;
  objHost: TzObjectHost;
  i: Integer;
begin
  Application.Initialize;
  host := TForm.CreateNew(nil);
  subject := BuildSubject;
  bmp := TBitmap.Create;
  try
    host.SetBounds(100, 100, 420, 700);
    insp := TzObjectInspector.Create(host);
    insp.Parent := host;
    insp.SetBounds(0, 0, 400, 660);
    host.Show;
    bmp.SetSize(insp.Width, insp.Height);

    btn := TButton(subject.FindComponent('Ctrl3'));
    insp.Component := btn;
    Writeln('TButton rows: ', insp.Items.Count, ' (visible ', insp.VisibleItems.Count, ')');
    Measure('TButton: UpdateProperties', 50, procedure begin insp.UpdateProperties(True); end);

    insp.Component := subject;
    Writeln('TForm rows: ', insp.Items.Count, ' (visible ', insp.VisibleItems.Count, ')');
    Measure('TForm: Component := (nil, then form)', 10,
      procedure begin insp.Component := nil; insp.Component := subject; end);
    Measure('TForm: UpdateProperties', 20, procedure begin insp.UpdateProperties(True); end);
    Measure('TForm: paint', 50, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    insp.ShowGridLines := True;
    Measure('TForm: paint, ShowGridLines', 50, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    insp.ShowGridLines := False;
    insp.SelectItem(3);
    Measure('TForm: paint, a row selected', 50, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    insp.SelectItem(-1);
    Measure('GDI baseline: 76 DrawText on the same bitmap', 50,
      procedure
      var
        i: Integer;
        r: TRect;
      begin
        bmp.Canvas.Font.Assign(insp.Font);
        for i := 0 to 75 do
        begin
          r := Rect(4, (i mod 38) * 17, 396, (i mod 38) * 17 + 17);
          DrawText(bmp.Canvas.Handle, 'AlignWithMargins value', -1, r, DT_LEFT or DT_VCENTER or DT_SINGLELINE);
        end;
      end);
    Measure('TForm: select 25 rows', 5,
      procedure
      var
        i: Integer;
      begin
        insp.SetFocus;
        for i := 0 to 24 do
          insp.SelectItem(i);
        insp.SelectItem(-1);
      end);
    Measure('TForm: select 25 rows, focus elsewhere', 5,
      procedure
      var
        i: Integer;
      begin
        host.ActiveControl := nil;
        Winapi.Windows.SetFocus(host.Handle);
        for i := 0 to 24 do
          insp.SelectItem(i);
        insp.SelectItem(-1);
      end);
    Measure('TForm: ExpandItem(Font) + CollapseItem', 20,
      procedure
      begin
        insp.ExpandItem(FindRow(insp, 'Font'));
        insp.CollapseItem(FindRow(insp, 'Font'));
      end);
    Measure('TForm: ExpandAll', 3, procedure begin insp.ExpandAll; end);
    Writeln('TForm rows after ExpandAll: ', insp.Items.Count, ' (visible ', insp.VisibleItems.Count, ')');
    Measure('TForm expanded: paint', 50, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    Measure('TForm expanded: UpdateProperties', 5, procedure begin insp.UpdateProperties(True); end);
    insp.CollapseAll;
    insp.Component := nil;

    { A large tree: every control of the form at once, as the demo's "Multi components". }
    objHost := TzObjectHost.Create;
    for i := 0 to subject.ComponentCount - 1 do
      if subject.Components[i] is TControl then
        objHost.AddObject(subject.Components[i], subject.Components[i].Name);
    insp.Component := objHost; // owned by the inspector from here
    Writeln('Host rows: ', insp.Items.Count, ' (visible ', insp.VisibleItems.Count, ')');
    Measure('Host: UpdateProperties', 3, procedure begin insp.UpdateProperties(True); end);
    Measure('Host: paint', 20, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    Measure('Host: ExpandAll', 1, procedure begin insp.ExpandAll; end);
    Writeln('Host rows after ExpandAll: ', insp.Items.Count, ' (visible ', insp.VisibleItems.Count, ')');
    Measure('Host expanded: UpdateProperties', 3, procedure begin insp.UpdateProperties(True); end);
    Measure('Host expanded: paint', 20, procedure begin insp.PaintTo(bmp.Canvas.Handle, 0, 0); end);
    Measure('Host expanded: select 25 rows', 2,
      procedure
      var
        j: Integer;
      begin
        insp.SetFocus;
        for j := 0 to 24 do
          insp.SelectItem(j);
        insp.SelectItem(-1);
      end);
    Measure('Host expanded: CollapseAll + ExpandAll', 1, procedure begin insp.CollapseAll; insp.ExpandAll; end);
    insp.CollapseAll;
    insp.Component := nil;
  finally
    bmp.Free;
    subject.Free;
    host.Free;
  end;
end.

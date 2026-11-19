program InspectorTests;

{ DUnitX tests for TzObjectInspector. They drive a real form and inspector, so they
  run in the main thread of a VCL application. Run RunTests.bat from a RAD Studio
  command prompt to build and run them for Win32 and Win64. The fixes the tests cover
  are described in CODE_REVIEW.md. }

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  PoisonMM in 'PoisonMM.pas', // must be first: turns use-after-free into access violations
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF}
  DUnitX.TestFramework,
  Testing.Inspector in 'Testing.Inspector.pas',
  Tests.Crashes in 'Tests.Crashes.pas',
  Tests.Values in 'Tests.Values.pas',
  Tests.Fixes in 'Tests.Fixes.pas',
  Tests.TextHooks in 'Tests.TextHooks.pas';

{$IFNDEF TESTINSIGHT}
var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
{$ENDIF}
begin
  ReportMemoryLeaksOnShutdown := False; // PoisonMM never frees a block
  Application.Initialize;
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := False; // the units register their fixtures
    runner.FailsOnNoAsserts := False;

    logger := TDUnitXConsoleLogger.Create(True);
    runner.AddLogger(logger);

    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    { keeps the console open when run from the IDE; RunTests.bat runs it without a debugger }
    if IsDebuggerPresent then
      TDUnitX.Options.ExitBehavior := TDUnitXExitBehavior.Pause;
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}
end.

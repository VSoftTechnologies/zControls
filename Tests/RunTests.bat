@echo off
rem Builds and runs the inspector tests for Win32 and Win64 (Debug configuration).
rem Run it from a RAD Studio command prompt, or with BDS set to the RAD Studio folder.
rem The exit code is 0 when every check passed.
setlocal
if "%BDS%"=="" (
  echo BDS is not set. Run this from a RAD Studio command prompt.
  exit /b 1
)
call "%BDS%\bin\rsvars.bat"
cd /d "%~dp0"
set FAILED=0
for %%P in (Win32 Win64) do (
  echo.
  echo ==== %%P ====
  msbuild InspectorTests.dproj /t:Build /p:Config=Debug /p:Platform=%%P /v:minimal /nologo
  if errorlevel 1 exit /b 1
  "%%P\Debug\InspectorTests.exe"
  if errorlevel 1 set FAILED=1
)
exit /b %FAILED%

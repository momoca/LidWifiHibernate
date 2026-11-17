@echo off
setlocal
cd /d "%~dp0" || exit /b 1
set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo .NET Framework x64 C# compiler not found.
    exit /b 1
)
"%CSC%" /nologo /target:winexe /platform:x64 /out:MT7922-Lid-Auto.exe /resource:MT7922-Power.ps1,power.ps1 LidWindow.cs
exit /b %errorlevel%

@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo pwshDoom needs PowerShell 7.4 or newer, not Windows PowerShell 5.1.
  echo Install it from https://aka.ms/powershell-release?tag=stable
  echo Then open Play.cmd again.
  pause
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -File "%~dp0Play.ps1" %*
set "PWSHDOOM_EXIT=%errorlevel%"
if not "%PWSHDOOM_EXIT%"=="0" pause
exit /b %PWSHDOOM_EXIT%

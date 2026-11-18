@echo off
rem Makes ARGUS open automatically when you sign in to Windows.
rem Double-click once. Run it again any time you move the ARGUS folder.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$startup = [Environment]::GetFolderPath('Startup');" ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'ARGUS.lnk'));" ^
  "$s.TargetPath = (Join-Path '%~dp0' 'argus-fullscreen.bat');" ^
  "$s.WorkingDirectory = '%~dp0';" ^
  "$s.WindowStyle = 7;" ^
  "$s.Save();" ^
  "Write-Host ''; Write-Host '  ARGUS will now start when you sign in.' -ForegroundColor Cyan; Write-Host ('  Shortcut: ' + (Join-Path $startup 'ARGUS.lnk')); Write-Host ''"
pause

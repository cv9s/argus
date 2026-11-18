@echo off
rem Starts ARGUS (minimized) and opens the dashboard full screen in Edge.
rem Exit full screen with Alt+F4. Microphone access is granted automatically in this window only.
cd /d "%~dp0"
start "ARGUS LINK" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0argus.ps1" -NoBrowser
timeout /t 4 /nobreak >nul
start "" msedge --kiosk http://localhost:8080 --edge-kiosk-type=fullscreen --no-first-run --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --user-data-dir="%LOCALAPPDATA%\ARGUS-Edge"

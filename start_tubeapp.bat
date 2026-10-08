@echo off
rem Double-click to start MATLAB R2022b and open the transfer-impedance tube GUI.
rem   start_tubeapp.bat        -> real instruments (config\user_config.json)
rem   start_tubeapp.bat sim    -> virtual tube (practice)
set "ROOT=%~dp0"
set "MODE=%~1"
set "ML=C:\Program Files\MATLAB\R2022b\bin\matlab.exe"
if not exist "%ML%" set "ML=matlab"
start "" "%ML%" -sd "%ROOT%" -r "tubeapp('%MODE%')"

@echo off
rem Double-click to start MATLAB R2022b and open tubebench (transfer impedance tube program).
rem   start_tubebench.bat        -> real instruments (config\user_config.json)
rem   start_tubebench.bat sim    -> virtual tube (practice)
set "ROOT=%~dp0"
set "MODE=%~1"
set "ML=C:\Program Files\MATLAB\R2022b\bin\matlab.exe"
if not exist "%ML%" set "ML=matlab"
start "" "%ML%" -sd "%ROOT%" -r "tubebench('%MODE%')"

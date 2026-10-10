@echo off
rem Double-click to start MATLAB R2022b and open tubebench (transfer impedance tube program).
rem   start_tubebench.bat        -> real instruments (config\user_config.json)
rem   start_tubebench.bat sim    -> virtual tube (practice)
rem MATLAB starts without its desktop (-nodesktop -nosplash: faster). A small MATLAB command
rem window stays open behind the program, also after the program is closed: type tubebench
rem (or tubebench sim) there to open the program again, and exit (or close that window) to
rem quit MATLAB.
set "ROOT=%~dp0"
set "MODE=%~1"
set "ML=C:\Program Files\MATLAB\R2022b\bin\matlab.exe"
if not exist "%ML%" set "ML=matlab"
start "" "%ML%" -nodesktop -nosplash -sd "%ROOT%" -r "tubebench('%MODE%')"

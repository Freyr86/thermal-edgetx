@echo off
setlocal
set "PYTHON_EXE=C:\Program Files\Inkscape\bin\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=python.exe"
"%PYTHON_EXE%" "%~dp0tools\thermal_map_manager.py"
if errorlevel 1 pause
endlocal

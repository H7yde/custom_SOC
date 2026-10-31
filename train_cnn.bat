@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Double-click this file to setup/train the COCO CNN and show results.
if not exist "%~dp0CNN_RTL\train_cnn.bat" (
    echo ERROR: Missing CNN_RTL\train_cnn.bat. Keep this file in the project root.
    if not "%CNN_NO_PAUSE%"=="1" pause
    exit /b 1
)
call "%~dp0CNN_RTL\train_cnn.bat" %*
exit /b %ERRORLEVEL%

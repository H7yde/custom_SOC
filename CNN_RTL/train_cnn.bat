@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Windows entry point. PyTorch training is implemented by auto_train_cnn.py.
rem Set CNN_PYTHON to select an interpreter; CNN_NO_PAUSE=1 for terminal/CI use.
set "TRAIN_EXIT=1"
set "TRAIN_USE_PY=0"
if defined CNN_PYTHON (
    set "TRAIN_PYTHON=%CNN_PYTHON%"
    goto python_ready
)
if defined VIRTUAL_ENV if exist "%VIRTUAL_ENV%\Scripts\python.exe" (
    set "TRAIN_PYTHON=%VIRTUAL_ENV%\Scripts\python.exe"
    goto python_ready
)
if defined CONDA_PREFIX if exist "%CONDA_PREFIX%\python.exe" (
    set "TRAIN_PYTHON=%CONDA_PREFIX%\python.exe"
    goto python_ready
)
if exist "%USERPROFILE%\miniforge3\python.exe" (
    set "TRAIN_PYTHON=%USERPROFILE%\miniforge3\python.exe"
    goto python_ready
)
where python >nul 2>nul
if not errorlevel 1 (
    set "TRAIN_PYTHON=python"
    goto python_ready
)
where py >nul 2>nul
if not errorlevel 1 (
    set "TRAIN_PYTHON=py"
    set "TRAIN_USE_PY=1"
    goto python_ready
)
echo ERROR: Python 3 was not found. Install Python or Miniforge, then retry.
goto finish

:python_ready
if not exist "%~dp0auto_train_cnn.py" (
    echo ERROR: Missing auto_train_cnn.py beside this BAT file.
    goto finish
)
pushd "%~dp0.."
if errorlevel 1 goto finish
echo COCO 2017 CNN - setup, training and results
echo Interpreter: "%TRAIN_PYTHON%"
echo Dataset: CNN_RTL\data\coco2017
echo Default: 30 float epochs + 20 QAT epochs. GPU selected when available.
echo.
if "%TRAIN_USE_PY%"=="1" (
    "%TRAIN_PYTHON%" -3 -u "%~dp0auto_train_cnn.py" %*
) else (
    "%TRAIN_PYTHON%" -u "%~dp0auto_train_cnn.py" %*
)
set "TRAIN_EXIT=%ERRORLEVEL%"
popd
if "%TRAIN_EXIT%"=="0" (
    echo.
    echo COMPLETE. Training runs save AUTO_RESULTS.md, report.json and weights in CNN_RTL\runs.
) else (
    echo.
    echo FAILED with exit code %TRAIN_EXIT%. Read the error above and the run logs.
)

:finish
if not "%CNN_NO_PAUSE%"=="1" pause
exit /b %TRAIN_EXIT%

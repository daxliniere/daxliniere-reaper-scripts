@echo off
cd /d "%~dp0"
python tools\verify.py
exit /b %errorlevel%

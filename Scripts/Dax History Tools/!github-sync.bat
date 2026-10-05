@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workflow.ps1" -Action sync
exit /b %errorlevel%

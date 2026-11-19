@echo off
REM Plane Self-Hosted Management Wrapper for Windows
powershell.exe -ExecutionPolicy Bypass -File "%~dp0scripts\manage.ps1" %*

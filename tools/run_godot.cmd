@echo off
rem Wrapper for systems whose PowerShell execution policy blocks .ps1 files:
rem bypasses the policy for this one call only (no system setting changes).
rem Usage: tools\run_godot.cmd play | smoke | capture | shots <list> | perf <scenario> | stress
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_godot.ps1" %*

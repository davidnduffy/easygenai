@echo off
cd /d "%~dp0..\ComfyUI" || exit /b 1
"venv\Scripts\python.exe" main.py

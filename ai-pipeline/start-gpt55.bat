@echo off
cd /d D:\Code\ai-pipeline
set HEADLESS=1
start /B node gpt55-server.js > logs\gpt55.log 2>&1

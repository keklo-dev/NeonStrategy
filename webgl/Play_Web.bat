@echo off
rem Play_Web.bat - двойной клик: поднимает локальный HTTP-сервер и открывает игру в браузере.
rem НЕ открывай index.html напрямую из Проводника (file://) - Unity WebGL требует http://.

cd /d "%~dp0"

if not exist "%~dp0Serve.ps1" (
    echo [ОШИБКА] Не найден Serve.ps1 рядом с Play_Web.bat
    echo Положите оба файла в папку WebGL-сборки рядом с index.html.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 goto :try_python

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Serve.ps1" -Root "%~dp0."
goto :end

:try_python
where python.exe >nul 2>nul
if errorlevel 1 goto :nothing
echo PowerShell не найден - запасной вариант: python -m http.server
start "" "http://localhost:8080/"
python.exe -m http.server 8080
goto :end

:nothing
echo [ОШИБКА] Ни PowerShell, ни Python не найдены в PATH.
echo Это странно для Windows: проверь, что powershell.exe доступен.
pause

:end
rem Если сервер завершился (ошибка или закрыт по Ctrl+C) - оставить окно открытым, чтобы было видно сообщение.
echo.
echo Сервер остановлен. Закрой это окно.
pause

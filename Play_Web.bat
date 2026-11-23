@echo off
rem Корневой ярлык: запускает веб-версию из подпапки webgl.
if exist "%~dp0webgl\Play_Web.bat" (
    call "%~dp0webgl\Play_Web.bat"
) else (
    echo [ОШИБКА] Не найден %~dp0webgl\Play_Web.bat
    pause
)

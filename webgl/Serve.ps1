param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)
# Serve.ps1 — крошечный статический HTTP-сервер для Unity WebGL-сборки.
# Запускается из Play_Web.bat. Не требует Python/Node/IIS — только встроенный System.Net.HttpListener.
# Основной сценарий: сборка БЕЗ сжатия (WebGL.data / .wasm / .framework.js лежат как есть).
# Если файлы пересобрали со сжатием (.gz/.br) — отдаём их байты с правильным Content-Encoding,
# чтобы браузер прозрачно распаковал (иначе Unity-загрузчик не сможет их прочесть).

$ErrorActionPreference = 'Stop'
# Защита от кавычки в конце пути, если батник передал %~dp0 с экранированной кавычкой.
$Root = $Root.Trim().TrimEnd('"')
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $Root 'index.html'))) {
    Write-Host ("ОШИБКА: в папке '" + $Root + "' нет index.html. Запускай Play_Web.bat из папки WebGL-сборки.")
    exit 1
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.mjs'  = 'application/javascript; charset=utf-8'
    '.json' = 'application/json'
    '.css'  = 'text/css; charset=utf-8'
    '.wasm' = 'application/wasm'
    '.data' = 'application/octet-stream'
    '.unityweb' = 'application/octet-stream'
    '.mem'  = 'application/octet-stream'
    '.symbols' = 'application/octet-stream'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.webp' = 'image/webp'
    '.txt'  = 'text/plain; charset=utf-8'
    '.xml'  = 'text/xml; charset=utf-8'
    '.woff' = 'font/woff'
    '.woff2' = 'font/woff2'
    '.ttf'  = 'font/ttf'
    '.eot'  = 'application/vnd.ms-fontobject'
    '.mp3'  = 'audio/mpeg'
    '.ogg'  = 'audio/ogg'
    '.wav'  = 'audio/wav'
    '.mp4'  = 'video/mp4'
    '.webm' = 'video/webm'
}

function Get-ContentType([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($mime.ContainsKey($ext)) { return $mime[$ext] }
    return 'application/octet-stream'
}

function Send-Status($ctx, [int]$code, [string]$text) {
    $body = [System.Text.Encoding]::UTF8.GetBytes($text)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = 'text/plain; charset=utf-8'
    $ctx.Response.ContentLength64 = $body.Length
    $ctx.Response.OutputStream.Write($body, 0, $body.Length)
    $ctx.Response.OutputStream.Close()
    $ctx.Response.Close()
}

# --- Выбор свободного порта: 8080, если занят — следующий, до 8100 ---
$listener = $null
$port = 0
for ($p = 8080; $p -lt 8100; $p++) {
    $candidate = New-Object System.Net.HttpListener
    try {
        $candidate.Prefixes.Add("http://localhost:$p/")
        $candidate.Start()
        $listener = $candidate
        $port = $p
        break
    } catch {
        try { $candidate.Close() } catch {}
    }
}
if ($null -eq $listener) {
    Write-Host 'ОШИБКА: не удалось занять порт 8080-8099. Закрой программы, которые могут их слушать, и попробуй снова.'
    exit 1
}

Write-Host ''
Write-Host "  Strategya WebGL — локальный сервер запущен."
Write-Host ("  Корень сайта:  " + $Root)
Write-Host ("  Адрес игры:    http://localhost:$port/")
Write-Host ''
Write-Host '  Браузер откроется сам. Если нет — введи адрес выше вручную.'
Write-Host '  Закрой ЭТО окно, чтобы остановить сервер.'
Write-Host ''

try {
    Start-Process "http://localhost:$port/"
} catch {
    Write-Host ('  Не удалось открыть браузер автоматически: ' + $_.Exception.Message)
}

# --- Цикл приёма запросов (синхронный; localhost — запросов немного) ---
try {
    while ($listener.IsListening) {
        $ctx = $null
        try { $ctx = $listener.GetContext() } catch { break }

        $method = $ctx.Request.HttpMethod
        $rel = $ctx.Request.Url.LocalPath
        try {
            if ($rel -eq '/' -or $rel -eq '') { $rel = '/index.html' }
            $rel = [System.Uri]::UnescapeDataString($rel)
            $rel = $rel -replace '/', '\'
            $full = [System.IO.Path]::GetFullPath((Join-Path $Root $rel))

            # защита от выхода за пределы папки сборки
            if (-not ($full + '\').StartsWith($Root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                Send-Status $ctx 403 'Forbidden'
                continue
            }
            if ([System.IO.Directory]::Exists($full)) {
                $full = Join-Path $full 'index.html'
            }
            if (-not [System.IO.File]::Exists($full)) {
                Send-Status $ctx 404 ('Not found: ' + $rel)
                continue
            }

            $encoding = $null
            $typePath = $full
            if ($full.EndsWith('.gz', [System.StringComparison]::OrdinalIgnoreCase)) {
                $encoding = 'gzip'
                $typePath = $full.Substring(0, $full.Length - 3)
            } elseif ($full.EndsWith('.br', [System.StringComparison]::OrdinalIgnoreCase)) {
                $encoding = 'br'
                $typePath = $full.Substring(0, $full.Length - 3)
            }

            $fs = [System.IO.File]::OpenRead($full)
            try {
                $ctx.Response.StatusCode = 200
                $ctx.Response.ContentType = Get-ContentType $typePath
                if ($encoding) { $ctx.Response.Headers['Content-Encoding'] = $encoding }
                $ctx.Response.ContentLength64 = $fs.Length
                if ($method -ne 'HEAD') {
                    $buf = New-Object byte[] 1048576
                    while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                        $ctx.Response.OutputStream.Write($buf, 0, $read)
                    }
                }
            } finally {
                try { $fs.Dispose() } catch {}
            }
            $ctx.Response.OutputStream.Close()
            $ctx.Response.Close()
            Write-Host ("  " + $method + " " + $ctx.Request.Url.LocalPath + " -> 200 (" + $ctx.Response.ContentLength64 + " bytes)" + $(if ($encoding) { " [" + $encoding + "]" } else { '' }))
        } catch {
            try {
                if ($ctx.Response.OutputStream) { $ctx.Response.OutputStream.Close() }
                $ctx.Response.Close()
            } catch {}
            Write-Host ("  " + $method + " " + $(if ($ctx) { $ctx.Request.Url.LocalPath } else { '?' }) + " -> ОШИБКА: " + $_.Exception.Message)
        }
    }
} finally {
    try { $listener.Stop(); $listener.Close() } catch {}
    Write-Host ''
    Write-Host '  Сервер остановлен.'
}

#Requires -Version 5.1
<#
.SYNOPSIS
    按需启动的本地免登录面板：把 http://127.0.0.1:47991 转发到 Sunshine Web UI。
.DESCRIPTION
    Sunshine 的 Web UI 每个请求都要 HTTP Basic 认证，浏览器不会保持登录会话。
    本脚本在本机回环地址起一个很小的转发器，自动注入 Authorization，浏览器打开
    http://127.0.0.1:<port>/ 就等于已经登录。

    - 只监听 127.0.0.1，不写防火墙规则、不注册服务、不开机自启
    - 凭据从 install-result.json 读取，不写命令行、不写日志
    - 把 Origin/Referer 重写为 https://127.0.0.1:47990（Sunshine 默认允许的 CSRF 来源）
    - 空闲 IdleMinutes 分钟无请求自动退出；Sunshine 服务停止也退出
.PARAMETER Port
    首选端口，默认 47991；被占用时自动向后尝试 4 个。
.PARAMETER IdleMinutes
    空闲多少分钟后退出，默认 10。
.PARAMETER Target
    Sunshine Web UI 地址，默认 https://127.0.0.1:47990。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Open-WebUI.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 47991,
    [int]$IdleMinutes = 10,
    [string]$Target = 'https://127.0.0.1:47990'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

$panelDir = Join-Path $env:LOCALAPPDATA 'SunshinePanel'
New-Item -ItemType Directory -Path $panelDir -Force | Out-Null
$pidFile  = Join-Path $panelDir 'webpanel.pid'
$portFile = Join-Path $panelDir 'webpanel.port'
$logFile  = Join-Path $panelDir 'webpanel.log'

# 单实例：已有进程活着就直接返回，启动器会读 port 文件
if (Test-Path -LiteralPath $pidFile) {
    $old = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue), [ref]$old)
    if ($old -gt 0 -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) {
        Write-Host "面板代理已在运行（PID $old）"
        exit 0
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

$svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
    Write-Host 'Sunshine 服务未运行，无法打开面板'
    exit 2
}

function Find-SunshineCredentials {
    $roots = @()
    try { $roots += (Split-Path (Get-DeviceStateRoot) -Parent) } catch { }
    $roots += 'C:\ProgramData\sunshine-lan-streaming\devices'
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter 'install-result.json' -File -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
        foreach ($f in $files) {
            try {
                $d = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($d.username -and $d.password) {
                    return [pscustomobject]@{ User = [string]$d.username; Pass = [string]$d.password }
                }
            } catch { }
        }
    }
    return $null
}

$cred = Find-SunshineCredentials
if (-not $cred) {
    Write-Host '找不到 Web UI 凭据（install-result.json），请先运行一键部署'
    exit 3
}
$token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cred.User):$($cred.Pass)"))

$targetBase = $Target.TrimEnd('/')
$targetUri = [Uri]$targetBase
$targetOrigin = "$($targetUri.Scheme)://$($targetUri.Host):$($targetUri.Port)"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

function Test-PortFree {
    param([int]$P)
    try {
        $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $P)
        $l.Start(); $l.Stop()
        return $true
    } catch { return $false }
}
$chosen = $null
foreach ($p in @($Port..($Port + 4))) {
    if (Test-PortFree -P $p) { $chosen = $p; break }
}
if (-not $chosen) {
    Write-Host "端口 $Port-$($Port + 4) 都被占用，无法启动面板"
    exit 4
}

function Find-HeaderEnd {
    param([byte[]]$Bytes)
    for ($i = 3; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i - 3] -eq 13 -and $Bytes[$i - 2] -eq 10 -and $Bytes[$i - 1] -eq 13 -and $Bytes[$i] -eq 10) {
            return ($i - 3)
        }
    }
    return -1
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $chosen)
$listener.Start()
Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII
Set-Content -LiteralPath $portFile -Value $chosen -Encoding ASCII
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') listen=http://127.0.0.1:$chosen target=$targetBase user=$($cred.User)" |
    Set-Content -LiteralPath $logFile -Encoding UTF8

$lastActivity = Get-Date
try {
    while ($true) {
        if (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 300
            if (((Get-Date) - $lastActivity).TotalMinutes -ge $IdleMinutes) {
                Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'HH:mm:ss') idle exit" -Encoding UTF8
                break
            }
            $svc = Get-Service -Name SunshineService -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.Status -ne 'Running') {
                Add-Content -LiteralPath $logFile -Value "$(Get-Date -Format 'HH:mm:ss') sunshine stopped" -Encoding UTF8
                break
            }
            continue
        }

        $client = $listener.AcceptTcpClient()
        $resp = $null
        try {
            $client.ReceiveTimeout = 15000
            $stream = $client.GetStream()
            $ms = New-Object IO.MemoryStream
            $buf = New-Object byte[] 8192
            $headerEnd = -1
            while ($headerEnd -lt 0) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $ms.Write($buf, 0, $n)
                $headerEnd = Find-HeaderEnd -Bytes $ms.ToArray()
            }
            if ($headerEnd -lt 0) { continue }

            $all = $ms.ToArray()
            $headText = [Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
            $lines = $headText -split "`r`n"
            $parts = $lines[0] -split ' '
            if ($parts.Count -lt 2) { continue }
            $method = $parts[0].ToUpperInvariant()
            $path = $parts[1]
            if ($path -match '^https?://') {
                try { $path = ([Uri]$path).PathAndQuery } catch { }
            }

            $headers = @{}
            for ($i = 1; $i -lt $lines.Count; $i++) {
                $idx = $lines[$i].IndexOf(':')
                if ($idx -gt 0) {
                    $headers[$lines[$i].Substring(0, $idx).Trim().ToLowerInvariant()] = $lines[$i].Substring($idx + 1).Trim()
                }
            }

            $contentLength = 0
            if ($headers.ContainsKey('content-length')) { [void][int]::TryParse($headers['content-length'], [ref]$contentLength) }
            $bodyStart = $headerEnd + 4
            $body = New-Object byte[] $contentLength
            $have = [Math]::Max(0, $all.Length - $bodyStart)
            if ($have -gt 0) { [Array]::Copy($all, $bodyStart, $body, 0, [Math]::Min($have, $contentLength)) }
            $read = [Math]::Min($have, $contentLength)
            while ($read -lt $contentLength) {
                $n = $stream.Read($body, $read, $contentLength - $read)
                if ($n -le 0) { break }
                $read += $n
            }

            $url = $targetBase + $path
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Method = $method
            $req.AllowAutoRedirect = $false
            $req.KeepAlive = $false
            $req.Timeout = 15000
            $req.ReadWriteTimeout = 15000
            $req.Headers['Authorization'] = "Basic $token"
            $req.Headers['Origin'] = $targetOrigin
            $req.Referer = "$targetOrigin/"
            foreach ($k in @('x-csrf-token', 'if-none-match', 'if-modified-since', 'cache-control', 'pragma')) {
                if ($headers.ContainsKey($k)) { $req.Headers[$k] = $headers[$k] }
            }
            if ($contentLength -gt 0) {
                $req.ContentType = if ($headers.ContainsKey('content-type')) { $headers['content-type'] } else { 'application/octet-stream' }
                $req.ContentLength = $contentLength
                $rs = $req.GetRequestStream()
                $rs.Write($body, 0, $contentLength)
                $rs.Close()
            }

            $status = 502
            $respStream = $null
            try {
                $resp = [Net.HttpWebResponse]$req.GetResponse()
                $status = [int]$resp.StatusCode
                $respStream = $resp.GetResponseStream()
            } catch [Net.WebException] {
                if ($_.Exception.Response) {
                    $resp = [Net.HttpWebResponse]$_.Exception.Response
                    $status = [int]$resp.StatusCode
                    $respStream = $resp.GetResponseStream()
                } else { throw }
            }

            $out = New-Object IO.MemoryStream
            if ($respStream) { $respStream.CopyTo($out) }
            $respBytes = $out.ToArray()

            $headersOut = @()
            if ($resp) {
                foreach ($hk in $resp.Headers.AllKeys) {
                    if ($hk -match '^(?i)(Content-Length|Content-Type|Transfer-Encoding|Connection|Keep-Alive|Set-Cookie|Proxy-)') { continue }
                    $hv = $resp.Headers[$hk]
                    if ($hk -eq 'Location' -and $hv -match [regex]::Escape($targetOrigin)) {
                        $hv = $hv -replace [regex]::Escape($targetOrigin), "http://127.0.0.1:$chosen"
                    }
                    $headersOut += "${hk}: $hv"
                }
                if ($resp.ContentType) { $headersOut += "Content-Type: $($resp.ContentType)" }
            }
            $headersOut += "Content-Length: $($respBytes.Length)"
            $headersOut += 'Connection: close'

            $statusDesc = if ($resp -and $resp.StatusDescription) { $resp.StatusDescription } else { 'Bad Gateway' }
            $head = "HTTP/1.1 $status $statusDesc`r`n" + ($headersOut -join "`r`n") + "`r`n`r`n"
            $hb = [Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($hb, 0, $hb.Length)
            if ($method -ne 'HEAD' -and $respBytes.Length -gt 0) { $stream.Write($respBytes, 0, $respBytes.Length) }
            $stream.Flush()

            Add-Content -LiteralPath $logFile -Value ("{0} {1} {2} {3}" -f (Get-Date -Format 'HH:mm:ss'), $method, $path, $status) -Encoding UTF8
            $lastActivity = Get-Date
        } catch {
            Add-Content -LiteralPath $logFile -Value ("{0} ERR {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message) -Encoding UTF8
        } finally {
            if ($resp) { $resp.Close() }
            $client.Close()
        }
    }
} finally {
    try { $listener.Stop() } catch { }
    Remove-Item -LiteralPath $pidFile, $portFile -Force -ErrorAction SilentlyContinue
}

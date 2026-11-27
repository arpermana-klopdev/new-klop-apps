$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$port = 5173
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
$ownerProcessIds = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)

foreach ($ownerProcessId in $ownerProcessIds) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ownerProcessId"
  if (-not $process) {
    continue
  }

  $isProjectVite = $process.Name -ieq "node.exe" `
    -and $process.CommandLine `
    -and $process.CommandLine.Contains($projectRoot) `
    -and $process.CommandLine -match "(?i)vite"

  if (-not $isProjectVite) {
    throw "Port $port is occupied by another process (PID $ownerProcessId, $($process.Name)). Stop it manually before starting the UI."
  }

  Write-Host "Stopping existing project Vite server (PID $ownerProcessId)..."
  Stop-Process -Id $ownerProcessId
}

$stopDeadline = (Get-Date).AddSeconds(10)
while ((Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) -and (Get-Date) -lt $stopDeadline) {
  Start-Sleep -Milliseconds 250
}
if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
  throw "Port $port is still in use after stopping the existing Vite server."
}

$certDirectory = Join-Path $env:LOCALAPPDATA "KLOP\dev-certs"
New-Item -ItemType Directory -Force -Path $certDirectory | Out-Null
$certificatePath = Join-Path $certDirectory "localhost.pem"
$keyPath = Join-Path $certDirectory "localhost.key"

& dotnet dev-certs https --trust
if ($LASTEXITCODE -ne 0) {
  throw "Could not trust the local ASP.NET Core HTTPS development certificate."
}

& dotnet dev-certs https --export-path $certificatePath --format PEM --no-password
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $certificatePath) -or -not (Test-Path $keyPath)) {
  throw "Could not export the local HTTPS certificate and key to $certDirectory."
}

$env:KLOP_DEV_TLS_CERT_PATH = $certificatePath
$env:KLOP_DEV_TLS_KEY_PATH = $keyPath

Set-Location $projectRoot
Write-Host "Starting KLOP UI at https://localhost:$port ..."
& npm run dev -- --host localhost --port $port
if ($LASTEXITCODE -ne 0) {
  throw "Vite exited with code $LASTEXITCODE."
}

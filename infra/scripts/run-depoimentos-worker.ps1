param(
  [switch]$Once,
  [switch]$Watch,
  [int]$Interval = 15,
  [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pythonExe = Join-Path $repoRoot 'infra\tools\python-runtime\python.exe'
$ffmpegBin = Join-Path $repoRoot 'infra\tools\ffmpeg\bin'
$workerScript = Join-Path $repoRoot 'infra\scripts\depoimentos_transcriber.py'
$envFile = Join-Path $repoRoot 'app\.env'

if (-not (Test-Path $pythonExe)) {
  throw "Python local nao encontrado em $pythonExe"
}
if (-not (Test-Path $workerScript)) {
  throw "Worker nao encontrado em $workerScript"
}
if (-not (Test-Path $envFile)) {
  throw "Arquivo app/.env ausente. Configure pelo menos SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e uma credencial GOOGLE_SERVICE_ACCOUNT_* antes de rodar o worker."
}
if (Test-Path $ffmpegBin) {
  $env:PATH = "$ffmpegBin;$env:PATH"
}

$args = @($workerScript)
if ($Once) {
  $args += '--once'
}
if ($Watch) {
  $args += '--watch'
}
if ($Interval -gt 0) {
  $args += @('--interval', [string]$Interval)
}
if ($Verbose) {
  $args += '--verbose'
}

& $pythonExe @args

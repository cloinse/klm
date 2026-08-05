[CmdletBinding()]
param(
  [string]$ReleaseDirectory = "build/windows/x64/runner/Release",
  [string]$OutputPath = "build/windows/x64/runner/Kontakt-Library-Manager-Windows.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$releasePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $ReleaseDirectory))
$portablePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputPath))
$sfxPath = Join-Path $PSScriptRoot "7zS2.sfx"
$sevenZipPath = Join-Path $PSScriptRoot "7zr.exe"
$manifestPath = Join-Path $PSScriptRoot "sfx-as-invoker.manifest"
$mainExecutable = Join-Path $releasePath "kontakt_library_manager.exe"
$portableDirectory = Split-Path -Parent $portablePath
$workingDirectory = Join-Path $portableDirectory ".klm-sfx"
$workingSfx = Join-Path $workingDirectory "7zS2.sfx"
$archivePath = Join-Path $workingDirectory "payload.7z"
$expectedSfxSha256 = "5844e4a1f78f309170b8a956df9a24caf932a6ba4cf1fcde3e0066d850fbf5e3"
$expectedSevenZipSha256 = "89645457d40b0e6731014a61ee6ebedd22c01a92fc38618480d385461c4347bb"

foreach ($requiredPath in @($releasePath, $mainExecutable, $sfxPath, $sevenZipPath, $manifestPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Required Windows packaging input is missing: $requiredPath"
  }
}

$topLevelExecutables = @(Get-ChildItem -LiteralPath $releasePath -Filter "*.exe" -File)
if ($topLevelExecutables.Count -ne 1 -or $topLevelExecutables[0].Name -ne "kontakt_library_manager.exe") {
  throw "The SFX payload must contain kontakt_library_manager.exe as its only top-level executable."
}

$actualSfxSha256 = (Get-FileHash -LiteralPath $sfxPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSfxSha256 -ne $expectedSfxSha256) {
  throw "The bundled LZMA SDK SFX module failed its SHA-256 integrity check."
}
$actualSevenZipSha256 = (Get-FileHash -LiteralPath $sevenZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSevenZipSha256 -ne $expectedSevenZipSha256) {
  throw "The bundled LZMA SDK compression tool failed its SHA-256 integrity check."
}

$manifestToolCommand = Get-Command "mt.exe" -ErrorAction SilentlyContinue
$manifestToolPath = if ($null -ne $manifestToolCommand) {
  $manifestToolCommand.Source
} else {
  $windowsKitsRoot = (Get-ItemProperty `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots" `
    -Name "KitsRoot10" `
    -ErrorAction Stop).KitsRoot10
  $manifestToolFile = Get-ChildItem `
    -Path (Join-Path $windowsKitsRoot "bin\*\x64\mt.exe") `
    -File `
    -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($null -ne $manifestToolFile) {
    $manifestToolFile.FullName
  }
}
if ([string]::IsNullOrWhiteSpace($manifestToolPath)) {
  throw "Windows SDK Manifest Tool (mt.exe) was not found."
}

New-Item -ItemType Directory -Force -Path $portableDirectory | Out-Null
if (Test-Path -LiteralPath $workingDirectory) {
  Remove-Item -LiteralPath $workingDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $workingDirectory | Out-Null

try {
  Copy-Item -LiteralPath $sfxPath -Destination $workingSfx

  # The portable container must not alter the application's UAC behavior.
  & $manifestToolPath -nologo -manifest $manifestPath "-outputresource:$workingSfx;#1"
  if ($LASTEXITCODE -ne 0) {
    throw "mt.exe failed with exit code $LASTEXITCODE"
  }

  Push-Location $releasePath
  try {
    # Fast LZMA2 compression keeps paid Windows build time low.
    & $sevenZipPath a -t7z -m0=LZMA2 -mx=1 -mmt=on $archivePath ".\*"
    if ($LASTEXITCODE -ne 0) {
      throw "7z.exe failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $outputStream = [IO.File]::Create($portablePath)
  try {
    foreach ($inputPath in @($workingSfx, $archivePath)) {
      $inputStream = [IO.File]::OpenRead($inputPath)
      try {
        $inputStream.CopyTo($outputStream)
      } finally {
        $inputStream.Dispose()
      }
    }
  } finally {
    $outputStream.Dispose()
  }

  $portableStream = [IO.File]::OpenRead($portablePath)
  try {
    if ($portableStream.ReadByte() -ne 0x4D -or $portableStream.ReadByte() -ne 0x5A) {
      throw "The generated portable executable does not have a valid PE header."
    }
  } finally {
    $portableStream.Dispose()
  }

  Write-Host "Created single-file portable executable: $portablePath"
} finally {
  if (Test-Path -LiteralPath $workingDirectory) {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

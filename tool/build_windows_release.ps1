[CmdletBinding()]
param(
  [switch]$Publish,
  [string]$Tag,
  [string]$FlutterRoot,
  [string]$ToolsRoot
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
}

$VersionMatches = @(
  Select-String -Path 'pubspec.yaml' `
    -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
)
if ($VersionMatches.Count -ne 1) {
  throw 'pubspec.yaml must contain one semantic version and numeric build.'
}

$Version = $VersionMatches[0].Matches[0].Groups[1].Value
$Build = $VersionMatches[0].Matches[0].Groups[2].Value
if ([string]::IsNullOrWhiteSpace($Tag)) {
  $Tag = "v$Version"
}
if ($Tag -ne "v$Version") {
  throw "Release tag $Tag does not match version $Version."
}
$GitHubTokenFile = '.secrets\GITHUB_TOKEN'
if ($Publish -and [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
  if (-not (Test-Path -LiteralPath $GitHubTokenFile -PathType Leaf)) {
    throw "Create $GitHubTokenFile or set GITHUB_TOKEN before using -Publish."
  }
  $LocalGitHubToken = [IO.File]::ReadAllText($GitHubTokenFile).Trim()
  if ([string]::IsNullOrWhiteSpace($LocalGitHubToken)) {
    throw "$GitHubTokenFile must contain a non-empty GitHub token."
  }
}

if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
  $FlutterRoot = $env:FLUTTER_ROOT
}
if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
  $FlutterRoot = Join-Path $env:USERPROFILE 'flutter'
}
if ([string]::IsNullOrWhiteSpace($ToolsRoot)) {
  $ToolsRoot = Join-Path $env:USERPROFILE '.klm-tools'
}

$Dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$FlutterTools = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
$InnoCompiler = Join-Path $ToolsRoot 'inno-7.0.2\ISCC.exe'
$WinSparkleRoot = Join-Path $ToolsRoot 'winsparkle-0.9.4'
$WinSparkleDll = Join-Path $WinSparkleRoot 'WinSparkle.dll'
$WinSparkleTool = Join-Path $WinSparkleRoot 'winsparkle-tool.exe'

foreach ($RequiredPath in @(
    $Dart,
    $FlutterTools,
    $InnoCompiler,
    $WinSparkleDll,
    $WinSparkleTool,
    '.secrets\KLM_SPARKLE_PRIVATE_KEY'
  )) {
  if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
    throw "Required release file not found: $RequiredPath"
  }
}

$UpdaterDirectory = Join-Path $PWD.Path 'windows\runner\third_party\winsparkle'
New-Item -ItemType Directory -Force -Path $UpdaterDirectory | Out-Null
Copy-Item $WinSparkleDll (Join-Path $UpdaterDirectory 'WinSparkle.dll') -Force

Invoke-Checked $Dart @($FlutterTools, 'analyze', '--no-pub') `
  'Flutter analyze failed.'
Invoke-Checked $Dart @($FlutterTools, 'test', '--no-pub') `
  'Flutter tests failed.'
Invoke-Checked $Dart @($FlutterTools, 'build', 'windows', '--release', '--no-pub') `
  'Windows Release build failed.'

$ReleaseDirectory = (Resolve-Path 'build\windows\x64\runner\Release').Path
$RetiredPowerShellHelper = Join-Path $ReleaseDirectory 'KontaktLibraryHelper.ps1'
if (Test-Path -LiteralPath $RetiredPowerShellHelper) {
  Remove-Item -LiteralPath $RetiredPowerShellHelper -Force
}

$PackageName = "klm-windows-v$Version"
$OutputDirectory = Join-Path $PWD.Path "build\windows-release\$PackageName"
if (Test-Path -LiteralPath $OutputDirectory) {
  Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Invoke-Checked $InnoCompiler @(
  "/DMyAppVersion=$Version",
  "/DMyAppBuild=$Build",
  "/DMySourceDir=$ReleaseDirectory",
  "/DMyOutputDir=$OutputDirectory",
  'windows\installer\kontakt_library_manager.iss'
) 'Inno Setup compilation failed.'

$Installer = Join-Path $OutputDirectory "$PackageName.exe"
if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
  throw "Installer was not created: $Installer"
}

$HashPath = "$Installer.sha256"
$Hash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(
  $HashPath,
  "$Hash  $([IO.Path]::GetFileName($Installer))`n",
  [Text.UTF8Encoding]::new($false)
)

$Appcast = Join-Path $OutputDirectory 'appcast-windows.xml'
$PreviousDownloadPrefix = $env:KLM_UPDATE_DOWNLOAD_URL_PREFIX
$PreviousPrivateKeyFile = $env:KLM_SPARKLE_PRIVATE_KEY_FILE
$env:KLM_UPDATE_DOWNLOAD_URL_PREFIX =
  "https://github.com/cloinse/klm/releases/download/$Tag"
$env:KLM_SPARKLE_PRIVATE_KEY_FILE =
  (Resolve-Path '.secrets\KLM_SPARKLE_PRIVATE_KEY').Path
try {
  Invoke-Checked $Dart @(
    'run',
    'tool\generate_appcast.dart',
    '--platform',
    'windows',
    '--installer',
    $Installer,
    '--output',
    $Appcast,
    '--version',
    $Version,
    '--build',
    $Build,
    '--winsparkle-tool',
    $WinSparkleTool,
    '--release-notes',
    'updates\release-notes.txt'
  ) 'Windows appcast generation failed.'

  $ExpectedFiles = @(
    "$PackageName.exe",
    "$PackageName.exe.sha256",
    'appcast-windows.xml'
  )
  $ActualFiles = @(
    Get-ChildItem -LiteralPath $OutputDirectory -File |
      Select-Object -ExpandProperty Name
  )
  if ($ActualFiles.Count -ne $ExpectedFiles.Count -or
      @($ExpectedFiles | Where-Object { $_ -notin $ActualFiles }).Count -ne 0 -or
      @($ActualFiles | Where-Object { $_ -notin $ExpectedFiles }).Count -ne 0) {
    throw "Windows release output must contain exactly: $($ExpectedFiles -join ', ')"
  }

  if ($Publish) {
    Invoke-Checked $Dart @(
      'run',
      'tool\publish_github_release.dart',
      '--version',
      $Version,
      '--tag',
      $Tag,
      '--appcast',
      $Appcast,
      '--repository-appcast-path',
      'updates/appcast-windows.xml',
      '--asset',
      $Installer,
      '--asset',
      $HashPath,
      '--release-notes',
      'updates\release-notes.txt'
    ) 'GitHub Windows release publishing failed.'
  } else {
    Write-Host "Windows release generated at $OutputDirectory."
    Write-Host 'Use -Publish with .secrets\GITHUB_TOKEN or GITHUB_TOKEN set to publish the EXE, SHA, and appcast.'
  }
} finally {
  if ($null -eq $PreviousDownloadPrefix) {
    Remove-Item Env:KLM_UPDATE_DOWNLOAD_URL_PREFIX -ErrorAction SilentlyContinue
  } else {
    $env:KLM_UPDATE_DOWNLOAD_URL_PREFIX = $PreviousDownloadPrefix
  }
  if ($null -eq $PreviousPrivateKeyFile) {
    Remove-Item Env:KLM_SPARKLE_PRIVATE_KEY_FILE -ErrorAction SilentlyContinue
  } else {
    $env:KLM_SPARKLE_PRIVATE_KEY_FILE = $PreviousPrivateKeyFile
  }
}

Write-Host "Windows release ready: $OutputDirectory"

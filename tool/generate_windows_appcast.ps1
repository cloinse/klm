param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$Build,
  [Parameter(Mandatory = $true)][string]$WinSparkleTool
)

$ErrorActionPreference = 'Stop'
$PublicKey = 'IEM06s9BrwRuC4XtbnRQi6/hVNrTP+aN0naS8RdQNA8='
$DownloadUrlPrefix = $env:KLM_UPDATE_DOWNLOAD_URL_PREFIX
if ([string]::IsNullOrWhiteSpace($DownloadUrlPrefix)) {
  throw 'Set KLM_UPDATE_DOWNLOAD_URL_PREFIX.'
}
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
  throw "Installer not found: $InstallerPath"
}
if (-not (Test-Path -LiteralPath $WinSparkleTool -PathType Leaf)) {
  throw "WinSparkle signing tool not found: $WinSparkleTool"
}

$PrivateKeyPath = $env:KLM_SPARKLE_PRIVATE_KEY_FILE
$TemporaryKeyPath = $null
try {
  if (-not [string]::IsNullOrWhiteSpace($env:KLM_SPARKLE_PRIVATE_KEY)) {
    $TemporaryKeyPath = Join-Path ([IO.Path]::GetTempPath()) (
      'klm-sparkle-key-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText(
      $TemporaryKeyPath,
      $env:KLM_SPARKLE_PRIVATE_KEY.Trim(),
      [Text.UTF8Encoding]::new($false)
    )
    $PrivateKeyPath = $TemporaryKeyPath
  }
  if ([string]::IsNullOrWhiteSpace($PrivateKeyPath) -or
      -not (Test-Path -LiteralPath $PrivateKeyPath -PathType Leaf)) {
    throw 'Configure KLM_SPARKLE_PRIVATE_KEY or KLM_SPARKLE_PRIVATE_KEY_FILE.'
  }

  $Signature = (& $WinSparkleTool sign `
    --private-key-file $PrivateKeyPath $InstallerPath).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'WinSparkle could not sign the installer.' }
  $SignatureBytes = [Convert]::FromBase64String($Signature)
  if ($SignatureBytes.Length -ne 64) { throw 'Invalid EdDSA signature.' }
  & $WinSparkleTool verify --public-key $PublicKey `
    --signature $Signature $InstallerPath
  if ($LASTEXITCODE -ne 0) { throw 'Installer signature verification failed.' }

  $Installer = Get-Item -LiteralPath $InstallerPath
  $DownloadUrl = $DownloadUrlPrefix.TrimEnd('/') + '/' + $Installer.Name
  $OutputDirectory = Split-Path -Parent $OutputPath
  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

  $Settings = [Xml.XmlWriterSettings]::new()
  $Settings.Encoding = [Text.UTF8Encoding]::new($false)
  $Settings.Indent = $true
  $Writer = [Xml.XmlWriter]::Create($OutputPath, $Settings)
  try {
    $SparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    $Writer.WriteStartDocument()
    $Writer.WriteStartElement('rss')
    $Writer.WriteAttributeString('version', '2.0')
    $Writer.WriteAttributeString('xmlns', 'sparkle', $null, $SparkleNamespace)
    $Writer.WriteStartElement('channel')
    $Writer.WriteElementString('title', 'Kontakt Library Manager - Windows')
    $Writer.WriteStartElement('item')
    $Writer.WriteElementString('title', $Version)
    $Writer.WriteElementString('pubDate', [DateTime]::UtcNow.ToString('r'))
    $Writer.WriteElementString('sparkle', 'version', $SparkleNamespace, $Build)
    $Writer.WriteElementString(
      'sparkle', 'shortVersionString', $SparkleNamespace, $Version)
    $Writer.WriteElementString(
      'sparkle', 'minimumSystemVersion', $SparkleNamespace, '10.0')
    $Writer.WriteStartElement('enclosure')
    $Writer.WriteAttributeString('url', $DownloadUrl)
    $Writer.WriteAttributeString('length', $Installer.Length.ToString())
    $Writer.WriteAttributeString('type', 'application/octet-stream')
    $Writer.WriteAttributeString(
      'sparkle', 'os', $SparkleNamespace, 'windows-x64')
    $Writer.WriteAttributeString(
      'sparkle', 'installerArguments', $SparkleNamespace,
      '/SILENT /SP- /NOICONS /NORESTART')
    $Writer.WriteAttributeString(
      'sparkle', 'edSignature', $SparkleNamespace, $Signature)
    $Writer.WriteEndElement()
    $Writer.WriteEndElement()
    $Writer.WriteEndElement()
    $Writer.WriteEndElement()
    $Writer.WriteEndDocument()
  } finally {
    $Writer.Dispose()
  }
  Write-Host "Created signed Windows appcast: $OutputPath"
} finally {
  if ($null -ne $TemporaryKeyPath -and
      (Test-Path -LiteralPath $TemporaryKeyPath)) {
    Remove-Item -LiteralPath $TemporaryKeyPath -Force
  }
}

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('inventory', 'mutation', 'classicOrder')]
  [string]$Mode,

  [string]$RequestPath,
  [string]$RequestSha256,

  [Parameter(Mandatory = $true)]
  [string]$ResponsePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$script:SafeRequestResponsePath = $null

function Test-IsAdministrator {
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  try {
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
      [System.Security.Principal.WindowsBuiltInRole]::Administrator
    )
  } finally {
    $identity.Dispose()
  }
}

function ConvertTo-NativeQuotedArgument {
  param([Parameter(Mandatory = $true)] [string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains('"')) {
    throw 'An invalid helper argument was rejected.'
  }
  return '"' + $Value + '"'
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory = $true)] [string]$Path,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    $Value
  )

  $parent = Split-Path -Parent $Path
  if ($parent) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
  }
  $json = ConvertTo-Json -InputObject $Value -Depth 8 -Compress
  [System.IO.File]::WriteAllText(
    $Path,
    $json,
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Invoke-ElevatedMutation {
  param(
    [Parameter(Mandatory = $true)] [string]$HelperPath,
    [Parameter(Mandatory = $true)] [string]$Request,
    [Parameter(Mandatory = $true)] [string]$RequestHash,
    [Parameter(Mandatory = $true)] [string]$Response
  )

  $argumentLine = @(
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy Bypass',
    ('-File ' + (ConvertTo-NativeQuotedArgument $HelperPath)),
    '-Mode mutation',
    ('-RequestPath ' + (ConvertTo-NativeQuotedArgument $Request)),
    ('-RequestSha256 ' + (ConvertTo-NativeQuotedArgument $RequestHash)),
    ('-ResponsePath ' + (ConvertTo-NativeQuotedArgument $Response))
  ) -join ' '

  try {
    $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
      -ArgumentList $argumentLine -Wait -PassThru
  } catch {
    Write-JsonFile $Response ([ordered]@{
      errorCode = 'authorization_cancelled'
      errorMessage = 'Administrator approval was cancelled or could not be started.'
    })
    return 1
  }

  if ($elevated.ExitCode -ne 0 -and
      -not (Test-Path -LiteralPath $Response -PathType Leaf)) {
    Write-JsonFile $Response ([ordered]@{
      errorCode = 'mutation_failed'
      errorMessage = 'The administrator operation failed.'
    })
  }
  return $elevated.ExitCode
}

function Get-RegistryValue {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryKey]$Key,
    [Parameter(Mandatory = $true)] [string]$Name,
    $DefaultValue = $null
  )

  return $Key.GetValue(
    $Name,
    $DefaultValue,
    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
  )
}

function Get-UserListIndexes {
  $indexes = @{}
  $views = @(
    [Microsoft.Win32.RegistryView]::Registry64,
    [Microsoft.Win32.RegistryView]::Registry32
  )

  foreach ($view in $views) {
    $baseKey = $null
    $nativeInstruments = $null
    try {
      $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        $view
      )
      $nativeInstruments = $baseKey.OpenSubKey(
        'SOFTWARE\Native Instruments',
        $false
      )
      if ($null -eq $nativeInstruments) { continue }

      foreach ($subKeyName in $nativeInstruments.GetSubKeyNames()) {
        $productKey = $null
        try {
          $productKey = $nativeInstruments.OpenSubKey($subKeyName, $false)
          if ($null -eq $productKey) { continue }
          $rawIndex = Get-RegistryValue $productKey 'UserListIndex'
          if ($null -eq $rawIndex) { continue }
          $parsedIndex = 0
          if (-not [int]::TryParse("$rawIndex", [ref]$parsedIndex)) { continue }

          $identity = $subKeyName.Trim().ToLowerInvariant()
          if ($identity -and -not $indexes.ContainsKey($identity)) {
            $indexes[$identity] = $parsedIndex
          }
          $regKey = [string](Get-RegistryValue $productKey 'RegKey' '')
          $regKeyIdentity = $regKey.Trim().ToLowerInvariant()
          if ($regKeyIdentity -and -not $indexes.ContainsKey($regKeyIdentity)) {
            $indexes[$regKeyIdentity] = $parsedIndex
          }
        } finally {
          if ($null -ne $productKey) { $productKey.Dispose() }
        }
      }
    } finally {
      if ($null -ne $nativeInstruments) { $nativeInstruments.Dispose() }
      if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
  }
  return $indexes
}

function Get-RegistryInventory {
  $records = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  $userListIndexes = Get-UserListIndexes
  $views = @(
    [Microsoft.Win32.RegistryView]::Registry64,
    [Microsoft.Win32.RegistryView]::Registry32
  )

  foreach ($view in $views) {
    $baseKey = $null
    $nativeInstruments = $null
    try {
      $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        $view
      )
      $nativeInstruments = $baseKey.OpenSubKey(
        'SOFTWARE\Native Instruments',
        $false
      )
      if ($null -eq $nativeInstruments) { continue }

      foreach ($subKeyName in $nativeInstruments.GetSubKeyNames()) {
        $identity = $subKeyName.Trim().ToLowerInvariant()
        if (-not $identity -or $seen.ContainsKey($identity)) { continue }

        $productKey = $null
        try {
          $productKey = $nativeInstruments.OpenSubKey($subKeyName, $false)
          if ($null -eq $productKey) { continue }

          $regKey = [string](Get-RegistryValue $productKey 'RegKey' $subKeyName)
          if ([string]::IsNullOrWhiteSpace($regKey)) { $regKey = $subKeyName }
          $record = [ordered]@{
            name = [string](Get-RegistryValue $productKey 'Name' $regKey)
            regKey = $regKey
          }
          $snpid = Get-RegistryValue $productKey 'SNPID'
          $contentPath = Get-RegistryValue $productKey 'ContentDir'
          $userListIndex = $null
          foreach ($candidate in @($regKey, $subKeyName)) {
            $candidateIdentity = $candidate.Trim().ToLowerInvariant()
            if ($candidateIdentity -and
                $userListIndexes.ContainsKey($candidateIdentity)) {
              $userListIndex = $userListIndexes[$candidateIdentity]
              break
            }
          }
          if ($null -eq $userListIndex) {
            $userListIndex = Get-RegistryValue $productKey 'UserListIndex'
          }
          if ($null -ne $snpid -and "$snpid".Trim()) {
            $record.snpid = "$snpid".Trim()
          }
          if ($null -ne $contentPath -and "$contentPath".Trim()) {
            $record.contentPath = "$contentPath".Trim()
          }
          if ($null -ne $userListIndex) {
            $parsedIndex = 0
            if ([int]::TryParse("$userListIndex", [ref]$parsedIndex)) {
              $record.userListIndex = $parsedIndex
            }
          }
          $records.Add([pscustomobject]$record) | Out-Null
          $seen[$identity] = $true
        } finally {
          if ($null -ne $productKey) { $productKey.Dispose() }
        }
      }
    } finally {
      if ($null -ne $nativeInstruments) { $nativeInstruments.Dispose() }
      if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
  }

  return ,$records.ToArray()
}

function Get-SafeComponent {
  param(
    [Parameter(Mandatory = $true)] $Value,
    [Parameter(Mandatory = $true)] [string]$Field
  )

  if ($Value -isnot [string]) { throw "Invalid $Field." }
  $candidate = $Value.Trim()
  if (-not $candidate -or
      $candidate.Length -gt 255 -or
      $candidate -eq '.' -or
      $candidate -eq '..' -or
      $candidate.EndsWith('.') -or
      $candidate.EndsWith(' ') -or
      $candidate.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
      $candidate.IndexOf([char]0) -ge 0) {
    throw "Invalid $Field."
  }
  foreach ($character in $candidate.ToCharArray()) {
    if ([char]::IsControl($character)) { throw "Invalid $Field." }
  }
  return $candidate
}

function Get-OptionalSafeString {
  param($Value, [Parameter(Mandatory = $true)] [string]$Field)
  if ($null -eq $Value) { return $null }
  return Get-SafeComponent $Value $Field
}

function Get-ObjectProperty {
  param(
    [Parameter(Mandatory = $true)] $Object,
    [Parameter(Mandatory = $true)] [string]$Name
  )
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-ContentDirectory {
  param([Parameter(Mandatory = $true)] $Value)

  if ($Value -isnot [string] -or
      $Value.Length -gt 4096 -or
      -not [System.IO.Path]::IsPathRooted($Value) -or
      -not (Test-Path -LiteralPath $Value -PathType Container)) {
    throw 'The Kontakt content directory is invalid or does not exist.'
  }
  return (Get-Item -LiteralPath $Value -Force).FullName
}

function Get-RequestTransportPaths {
  param(
    [Parameter(Mandatory = $true)] [string]$Request,
    [Parameter(Mandatory = $true)] [string]$Response,
    [Parameter(Mandatory = $true)]
    [ValidateSet('mutation', 'order')]
    [string]$Kind
  )

  $requestFullPath = [System.IO.Path]::GetFullPath($Request)
  $responseFullPath = [System.IO.Path]::GetFullPath($Response)
  $temporaryRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetTempPath()
  ).TrimEnd('\') + '\'
  if (-not $requestFullPath.StartsWith(
        $temporaryRoot,
        [System.StringComparison]::OrdinalIgnoreCase
      ) -or
      -not $responseFullPath.StartsWith(
        $temporaryRoot,
        [System.StringComparison]::OrdinalIgnoreCase
      ) -or
      [System.IO.Path]::GetFileName($requestFullPath) -cne 'request.json' -or
      [System.IO.Path]::GetFileName($responseFullPath) -cne 'response.json' -or
      (Split-Path -Parent $requestFullPath) -ine
        (Split-Path -Parent $responseFullPath) -or
      (Split-Path -Leaf (Split-Path -Parent $requestFullPath)) -notmatch
        "^klm-$Kind-[A-Za-z0-9_-]+$") {
    throw 'The mutation transport paths are invalid.'
  }
  Assert-NoReparsePoint (Split-Path -Parent $requestFullPath)
  return [pscustomobject]@{
    Request = $requestFullPath
    Response = $responseFullPath
  }
}

function Get-VerifiedRequest {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('mutation', 'order')]
    [string]$Kind
  )

  if (-not $RequestPath -or
      -not $RequestSha256 -or
      $RequestSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
      -not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
    throw 'The helper request is missing or invalid.'
  }
  $transport = Get-RequestTransportPaths $RequestPath $ResponsePath $Kind
  $script:SafeRequestResponsePath = $transport.Response
  $requestBytes = [System.IO.File]::ReadAllBytes($transport.Request)
  if ($requestBytes.Length -gt 2500000) { throw 'The helper request is too large.' }
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $actualHash = [System.BitConverter]::ToString(
      $sha256.ComputeHash($requestBytes)
    ).Replace('-', '')
  } finally {
    $sha256.Dispose()
  }
  if ($actualHash -ine $RequestSha256) {
    throw 'The helper request checksum does not match.'
  }

  $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
  $request = ConvertFrom-Json -InputObject $strictUtf8.GetString($requestBytes)
  if ((Get-ObjectProperty $request 'version') -ne 1) {
    throw 'Unsupported helper request version.'
  }
  return $request
}

function Assert-NoReparsePoint {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($fullPath)
  $relative = $fullPath.Substring($root.Length)
  $current = $root
  foreach ($component in $relative.Split(
      [char[]]@([System.IO.Path]::DirectorySeparatorChar),
      [System.StringSplitOptions]::RemoveEmptyEntries
    )) {
    $current = Join-Path $current $component
    if (-not (Test-Path -LiteralPath $current)) { continue }
    $attributes = (Get-Item -LiteralPath $current -Force).Attributes
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "A reparse point was rejected: $current"
    }
  }
}

function Assert-ProductHints {
  param(
    [Parameter(Mandatory = $true)] [string]$Xml,
    [Parameter(Mandatory = $true)] [string]$Name,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] [string]$Snpid
  )

  if ([System.Text.Encoding]::UTF8.GetByteCount($Xml) -gt 2000000 -or
      $Xml -match '(?i)<!DOCTYPE|<!ENTITY') {
    throw 'Invalid ProductHints XML.'
  }

  $settings = New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver = $null
  $stringReader = New-Object System.IO.StringReader($Xml)
  $reader = $null
  try {
    $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($reader)
    $products = $document.SelectNodes('/ProductHints/Product')
    if ($products.Count -ne 1 -or
        $document.SelectSingleNode('/ProductHints/Product/Name').InnerText.Trim() -cne $Name -or
        $document.SelectSingleNode('/ProductHints/Product/RegKey').InnerText.Trim() -cne $RegKey -or
        $document.SelectSingleNode('/ProductHints/Product/SNPID').InnerText.Trim() -cne $Snpid) {
      throw 'ProductHints fields do not match the selected library.'
    }
  } finally {
    if ($null -ne $reader) { $reader.Dispose() }
    $stringReader.Dispose()
  }
}

function Get-FileBackup {
  param([Parameter(Mandatory = $true)] [string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    return [pscustomobject]@{ Exists = $true; Bytes = [System.IO.File]::ReadAllBytes($Path) }
  }
  return [pscustomobject]@{ Exists = $false; Bytes = $null }
}

function Restore-FileBackup {
  param(
    [Parameter(Mandatory = $true)] [string]$Path,
    [Parameter(Mandatory = $true)] $Backup
  )
  if ($Backup.Exists) {
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllBytes($Path, $Backup.Bytes)
  } elseif (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Set-AtomicUtf8File {
  param(
    [Parameter(Mandatory = $true)] [string]$Path,
    [Parameter(Mandatory = $true)] [string]$Contents
  )

  $parent = Split-Path -Parent $Path
  Assert-NoReparsePoint $parent
  [System.IO.Directory]::CreateDirectory($parent) | Out-Null
  Assert-NoReparsePoint $parent
  $temporary = Join-Path $parent ('.klm-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [System.IO.File]::WriteAllText(
      $temporary,
      $Contents,
      (New-Object System.Text.UTF8Encoding($false))
    )
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) {
      Remove-Item -LiteralPath $temporary -Force
    }
  }
}

function Get-RegistryBackup {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryHive]$Hive,
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    $Hive,
    $View
  )
  $key = $null
  try {
    $key = $baseKey.OpenSubKey("SOFTWARE\Native Instruments\$RegKey", $false)
    if ($null -eq $key) {
      return [pscustomobject]@{ Exists = $false; Values = @{} }
    }
    $values = @{}
    foreach ($name in $key.GetValueNames()) {
      $values[$name] = [pscustomobject]@{
        Value = Get-RegistryValue $key $name
        Kind = $key.GetValueKind($name)
      }
    }
    return [pscustomobject]@{ Exists = $true; Values = $values }
  } finally {
    if ($null -ne $key) { $key.Dispose() }
    $baseKey.Dispose()
  }
}

function Restore-RegistryBackup {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryHive]$Hive,
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] $Backup
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    $Hive,
    $View
  )
  try {
    $nativeInstruments = $baseKey.CreateSubKey('SOFTWARE\Native Instruments')
    try {
      $nativeInstruments.DeleteSubKeyTree($RegKey, $false)
      if ($Backup.Exists) {
        $key = $nativeInstruments.CreateSubKey($RegKey)
        try {
          foreach ($name in $Backup.Values.Keys) {
            $entry = $Backup.Values[$name]
            $key.SetValue($name, $entry.Value, $entry.Kind)
          }
        } finally {
          $key.Dispose()
        }
      }
    } finally {
      $nativeInstruments.Dispose()
    }
  } finally {
    $baseKey.Dispose()
  }
}

function Get-RegistryValuesBackup {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryHive]$Hive,
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] [string[]]$Names
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
  $key = $null
  try {
    $key = $baseKey.OpenSubKey("SOFTWARE\Native Instruments\$RegKey", $false)
    $backup = @{}
    foreach ($name in $Names) {
      $value = if ($null -eq $key) { $null } else {
        Get-RegistryValue $key $name
      }
      $exists = $null -ne $key -and $key.GetValueNames() -contains $name
      $backup[$name] = [pscustomobject]@{
        Exists = $exists
        Value = $value
        Kind = if ($exists) { $key.GetValueKind($name) } else { $null }
      }
    }
    return [pscustomobject]@{
      KeyExisted = $null -ne $key
      Values = $backup
    }
  } finally {
    if ($null -ne $key) { $key.Dispose() }
    $baseKey.Dispose()
  }
}

function Restore-RegistryValuesBackup {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryHive]$Hive,
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] $Backup
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
  try {
    $nativeInstruments = $baseKey.CreateSubKey('SOFTWARE\Native Instruments')
    try {
      $key = $nativeInstruments.CreateSubKey($RegKey)
      try {
        foreach ($name in $Backup.Values.Keys) {
          $entry = $Backup.Values[$name]
          if ($entry.Exists) {
            $key.SetValue($name, $entry.Value, $entry.Kind)
          } else {
            $key.DeleteValue($name, $false)
          }
        }
      } finally {
        $key.Dispose()
      }
      if (-not $Backup.KeyExisted) {
        $createdKey = $nativeInstruments.OpenSubKey($RegKey, $false)
        try {
          if ($null -ne $createdKey -and
              $createdKey.ValueCount -eq 0 -and
              $createdKey.SubKeyCount -eq 0) {
            $createdKey.Dispose()
            $createdKey = $null
            $nativeInstruments.DeleteSubKey($RegKey, $false)
          }
        } finally {
          if ($null -ne $createdKey) { $createdKey.Dispose() }
        }
      }
    } finally {
      $nativeInstruments.Dispose()
    }
  } finally {
    $baseKey.Dispose()
  }
}

function Set-RegistryRecord {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] [hashtable]$Values,
    [Parameter(Mandatory = $true)] [bool]$Remove
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    $View
  )
  try {
    $nativeInstruments = $baseKey.CreateSubKey('SOFTWARE\Native Instruments')
    try {
      if ($Remove) {
        $nativeInstruments.DeleteSubKeyTree($RegKey, $false)
        return
      }
      $key = $nativeInstruments.CreateSubKey($RegKey)
      try {
        foreach ($entry in $Values.GetEnumerator()) {
          $kind = if ($entry.Key -in @('Visibility', 'UserListIndex')) {
            [Microsoft.Win32.RegistryValueKind]::DWord
          } else {
            [Microsoft.Win32.RegistryValueKind]::String
          }
          $key.SetValue($entry.Key, $entry.Value, $kind)
        }
      } finally {
        $key.Dispose()
      }
    } finally {
      $nativeInstruments.Dispose()
    }
  } finally {
    $baseKey.Dispose()
  }
}

function Set-UserRegistryValues {
  param(
    [Parameter(Mandatory = $true)] [Microsoft.Win32.RegistryView]$View,
    [Parameter(Mandatory = $true)] [string]$RegKey,
    [Parameter(Mandatory = $true)] [hashtable]$Values
  )

  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser,
    $View
  )
  try {
    $nativeInstruments = $baseKey.CreateSubKey('SOFTWARE\Native Instruments')
    try {
      $key = $nativeInstruments.CreateSubKey($RegKey)
      try {
        foreach ($entry in $Values.GetEnumerator()) {
          $kind = if ($entry.Key -in @('UserListIndex', 'browserLibsAZSort')) {
            [Microsoft.Win32.RegistryValueKind]::DWord
          } else {
            [Microsoft.Win32.RegistryValueKind]::String
          }
          $key.SetValue($entry.Key, $entry.Value, $kind)
        }
      } finally {
        $key.Dispose()
      }
    } finally {
      $nativeInstruments.Dispose()
    }
  } finally {
    $baseKey.Dispose()
  }
}

function Invoke-Mutation {
  $request = Get-VerifiedRequest 'mutation'
  $operation = [string](Get-ObjectProperty $request 'operation')
  if ($operation -notin @('upsert', 'relocate', 'remove')) {
    throw 'Unknown mutation operation.'
  }
  $name = Get-SafeComponent (Get-ObjectProperty $request 'name') 'name'
  $regKey = Get-SafeComponent (Get-ObjectProperty $request 'regKey') 'RegKey'

  $programFiles = [System.Environment]::GetFolderPath(
    [System.Environment+SpecialFolder]::ProgramFiles
  )
  $commonDocuments = [System.Environment]::GetFolderPath(
    [System.Environment+SpecialFolder]::CommonDocuments
  )
  $serviceDirectory = Join-Path $programFiles 'Common Files\Native Instruments\Service Center'
  $productsDirectory = Join-Path $commonDocuments 'Native Instruments\installed_products'
  $xmlPath = Join-Path $serviceDirectory "$name.xml"
  $jsonPath = Join-Path $productsDirectory "$name.json"

  $fileChanges = @()
  $registryValues = @{}
  $removeRegistry = $operation -eq 'remove'
  if ($operation -eq 'upsert') {
    $snpid = Get-SafeComponent (Get-ObjectProperty $request 'snpid') 'SNPID'
    $contentPath = Get-ContentDirectory (Get-ObjectProperty $request 'contentPath')
    $productHintsXml = [string](Get-ObjectProperty $request 'productHintsXml')
    Assert-ProductHints $productHintsXml $name $regKey $snpid
    $visibility = 3
    $requestedVisibility = Get-ObjectProperty $request 'visibility'
    if ($null -ne $requestedVisibility) { $visibility = [int]$requestedVisibility }
    if ($visibility -lt 0 -or $visibility -gt 255) { throw 'Invalid visibility.' }

    $registryValues = @{
      Name = $name
      RegKey = $regKey
      SNPID = $snpid
      ContentDir = $contentPath
      Visibility = $visibility
    }
    foreach ($pair in @(
      @('hu', 'HU'), @('jdx', 'JDX'), @('upid', 'UPID'),
      @('authSystem', 'AuthSystem')
    )) {
      $value = Get-OptionalSafeString (
        Get-ObjectProperty $request $pair[0]
      ) $pair[0]
      if ($null -ne $value) { $registryValues[$pair[1]] = $value }
    }
    $json = ConvertTo-Json -InputObject ([ordered]@{ ContentDir = $contentPath }) -Depth 3
    $fileChanges = @(
      [pscustomobject]@{ Path = $xmlPath; Contents = $productHintsXml },
      [pscustomobject]@{ Path = $jsonPath; Contents = $json }
    )
  } elseif ($operation -eq 'relocate') {
    $contentPath = Get-ContentDirectory (Get-ObjectProperty $request 'contentPath')
    $registryValues = @{
      Name = $name
      RegKey = $regKey
      ContentDir = $contentPath
    }
    $snpid = Get-OptionalSafeString (
      Get-ObjectProperty $request 'snpid'
    ) 'SNPID'
    if ($null -ne $snpid) { $registryValues.SNPID = $snpid }
    $json = ConvertTo-Json -InputObject ([ordered]@{ ContentDir = $contentPath }) -Depth 3
    $fileChanges = @(
      [pscustomobject]@{ Path = $jsonPath; Contents = $json }
    )
  } else {
    $fileChanges = @(
      [pscustomobject]@{ Path = $xmlPath; Contents = $null },
      [pscustomobject]@{ Path = $jsonPath; Contents = $null }
    )
  }

  $views = @([Microsoft.Win32.RegistryView]::Registry64)
  $registry32 = Get-RegistryBackup `
    ([Microsoft.Win32.RegistryHive]::LocalMachine) `
    ([Microsoft.Win32.RegistryView]::Registry32) `
    $regKey
  if ($registry32.Exists) { $views += [Microsoft.Win32.RegistryView]::Registry32 }
  $fileBackups = @{}
  $registryBackups = @{}
  $changedPaths = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($change in $fileChanges) {
      Assert-NoReparsePoint (Split-Path -Parent $change.Path)
      $fileBackups[$change.Path] = Get-FileBackup $change.Path
      if ($null -eq $change.Contents) {
        if (Test-Path -LiteralPath $change.Path -PathType Leaf) {
          Remove-Item -LiteralPath $change.Path -Force
        }
      } else {
        Set-AtomicUtf8File $change.Path $change.Contents
      }
      $changedPaths.Add($change.Path) | Out-Null
    }

    foreach ($view in $views) {
      $key = "$view"
      $registryBackups[$key] = if ($view -eq [Microsoft.Win32.RegistryView]::Registry32) {
        $registry32
      } else {
        Get-RegistryBackup ([Microsoft.Win32.RegistryHive]::LocalMachine) $view $regKey
      }
      Set-RegistryRecord $view $regKey $registryValues $removeRegistry
      $changedPaths.Add(
        "HKLM [$view]\SOFTWARE\Native Instruments\$regKey"
      ) | Out-Null
    }
  } catch {
    foreach ($change in $fileChanges) {
      if ($fileBackups.ContainsKey($change.Path)) {
        try { Restore-FileBackup $change.Path $fileBackups[$change.Path] } catch {}
      }
    }
    foreach ($view in $views) {
      $key = "$view"
      if ($registryBackups.ContainsKey($key)) {
        try {
          Restore-RegistryBackup `
            ([Microsoft.Win32.RegistryHive]::LocalMachine) `
            $view $regKey $registryBackups[$key]
        } catch {}
      }
    }
    throw
  }

  return [ordered]@{
    operation = $operation
    libraryName = $name
    changedPaths = $changedPaths.ToArray()
  }
}

function Invoke-ClassicOrder {
  $request = Get-VerifiedRequest 'order'
  $rawEntries = @(Get-ObjectProperty $request 'entries')
  if ($rawEntries.Count -gt 10000) {
    throw 'The classic Kontakt order is too large.'
  }

  $kontaktIsRunning = @(
    Get-Process -ErrorAction SilentlyContinue |
      Where-Object { $_.ProcessName -match '^Kontakt(?:\s+\d+(?:\.\d+)*)?$' }
  ).Count -gt 0
  if ($kontaktIsRunning) {
    throw 'Close Kontakt and any DAW using Kontakt before saving the classic library order.'
  }

  $entries = New-Object System.Collections.Generic.List[object]
  $regKeys = @{}
  $indexes = @{}
  foreach ($rawEntry in $rawEntries) {
    $regKey = Get-SafeComponent (Get-ObjectProperty $rawEntry 'regKey') 'RegKey'
    $name = Get-SafeComponent (Get-ObjectProperty $rawEntry 'name') 'name'
    $snpid = Get-OptionalSafeString (
      Get-ObjectProperty $rawEntry 'snpid'
    ) 'SNPID'
    $index = 0
    $rawIndex = Get-ObjectProperty $rawEntry 'userListIndex'
    if (-not [int]::TryParse("$rawIndex", [ref]$index) -or
        $index -lt 1 -or
        $index -gt $rawEntries.Count) {
      throw 'The classic Kontakt order contains an invalid index.'
    }
    $identity = $regKey.ToLowerInvariant()
    if ($regKeys.ContainsKey($identity) -or $indexes.ContainsKey($index)) {
      throw 'The classic Kontakt order contains duplicate values.'
    }
    $regKeys[$identity] = $true
    $indexes[$index] = $true
    $entries.Add([pscustomobject]@{
      RegKey = $regKey
      Name = $name
      Snpid = $snpid
      Index = $index
    }) | Out-Null
  }

  $views = @(
    [Microsoft.Win32.RegistryView]::Registry64,
    [Microsoft.Win32.RegistryView]::Registry32
  )
  $applicationKeys = @('Kontakt', 'Kontakt 5', 'Kontakt 6', 'Kontakt 7', 'Kontakt 8')
  $backups = New-Object System.Collections.Generic.List[object]
  $changedPaths = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($view in $views) {
      foreach ($entry in $entries) {
        $backup = Get-RegistryValuesBackup `
          ([Microsoft.Win32.RegistryHive]::CurrentUser) `
          $view $entry.RegKey @('UserListIndex', 'Name', 'RegKey', 'SNPID')
        $backups.Add([pscustomobject]@{
          View = $view
          RegKey = $entry.RegKey
          Backup = $backup
        }) | Out-Null

        $values = @{
          UserListIndex = $entry.Index
          Name = $entry.Name
          RegKey = $entry.RegKey
        }
        if ($null -ne $entry.Snpid) { $values.SNPID = $entry.Snpid }
        Set-UserRegistryValues $view $entry.RegKey $values

        $verification = Get-RegistryValuesBackup `
          ([Microsoft.Win32.RegistryHive]::CurrentUser) `
          $view $entry.RegKey @('UserListIndex')
        if (-not $verification.KeyExisted -or
            -not $verification.Values.UserListIndex.Exists -or
            ([int]$verification.Values.UserListIndex.Value) -ne $entry.Index) {
          throw "The saved order for $($entry.Name) could not be verified."
        }
        $changedPaths.Add(
          "HKCU [$view]\SOFTWARE\Native Instruments\$($entry.RegKey)"
        ) | Out-Null
      }

      foreach ($applicationKey in $applicationKeys) {
        $backup = Get-RegistryValuesBackup `
          ([Microsoft.Win32.RegistryHive]::CurrentUser) `
          $view $applicationKey @('browserLibsAZSort')
        $backups.Add([pscustomobject]@{
          View = $view
          RegKey = $applicationKey
          Backup = $backup
        }) | Out-Null
        Set-UserRegistryValues $view $applicationKey @{
          browserLibsAZSort = 0
        }
      }
    }
  } catch {
    for ($index = $backups.Count - 1; $index -ge 0; $index--) {
      $backupEntry = $backups[$index]
      try {
        Restore-RegistryValuesBackup `
          ([Microsoft.Win32.RegistryHive]::CurrentUser) `
          $backupEntry.View $backupEntry.RegKey $backupEntry.Backup
      } catch {}
    }
    throw
  }

  return [ordered]@{
    operation = 'classicOrder'
    libraryName = ''
    changedPaths = $changedPaths.ToArray()
  }
}

try {
  if ($Mode -eq 'inventory') {
    Write-JsonFile $ResponsePath (Get-RegistryInventory)
  } elseif ($Mode -eq 'mutation') {
    if (-not (Test-IsAdministrator)) {
      $transport = Get-RequestTransportPaths $RequestPath $ResponsePath 'mutation'
      $script:SafeRequestResponsePath = $transport.Response
      $exitCode = Invoke-ElevatedMutation `
        -HelperPath $PSCommandPath `
        -Request $transport.Request `
        -RequestHash $RequestSha256 `
        -Response $transport.Response
      exit $exitCode
    }
    $result = Invoke-Mutation
    Write-JsonFile $script:SafeRequestResponsePath $result
  } else {
    $result = Invoke-ClassicOrder
    Write-JsonFile $script:SafeRequestResponsePath $result
  }
} catch {
  try {
    if ($Mode -eq 'inventory' -or $null -ne $script:SafeRequestResponsePath) {
      $errorPath = if ($Mode -eq 'inventory') {
        $ResponsePath
      } else {
        $script:SafeRequestResponsePath
      }
      $errorCode = if ($Mode -eq 'classicOrder') {
        if ($_.Exception.Message -like 'Close Kontakt*') {
          'kontakt_running'
        } else {
          'classic_order_write_failed'
        }
      } else {
        'mutation_failed'
      }
      Write-JsonFile $errorPath ([ordered]@{
        errorCode = $errorCode
        errorMessage = $_.Exception.Message
      })
    }
  } catch {}
  exit 1
}

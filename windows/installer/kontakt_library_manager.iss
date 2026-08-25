#ifndef MyAppVersion
  #error MyAppVersion must be provided by the build.
#endif
#ifndef MyAppBuild
  #error MyAppBuild must be provided by the build.
#endif
#ifndef MySourceDir
  #error MySourceDir must be provided by the build.
#endif
#ifndef MyOutputDir
  #error MyOutputDir must be provided by the build.
#endif

#define MyAppName "Kontakt Library Manager"
#define MyAppExeName "kontakt_library_manager.exe"

[Setup]
AppId={{5E8B9E32-06D1-41FF-A80A-DB8069437C7D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=cloin.se
AppPublisherURL=https://github.com/cloinse/klm
AppSupportURL=https://github.com/cloinse/klm/issues
AppUpdatesURL=https://github.com/cloinse/klm/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UsePreviousAppDir=no
OutputDir={#MyOutputDir}
OutputBaseFilename=klm-windows-v{#MyAppVersion}
SetupIconFile={#SourcePath}\..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern dynamic
CloseApplications=yes
RestartApplications=no
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
VersionInfoCompany=cloin.se
VersionInfoCopyright=KLM v{#MyAppVersion} cloin.se
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Remove the retired script from installations created before the native-only
; elevator was introduced.
Type: files; Name: "{app}\KontaktLibraryHelper.ps1"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall runasoriginaluser

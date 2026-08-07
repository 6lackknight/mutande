; Inno Setup script for mutande Windows alpha (per-user, unsigned).
; Compile after Flutter Release/ is ready (see .github/workflows/release-windows.yml).
;
; Defines (optional overrides via ISCC /D…):
;   MyAppVersion  — semver from app/pubspec.yaml
;   ReleaseDir    — absolute path to Flutter runner Release folder

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows\x64\runner\Release"
#endif

#define MyAppName "mutande"
#define MyAppPublisher "mutande"
#define MyAppURL "https://mutande.online"
#define MyAppExeName "mutande.exe"

[Setup]
; Stable AppId — do not change between releases (controls uninstall/upgrade).
AppId={{A8E3C1F2-6B4D-4E9A-9C2F-1D7B5E8A3F06}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/download
DefaultDirName={localappdata}\Programs\mutande
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=.
OutputBaseFilename=mutande-alpha-windows-setup
; Allow /O and /F from CI to redirect output to the repo root.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Inno Setup script for the Vittam Windows build.
; Built in CI (see .github/workflows/ci.yml) with:
;   iscc /DAppVersion=1.2.3 frontend\windows\installer.iss
;
; PrivilegesRequired=lowest installs per-user into %LOCALAPPDATA%\Programs\Vittam,
; so the in-app updater can run "VittamSetup.exe /VERYSILENT" without a UAC prompt.
; That is the whole point: a shop till should update itself, not ask for admin.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change AppId — Inno matches it to upgrade in place instead of
; installing a second copy alongside the old one.
AppId={{8F3C1D42-6B7A-4E59-9C21-A5D0E7B41F63}
AppName=Vittam
AppVersion={#AppVersion}
AppPublisher=Vengurla Tech
AppPublisherURL=https://vittam.vengurlatech.com
DefaultDirName={autopf}\Vittam
DefaultGroupName=Vittam
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
; x64 (not x64compatible) — the older spelling still compiles on every Inno 6.x,
; including the 6.2 that some runner images ship.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\build\windows\dist
OutputBaseFilename=VittamSetup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Shut the running app down before overwriting its files (silent updates).
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Vittam"; Filename: "{app}\Vittam.exe"
Name: "{autodesktop}\Vittam"; Filename: "{app}\Vittam.exe"; Tasks: desktopicon

[Run]
; No skipifsilent — a silent update must relaunch the app it just replaced.
Filename: "{app}\Vittam.exe"; Description: "{cm:LaunchProgram,Vittam}"; Flags: nowait postinstall

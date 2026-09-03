; Inno Setup script for the Vittam Windows build.
; Built in CI (see .github/workflows/ci.yml) with:
;   iscc /DAppVersion=1.2.3 frontend\windows\installer.iss
;
; PrivilegesRequired=lowest installs per-user into %LOCALAPPDATA%\Programs\Vittam,
; so the in-app updater can run "VittamSetup.exe /VERYSILENT" without a UAC prompt.
; That is the whole point: a shop till should update itself, not ask for admin.
;
; VC++ Runtime: flutter_windows.dll and every native plugin link the MSVC
;   runtime dynamically (VS 2022, see windows-release.yml) — Flutter's default.
;   A machine that has never installed anything built with a recent MSVC
;   toolchain is missing vcruntime140_1.dll. A bare Windows 10 box is the
;   common case; Windows 11 usually already carries it via other software or
;   Windows Update. The app then fails to LAUNCH right after a silent,
;   error-free install, which a user reads as "it doesn't install".
;   vc_redist.x64.exe below is Microsoft's own installer for it, downloaded
;   fresh by CI on every release and run ONLY when missing (see
;   VCRedistNeedsInstall in [Code]).

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
; Only ever launched from {tmp} (see [Run]) — never installed into {app}.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Vittam"; Filename: "{app}\Vittam.exe"
Name: "{autodesktop}\Vittam"; Filename: "{app}\Vittam.exe"; Tasks: desktopicon

[Run]
; Silent and gated: skipped entirely once a machine has the runtime (every
; update after the first, and most first installs), so the self-update path
; stays UAC-free exactly as designed. vc_redist.x64.exe's own manifest
; requires elevation, so Windows prompts for it ALONE when it truly runs — a
; per-user (PrivilegesRequired=lowest) install triggers one UAC prompt only on
; a bare machine's first install, never on the silent auto-update path.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
; No skipifsilent — a silent update must relaunch the app it just replaced.
Filename: "{app}\Vittam.exe"; Description: "{cm:LaunchProgram,Vittam}"; Flags: nowait postinstall

[Code]
// The VC++ 2015-2022 runtimes share one ABI and install in place under a
// single umbrella version - Microsoft still keys the registry "14.0" for
// every release since VS2015, so this one check covers whatever the CI
// runner's VS 2022 toolchain actually built against.
function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', Installed)
    and (Installed = 1));
end;

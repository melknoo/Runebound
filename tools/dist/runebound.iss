; RUNEBOUND installer (Inno Setup 6, https://jrsoftware.org). Built by
; tools/dist/build_windows.ps1, which passes the defines below. Per-user:
; no admin rights, installs to %LOCALAPPDATA%\Programs\RUNEBOUND. Saves live
; in %APPDATA%\Godot\app_userdata\RUNEBOUND and survive an uninstall.
; docs/dev-notes/release-builds.md

#ifndef AppVersion
  #define AppVersion "0.0.0-local"
#endif
#ifndef FileVersion
  #define FileVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\dist\Runebound"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\dist"
#endif
#ifndef OutputBase
  #define OutputBase "Runebound-setup"
#endif

[Setup]
; Never change the AppId: it ties updates and the uninstaller together.
AppId={{AEF7FF71-F52F-45AF-B743-EFC46A6224AE}
AppName=RUNEBOUND
AppVersion={#AppVersion}
AppVerName=RUNEBOUND {#AppVersion}
AppPublisher=RUNEBOUND
AppPublisherURL=https://github.com/melknoo/Runebound
AppSupportURL=https://github.com/melknoo/Runebound/issues
AppUpdatesURL=https://github.com/melknoo/Runebound/releases
VersionInfoVersion={#FileVersion}
VersionInfoProductName=RUNEBOUND
VersionInfoDescription=RUNEBOUND Setup
PrivilegesRequired=lowest
DefaultDirName={autopf}\RUNEBOUND
DefaultGroupName=RUNEBOUND
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\Runebound.exe
UninstallDisplayName=RUNEBOUND
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBase}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
de.Dx12Name=RUNEBOUND (DirectX 12)
en.Dx12Name=RUNEBOUND (DirectX 12)
de.Dx12Comment=Bei Absturz oder schwarzem Bild: mit DirectX 12 starten
en.Dx12Comment=On a crash or a black screen: start with DirectX 12

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; An update replaces the whole game; the .pck must match the .exe.
Type: files; Name: "{app}\Runebound.pck"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\RUNEBOUND"; Filename: "{app}\Runebound.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\{cm:Dx12Name}"; Filename: "{app}\Runebound.exe"; Parameters: "--rendering-driver d3d12"; WorkingDir: "{app}"; Comment: "{cm:Dx12Comment}"
Name: "{autodesktop}\RUNEBOUND"; Filename: "{app}\Runebound.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Runebound.exe"; Description: "{cm:LaunchProgram,RUNEBOUND}"; Flags: nowait postinstall skipifsilent

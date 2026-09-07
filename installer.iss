; ============================================================
; Inno Setup Script for TunnelKeeper
; Compiles a single TunnelKeeper-Setup.exe installer
; Download Inno Setup from: https://jrsoftware.org/isdl.php
; ============================================================

#define MyAppName "TunnelKeeper"
#define MyAppVersion "3.0"
#define MyAppPublisher "CyberSphinxxx"
#define MyAppURL "https://github.com/CyberSphinxxx/TunnelKeeper"
#define MyAppExeName "TunnelKeeper.exe"

[Setup]
AppId={{D37E775F-B4FA-4EC1-859D-351E98F4E839}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Release
OutputBaseFilename=TunnelKeeper-Setup
SetupIconFile=TunnelKeeper.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "TunnelKeeper.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "TunnelKeeper-GUI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "minecraft-tunnel-autostart.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "TunnelKeeper.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "TunnelKeeper.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "TunnelKeeper.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: ".env.example"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\TunnelKeeper.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\TunnelKeeper.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

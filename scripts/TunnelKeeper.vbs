Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
ParentDir = FSO.GetParentFolderName(ScriptDir)

ExeFile = ScriptDir & "\TunnelKeeper.exe"
If Not FSO.FileExists(ExeFile) Then
    ExeFile = ParentDir & "\TunnelKeeper.exe"
End If

MainScript = ScriptDir & "\..\src\main.ps1"
If Not FSO.FileExists(MainScript) Then
    MainScript = ParentDir & "\src\main.ps1"
End If
If Not FSO.FileExists(MainScript) Then
    MainScript = ScriptDir & "\src\main.ps1"
End If
If Not FSO.FileExists(MainScript) Then
    MainScript = ParentDir & "\src\TunnelKeeper-GUI.ps1"
End If
If Not FSO.FileExists(MainScript) Then
    MainScript = ParentDir & "\TunnelKeeper-GUI.ps1"
End If

If FSO.FileExists(ExeFile) Then
    WshShell.Run """" & ExeFile & """", 1, False
Else
    WshShell.Run "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File """ & MainScript & """", 1, False
End If


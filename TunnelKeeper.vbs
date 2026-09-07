Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
ExeFile = ScriptDir & "\TunnelKeeper.exe"
GuiScript = ScriptDir & "\TunnelKeeper-GUI.ps1"

If FSO.FileExists(ExeFile) Then
    WshShell.Run """" & ExeFile & """", 1, False
Else
    WshShell.Run "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File """ & GuiScript & """", 1, False
End If


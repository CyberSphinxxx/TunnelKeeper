Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
ParentDir = FSO.GetParentFolderName(ScriptDir)

ExeFile = ScriptDir & "\TunnelKeeper.exe"
If Not FSO.FileExists(ExeFile) Then
    ExeFile = ParentDir & "\TunnelKeeper.exe"
End If

GuiScript = ScriptDir & "\TunnelKeeper-GUI.ps1"
If Not FSO.FileExists(GuiScript) Then
    GuiScript = ParentDir & "\TunnelKeeper-GUI.ps1"
End If

If FSO.FileExists(ExeFile) Then
    WshShell.Run """" & ExeFile & """", 1, False
Else
    WshShell.Run "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File """ & GuiScript & """", 1, False
End If


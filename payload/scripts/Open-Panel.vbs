' Hidden launcher for the on-demand Sunshine panel.
' Runs Panel.ps1 without a console window, so double-click only opens the browser.
Option Explicit

Dim fso, shell, base, script, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

base = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(base, "scripts\Panel.ps1")
If Not fso.FileExists(script) Then script = fso.BuildPath(base, "Panel.ps1")
If Not fso.FileExists(script) Then
    MsgBox "Panel.ps1 not found:" & vbCrLf & script, 16, "Sunshine"
    WScript.Quit 2
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"
' 0 = hidden window, False = do not wait
shell.Run cmd, 0, False

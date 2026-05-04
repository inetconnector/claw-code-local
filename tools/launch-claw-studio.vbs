Set shell = CreateObject("WScript.Shell")
launcher = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\ClawCode\studio\build-run-claw-studio.bat"
legacy = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\ClawCode\studio\ClawStudio.ps1"
Set fso = CreateObject("Scripting.FileSystemObject")
If fso.FileExists(launcher) Then
  shell.Run Chr(34) & launcher & Chr(34), 0, False
Else
  shell.Run "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & legacy & Chr(34), 0, False
End If

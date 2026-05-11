' Hidden launcher for ContextLens Explorer verbs.
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\Invoke-ContextLens.ps1"

If WScript.Arguments.Count > 0 Then
    action = WScript.Arguments(0)
Else
    action = "Manager"
End If

If WScript.Arguments.Count > 1 Then
    targetPath = WScript.Arguments(1)
Else
    targetPath = ""
End If

quote = Chr(34)
cmd = "pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File " & quote & scriptPath & quote & _
      " -Action " & quote & action & quote & " -TargetPath " & quote & targetPath & quote

If UCase(action) = "MANAGER" Then
    windowStyle = 1
Else
    windowStyle = 0
End If

shell.Run cmd, windowStyle, False

' Runs the AI skills sync with no visible console window.
' Launched by the "Unsloth Skills Sync" scheduled task instead of powershell.exe,
' because Windows Terminal (the default terminal on Windows 11) flashes a window
' before PowerShell's -WindowStyle Hidden can take effect.
Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""C:\jrsmDev Workspace\FULL STACK AI SKILL\sync_skills.ps1"" -Quiet"
shell.Run cmd, 0, True

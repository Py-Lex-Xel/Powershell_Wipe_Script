New-Item -Path C:\Scripts -ItemType Directory -Force

# Mini-wipe for each disk 0-9
0..9 | ForEach-Object {
    @"
select disk $_
clean
exit
"@ | Out-File "C:\Scripts\wipe$_.txt" -Encoding ascii
}

# auto_wipe.bat: Explicit calls NO loops/% vars
@"
@echo off
echo Starting wipe disks 0-9...
echo Cleaning Disk 0...
diskpart /s X:\Scripts\wipe0.txt
echo Cleaning Disk 1...
diskpart /s X:\Scripts\wipe1.txt
echo Cleaning Disk 2...
diskpart /s X:\Scripts\wipe2.txt
echo Cleaning Disk 3...
diskpart /s X:\Scripts\wipe3.txt
echo Cleaning Disk 4...
diskpart /s X:\Scripts\wipe4.txt
echo Cleaning Disk 5...
diskpart /s X:\Scripts\wipe5.txt
echo Cleaning Disk 6...
diskpart /s X:\Scripts\wipe6.txt
echo Cleaning Disk 7...
diskpart /s X:\Scripts\wipe7.txt
echo Cleaning Disk 8...
diskpart /s X:\Scripts\wipe8.txt
echo Cleaning Disk 9...
diskpart /s X:\Scripts\wipe9.txt
echo All 10 attempts complete ^(errors OK^).
ping 127.0.0.1 -n 6 >nul
wpeutil reboot
"@ | Out-File C:\Scripts\auto_wipe.bat -Encoding ascii

# doom.bat
@"
@echo off
reagentc /boottore
shutdown /r /f /t 1
"@ | Out-File C:\Scripts\doom.bat -Encoding ascii

# 1. Disable + backup
Write-Host "Disabling WinRE..."
reagentc /disable
Copy-Item 'C:\Windows\System32\Recovery\winre.wim' C:\winre_backup.wim -Force

# 2. Mount
New-Item C:\mount\winre -ItemType Directory -Force
dism /mount-wim /wimfile:'C:\Windows\System32\Recovery\winre.wim' /index:1 /mountdir:C:\mount\winre

# 3. Copy bat + 10 wipe*.txt
New-Item 'C:\mount\winre\Scripts' -ItemType Directory -Force
Copy-Item C:\Scripts\auto_wipe.bat 'C:\mount\winre\Scripts\' -Force
0..9 | ForEach-Object { Copy-Item "C:\Scripts\wipe$_.txt" 'C:\mount\winre\Scripts\' -Force }

# 4. winpeshl.ini
@"
[LaunchApps]
%SYSTEMROOT%\system32\cmd.exe /k X:\Scripts\auto_wipe.bat
"@ | Out-File 'C:\mount\winre\Windows\System32\winpeshl.ini' -Encoding ascii

# 5. Unmount
dism /unmount-wim /mountdir:C:\mount\winre /commit

# 6. Enable
reagentc /enable

# Step 7: Elevated shortcut
$WshShell = New-Object -comObject WScript.Shell
$ShortcutPath = "$env:USERPROFILE\Desktop\WipeNow.lnk"
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "C:\Scripts\doom.bat"
$Shortcut.Save()
$bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)
Write-Host "Shortcut created: WipeNow.lnk (Run as Admin)."

# Cleanup
Remove-Item -Path C:\mount -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Setup ready. Double-click WipeNow.lnk for full wipe."

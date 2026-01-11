# ============================================
# WINDOWS DISK WIPE SETUP
# Version: 1.7 (Fixed Remote Task)
# ============================================

$ErrorActionPreference = 'Stop'

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "WINDOWS DISK WIPE SETUP" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan

try {
    # 1. Scripts
    if (-not (Test-Path C:\Scripts)) { New-Item -Path C:\Scripts -ItemType Directory -Force | Out-Null }
    Write-Host "[1/7] Scripts folder created." -ForegroundColor Green

    # 2. Wipe files
    Write-Host "[2/7] Generating wipe scripts..." -ForegroundColor Yellow
    0..9 | ForEach-Object { "select disk $_`r`nclean`r`nexit" | Out-File "C:\Scripts\wipe$_.txt" -Encoding ascii }

    $autoWipe = @"
@echo off
echo Wiping disks 0-9...
diskpart /s X:\Scripts\wipe0.txt
diskpart /s X:\Scripts\wipe1.txt
diskpart /s X:\Scripts\wipe2.txt
diskpart /s X:\Scripts\wipe3.txt
diskpart /s X:\Scripts\wipe4.txt
diskpart /s X:\Scripts\wipe5.txt
diskpart /s X:\Scripts\wipe6.txt
diskpart /s X:\Scripts\wipe7.txt
diskpart /s X:\Scripts\wipe8.txt
diskpart /s X:\Scripts\wipe9.txt
echo Done.
ping 127.0.0.1 -n 6 >nul
wpeutil reboot
"@ 
    $autoWipe | Out-File C:\Scripts\auto_wipe.bat -Encoding ascii
    "@echo off`r`nreagentc /boottore`r`nshutdown /r /f /t 1" | Out-File C:\Scripts\doom.bat -Encoding ascii
    Write-Host "[2/7] Wipe scripts generated." -ForegroundColor Green

    # 3. WinRE Backup
    Write-Host "[3/7] Disabling WinRE..." -ForegroundColor Yellow
    reagentc /disable | Out-Null
    if (Test-Path 'C:\Windows\System32\Recovery\winre.wim') {
        Copy-Item 'C:\Windows\System32\Recovery\winre.wim' C:\winre_backup.wim -Force
        Write-Host "[3/7] Backup created." -ForegroundColor Green
    }

    # 4. Mount
    Write-Host "[4/7] Mounting WinRE..." -ForegroundColor Yellow
    if (-not (Test-Path C:\mount\winre)) { New-Item C:\mount\winre -ItemType Directory -Force | Out-Null }
    dism /cleanup-wim | Out-Null
    dism /mount-wim /wimfile:'C:\Windows\System32\Recovery\winre.wim' /index:1 /mountdir:C:\mount\winre | Out-Null
    Write-Host "[4/7] Mounted." -ForegroundColor Green

    # 5. Copy & Config
    Write-Host "[5/7] Copying files..." -ForegroundColor Yellow
    if (-not (Test-Path 'C:\mount\winre\Scripts')) { New-Item 'C:\mount\winre\Scripts' -ItemType Directory -Force | Out-Null }
    Copy-Item C:\Scripts\auto_wipe.bat 'C:\mount\winre\Scripts\' -Force
    0..9 | ForEach-Object { Copy-Item "C:\Scripts\wipe$_.txt" 'C:\mount\winre\Scripts\' -Force }
    "[LaunchApps]`r`n%SYSTEMROOT%\system32\cmd.exe /k X:\Scripts\auto_wipe.bat" | Out-File 'C:\mount\winre\Windows\System32\winpeshl.ini' -Encoding ascii
    Write-Host "[5/7] Files copied." -ForegroundColor Green

    Write-Host "[5/7] Unmounting..." -ForegroundColor Yellow
    dism /unmount-wim /mountdir:C:\mount\winre /commit | Out-Null

    # 6. Enable WinRE
    Write-Host "[6/7] Enabling WinRE..." -ForegroundColor Yellow
    reagentc /enable | Out-Null
    Write-Host "[6/7] WinRE enabled." -ForegroundColor Green

    # 7. REMOTE TASK (FIXED)
    Write-Host "[6/7] Configuring remote trigger..." -ForegroundColor Yellow
    try { schtasks /delete /tn "WipeTask" /f | Out-Null } catch {}
    
    # FIX: Using /sc ONCE /st 23:59 (Valid schedule that won't auto-run effectively)
    schtasks /create /tn "WipeTask" /tr "C:\Scripts\doom.bat" /sc ONCE /st 23:59 /ru SYSTEM /f | Out-Null

    # Firewall Ports
    Write-Host "Configuring Firewall..." -ForegroundColor Yellow
    try {
        New-NetFirewallRule -DisplayName "Allow SMB 445" -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Allow RPC 135" -Direction Inbound -LocalPort 135 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    Write-Host "[6/7] Remote trigger ready." -ForegroundColor Green

    # 8. Shortcut
    Write-Host "[7/7] Creating shortcut..." -ForegroundColor Yellow
    $WshShell = New-Object -comObject WScript.Shell
    $ShortcutPath = "$env:USERPROFILE\Desktop\WipeNow.lnk"
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = "C:\Scripts\doom.bat"
    $Shortcut.Save()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)
    } catch {}
    Write-Host "[7/7] Shortcut created." -ForegroundColor Green

    # Cleanup
    Remove-Item -Path C:\mount -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n========================================"  -ForegroundColor Green
    Write-Host "SETUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "========================================"  -ForegroundColor Green
    Write-Host "Hostname: $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "Remote: schtasks /run /s $env:COMPUTERNAME /tn WipeTask /u USER /p PASS" -ForegroundColor Cyan
    Write-Host "`nWARNING: ALL DATA WILL BE DELETED!" -ForegroundColor Red

} catch {
    Write-Error "CRITICAL ERROR: $($_.Exception.Message)"
    dism /unmount-wim /mountdir:C:\mount\winre /discard | Out-Null
}

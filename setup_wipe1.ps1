# ============================================
# WINDOWS DISK WIPE SETUP
# Version: 2.0 (WinRM Remote Trigger)
# ============================================

$ErrorActionPreference = 'Stop'

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "WINDOWS DISK WIPE SETUP" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan

try {
    # 1. Scripts
    if (-not (Test-Path C:\Scripts)) { New-Item -Path C:\Scripts -ItemType Directory -Force | Out-Null }
    Write-Host "[1/8] Scripts folder created." -ForegroundColor Green

    # 2. Wipe files
    Write-Host "[2/8] Generating wipe scripts..." -ForegroundColor Yellow
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
    Write-Host "[2/8] Wipe scripts generated." -ForegroundColor Green

    # 3. WinRE Backup
    Write-Host "[3/8] Disabling WinRE..." -ForegroundColor Yellow
    reagentc /disable | Out-Null
    if (Test-Path 'C:\Windows\System32\Recovery\winre.wim') {
        Copy-Item 'C:\Windows\System32\Recovery\winre.wim' C:\winre_backup.wim -Force
        Write-Host "[3/8] Backup created." -ForegroundColor Green
    }

    # 4. Mount
    Write-Host "[4/8] Mounting WinRE..." -ForegroundColor Yellow
    if (-not (Test-Path C:\mount\winre)) { New-Item C:\mount\winre -ItemType Directory -Force | Out-Null }
    dism /cleanup-wim | Out-Null
    dism /mount-wim /wimfile:'C:\Windows\System32\Recovery\winre.wim' /index:1 /mountdir:C:\mount\winre | Out-Null
    Write-Host "[4/8] Mounted." -ForegroundColor Green

    # 5. Copy & Config
    Write-Host "[5/8] Copying files..." -ForegroundColor Yellow
    if (-not (Test-Path 'C:\mount\winre\Scripts')) { New-Item 'C:\mount\winre\Scripts' -ItemType Directory -Force | Out-Null }
    Copy-Item C:\Scripts\auto_wipe.bat 'C:\mount\winre\Scripts\' -Force
    0..9 | ForEach-Object { Copy-Item "C:\Scripts\wipe$_.txt" 'C:\mount\winre\Scripts\' -Force }
    "[LaunchApps]`r`n%SYSTEMROOT%\system32\cmd.exe /k X:\Scripts\auto_wipe.bat" | Out-File 'C:\mount\winre\Windows\System32\winpeshl.ini' -Encoding ascii
    Write-Host "[5/8] Files copied." -ForegroundColor Green

    Write-Host "[5/8] Unmounting..." -ForegroundColor Yellow
    dism /unmount-wim /mountdir:C:\mount\winre /commit | Out-Null

    # 6. Enable WinRE
    Write-Host "[6/8] Enabling WinRE..." -ForegroundColor Yellow
    reagentc /enable | Out-Null
    Write-Host "[6/8] WinRE enabled." -ForegroundColor Green

    # 7. Configure WinRM (Remote Management)
    Write-Host "[7/8] Configuring WinRM..." -ForegroundColor Yellow
    
    # Enable PowerShell Remoting
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    
    # Start and set WinRM to auto-start
    Start-Service WinRM -ErrorAction SilentlyContinue
    Set-Service WinRM -StartupType Automatic
    
    # Allow remote connections from any host (для Radmin VPN)
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
    
    # UAC Bypass for remote local admins
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
    
    # Firewall for WinRM
    New-NetFirewallRule -DisplayName "Allow WinRM 5985" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    
    # Optional: Firewall for SMB/RPC (for schtasks fallback)
    New-NetFirewallRule -DisplayName "Allow SMB 445" -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Allow RPC 135" -Direction Inbound -LocalPort 135 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "[7/8] WinRM configured." -ForegroundColor Green

    # 8. Shortcut
    Write-Host "[8/8] Creating shortcut..." -ForegroundColor Yellow
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
    Write-Host "[8/8] Shortcut created." -ForegroundColor Green

    # Cleanup
    Remove-Item -Path C:\mount -Recurse -Force -ErrorAction SilentlyContinue

    # Get system info for final instructions
    $hostname = $env:COMPUTERNAME
    $currentUser = $env:USERNAME
    
    # Try to get Radmin VPN IP (26.x.x.x range)
    $radminIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "26.*"}).IPAddress
    if (-not $radminIP) {
        $radminIP = "NOT_CONNECTED_TO_RADMIN_VPN"
    }

    # Final Summary
    Write-Host "`n========================================"  -ForegroundColor Green
    Write-Host "SETUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "========================================"  -ForegroundColor Green
    Write-Host "`nSYSTEM INFO:" -ForegroundColor Cyan
    Write-Host "  Hostname: $hostname" -ForegroundColor White
    Write-Host "  Current User: $currentUser" -ForegroundColor White
    Write-Host "  Radmin VPN IP: $radminIP" -ForegroundColor White
    
    Write-Host "`nLOCAL TRIGGER:" -ForegroundColor Cyan
    Write-Host "  Double-click: Desktop\WipeNow.lnk" -ForegroundColor White
    
    Write-Host "`nREMOTE TRIGGER (PowerShell on HOST):" -ForegroundColor Cyan
    Write-Host "  Copy-paste this command:" -ForegroundColor Yellow
    Write-Host @"

`$pass = ConvertTo-SecureString "YOUR_PASSWORD" -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("$currentUser", `$pass)
Invoke-Command -ComputerName $hostname -Credential `$cred -ScriptBlock { C:\Scripts\doom.bat }

"@ -ForegroundColor White

    Write-Host "  Replace YOUR_PASSWORD with actual password for user: $currentUser" -ForegroundColor Yellow
    
    Write-Host "`nREQUIREMENTS ON HOST:" -ForegroundColor Cyan
    Write-Host "  1. Install Radmin VPN and join same network" -ForegroundColor White
    Write-Host "  2. Run on host: Enable-PSRemoting -Force" -ForegroundColor White
    Write-Host "  3. Run on host: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$hostname' -Force" -ForegroundColor White
    
    Write-Host "`nWARNING: ALL DATA WILL BE PERMANENTLY DELETED!" -ForegroundColor Red
    Write-Host "Backup location: C:\winre_backup.wim`n" -ForegroundColor Yellow

    # Save config to file for convenience
    $configFile = "C:\Scripts\wipe_remote_command.txt"
    @"
========================================
REMOTE WIPE COMMAND
========================================
Hostname: $hostname
User: $currentUser
Radmin IP: $radminIP

COMMAND FOR HOST (PowerShell):
----------------------------------------
`$pass = ConvertTo-SecureString "YOUR_PASSWORD" -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential ("$currentUser", `$pass)
Invoke-Command -ComputerName $hostname -Credential `$cred -ScriptBlock { C:\Scripts\doom.bat }
========================================
"@ | Out-File $configFile -Encoding UTF8

    Write-Host "Command saved to: $configFile" -ForegroundColor Green

} catch {
    Write-Error "CRITICAL ERROR: $($_.Exception.Message)"
    dism /unmount-wim /mountdir:C:\mount\winre /discard 2>$null | Out-Null
}

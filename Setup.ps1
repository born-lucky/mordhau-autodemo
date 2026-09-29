# Installs / uninstalls Mordhau Auto Demo for the current Windows user.
# No admin needed. Everything lives in %LOCALAPPDATA%\MordhauAutoDemo.
#
#   Setup.ps1            install (or update) and start it now
#   Setup.ps1 -Uninstall stop it and remove everything except your demos

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$Src     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir     = Join-Path $env:LOCALAPPDATA "MordhauAutoDemo"
$Script  = Join-Path $Dir "MordhauAutoDemo.ps1"
$Lnk     = Join-Path ([Environment]::GetFolderPath("Startup")) "Mordhau Auto Demo.lnk"
$RegKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MordhauAutoDemo"
$Ps      = Join-Path $PSHOME "powershell.exe"

function Su-Stop {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*MordhauAutoDemo\MordhauAutoDemo.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($Uninstall) {
    Su-Stop
    if (Test-Path $Lnk) { Remove-Item $Lnk }
    if (Test-Path $RegKey) { Remove-Item $RegKey -Recurse }
    Start-Sleep -Milliseconds 500
    if (Test-Path $Dir) {
        # Setup.ps1 may be running from inside $Dir (Installed apps -> Uninstall),
        # so delete the folder from a separate process after we exit.
        Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c ping -n 7 127.0.0.1 >nul & rmdir /s /q `"$Dir`""
    }
    Write-Host "Mordhau Auto Demo removed. Your recorded demos were kept in:"
    Write-Host "  $env:LOCALAPPDATA\Mordhau\Saved\Demos"
    Start-Sleep -Seconds 4
    exit
}

# ---- install / update
Su-Stop
New-Item -ItemType Directory -Force $Dir | Out-Null
foreach ($F in "MordhauAutoDemo.ps1", "Setup.ps1", "README.md") {
    Copy-Item (Join-Path $Src $F) $Dir -Force
}
# keep the user's settings on update
if (-not (Test-Path (Join-Path $Dir "settings.ini"))) { Copy-Item (Join-Path $Src "settings.ini") $Dir }
Get-ChildItem $Dir | Unblock-File   # clear the "downloaded from internet" mark

# Start at every login, with no window.
$Args1 = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
$Sc = (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk)
$Sc.TargetPath = $Ps
$Sc.Arguments = $Args1
$Sc.WorkingDirectory = $Dir
$Sc.WindowStyle = 7
$Sc.Description = "Records a Mordhau demo of every match"
$Sc.Save()

# Show up in Settings -> Apps -> Installed apps, so it can be removed normally.
New-Item $RegKey -Force | Out-Null
$Uni = "`"$Ps`" -NoProfile -ExecutionPolicy Bypass -File `"$Dir\Setup.ps1`" -Uninstall"
Set-ItemProperty $RegKey DisplayName "Mordhau Auto Demo"
Set-ItemProperty $RegKey Publisher "Mordhau Auto Demo"
Set-ItemProperty $RegKey DisplayVersion "1.0.0"
Set-ItemProperty $RegKey InstallLocation $Dir
Set-ItemProperty $RegKey UninstallString $Uni
Set-ItemProperty $RegKey NoModify 1 -Type DWord
Set-ItemProperty $RegKey NoRepair 1 -Type DWord

Start-Process $Ps -ArgumentList $Args1 -WorkingDirectory $Dir -WindowStyle Hidden

Write-Host ""
Write-Host "  Mordhau Auto Demo is installed and running." -ForegroundColor Green
Write-Host ""
Write-Host "  Every match you play is now recorded automatically, and it starts"
Write-Host "  by itself whenever you log in to Windows. Nothing else to do."
Write-Host ""
Write-Host "  Demos:     $env:LOCALAPPDATA\Mordhau\Saved\Demos"
Write-Host "  Activity:  $Dir\autodemo.log"
Write-Host "  Remove:    Settings > Apps > Installed apps > Mordhau Auto Demo"
Write-Host ""

# Mordhau Auto Demo - records a demo (demorec) of every match you join.
#
# How it works: watches Mordhau's own log file. When the log shows you joined a
# server (or started an offline game) and the map finished loading, it opens the console and types
#   demorec <name>
# Mordhau stops the demo by itself on every map change / disconnect, so a new
# one is started for each map. Nothing is injected into the game process; it
# only reads the log and presses keys (only while Mordhau is the focused window).
#
# Demos land in %LOCALAPPDATA%\Mordhau\Saved\Demos. Watch one with: demoplay <name>

param(
    [string]$LogPath = "",   # testing: watch this file instead of Mordhau.log
    [switch]$DryRun          # testing: print what would be typed, press nothing
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------- settings
$Cfg = @{
    Prefix      = "auto"   # demo names: auto_20260929_1403_skm_mashpit
    StartDelay  = 3        # seconds after the map loads before typing
    MaxGB       = 10       # delete oldest auto demos past this size (0 = never)
    RecordHz    = 0        # >0 also types "demo.recordhz N" first (sharper timing, bigger files)
    ConsoleKey  = ""       # blank = read from Mordhau's Input.ini (default Tilde)
    Beep        = 0        # 1 = short sound when a recording starts
    QuietMs     = 1200     # only type after this long with no key / mouse button held
    RecordOffline = 1      # 1 = also record offline / practice / bot games
}
$CfgFile = Join-Path $Here "settings.ini"
if (Test-Path $CfgFile) {
    foreach ($L in Get-Content $CfgFile) {
        if ($L -match '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$' -and $Cfg.ContainsKey($Matches[1])) {
            $Cfg[$Matches[1]] = $Matches[2]
        }
    }
}

$MhSaved  = Join-Path $env:LOCALAPPDATA "Mordhau\Saved"
$MhLogs   = Join-Path $MhSaved "Logs"
$MhDemos  = Join-Path $MhSaved "Demos"
$MhInput  = Join-Path $MhSaved "Config\WindowsClient\Input.ini"
$GameProc = "Mordhau-Win64-Shipping"

# ---------------------------------------------------------------- keyboard
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AdKeys {
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inp, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    const uint SCANCODE = 0x8, KEYUP = 0x2, UNICODE = 0x4;

    static void Send(ushort vk, ushort scan, uint flags) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1; i[0].u.ki.vk = vk; i[0].u.ki.scan = scan; i[0].u.ki.flags = flags;
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }
    // Real key press by scancode - games read these reliably.
    public static void Tap(ushort vk) {
        ushort sc = (ushort)MapVirtualKey(vk, 0);
        Send(0, sc, SCANCODE); System.Threading.Thread.Sleep(30);
        Send(0, sc, SCANCODE | KEYUP); System.Threading.Thread.Sleep(30);
    }
    // Quick tap for repeated keys (clearing the console line).
    public static void TapFast(ushort vk, int n) {
        ushort sc = (ushort)MapVirtualKey(vk, 0);
        for (int k = 0; k < n; k++) {
            Send(0, sc, SCANCODE); Send(0, sc, SCANCODE | KEYUP);
            System.Threading.Thread.Sleep(3);
        }
    }
    // Text as unicode characters - independent of keyboard layout.
    public static void Type(string s) {
        foreach (char c in s) {
            Send(0, c, UNICODE); Send(0, c, UNICODE | KEYUP);
            System.Threading.Thread.Sleep(4);
        }
    }
    // True if any key or mouse button is held right now.
    public static bool AnyDown() {
        for (int vk = 1; vk < 0xFF; vk++) {
            if (vk == 0x14 || vk == 0x90 || vk == 0x91) continue;   // lock keys
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) return true;
        }
        return false;
    }
    // Watch the keyboard and mouse buttons for ms; false the moment anything is pressed.
    public static bool Quiet(int ms) {
        var t = System.Diagnostics.Stopwatch.StartNew();
        while (t.ElapsedMilliseconds < ms) {
            if (AnyDown()) return false;
            System.Threading.Thread.Sleep(15);
        }
        return true;
    }
    public static uint ForegroundPid() {
        uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid;
    }
}
"@

# UE key name -> Windows virtual key
$UeKeys = @{ Tilde = 0xC0; Caret = 0xDC; Backslash = 0xDC; Apostrophe = 0xDE; Semicolon = 0xBA
             Insert = 0x2D; Home = 0x24; End = 0x23; PageUp = 0x21; PageDown = 0x22; Section = 0xC0 }
1..12 | ForEach-Object { $UeKeys["F$_"] = 0x6F + $_ }
65..90 | ForEach-Object { $UeKeys[[string][char]$_] = $_ }

function Ad-ConsoleVk {
    $Name = $Cfg.ConsoleKey
    if (-not $Name -and (Test-Path $MhInput)) {
        $M = Select-String -Path $MhInput -Pattern '^\s*\+?ConsoleKeys\s*=\s*(\w+)' | Select-Object -First 1
        if ($M) { $Name = $M.Matches[0].Groups[1].Value }
    }
    if (-not $Name) { $Name = "Tilde" }
    if (-not $UeKeys.ContainsKey($Name)) { Ad-Say "Unknown console key '$Name', using Tilde" Yellow; $Name = "Tilde" }
    return @($Name, $UeKeys[$Name])
}

# ---------------------------------------------------------------- output
# Printed to the window (if any) and kept in autodemo.log, since the installed
# copy runs hidden.
$OutLog = Join-Path $Here "autodemo.log"
function Ad-Say([string]$Msg, [string]$Color = "Gray") {
    $T = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
    Write-Host $T -ForegroundColor $Color
    if (-not $LogPath) { try { Add-Content -Path $OutLog -Value $T } catch {} }
}

# ---------------------------------------------------------------- game state
# Built only from log lines, so starting this mid-match still works: the whole
# log is read once and the final state is acted on.
$S = @{ Pending = $null; Map = $null; InMatch = $false; Recording = $false
        LoadedAt = [datetime]::MinValue; Tries = 0; LastTry = [datetime]::MinValue; Name = $null }

function Ad-Line([string]$L, [bool]$Live) {
    if ($L -match 'LogNet: Welcomed by server \(Level: ([^,]+),') {
        $S.Pending = $Matches[1]
    }
    elseif ($L -match 'LogLoad: Took [\d.]+ seconds to LoadMap\(') {
        # Only a load that follows "Welcomed by server" (or an offline map
        # browse) is a match - the main menu and demo playback are neither.
        $S.InMatch = [bool]$S.Pending
        $S.Map = $S.Pending; $S.Pending = $null
        $S.Recording = $false; $S.Tries = 0; $S.LoadedAt = Get-Date; $S.Name = $null
        if ($S.InMatch -and $Live) { Ad-Say "Joined match: $($S.Map)" Cyan }
    }
    elseif ($L -match 'LogNet: Browse: (\S*)|NetworkFailure: |Engine exit requested') {
        if ($S.InMatch -and $Live) { Ad-Say "Left match" DarkGray }
        $S.InMatch = $false; $S.Pending = $null
        # Offline game: a Browse to a local map (no server address in front).
        # Online joins are "ip:port/map" and get welcomed by the server instead.
        $Url = if ($Matches[1]) { ($Matches[1] -split '\?')[0] } else { "" }
        if ([int]$Cfg.RecordOffline -and $Url -like "/*" -and $Url -notmatch 'MainMenu|Entry|Demo|Replay') {
            $S.Pending = $Url
        }
    }
    elseif ($L -match 'LogLocalFileReplay: Writing replay to') {
        $S.Recording = $true
        if ($Live) {
            Ad-Say ("RECORDING  " + $(if ($S.Tries -gt 0) { $S.Name } else { "(started by you)" })) Green
            if ([int]$Cfg.Beep) { [System.Media.SystemSounds]::Asterisk.Play() }
        }
    }
    elseif ($L -match 'LogDemo: StopDemo: Demo (\S+) stopped') {
        $S.Recording = $false
        if ($Live) { Ad-Say "Saved demo: $($Matches[1])" DarkGreen; Ad-Prune }
    }
}

# ---------------------------------------------------------------- recording
function Ad-DemoName {
    $Short = ($S.Map -split '/')[-1] -replace '[^A-Za-z0-9_]', ''
    return "{0}_{1}_{2}" -f $Cfg.Prefix, (Get-Date -Format "yyyyMMdd_HHmmss"), $Short
}

function Ad-Command([string]$Cmd, [int]$Vk) {
    if ($DryRun) { Ad-Say "(dry run) would type: $Cmd" Magenta; return }
    [AdKeys]::Tap($Vk)
    Start-Sleep -Milliseconds 150        # let the console open
    # Mordhau keeps half-typed text in the console line between openings;
    # without this it gets glued in front ("t.MaxFPS 500demorec ...").
    [AdKeys]::Tap(0x23)                  # End
    [AdKeys]::TapFast(0x08, 80)          # Backspace the line clear
    [AdKeys]::Type($Cmd)
    Start-Sleep -Milliseconds 50
    [AdKeys]::Tap(0x0D)                  # Enter runs it and closes the console
}

function Ad-GameFocused {
    if ($DryRun) { return $true }
    $Pid2 = [AdKeys]::ForegroundPid()
    $P = Get-Process -Id $Pid2 -ErrorAction SilentlyContinue
    return ($P -and $P.ProcessName -eq $GameProc)
}

function Ad-TryStart {
    if (-not $S.InMatch -or $S.Recording) { return }
    $Now = Get-Date
    if (($Now - $S.LoadedAt).TotalSeconds -lt [double]$Cfg.StartDelay) { return }
    if ($S.Tries -ge 4) { return }
    if (($Now - $S.LastTry).TotalSeconds -lt 6) { return }   # wait for the log to confirm
    if (-not (Ad-GameFocused)) { return }                     # never type into other windows
    # Wait until the player isn't pressing anything (spawn screen, standing
    # still) so our keys can't mix with theirs. Doesn't use up a try.
    if (-not $DryRun -and -not [AdKeys]::Quiet([int]$Cfg.QuietMs)) { return }
    if (-not (Ad-GameFocused)) { return }

    $S.Tries++; $S.LastTry = $Now
    if (-not $S.Name) { $S.Name = Ad-DemoName }   # same name on retries: a late start just gets overwritten
    Ad-Say "Starting demo (try $($S.Tries)/4): $($S.Name)" Yellow
    if ([int]$Cfg.RecordHz -gt 0) { Ad-Command "demo.recordhz $($Cfg.RecordHz)" $script:ConVk; Start-Sleep -Milliseconds 250 }
    Ad-Command "demorec $($S.Name)" $script:ConVk
    if ($S.Tries -ge 4) {
        # checked again next loop; if still not recording, say so once
        $script:WarnAt = $Now.AddSeconds(6)
    }
}

# Keep only the newest auto demos under MaxGB. Never touches other demos.
function Ad-Prune {
    $Max = [double]$Cfg.MaxGB
    if ($Max -le 0 -or -not (Test-Path $MhDemos)) { return }
    $Files = @(Get-ChildItem $MhDemos -Filter "$($Cfg.Prefix)_*.replay" | Sort-Object LastWriteTime)
    $Total = ($Files | Measure-Object Length -Sum).Sum
    $i = 0
    while ($Total -gt $Max * 1GB -and $i -lt $Files.Count - 1) {
        $Total -= $Files[$i].Length
        Remove-Item $Files[$i].FullName
        Ad-Say "Deleted old demo $($Files[$i].Name) (over $Max GB)" DarkGray
        $i++
    }
}

# ---------------------------------------------------------------- log tail
function Ad-FindLog {
    if ($LogPath) { return $(if (Test-Path $LogPath) { Get-Item $LogPath } else { $null }) }
    if (-not (Test-Path $MhLogs)) { return $null }
    return Get-ChildItem $MhLogs -Filter "Mordhau*.log" |
        Where-Object { $_.Name -notlike "*backup*" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Ad-ReadNew([string]$Path, [long]$From) {
    $Fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        $Fs.Seek($From, 'Begin') | Out-Null
        $Buf = New-Object byte[] ($Fs.Length - $From)
        $N = $Fs.Read($Buf, 0, $Buf.Length)
        # only hand back complete lines; a half-written line waits for next poll
        $Last = [Array]::LastIndexOf($Buf, [byte]10, [Math]::Max($N - 1, 0))
        if ($N -eq 0 -or $Last -lt 0) { return @{ Lines = @(); Pos = $From } }
        $Text = [System.Text.Encoding]::UTF8.GetString($Buf, 0, $Last + 1)
        return @{ Lines = $Text -split "`r?`n"; Pos = $From + $Last + 1 }
    } finally { $Fs.Close() }
}

# ---------------------------------------------------------------- main
# One copy only - two would both type demorec.
$Mutex = New-Object System.Threading.Mutex($false, "Local\MordhauAutoDemo")
if (-not $DryRun -and -not $Mutex.WaitOne(0)) { Write-Host "Mordhau Auto Demo is already running."; exit }
if ((Test-Path $OutLog) -and (Get-Item $OutLog).Length -gt 1MB) { Remove-Item $OutLog }

$Host.UI.RawUI.WindowTitle = "Mordhau Auto Demo"
$Con = Ad-ConsoleVk; $script:ConVk = $Con[1]
Ad-Say "Mordhau Auto Demo running. Console key: $($Con[0]). Demos -> $MhDemos" White
if ($DryRun) { Ad-Say "DRY RUN - no keys will be pressed" Magenta }

$Cur = $null; $Pos = 0L; $Waiting = $false; $script:WarnAt = $null
while ($true) {
    $Running = $LogPath -or (Get-Process $GameProc -ErrorAction SilentlyContinue)
    if (-not $Running) {
        if (-not $Waiting) { Ad-Say "Waiting for Mordhau to start..." DarkGray; $Waiting = $true }
        $Cur = $null; $S.InMatch = $false
        Start-Sleep -Seconds 3; continue
    }
    if ($Waiting) { Ad-Say "Mordhau detected" White; $Waiting = $false }

    $F = Ad-FindLog
    if ($F) {
        # new game session = new log file (or it was truncated): start over
        $Key = "$($F.FullName)|$($F.CreationTimeUtc.Ticks)"
        $Fresh = $Key -ne $Cur -or $F.Length -lt $Pos
        if ($Fresh) {
            $Cur = $Key; $Pos = 0L
            $S.Pending = $null; $S.InMatch = $false; $S.Recording = $false
        }
        if ($F.Length -gt $Pos) {
            $R = Ad-ReadNew $F.FullName $Pos
            foreach ($L in $R.Lines) { if ($L) { Ad-Line $L (-not $Fresh) } }
            $Pos = $R.Pos
            if ($Fresh -and $S.InMatch) {
                Ad-Say ("Already in a match: $($S.Map)" + $(if ($S.Recording) { " (already recording)" } else { "" })) Cyan
            }
        }
    }

    Ad-TryStart
    if ($script:WarnAt -and (Get-Date) -ge $script:WarnAt) {
        if ($S.InMatch -and -not $S.Recording) {
            Ad-Say "Could not start a demo on this map. Is the console key right? (see settings.ini)" Red
        }
        $script:WarnAt = $null
    }
    Start-Sleep -Milliseconds 500
}

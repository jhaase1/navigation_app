# Drive the built Windows app deterministically, for testing against the mock rig.
# The Windows twin of drive_macos_app.sh: same verbs, same idea.
#
#   .\drive_windows_app.ps1 shot <name>       focus, pin the window, screenshot
#   .\drive_windows_app.ps1 click <wx> <wy>   focus, click at a window-relative point
#   .\drive_windows_app.ps1 scroll <wx> <wy> <n>  focus, wheel n notches at a point (n>0 scrolls down)
#   .\drive_windows_app.ps1 type '<text>'     focus, type text (quote it: PowerShell splits on commas and spaces)
#   .\drive_windows_app.ps1 key <key>         focus, press a key (SendKeys name: ENTER, TAB, ESC, DOWN...)
#   .\drive_windows_app.ps1 bounds            print the current window frame
#
# The window is pinned to a fixed frame before every action, because otherwise
# coordinates go stale the moment anything moves the window -- and because the
# terminal takes focus back after each command, so the app has to be brought to
# the front every time or the click lands on whatever is in front.
#
# Coordinates are physical pixels, measured from the top-left of the visible
# window frame (title bar included, invisible resize border excluded). The
# script is DPI-aware, so unlike the macOS script there is no scale to undo: a
# point read off a screenshot is the point to click.
#
# Requires nothing beyond Windows PowerShell 5.1 or PowerShell 7. The app must
# already be running (flutter run -d windows, or the built navigation_app.exe).
#
# Environment overrides: APP_PROCESS, APP_TITLE, WIN_X, WIN_Y, WIN_W, WIN_H, SHOT_DIR.

param(
  [Parameter(Position = 0)] [string] $Verb,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

function Env($name, $default) {
  $v = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrEmpty($v)) { $default } else { $v }
}

$AppProcess = Env 'APP_PROCESS' 'navigation_app'
$AppTitle = Env 'APP_TITLE' 'Production Control'
$WinX = [int](Env 'WIN_X' 60)
$WinY = [int](Env 'WIN_Y' 80)
$WinW = [int](Env 'WIN_W' 1200)
$WinH = [int](Env 'WIN_H' 820)
$ShotDir = Env 'SHOT_DIR' (Get-Location).Path

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Drive {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
  [DllImport("user32.dll")] public static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr v);

  // PowerShell passes $null to a string parameter as "", which FindWindow
  // reads as a class named "" and matches nothing. Pass a real null here.
  public static IntPtr FindByTitle(string title) { return FindWindow(null, title); }
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);

  // Windows refuses SetForegroundWindow from a process that is not already
  // in front. Borrowing the front window's input queue lifts that.
  public static void Focus(IntPtr h) {
    IntPtr fg = GetForegroundWindow();
    if (fg == h) return;
    uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint me = GetCurrentThreadId();
    bool attached = fgThread != me && AttachThreadInput(me, fgThread, true);
    try { BringWindowToTop(h); SetForegroundWindow(h); }
    finally { if (attached) AttachThreadInput(me, fgThread, false); }
  }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after,
      int x, int y, int w, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr,
      out RECT r, int size);

  // The visible frame. GetWindowRect includes the invisible resize border
  // DWM draws around every window, which would offset every coordinate.
  public static RECT Frame(IntPtr h) {
    RECT r;
    if (DwmGetWindowAttribute(h, 9 /* EXTENDED_FRAME_BOUNDS */, out r,
        Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);
    return r;
  }
}
'@

# Per-monitor v2: window positions, cursor and capture all in physical pixels.
# The call fails if the process already has an awareness (a second run in the
# same session, or a host manifest); only the wrong awareness is a problem.
# If the process is locked to another awareness, the thread can still opt in.
if (-not [Drive]::SetProcessDpiAwarenessContext([IntPtr]-4) -and
    -not [Drive]::AreDpiAwarenessContextsEqual([Drive]::GetThreadDpiAwarenessContext(), [IntPtr]-4) -and
    [Drive]::SetThreadDpiAwarenessContext([IntPtr]-4) -eq [IntPtr]::Zero) {
  Write-Warning 'could not make this process per-monitor DPI aware; coordinates may be scaled'
}

function Find-Window {
  $procs = @(Get-Process -Name $AppProcess -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
  if ($procs.Count -gt 1) {
    # Several worktrees can each have a build running; say which one we drive.
    Write-Warning ("$($procs.Count) '$AppProcess' windows are open; driving pid $($procs[0].Id) " +
      "($($procs[0].Path)). Close the others to be sure.")
  }
  $p = $procs | Select-Object -First 1
  $h = if ($p) { $p.MainWindowHandle } else { [Drive]::FindByTitle($AppTitle) }
  if ($h -eq [IntPtr]::Zero) {
    Write-Error "no window for process '$AppProcess' or title '$AppTitle' -- is the app running?"
  }
  $h
}

function Pin([switch] $NeedFocus) {
  $h = Find-Window
  # SW_RESTORE: a minimized or maximized window would not take the pinned frame.
  if ([Drive]::IsIconic($h) -or [Drive]::IsZoomed($h)) { [void][Drive]::ShowWindow($h, 9) }
  # No Alt-tap trick here: a lone Alt toggles the window's menu mode, so
  # every other run left the app in it, swallowing the mouse wheel.
  [Drive]::Focus($h)
  # Topmost-then-not raises it over everything even if focus was refused,
  # so a screenshot or click still lands on the app.
  [void][Drive]::SetWindowPos($h, [IntPtr]-1, 0, 0, 0, 0, 0x0003)
  [void][Drive]::SetWindowPos($h, [IntPtr]-2, 0, 0, 0, 0, 0x0003)
  Start-Sleep -Milliseconds 300

  # Size the visible frame, not the outer rect: correct for the invisible border.
  [void][Drive]::SetWindowPos($h, [IntPtr]::Zero, $WinX, $WinY, $WinW, $WinH, 0x0040)
  $outer = New-Object Drive+RECT
  [void][Drive]::GetWindowRect($h, [ref]$outer)
  $f = [Drive]::Frame($h)
  $dl = $f.Left - $outer.Left; $dt = $f.Top - $outer.Top
  $dr = $outer.Right - $f.Right; $db = $outer.Bottom - $f.Bottom
  [void][Drive]::SetWindowPos($h, [IntPtr]::Zero, ($WinX - $dl), ($WinY - $dt),
    ($WinW + $dl + $dr), ($WinH + $dt + $db), 0x0040)
  Start-Sleep -Milliseconds 400

  if ([Drive]::GetForegroundWindow() -ne $h) {
    # Keystrokes go to whatever has focus -- usually this terminal, where an
    # ENTER would run whatever was just typed. Refuse rather than risk it.
    if ($NeedFocus) { Write-Error 'app did not come to the front; refusing to send keys elsewhere' }
    Write-Warning 'app did not come to the front; the action may land on another window'
  }
  $h
}

function Need-Args($n, $usage) {
  if ($Rest.Count -lt $n) { Write-Error "usage: $usage" }
}

switch ($Verb) {
  'shot' {
    Need-Args 1 'shot <name>'
    # .NET resolves relative paths against the process directory, not the
    # PowerShell location, so make the path absolute before Save sees it.
    $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ShotDir)
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
      Write-Error "SHOT_DIR '$dir' is not a directory"
    }
    $out = Join-Path $dir "$($Rest[0]).png"
    $h = Pin
    $f = [Drive]::Frame($h)
    $w = $f.Right - $f.Left; $ht = $f.Bottom - $f.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $ht
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.CopyFromScreen($f.Left, $f.Top, 0, 0, $bmp.Size)
      $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
    "wrote $out"
  }
  'click' {
    Need-Args 2 'click <x> <y>'
    $h = Pin
    $f = [Drive]::Frame($h)
    [void][Drive]::SetCursorPos($f.Left + [int]$Rest[0], $f.Top + [int]$Rest[1])
    Start-Sleep -Milliseconds 50
    [Drive]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero)  # left down
    [Drive]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)  # left up
    "clicked window($($Rest[0]),$($Rest[1]))"
  }
  'scroll' {
    Need-Args 3 'scroll <x> <y> <notches>'
    $h = Pin
    $f = [Drive]::Frame($h)
    $sx = $f.Left + [int]$Rest[0]; $sy = $f.Top + [int]$Rest[1]
    # Tell Flutter the pointer is here before the wheel turns. Absolute
    # moves: relative ones go through pointer acceleration and may not cancel.
    [void][Drive]::SetCursorPos($sx + 1, $sy)
    Start-Sleep -Milliseconds 30
    [void][Drive]::SetCursorPos($sx, $sy)
    Start-Sleep -Milliseconds 300
    # One notch per event, as a real wheel sends them. The delta is a signed
    # DWORD; positive is away from the user (up).
    $n = [int]$Rest[2]
    $notch = if ($n -ge 0) { -120 } else { 120 }
    $delta = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$notch), 0)
    for ($i = 0; $i -lt [Math]::Abs($n); $i++) {
      [Drive]::mouse_event(0x800, 0, 0, $delta, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 40
    }
    Start-Sleep -Milliseconds 300
    "scrolled $($Rest[2]) at window($($Rest[0]),$($Rest[1]))"
  }
  'type' {
    Need-Args 1 'type <text>'
    [void](Pin -NeedFocus)
    # SendKeys treats these as syntax; brace them to type them literally.
    $text = ($Rest -join ' ') -replace '([+^%~(){}\[\]])', '{$1}'
    [System.Windows.Forms.SendKeys]::SendWait($text)
  }
  'key' {
    Need-Args 1 'key <keyname>'
    [void](Pin -NeedFocus)
    # Key names are case-insensitive; upper-casing would turn `key a` into Shift+A.
    [System.Windows.Forms.SendKeys]::SendWait("{$($Rest[0])}")
  }
  'bounds' {
    $f = [Drive]::Frame((Find-Window))
    "{$($f.Left), $($f.Top)}, {$($f.Right - $f.Left), $($f.Bottom - $f.Top)}"
  }
  default {
    Get-Content $PSCommandPath -TotalCount 24 | Select-Object -Skip 1 |
      ForEach-Object { $_ -replace '^# ?', '' }
    exit 1
  }
}

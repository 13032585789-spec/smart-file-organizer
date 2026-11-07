<#
.SYNOPSIS
  Smart File Organizer - memory (RAM) step.
  Shows RAM usage, the heaviest apps and startup programs. With -Close it closes the
  named apps (asks them to close normally first, so unsaved work can be saved).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory.ps1 -Close chrome,Teams
#>
param(
  [string[]]$Close,
  [int]$Top = 15,
  [switch]$Force
)

# Never touch these
$protected = '^(System|Idle|Registry|smss|csrss|wininit|winlogon|services|lsass|svchost|explorer|dwm|fontdrvhost|Memory Compression|MsMpEng|SecurityHealthService|audiodg|spoolsv|ctfmon|sihost|taskhostw|RuntimeBroker|Claude|powershell|pwsh|conhost|WindowsTerminal)$'

function GB($b) { '{0:N2} GB' -f ($b / 1GB) }
function Show-Memory {
  $os = Get-CimInstance Win32_OperatingSystem
  $total = [int64]$os.TotalVisibleMemorySize * 1KB; $free = [int64]$os.FreePhysicalMemory * 1KB
  $used = $total - $free
  Write-Host ("RAM: {0} used of {1} ({2:P0}), {3} available" -f (GB $used), (GB $total), ($used / $total), (GB $free))
  return $free
}

$freeBefore = Show-Memory
Write-Host ''
Write-Host "Top $Top apps by memory (all processes of the same app added together):"
$apps = Get-Process | Group-Object ProcessName | ForEach-Object {
  [pscustomobject]@{ App = $_.Name; Processes = $_.Count; MemoryMB = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB) }
} | Sort-Object MemoryMB -Descending
$apps | Select-Object -First $Top | Format-Table -AutoSize | Out-String | Write-Host

Write-Host 'Programs that start automatically with Windows (disable unneeded ones in Task Manager > Startup apps):'
try {
  Get-CimInstance Win32_StartupCommand | Select-Object Name, Location | Format-Table -AutoSize | Out-String | Write-Host
} catch { Write-Host '  (could not read startup list)' }

if (-not $Close) {
  Write-Host 'Tip: re-run with -Close <app1>,<app2> to close apps you do not need right now.'
  return
}

foreach ($name in $Close) {
  $n = $name -replace '\.exe$', ''
  if ($n -match $protected) { Write-Host "Skipping protected system process: $n"; continue }
  $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
  if (-not $procs) { Write-Host "Not running: $n"; continue }
  foreach ($p in $procs) { if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } }
  Start-Sleep -Seconds 5
  $left = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
  if ($left -and $Force) { $left | Stop-Process -Force -ErrorAction SilentlyContinue; Write-Host "Force-closed: $n" }
  elseif ($left) { Write-Host "$n is still running (it may be asking to save). Re-run with -Force to force-close." }
  else { Write-Host "Closed: $n" }
}
Write-Host ''
$freeAfter = Show-Memory
Write-Host ("Freed about {0}" -f (GB ([math]::Max(0, $freeAfter - $freeBefore))))

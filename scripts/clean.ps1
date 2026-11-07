<#
.SYNOPSIS
  Smart File Organizer - clean step.
  Deletes every row of cleanup_plan.csv whose Delete column is "Yes".
  Files go to the Recycle Bin by default (recoverable). Temp/cache files are removed directly.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\clean.ps1 -Plan "C:\Users\me\SmartCleanReports\20261107_163000\cleanup_plan.csv"
  ... -Yes                 # skip the typed confirmation (fully automatic)
  ... -Permanent           # delete directly instead of Recycle Bin
  ... -EmptyRecycleBinAfter  # also empty the Recycle Bin at the end (files from this run become unrecoverable)
#>
param(
  [Parameter(Mandatory = $true)][string]$Plan,
  [switch]$Yes,
  [switch]$Permanent,
  [switch]$EmptyRecycleBinAfter
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
$rows = @(Import-Csv -LiteralPath $Plan | Where-Object { $_.Delete -eq 'Yes' })
if ($rows.Count -eq 0) { Write-Host 'Nothing marked Delete=Yes. Done.'; return }

function GB($b) { '{0:N2} GB' -f ($b / 1GB) }
$total = [int64](($rows | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)
$sys = New-Object IO.DriveInfo($env:SystemDrive)
$freeBefore = $sys.AvailableFreeSpace

Write-Host "About to delete $($rows.Count) items, about $(GB $total)."
$rows | Group-Object Category | ForEach-Object {
  Write-Host ("  {0,-11} {1,6} items  {2}" -f $_.Name, $_.Count, (GB (($_.Group | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)))
}
if ($Permanent) { Write-Host 'Mode: PERMANENT delete (no Recycle Bin).' } else { Write-Host 'Mode: user files -> Recycle Bin; temp/cache files removed directly.' }
if (-not $Yes) {
  $ans = Read-Host 'Type YES to continue'
  if ($ans -cne 'YES') { Write-Host 'Cancelled. Nothing deleted.'; return }
}

$log = New-Object 'System.Collections.Generic.List[object]'
function Log($row, $status, $freed, $note) {
  $log.Add([pscustomobject]@{ Time = (Get-Date -Format o); Id = $row.Id; Category = $row.Category; Path = $row.Path; Bytes = $freed; Status = $status; Note = $note })
}
$recycle = if ($Permanent) { [Microsoft.VisualBasic.FileIO.RecycleOption]::DeletePermanently } else { [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin }
$ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
$emptyBin = $false

# old Recycle Bin content first (so this run's files stay recoverable), then user files, then caches
$order = @{ RecycleBin = 0; Duplicate = 1; Installer = 2; TempFile = 3; OldArchive = 4; Stale = 5; Junk = 6 }
foreach ($r in ($rows | Sort-Object { $order[$_.Category] })) {
  try {
    switch ($r.Category) {
      'RecycleBin' {
        Clear-RecycleBin -Force -ErrorAction Stop; $emptyBin = $true
        Log $r 'Emptied' ([int64]$r.Bytes) 'Old Recycle Bin content'
        continue
      }
      'Junk' {
        $cut = (Get-Date).AddDays(-1); $freed = [int64]0; $fail = 0
        $filter = if ($r.Filter) { $r.Filter } else { '*' }
        Get-ChildItem -LiteralPath $r.Path -Recurse -Force -File -Filter $filter -ErrorAction SilentlyContinue |
          Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object {
            try { $len = $_.Length; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $freed += $len } catch { $fail++ }
          }
        # remove now-empty subfolders (never the cache root itself)
        Get-ChildItem -LiteralPath $r.Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
          Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
          }
        Log $r 'Cleaned' $freed "$fail files in use / no permission, skipped"
        continue
      }
      default {
        $f = Get-Item -LiteralPath $r.Path -Force -ErrorAction SilentlyContinue
        if (-not $f) { Log $r 'Skipped' 0 'File no longer exists'; continue }
        if ([int64]$f.Length -ne [int64]$r.Bytes -or ($r.ModifiedUtc -and $f.LastWriteTimeUtc.ToString('o') -ne $r.ModifiedUtc)) {
          Log $r 'Skipped' 0 'File changed since scan'; continue
        }
        if ($r.Category -eq 'Duplicate') {
          if (-not (Test-Path -LiteralPath $r.KeepCopy)) { Log $r 'Skipped' 0 'Kept copy is missing - not deleting the last copy'; continue }
          $kh = (Get-FileHash -LiteralPath $r.KeepCopy -Algorithm SHA256).Hash
          $fh = (Get-FileHash -LiteralPath $r.Path -Algorithm SHA256).Hash
          if ($kh -ne $r.SHA256 -or $fh -ne $r.SHA256) { Log $r 'Skipped' 0 'Hash changed - not identical any more'; continue }
        }
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.FullName, $ui, $recycle)
        Log $r $(if ($Permanent) { 'Deleted' } else { 'Recycled' }) ([int64]$f.Length) ''
      }
    }
  } catch { Log $r 'Failed' 0 $_.Exception.Message }
}

if ($EmptyRecycleBinAfter -and -not $Permanent) {
  # Recycled files only free disk space once the bin is emptied.
  try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Host 'Recycle Bin emptied.' } catch { Write-Host "Could not empty Recycle Bin: $($_.Exception.Message)" }
}

$logPath = Join-Path (Split-Path -Parent $Plan) 'action_log.csv'
$log | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8
$sys = New-Object IO.DriveInfo($env:SystemDrive)
$gain = $sys.AvailableFreeSpace - $freeBefore
Write-Host ''
$log | Group-Object Status | ForEach-Object { Write-Host ("  {0,-9} {1} items" -f $_.Name, $_.Count) }
Write-Host "Free space on $($env:SystemDrive): $(GB $freeBefore) -> $(GB $sys.AvailableFreeSpace) ($(GB $gain) gained)"
if (-not $Permanent -and -not $EmptyRecycleBinAfter) { Write-Host 'Files from this run are in the Recycle Bin and still use space. Check them, then empty the bin (or re-run with -EmptyRecycleBinAfter).' }
Write-Host "Log: $logPath"

<#
.SYNOPSIS
  Smart File Organizer - scan step (read-only).
  Finds junk/cache files, duplicate files, old installers and long-unused files,
  and writes a cleanup plan that clean.ps1 can execute.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan.ps1 -Roots "D:\Stuff" -StaleDays 365
#>
param(
  [string[]]$Roots,
  [string]$ReportDir,
  [int]$StaleDays = 180,
  [int]$MinStaleMB = 20,
  [int]$MinDuplicateKB = 100,
  [switch]$SkipSystemJunk
)

$ErrorActionPreference = 'Stop'
$home_ = $env:USERPROFILE
if (-not $Roots -or $Roots.Count -eq 0) {
  $Roots = @("$home_\Downloads", "$home_\Desktop", "$home_\Documents") | Where-Object { Test-Path -LiteralPath $_ }
}
if (-not $ReportDir) { $ReportDir = Join-Path $home_ ("SmartCleanReports\" + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
$ReportDir = [IO.Path]::GetFullPath($ReportDir)
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

# ---------- protection rules ----------
$forbiddenRoot = '^[A-Za-z]:\\?$|^[A-Za-z]:\\(Windows|Program Files|Program Files \(x86\)|ProgramData|Recovery|System Volume Information|\$Recycle\.Bin)(\\|$)'
$protectPath = '(?i)\\(\.git|\.svn|\.hg|\.venv|venv|env|node_modules|site-packages|\.ssh|\.gnupg|AppData|OneDrive[^\\]*|WPS Cloud Files|WPSDrive|iCloudDrive|Dropbox|Google Drive|SmartCleanReports)(\\|$)'
$protectFile = '(?i)(\.env$|\.pem$|\.key$|\.pfx$|\.p12$|\.kdbx$|id_rsa|id_ed25519|wallet|\.ovpn$|\.lnk$|desktop\.ini$|\.(pt|pth|ckpt|safetensors|onnx|h5)$)'
$docExt = '(?i)\.(docx?|xlsx?|pptx?|pdf|txt|md|tex|bib|odt|ods|odp|pages|key|numbers|psd|ai|fig|sketch|py|ipynb|js|ts|java|c|cpp|h|cs|rs|go|m|r|sql|json|ya?ml|csv)$'
$installerExt = '(?i)\.(exe|msi|msix|appx|dmg|iso|apk)$'
$archiveExt = '(?i)\.(zip|7z|rar|tar|gz|bz2|xz)$'
$OFFLINE = 0x1000; $RECALL = 0x400000; $PINNED_CLOUD = 0x80000

foreach ($r in @($Roots)) {
  $p = [IO.Path]::GetFullPath($r).TrimEnd('\')
  if ($p -match $forbiddenRoot) { throw "Refusing to scan system location: $p" }
  if ($p -ieq $home_.TrimEnd('\')) { throw "Pass specific folders (Downloads, Desktop, ...), not the whole user profile." }
}

$errors = New-Object 'System.Collections.Generic.List[string]'
$files  = New-Object 'System.Collections.Generic.List[object]'
$plan   = New-Object 'System.Collections.Generic.List[object]'
$script:id = 0
function Add-Plan($cat, $path, $bytes, $mtime, $hash, $keeper, $reason, $risk, $delete) {
  $script:id++
  $plan.Add([pscustomobject]@{
    Id = $script:id; Category = $cat; Delete = $delete; Risk = $risk; Bytes = [int64]$bytes
    SizeMB = [math]::Round($bytes / 1MB, 2); Path = $path; ModifiedUtc = $mtime; SHA256 = $hash
    KeepCopy = $keeper; Filter = ''; Reason = $reason })
}

# ---------- 1. walk user folders ----------
function Walk([string]$dir) {
  try { $items = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop } catch { $errors.Add("No access: $dir"); return }
  foreach ($x in $items) {
    $a = [int]$x.Attributes
    if ($a -band [int][IO.FileAttributes]::ReparsePoint) { continue }
    if ($a -band ($OFFLINE -bor $RECALL -bor $PINNED_CLOUD)) { continue }   # cloud placeholder
    if ($x.FullName -match $protectPath) { continue }
    if ($x.PSIsContainer) { Walk $x.FullName; continue }
    if ($x.Name -match $protectFile) { continue }
    $files.Add($x)
  }
}
foreach ($r in @($Roots)) { Write-Host "Scanning $r ..."; Walk ([IO.Path]::GetFullPath($r)) }
$fileCount = $files.Count
Write-Host "Files scanned: $fileCount"

# ---------- 2. duplicates (size -> SHA256) ----------
$dupPaths = @{}
$bySize = $files | Where-Object { $_.Length -ge ($MinDuplicateKB * 1KB) } | Group-Object Length | Where-Object Count -gt 1
$groupNo = 0
foreach ($g in $bySize) {
  $byHash = @{}
  foreach ($f in $g.Group) {
    try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } catch { $errors.Add("Hash failed: $($f.FullName)"); continue }
    if (-not $byHash.ContainsKey($h)) { $byHash[$h] = @() }
    $byHash[$h] += $f
  }
  foreach ($h in $byHash.Keys) {
    $set = @($byHash[$h]); if ($set.Count -lt 2) { continue }
    $groupNo++
    # keep the copy outside Downloads/Desktop, then shortest path, then oldest
    $keeper = $set | Sort-Object @{e={ if ($_.FullName -match '(?i)\\(Downloads|Desktop)\\') {1} else {0} }}, @{e={$_.FullName.Length}}, LastWriteTimeUtc | Select-Object -First 1
    foreach ($f in $set) {
      if ($f.FullName -eq $keeper.FullName) { continue }
      $dupPaths[$f.FullName] = $true
      Add-Plan 'Duplicate' $f.FullName $f.Length $f.LastWriteTimeUtc.ToString('o') $h $keeper.FullName "Identical (SHA256) to kept copy, group $groupNo" 'Low' 'Yes'
    }
  }
}

# ---------- 3. installers, archives, stale files ----------
$cut = (Get-Date).ToUniversalTime().AddDays(-$StaleDays)
foreach ($f in $files) {
  if ($dupPaths.ContainsKey($f.FullName)) { continue }
  $inDownloads = $f.FullName -match '(?i)\\Downloads\\'
  $last = $f.LastWriteTimeUtc; if ($f.LastAccessTimeUtc -gt $last) { $last = $f.LastAccessTimeUtc }
  $old = $last -lt $cut
  $m = $f.LastWriteTimeUtc.ToString('o')
  if ($f.Name -match $installerExt -and $inDownloads) {
    Add-Plan 'Installer' $f.FullName $f.Length $m '' '' 'Downloaded installer; can be downloaded again' 'Low' 'Yes'
  } elseif ($f.Name -match $archiveExt -and $inDownloads -and $old) {
    Add-Plan 'OldArchive' $f.FullName $f.Length $m '' '' "Archive in Downloads, unused > $StaleDays days" 'Medium' 'Yes'
  } elseif ($f.Name -match '(?i)\.(tmp|temp|crdownload|part|partial|dmp|old|bak)$|^~\$') {
    Add-Plan 'TempFile' $f.FullName $f.Length $m '' '' 'Temporary / leftover file' 'Low' 'Yes'
  } elseif ($old -and $f.Length -ge ($MinStaleMB * 1MB)) {
    $isDoc = $f.Name -match $docExt
    $del = if ($inDownloads -and -not $isDoc) { 'Yes' } else { 'No' }
    $risk = if ($isDoc) { 'High' } else { 'Medium' }
    Add-Plan 'Stale' $f.FullName $f.Length $m '' '' ("Not used for > $StaleDays days" + $(if ($isDoc) {' (document/code - review)'} else {''})) $risk $del
  }
}

# ---------- 4. system junk & caches (folder-level) ----------
if (-not $SkipSystemJunk) {
  $L = $env:LOCALAPPDATA
  $junk = @(
    @{p=$env:TEMP; r='User temp files'},
    @{p="$env:WINDIR\Temp"; r='Windows temp files (needs admin)'},
    @{p="$L\CrashDumps"; r='Crash dumps'},
    @{p="$L\Microsoft\Windows\INetCache"; r='Internet cache'},
    @{p="$L\Microsoft\Windows\Explorer"; r='Thumbnail cache (thumbcache_*.db)'; f='thumbcache_*.db'},
    @{p="$L\D3DSCache"; r='DirectX shader cache'},
    @{p="$L\NVIDIA\DXCache"; r='NVIDIA shader cache'},
    @{p="$L\pip\Cache"; r='pip download cache'},
    @{p="$L\npm-cache"; r='npm cache'},
    @{p="$env:APPDATA\npm-cache"; r='npm cache'},
    @{p="$L\yarn\Cache"; r='yarn cache'},
    @{p="$env:WINDIR\SoftwareDistribution\Download"; r='Windows Update downloads (needs admin)'}
  )
  foreach ($b in @('Google\Chrome','Microsoft\Edge','BraveSoftware\Brave-Browser')) {
    $ud = "$L\$b\User Data"
    if (Test-Path -LiteralPath $ud) {
      Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($c in @('Cache','Code Cache','GPUCache','Service Worker\CacheStorage')) {
          $junk += @{p=(Join-Path $_.FullName $c); r="Browser cache ($b, profile $($_.Name)) - close the browser first"}
        }
      }
    }
  }
  $junkCut = (Get-Date).AddDays(-1)
  foreach ($j in $junk) {
    if (-not $j.p -or -not (Test-Path -LiteralPath $j.p)) { continue }
    $filter = if ($j.f) { $j.f } else { '*' }
    $sum = [int64]0; $n = 0
    try {
      Get-ChildItem -LiteralPath $j.p -Recurse -Force -File -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $junkCut } | ForEach-Object { $sum += $_.Length; $n++ }
    } catch { $errors.Add("Junk scan failed: $($j.p)") }
    if ($n -gt 0) { Add-Plan 'Junk' $j.p $sum '' '' '' "$($j.r); $n files older than 1 day" 'Low' 'Yes'; $plan[$plan.Count-1].Filter = $filter }
  }
  try {
    $rb = (New-Object -ComObject Shell.Application).NameSpace(10)
    $rbBytes = [int64]0; foreach ($i in $rb.Items()) { $rbBytes += [int64]$i.Size }
    if ($rbBytes -gt 0) { Add-Plan 'RecycleBin' 'RecycleBin' $rbBytes '' '' '' "Recycle Bin contents ($($rb.Items().Count) items)" 'Medium' 'Yes' }
  } catch { $errors.Add('Could not read Recycle Bin size') }
}

# ---------- 5. reports ----------
$planPath = Join-Path $ReportDir 'cleanup_plan.csv'
$plan | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8

$sysDrive = New-Object IO.DriveInfo($env:SystemDrive)
$yes = $plan | Where-Object Delete -eq 'Yes'
$yesBytes = ($yes | Measure-Object Bytes -Sum).Sum; if (-not $yesBytes) { $yesBytes = 0 }
$noBytes = ($plan | Where-Object Delete -eq 'No' | Measure-Object Bytes -Sum).Sum; if (-not $noBytes) { $noBytes = 0 }
function GB($b) { '{0:N2} GB' -f ($b / 1GB) }

$md = @('# Smart Clean - scan summary', '',
  "- Scanned: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "- Folders: $($Roots -join '; ')",
  "- System drive $($env:SystemDrive): $(GB $sysDrive.AvailableFreeSpace) free of $(GB $sysDrive.TotalSize)",
  "- Files scanned: $fileCount; duplicate groups: $groupNo",
  "- **Marked for deletion: $(GB $yesBytes)** ($(@($yes).Count) items)",
  "- Needs review (Delete=No): $(GB $noBytes)", '',
  '## By category', '', '| Category | Items | Size | Marked Yes |', '| --- | ---: | ---: | ---: |')
foreach ($c in ($plan | Group-Object Category | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending)) {
  $s = ($c.Group | Measure-Object Bytes -Sum).Sum
  $y = ($c.Group | Where-Object Delete -eq 'Yes' | Measure-Object Bytes -Sum).Sum; if (-not $y) { $y = 0 }
  $md += "| $($c.Name) | $($c.Count) | $(GB $s) | $(GB $y) |"
}
$md += @('', '## 20 largest items', '')
$md += @($plan | Sort-Object Bytes -Descending | Select-Object -First 20 | ForEach-Object { "- [$($_.Delete)] $($_.Category) $($_.SizeMB) MB - $($_.Path)" })
$md += @('', '## Next step', '', 'Review / edit the Delete column in cleanup_plan.csv, then run:', '',
  '```powershell', "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\clean.ps1 -Plan `"$planPath`"", '```')
if ($errors.Count) { $md += @('', '## Skipped / errors', ''); $md += @($errors | Select-Object -First 50 | ForEach-Object { "- $_" }) }
$md | Set-Content -LiteralPath (Join-Path $ReportDir 'summary.md') -Encoding UTF8

Write-Host ''
Write-Host "Marked for deletion: $(GB $yesBytes) in $(@($yes).Count) items; needs review: $(GB $noBytes)"
Write-Host "Plan:    $planPath"
Write-Host "Summary: $(Join-Path $ReportDir 'summary.md')"

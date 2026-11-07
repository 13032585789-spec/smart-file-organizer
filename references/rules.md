# Cleanup rules

| Category | Found where | Default `Delete` | Risk | Notes |
| --- | --- | --- | --- | --- |
| `RecycleBin` | Windows Recycle Bin | Yes | Medium | Emptied first, before this run recycles anything. |
| `Junk` | `%TEMP%`, `Windows\Temp`*, CrashDumps, INetCache, thumbnail cache, DirectX/NVIDIA shader cache, pip/npm/yarn cache, browser caches (Chrome/Edge/Brave), Windows Update downloads* | Yes | Low | Only files older than 1 day; in-use files are skipped. Removed directly (not to Recycle Bin). *needs admin |
| `Duplicate` | scanned folders | Yes | Low | Same size and SHA-256. Keeps the copy outside Downloads/Desktop, then the shortest path, then the oldest. Files < 100 KB ignored (`-MinDuplicateKB`). |
| `Installer` | Downloads | Yes | Low | `.exe .msi .msix .appx .iso .dmg .apk` |
| `TempFile` | scanned folders | Yes | Low | `.tmp .temp .crdownload .part .dmp .old .bak`, Office `~$` lock files |
| `OldArchive` | Downloads | Yes | Medium | `.zip .7z .rar .tar .gz …` not opened or changed for `StaleDays` |
| `Stale` | scanned folders | Yes in Downloads (non-documents), otherwise No | Medium / High | ≥ `MinStaleMB`, not opened or changed for `StaleDays`. Documents and code are always `No`. |

"Unused" uses the later of last-write and last-access time. Windows may not update last-access time on every read, so stale results are an estimate — that is why stale files outside Downloads default to `No`.

## Always excluded

- System roots: `C:\`, `Windows`, `Program Files`, `ProgramData`, `Recovery`, `$Recycle.Bin`
- Folders anywhere in the path: `.git .svn .hg .venv venv env node_modules site-packages .ssh .gnupg AppData OneDrive* WPS Cloud Files WPSDrive iCloudDrive Dropbox Google Drive SmartCleanReports`
- Files: `.env .pem .key .pfx .p12 .kdbx id_rsa id_ed25519 *wallet* .ovpn .lnk desktop.ini` and model weights `.pt .pth .ckpt .safetensors .onnx .h5`
- Symlinks / junctions and cloud-only placeholders

## Before each deletion `clean.ps1` checks

1. The file still exists with the same size and modified time as in the plan.
2. For duplicates: the kept copy exists and both files still have the planned SHA-256.
3. Anything failing a check is logged as `Skipped`, never deleted.

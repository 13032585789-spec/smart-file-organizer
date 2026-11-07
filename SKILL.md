---
name: smart-file-organizer
description: Free disk space and memory on a Windows PC. Finds junk/cache files, duplicate files, old installers and long-unused files, deletes them after one confirmation, and shows which apps are using RAM. Use for "clean my disk", "free up space", "delete duplicate files", "free memory", "清理磁盘", "释放空间", "删除重复文件", "释放内存".
---

# Smart File Organizer

Windows cleanup skill: **scan → one confirmation → delete → report**. Pure PowerShell 5.1+, no installs.

## Scripts

| Script | What it does | Changes files? |
| --- | --- | --- |
| `scripts/scan.ps1` | Builds `cleanup_plan.csv` + `summary.md` in `%USERPROFILE%\SmartCleanReports\<time>\` | No (read-only) |
| `scripts/clean.ps1 -Plan <csv>` | Deletes every row with `Delete=Yes` | Yes |
| `scripts/memory.ps1 [-Close app1,app2]` | RAM usage, heaviest apps, startup apps; optionally closes named apps | Only with `-Close` |

Run every script with `powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...` from the skill folder.

## Workflow

1. **Scan.** Run `scan.ps1`. Default folders: Downloads, Desktop, Documents, plus system temp/caches and the Recycle Bin. Add folders with `-Roots "D:\Data","E:\Old"`. Options: `-StaleDays 180`, `-MinStaleMB 20`, `-SkipSystemJunk`.
2. **Report.** Read `summary.md` and tell the user, in their language: free space now, total marked for deletion, a size breakdown by category, the largest items, and the `Delete=No` items that need their review. Keep it short.
3. **Confirm once.** Ask one question: delete everything marked Yes? Offer to flip specific rows (edit the `Delete` column in the CSV) before running. Ask whether to empty the Recycle Bin afterwards (`-EmptyRecycleBinAfter`) — that is what actually frees the space of recycled files, and it makes them unrecoverable.
4. **Clean.** Run `clean.ps1 -Plan <csv> -Yes` (add `-EmptyRecycleBinAfter` only if the user agreed). Report freed space and anything skipped from `action_log.csv`.
5. **Memory.** If the user asked about RAM, run `memory.ps1`, explain which apps use the most, and close apps only when the user names them (`-Close`). Never close apps the user didn't name; warn about unsaved work.

If the user says they want it fully automatic, steps 3–4 collapse into running `clean.ps1 -Yes` right after reporting, but still state what will be deleted before deleting.

## What gets marked

See [references/rules.md](references/rules.md). Summary:

- **Delete=Yes:** temp & cache folders (files older than 1 day), extra copies of identical files (SHA-256, one copy always kept), installers in Downloads, `.tmp/.crdownload/.bak/~$` leftovers, archives in Downloads unused for `StaleDays`, large non-document files in Downloads unused for `StaleDays`, old Recycle Bin content.
- **Delete=No (review):** large stale files outside Downloads, and any stale document/code file.
- **Never touched:** Windows / Program Files / ProgramData, AppData (except the listed caches), `.git`, virtual envs, `node_modules`, keys and secrets, model weights, cloud-sync folders (OneDrive, WPS Cloud, Dropbox…) and cloud placeholders, shortcuts.

## Safety rules

- `clean.ps1` re-checks size and modified time of every file (and SHA-256 of both copies for duplicates) and skips anything that changed or whose kept copy is gone.
- User files go to the Recycle Bin unless the user explicitly asks for `-Permanent`.
- Do not widen the scan to a whole drive or the whole user profile; the script refuses system roots and the profile root.
- Admin-only locations (Windows\Temp, Windows Update cache) are skipped silently when not elevated; mention that running PowerShell as administrator cleans them too.
- RAM: Windows already uses free RAM as cache; the real lever is closing heavy apps and disabling startup apps. Do not use "RAM booster" tricks.

---
name: smart-file-organizer
description: Audit authorized Windows user folders for disk usage, duplicates, organization and cleanup candidates; preview changes and execute only explicitly approved file actions.
---

# Smart File Organizer

Use this skill for Windows user-file audits, duplicate detection, organization plans, archival plans, and approved cleanup. It is portable Markdown plus PowerShell and can be published as a standalone repository.

## Scope and modes

Accept explicit folder roots from the user. Never infer authorization for other disks, users, system directories, or cloud content. Default to **Audit Only**. **Organize Preview** and **Cleanup Preview** produce plans only. **Approved Organize** and **Approved Cleanup** require approval of each full-path action or an unambiguous full-path scope after reviewing a concrete manifest. A request to maximize savings does not waive this step.

Run `scripts/audit.ps1 -Roots <absolute paths> -ReportDir <separate directory>` for read-only analysis. Reports may be written only to the report directory. Read [references/rules.md](references/rules.md) when assessing candidates. Use [assets/report-template.md](assets/report-template.md) for human summaries.

## Safety invariants

- Do not move, rename, overwrite, delete, empty Recycle Bin, edit registry/settings, upload, or synchronize files during audit or preview.
- Treat reparse points, symbolic links, cloud placeholders, inaccessible files, Git repositories, source, secrets, virtual environments, datasets, and model weights conservatively. Mark uncertain items `Unknown`.
- Duplicate identity requires equal size and SHA-256; same name alone proves nothing. Distinguish hard links by file identity when possible; if identity cannot be established, mark `Unknown` and do not count the saving as safe.
- Never remove a sole copy. Age alone does not imply low value.
- Before any approved action, recheck full path, size, modification time and SHA-256 against the reviewed manifest. Abort changed or missing items. Prefer reversible moves to a user-approved quarantine or archive on the same volume, preserve original paths and a recovery log, and never use irreversible deletion.
- Stop after reporting until the user approves concrete actions.

## Reports

Produce `disk_overview.md`, `large_files.csv`, `duplicate_files.csv`, `organization_plan.md`, and `cleanup_candidates.csv`. Create `action_log.md` only after an actual approved operation. Separate measured disk usage from estimated safe-to-consider cleanup, manual-review space, organization-only bytes, and important-to-retain bytes. Savings estimates must avoid double counting. State scan limits and errors.

For approved actions, build and show a manifest with source, destination/quarantine, size, hash, expected impact, risk, and recovery path before approval. Log each completed action and its rollback command. If an approved action cannot be performed safely, skip it and report why.

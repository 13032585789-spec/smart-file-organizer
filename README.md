# smart-file-organizer

Portable Windows file-audit Skill for Codex and other assistants that support `SKILL.md`, including Claude environments that load Skills. Clone this folder into your assistant's Skills directory. No private paths or scan reports are bundled.

Codex install: place the `smart-file-organizer` folder under `%USERPROFILE%\.codex\skills\`. Invoke `$smart-file-organizer` or ask “审计我的 Downloads 和 Documents”, “预览课程资料归档”, “找出重复文件并估算空间”.

Run the scanner directly with PowerShell 5.1+:

```powershell
powershell -NoProfile -File .\scripts\audit.ps1 -Roots "$env:USERPROFILE\Downloads","$env:USERPROFILE\Documents" -ReportDir "C:\path\to\reports"
```

Adjust `-Roots` to the exact authorized directories. Use a separate `-ReportDir`; it is created if needed. Audit does not alter scanned files. Review the reports before asking for a preview or approving any operation.

To upgrade, replace the Skill folder from a reviewed release, retaining local custom rules separately. Run a small-scope audit and inspect reports before broad use. Do not commit personal reports to GitHub. The scanner uses only built-in PowerShell commands; Python is unnecessary.

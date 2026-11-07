# smart-file-organizer

一个给 AI 助手（Claude、Codex 等支持 `SKILL.md` 的环境）用的 Windows 清理 Skill：扫描磁盘 → 确认一次 → 自动删除 → 报告释放了多少空间。也可以不通过 AI，直接用 PowerShell 运行。

A Windows cleanup skill for assistants that load `SKILL.md`: scan, confirm once, delete, report. Works standalone in PowerShell 5.1+ with no installs.

## 能做什么

- **清理垃圾和缓存**：系统临时文件、崩溃转储、缩略图缓存、浏览器缓存、pip/npm 缓存、Windows 更新残留、回收站
- **删除重复文件**：按 SHA-256 判断完全相同的文件，每组只保留一份
- **删除用不着的文件**：Downloads 里的安装包、旧压缩包、长期没打开的大文件、`.tmp/.bak` 残留
- **释放内存**：显示哪些程序最占内存、哪些开机自启，并可一键关闭指定程序

用户文件默认进回收站，可以恢复；文档、代码、`.git`、密钥、云同步文件夹和系统目录不会被删。完整规则见 [references/rules.md](references/rules.md)。

## 安装

把整个 `smart-file-organizer` 文件夹放到助手的 Skills 目录，例如：

- Claude Code：`%USERPROFILE%\.claude\skills\smart-file-organizer`
- Codex：`%USERPROFILE%\.codex\skills\smart-file-organizer`

然后对助手说"帮我清理磁盘""删掉重复文件""释放内存"即可。

## 直接运行

在 Skill 文件夹里打开 PowerShell：

```powershell
# 1. 扫描（只读，不删任何东西）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan.ps1

# 2. 看 summary.md，必要时改 cleanup_plan.csv 的 Delete 列，然后清理
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\clean.ps1 -Plan "<scan 输出的 cleanup_plan.csv 路径>"

# 3. 查看/释放内存
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\memory.ps1 -Close chrome
```

常用参数：

| 脚本 | 参数 | 作用 |
| --- | --- | --- |
| scan.ps1 | `-Roots "D:\资料","E:\旧文件"` | 额外/指定扫描的文件夹（默认 Downloads、Desktop、Documents） |
| scan.ps1 | `-StaleDays 365` | 多少天没用算"用不着"（默认 180） |
| clean.ps1 | `-Yes` | 不再询问，直接删除 |
| clean.ps1 | `-EmptyRecycleBinAfter` | 删完后清空回收站，真正释放空间（之后无法恢复） |
| clean.ps1 | `-Permanent` | 不进回收站，直接永久删除 |
| memory.ps1 | `-Close app1,app2 [-Force]` | 关闭指定程序 |

以管理员身份运行 PowerShell 可以额外清理 `C:\Windows\Temp` 和 Windows 更新缓存。

报告保存在 `%USERPROFILE%\SmartCleanReports\`，不要把这些报告提交到 GitHub。

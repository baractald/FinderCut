---
name: local-release
description: >-
  Release the already-built FinderCut.app into /Applications, clear stale macOS Accessibility
  TCC permissions, and relaunch the app. Use when the user asks for "本地发布" or to replace
  the installed FinderCut app in /Applications with the newly compiled build.
---

# FinderCut 本地发布（Local Release）

在当前工作区执行「本地发布」时，仅负责将工作区中**已编译完成**的 `./FinderCut.app` 部署替换到 `/Applications/FinderCut.app` 并重启应用（不自动执行 `./build.sh` 重新编译）。

## 发布步骤

1. **检查已构建产物存在**：
   - 执行 `test -d ./FinderCut.app` 确认工作区根目录下已有编译好的 `FinderCut.app`。
   - 若 `./FinderCut.app` 不存在，停止并告知用户需要先执行 `./build.sh` 构建，不要擅自跳过或擅自编译。
2. **退出运行中的旧实例**：
   - 执行 `pkill -x FinderCut || true`，并确认 `pgrep -x FinderCut` 已无残留进程，避免替换包体时文件被占用。
3. **覆盖复制到 `/Applications`**：
   - 执行 `rm -rf /Applications/FinderCut.app && ditto ./FinderCut.app /Applications/FinderCut.app`。
4. **清理旧的辅助功能权限记录（仅 ad-hoc 签名时需要）**：
   - 检查新安装应用的签名方式：`codesign -dvv /Applications/FinderCut.app 2>&1`。
   - 若包含 `Signature=adhoc`，执行 `tccutil reset Accessibility work.oneman.FinderCut`（如本机仍有早期 `com.local.FinderCut` 残留条目也可顺便清理），清除因 ad-hoc 签名哈希变化而失效的 TCC 记录。
   - 若为正式 `Developer ID Application` 签名（非 ad-hoc），**跳过** `tccutil reset`，macOS 会自动保留原有辅助功能授权。
5. **校验签名并重启应用**：
   - 执行 `codesign --verify --deep --strict /Applications/FinderCut.app && open /Applications/FinderCut.app`。
6. **验证与提示**：
   - 运行 `pgrep -fl FinderCut` 确认进程已从 `/Applications/FinderCut.app/Contents/MacOS/FinderCut` 正常启动。
   - 如果是 ad-hoc 签名或首次切换为正式 Bundle ID `work.oneman.FinderCut`，提醒用户在系统提示或「系统设置 → 隐私与安全性 → 辅助功能」中重新勾选授权；同 Developer ID 证书与同 Bundle ID 的后续本地更新无需重复授权。

---
name: dmg-release
description: >-
  Bump FinderCut version metadata, build and verify the Apple Silicon (arm64, minos 13.0) app
  bundle, package a branded UDZO .dmg installer with a custom .VolumeIcon.icns volume icon and
  drag-to-Applications Finder window layout, and publish a new GitHub Release without overwriting
  existing tags. Use when the user asks to release a new version, publish to GitHub, or package a
  FinderCut .dmg.
---

# FinderCut 品牌化 DMG 打包与发版（DMG Release）

本技能用于规范 FinderCut 的版本递增、品牌化 `.dmg` 镜像制作与 GitHub Release 发布流程。

## 硬性约束

- **永不覆盖已有版本**：先运行 `gh release list` 与 `git tag -l` 确认目标 tag（如 `v1.0.3`）尚不存在；禁止覆盖或删除已发布版本。
- **仅发布 `.dmg` + `.sha256`**：不生成 `.pkg` 或 `.zip`；仅提供 Apple Silicon（`arm64`）构建，并保持 `minos 13.0` 部署目标。
- **不擅自改动本机安装**：远程发版不得覆盖 `/Applications/FinderCut.app`、终止运行中的本地实例或重置 TCC 权限（本机部署仅由 [local-release](../local-release/SKILL.md) 处理）。
- **保持仓库干净**：所有 `.dmg`、临时挂载点与 `.sha256` 产物一律生成在 `mktemp -d` 临时目录内并在发布完成后清理，不在仓库目录残留发布文件。

## 执行步骤

### 1. 确认并更新版本号与文案

1. 检查现有版本与标签：`gh release list`、`git tag -l`、[`Resources/Info.plist`](../../../Resources/Info.plist)。
2. 确定目标版本号：
   - `./build.sh` 每次编译都会自动递增 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 末位（patch +1）与 `CFBundleVersion`（+1）；
   - 如果本地调试编译时**已经**自动递增到一个尚未发布的新版本，或你需要手动指定大/中版本号（如 `1.1.0`），在下一步执行 `./build.sh --no-bump` 以免重复递增。
3. 先完成（或确认）`build.sh` 编译后的目标版本号，再同步更新 [`docs/index.html`](../../../docs/index.html) 中所有旧版本号引用、Release 下载链接（`releases/tag/v<新版本>`）以及 `zh`/`en` 双语文案，确保网页、tag 与 `.app` 版本一致。
4. 如本次包含面向用户的新特性或结构变动，同步更新 [`README.md`](../../../README.md) 与 [`README.zh-CN.md`](../../../README.zh-CN.md)。

### 2. 编译与二进制校验

若本次尚未递增到目标发布版本，运行 `./build.sh`（否则使用 `./build.sh --no-bump` 避免二次递增）：

```zsh
./build.sh && \
codesign --verify --deep --strict ./FinderCut.app && \
plutil -p ./FinderCut.app/Contents/Info.plist | grep -E 'CFBundleShortVersionString|CFBundleVersion' && \
otool -l ./FinderCut.app/Contents/MacOS/FinderCut | grep -A 3 LC_BUILD_VERSION
```

确认输出：
- `CFBundleShortVersionString` 与目标版本号一致；
- `codesign --verify --deep --strict` 通过；
- `LC_BUILD_VERSION` 中包含 `minos 13.0`。

### 3. 提交并推送代码

1. 检查 `git status -sb` 与 `git diff --stat`，确认仅包含预期的源码、配置、文档改动，无临时文件。
2. 提交并推送到 `origin/main`（若本机使用 1Password SSH Agent 弹出认证提示，使用足够长的超时等待用户批准）。

### 4. 制作并校验品牌化 `.dmg`

在 `mktemp -d` 临时目录中调用辅助脚本 [package-dmg.sh](./scripts/package-dmg.sh)：

```zsh
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT
.agents/skills/dmg-release/scripts/package-dmg.sh ./FinderCut.app "$TMP_OUT"
```

该脚本会自动完成：
- 验证 `./FinderCut.app` 签名与 `minos 13.0`；
- 使用 AppKit 生成 Retina 拖拽引导背景图（`.background/bg.tiff`）；
- 创建可写 `UDRW`（HFS+）镜像后，先通过 AppleScript 配置无工具栏/状态栏的 `600×380` 内容区访达图标视图（左侧 `FinderCut.app`，右侧 `Applications` 软链接，中间 `→` 箭头）并写入 `.DS_Store`；
- 待访达窗口关闭后再写入 `.VolumeIcon.icns` 并执行 `SetFile -a C` 启用自定义卷图标（避免访达脚本写入布局时移除卷图标文件）；
- 转换为高压缩 `UDZO` 镜像 `FinderCut-v<版本>-arm64.dmg`，执行 `hdiutil verify` 与只读挂载全检（卷图标、`.DS_Store`、`Applications` 软链接、签名、版本号、`minos 13.0`），并生成 `FinderCut-v<版本>-arm64.dmg.sha256`。

### 5. 发布 GitHub Release 并清理收尾

1. 使用 `gh release create` 创建新版本 Release（不要覆盖旧 tag）：

```zsh
gh release create "v<版本>" \
  "$TMP_OUT/FinderCut-v<版本>-arm64.dmg" \
  "$TMP_OUT/FinderCut-v<版本>-arm64.dmg.sha256" \
  --target main \
  --title "FinderCut v<版本>" \
  --latest \
  --notes "..."
```

Release Notes 应写明：
- 本次变更内容（What's Changed）；
- `Full Changelog` 对比链接（`https://github.com/baractald/FinderCut/compare/v<旧版本>...v<版本>`）；
- 安装与运行说明（macOS 13.0+ Apple Silicon `arm64`、拖拽安装、首次运行需授权「辅助功能」权限）。

2. 验证发布与仓库状态：
   - 运行 `gh release view "v<版本>"` 与 `gh release list`，确认新 Release 为 `Latest`、附件仅含 `.dmg` 与 `.dmg.sha256`，且历史版本未被修改；
   - 运行 `git status -sb` 确认工作区干净（`trap` 已自动清理临时输出目录）。

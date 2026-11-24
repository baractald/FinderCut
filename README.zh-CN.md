# FinderCut

[English](./README.md) | **简体中文**

一个轻量、零依赖的原生 macOS 菜单栏工具，为访达（Finder）补齐熟悉的 **`⌘X` 剪切 → `⌘V` 移动** 文件操作体验。

## 核心特性

- **复用访达原生移动引擎**：按 `⌘X` 触发复制并记录待移动状态，切到目标文件夹按 `⌘V` 自动改写为访达原生的 `⌥⌘V`（将项目移到这里），保留原生进度条、同名冲突处理、跨盘移动及 `⌘Z` 撤销，不注入访达进程，无需关闭 SIP。
- **防误触保护**：自动识别访达内重命名输入框、搜索栏、简介标签栏（`AXTokenField`）、密码框（`AXSecureTextField`）、弹出 Sheet 以及 Quick Look（快速查看）窗口，保持系统原生文字剪切/粘贴；若在剪切后又复制了其他文本或文件，待移动状态会自动失效。
- **轻量视觉与听觉反馈**：居中液态玻璃 HUD 浮窗（macOS 26+ 原生 Liquid Glass，macOS 13–15 自动适配圆角毛玻璃）与轻量系统提示音，均可在菜单栏中单独开关并持久化偏好；菜单栏图标本身也支持隐藏，再次运行 FinderCut 即可重新显示。
- **多语言与非 QWERTY 布局支持**：内置简体中文、繁体中文、英文、日文、韩文、法文、德文、西班牙文 8 种语言，默认跟随系统并支持菜单栏实时切换；支持根据当前键盘输入源动态映射 `X` / `C` / `V` 键位。
- **单实例保护与状态自愈**：防止重复启动导致事件重复拦截；定期及唤醒后校验系统“辅助功能”权限与事件监听状态，权限被撤销或恢复时自动更新状态并重连。

## 系统要求

- macOS 13.0 或更高版本
- Apple Silicon（`arm64`）

## 编译与安装

```zsh
./build.sh
```

脚本会编译生成并签名工作区根目录下的 `FinderCut.app`。将 `FinderCut.app` 拖入或复制到 `/Applications/` 后运行，并在首次提示时于 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选允许 `FinderCut`。

## 使用方法

1. 在访达（或桌面）选中一个或多个文件/文件夹，按下 `⌘X`。
2. 菜单栏剪刀图标旁显示 `⌘X` 标记（可选显示 HUD 与提示音）。
3. 切换到目标目录后按 `⌘V` 完成移动，或随时按 `Esc` / 在菜单栏点击「取消当前剪切」退出待移动状态。
4. 若在菜单栏选择了「隐藏菜单栏图标」，FinderCut 仍会在后台持续生效；之后随时通过启动台、聚焦搜索或 `/Applications/FinderCut.app` 再次打开即可恢复显示菜单栏图标。

## 工程结构

```text
FinderCut/
├── Sources/
│   ├── main.swift                   # 应用入口、单实例保护与权限/唤醒监控
│   ├── KeyInterceptor.swift         # CGEventTap 全局键盘拦截与剪切状态机
│   ├── KeyboardLayoutResolver.swift # 基于 TIS/UCKeyTranslate 的键位解析
│   ├── FocusInspector.swift         # AXUIElement 焦点与窗口防误触检查
│   ├── HUDController.swift          # 液态玻璃 / 圆角毛玻璃 HUD 浮窗与开关持久化
│   ├── SoundFeedbackManager.swift   # 轻量系统提示音反馈与开关持久化
│   ├── MenuBarController.swift      # 菜单栏状态展示、选项开关与语言切换
│   ├── LoginItemManager.swift       # SMAppService 登录项管理与设置跳转
│   ├── SupportManager.swift         # 菜单栏支持入口与低频本地提示
│   ├── UpdateChecker.swift          # GitHub Release 检查更新（手动与启动检查）
│   ├── AboutWindowController.swift  # 原生关于窗口（版本信息与快捷操作）
│   └── L10n.swift                   # 本地化与语言偏好持久化
├── Resources/
│   ├── Info.plist                   # Bundle 配置（LSUIElement=true、支持语言列表）
│   └── *.lproj/Localizable.strings  # 8 种语言本地化文案
├── docs/
│   └── index.html                   # 单文件响应式产品官网
└── build.sh                         # swiftc 编译、资源打包与签名脚本
```

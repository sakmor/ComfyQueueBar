<p align="center"><img src="../../assets/app-icon.png" width="112" alt="ComfyQueueBar 图标" /></p>

# ComfyQueueBar

**在 macOS 菜单栏，一键查看 ComfyUI 队列。** 查看正在运行的任务、当前节点进度，并决定下一个运行的任务。

[English](../../README.md) · **简体中文** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

## 看看它怎么用

**点击 macOS 菜单栏图标，即可展开队列面板。**

![macOS 桌面上的 ComfyQueueBar 菜单栏图标与队列面板](../images/desktop-menubar-annotated.png)

这是真实 macOS 桌面截图，面板使用文档演示模式与固定示例任务；不包含私人桌面内容或实时工作流。图中的英文提示表示“点击菜单栏图标”。App 界面目前为英文；本页提供简体中文使用说明。

<details>
<summary>查看浅色与深色界面</summary>

![浅色界面](../images/queue-light.png)
![深色界面](../images/queue-dark.png)

</details>

## 功能与要求

- 原生 SwiftUI 工具，没有 Dock 窗口，不使用 Electron 或第三方 Swift 包。
- 菜单栏显示运行中与等待中任务的总数；两份列表每 **4 秒**刷新。
- 显示工作流名称、简短 prompt ID、节点数与等待位置。
- **Prioritize（优先执行）**：确认后将等待中的任务移至队列前端。
- **Stop（停止）**：确认后请求中断正在运行的任务，保留等待队列。
- 安装可选的服务器扩展后，每 **1 秒**更新当前节点名称与百分比。
- 保存服务器地址，支持手动刷新、本地连接与 SSH 转发。

| 项目 | 要求 |
| --- | --- |
| Mac | macOS 13 Ventura 或更新版本 |
| 编译 | Swift 5.9 或更新版本，由适用的 Xcode／Command Line Tools 提供 |
| ComfyUI | 可访问 `/queue`、`/prompt`；停止指定任务需要 `/interrupt` 支持 `prompt_id` |
| 节点进度 | ComfyUI 提供 `comfy_execution.progress.ProgressHandler`、`add_progress_handler`、`execution.reset_progress_state` |
| 扩展环境 | 使用 ComfyUI 自身的 Python 环境与现有 `aiohttp` |

App 仅支持 macOS；远程 ComfyUI 可在 macOS、Linux 或 Windows 运行。构建生成当前 Mac 架构的程序，不是 universal binary。旧版或第三方 ComfyUI 的兼容性可能不同。

## 快速开始

### 1. 准备编译工具

```sh
xcode-select --install
swift --version
```

已安装工具可跳过安装。确认 Swift 至少为 5.9；版本过旧时更新 Command Line Tools，或选择适用的 Xcode。

### 2. 下载并构建

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash build-app.sh
open build/ComfyQueueBar.app
```

脚本编译 release 程序、创建 App bundle 并进行本地 ad-hoc 签名；只重新构建本仓库的 `build/ComfyQueueBar.app`，不会安装或启动 ComfyUI。

### 3. 连接

1. 启动现有的 ComfyUI。
2. 点击 macOS 菜单栏上的 ComfyQueueBar 图标。
3. 在 **ComfyUI address** 输入地址，通常为 `http://127.0.0.1:8188`。
4. 点击 **Connect**。
5. 在 ComfyUI 提交任务，下一次刷新时应出现在面板中。

空队列与未连接都可能显示 0，请查看面板的连接状态。也可直接检查：

```sh
curl --fail http://127.0.0.1:8188/queue
```

### 4. 启用节点进度（可选）

基本队列监控不需要扩展。要查看节点进度，请安装到**实际提供连接端点的 ComfyUI**：

```sh
bash install-comfyui-extension.sh /path/to/ComfyUI
# 路径包含空格时加上引号
bash install-comfyui-extension.sh "$HOME/AI Tools/ComfyUI"
```

等待生成结束后重启 ComfyUI，再检查：

```sh
curl --fail http://127.0.0.1:8188/comfyqueuebar/queue-progress
```

尚未报告进度时，响应中的 null 值是正常的。App 只显示 prompt ID 与运行中任务匹配的进度。**百分比是当前节点的进度，不是整个工作流的完成度**；切换节点时可能重新开始，部分节点不报告百分比。远程连接需要将扩展安装在服务器上。

## 安装与登录时启动

```sh
mkdir -p "$HOME/Applications"
cp -R build/ComfyQueueBar.app "$HOME/Applications/"
open "$HOME/Applications/ComfyQueueBar.app"
```

替换前先退出现有 App。需要登录时启动，可在 macOS“系统设置 → 通用 → 登录项”添加 App；名称可能随系统版本变化，App 不会自动注册。

## 操作的实际行为

**Prioritize** 使用 `front: true` 重新提交选中的工作流，再删除原来的等待项，因此 prompt ID 会改变，不会中断当前运行的任务。这是多次请求的操作；中途断线或原任务开始运行时，可能产生竞态或重复项。App 会尝试恢复，无法确认结果时报告 ID；重试前请先检查队列。

**Stop** 重新确认队列后，将选中的 prompt ID 发送到 `/interrupt`，不清除等待任务。兼容的服务器会中断指定任务，下一项可能接着开始。旧服务器可能忽略 ID，执行全局中断。

重新提交保留 `/queue` 返回的 prompt graph 与 `extra_data`，无法保留 API 未返回的私有字段或提交选项。含外部副作用或付费 API 节点的任务，重新提交前请确认影响。

## 隐私与远程连接

App 仅向设置的 ComfyUI 地址发送请求；没有分析、遥测、云端账号或更新检查。地址保存在 macOS user defaults，队列响应可能包含工作流 metadata。

扩展添加只读 JSON 路由，通过 ComfyUI 内部进度 registry 观察进度，并包装 reset 函数以便逐任务重新注册；不开 WebSocket、不修改队列。路由沿用服务器的网络暴露范围，**不会自动限制为 localhost**。建议使用可信网络或 SSH port forwarding。

App 没有自定义 API key、bearer token 或登录界面；请求会丢弃网址的 query 与 fragment，因此不支持 query-string 凭据。

## 更多文档（英文）

- [完整操作说明](../USAGE.md)
- [远程连接、SSH 与 Windows 设置](../REMOTE_SETUP.md)
- [故障排查、更新与卸载](../TROUBLESHOOTING.md)
- [架构、API、测试与兼容性](../DEVELOPMENT.md)
- [安全说明](../../SECURITY.md)、[贡献指南](../../CONTRIBUTING.md)、[更新日志](../../CHANGELOG.md)

## 许可与致谢

采用 [MIT 许可](../../LICENSE)。源自 AniClayFilm 仓库中供 [Clay Trouble](https://www.youtube.com/@ClayTrouble) 使用的工具；独立版本具有英文界面、独立 App identifier 与进度端点，不包含影片素材、工作流、模型或凭据。

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) 是独立项目；ComfyQueueBar 是社区工具，并非官方产品，也未附带 ComfyUI 源代码。

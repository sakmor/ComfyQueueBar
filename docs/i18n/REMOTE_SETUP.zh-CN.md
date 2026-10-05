# 远程 ComfyUI 设置教程

[English](../REMOTE_SETUP.md) · **简体中文** · [繁體中文](REMOTE_SETUP.zh-TW.md) · [日本語](REMOTE_SETUP.ja.md)

本教程涵盖 GPUtw 登录、辨认正确的 ComfyUI 服务、SSH 连接和远程 Mac 唤醒。App 一次监控一台服务器，数字代表该队列“运行中＋等待中”的任务数。

**适用版本：** GPUtw 内置登录、连接确认卡、连接状态符号和 Wake-on-LAN 自 v1.5.3 起提供。使用 v1.5.2 时，可在 App 设置中点击“检查更新…”。

## GPUtw 私有或密码保护的实例

### 登录并选择服务

1. 保持租用的实例运行。在 ComfyQueueBar 点击齿轮 → **登录 GPUtw…**。也可以在 **ComfyUI 地址** 中粘贴 `https://gputw.ai/dashboard`，点击 **连接** 打开相同流程。
2. 在 App 内的浏览器登录。Safari、Chrome 的登录状态不会自动共用。
3. 打开实例的 **ComfyUI Web UI**。如果生成使用其他已配置的 HTTP 端口，请从控制台打开该端口的 Web UI；密码保护的端口须在 GPUtw 页面输入密码。
4. 点击 **确认此 ComfyUI**，核对端口、运行中／等待中任务数以及最近三条成功任务。确认卡读取队列和最新最多 20 条历史；历史无法读取时会标为未知，队列验证失败则不能确认。
5. 点击 **监控此服务器**，才会保存并选用此 GPUtw 服务。点击 **取消** 会保留当前监控连接。主界面和菜单栏提示会显示选用的端口。
6. 可将 **服务器名称** 改成容易辨认的名称，例如 `GPUtw · 8090 · 视频生成`，再点击 **保存地址**。通过 GPUtw 重新连接会保留已有的自定义名称。

GPUtw 服务地址格式为 `https://<port>-<instance-id>.gputw.ai`。私有服务需要控制台建立所有者会话；密码保护的服务会先显示密码页。保持已有访问模式即可，此登录流程不需要平台 API 密钥或公开端口。参考 [GPUtw Web UI](https://docs.gputw.ai/zh-TW/docs/jupyter-web-ui) 和[端口访问模式](https://docs.gputw.ai/zh-TW/docs/ports)。

### GPU 很忙，但 App 显示 0

同一 GPU 实例的不同端口可能分别运行独立的 ComfyUI。例如 `8080` 打开默认服务，`8090` 运行自定义视频环境。这只是示例，实际端口以你提交任务的 ComfyUI 地址为准。

1. 比较生成页面的端口与 ComfyQueueBar 显示的端口。
2. 点击 **查看此连接**，或选择准备使用的已保存服务器，先查看近期任务。
3. 比对任务名称与完成时间。空队列加上不相关的历史可能代表连错服务；读不到历史不能视为任务已完成。
4. 如果正确服务的队列为空，查看 **最近完成** 和 **失败与中断**。任务可能已在两次刷新之间结束。

GPU 使用率和已分配 VRAM 都不是 ComfyUI 任务数。App 当前不读取 GPU 使用率、不自动搜索所有端口，也不合并多个服务的队列；只会每四秒检查选用的队列。不要仅因看到 0 就重新提交同一任务。

### 菜单栏符号

| 显示 | 含义 | 建议操作 |
| --- | --- | --- |
| `0` | 最新有效响应确认当前队列为空 | 若预期有任务，核对端口和近期记录 |
| `1`–`99`、`99+` | 运行中＋等待中任务数 | 打开面板看详情；菜单栏提示显示完整总数 |
| `—` | 连接断开、队列响应格式错误，或超过 30 秒未取得最新队列 | 检查连接；当前任务数未知 |
| `!` | 需要登录 | GPUtw 请重新登录并打开实例 Web UI |
| `…` | 等待首次队列响应 | 等待连接确认完成 |

取得有效队列后会自动恢复任务数。历史或节点进度读取失败不会把正常队列判为断开连接。0 本身不代表成功；成功任务必须有明确的成功历史记录。

### 登录、输出和恢复

- 登录过期时，再点击 **登录 GPUtw…**，打开正确端口、查看确认卡并确认。只打开控制台或 Jupyter 页面不能识别 ComfyUI 服务。
- **清除 GPUtw 登录** 会移除此 App 的浏览器登录数据，包括账号和实例会话；不会退出其他浏览器的登录或停止租用的 GPU。
- 保存的服务地址会移除 handoff 路径、query token 和 fragment。Cookie 留在 App 的 WebKit 存储区，不写入书签或 Agent 桥接文件。详见[安全说明](../../SECURITY.md)。
- 图片和下载会使用登录状态。受保护的视频预览会先下载临时副本，关闭或切换预览后移除；视频缩略图显示占位图标。
- 节点百分比需要将进度扩展安装到**同一套远程 ComfyUI**。Mac 上的安装按钮只安装到本机；云端服务器请按下方步骤操作。
- 如果身份提供者不允许内嵌浏览器登录，可以使用已有且兼容的 SSH 连接；不要为登录而停用访问控制。

## 唤醒远程 Mac

Wake-on-LAN 是每个已保存服务器的可选设置，通过 UDP 发送指定网卡 MAC 地址的 magic packet。它不会启动已停止的 GPUtw 租用实例、启动 ComfyUI 或建立 SSH 隧道。

### 设置与测试

1. 在目标 Mac 的系统设置中启用可用的 **唤醒以供网络访问** 选项。机型、供电、网络和 macOS 设置都会影响支持情况，参考 [Apple 唤醒说明](https://support.apple.com/en-gb/guide/mac-help/mh27905/mac)。
2. 在 ComfyQueueBar 输入目标 ComfyUI 地址和名称，点击 **保存地址**。保存书签不要求睡眠中的服务器立即响应。
3. 展开该地址下的 **唤醒 Mac**，填写目标网卡的 **MAC 地址**、网络允许的 **广播 IPv4 地址** 和 **UDP 端口**。默认值是 `255.255.255.255` 和 `9`，请根据实际网络调整。`02:11:22:33:44:55` 仅为示例 MAC。
4. 点击 **保存唤醒设置**，再点击 **立即唤醒**。立即唤醒也会先验证并保存界面上的设置。
5. “已发送唤醒数据包”仅表示本机发送成功。等待目标醒来且 ComfyUI 可连接，再选择书签、检查确认卡并点击 **监控此服务器**。
6. 如果需要，勾选 **离线时自动唤醒** 并再次保存。当前选用此服务器时，符合条件的网络离线错误可能触发数据包，每台服务器最多每两分钟一次。HTTP 错误和登录失败不会触发唤醒。取消勾选并保存即可停用。

运行 ComfyQueueBar 的 Mac 必须保持唤醒，App 必须持续运行。手动 **立即唤醒** 可用于任意已保存服务器；自动唤醒只处理当前选用的服务器，不会轮询其他书签。

### 目标仍在睡眠时

确认网卡 MAC、唤醒设置、供电状态以及 UDP 目标是否可达。广播包不会通过 App 的 SSH 隧道传送，也不会自动跨路由器／VPN 转发。请使用已有可用的局域网路径；App 不会配置路由器、防火墙或转发服务。发送成功不等于实体 Mac 已醒来；醒来后仍须确认 ComfyUI 和 SSH 隧道可用。

## SSH 连接与远程进度设置

以下示例使用本机 `18188`、远程 ComfyUI `8188`，请换成实际端口。

### 1. 确认远程服务

在运行 ComfyUI 的机器执行：

```sh
curl --fail http://127.0.0.1:8188/queue
```

使用原来的 ComfyUI 启动方式；本 App 不会安装 ComfyUI 或模型。

### 2. 从 Mac 建立隧道

```sh
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:18188:127.0.0.1:8188 user@your-server
```

替换 `user@your-server`。自定义 SSH 端口可加 `-p 2222`；需要私钥时加 `-i /path/to/private-key`，切勿提交私钥。本机端绑定 `127.0.0.1`，不向局域网开放。保持终端运行，Control-C 结束隧道。若 ComfyUI 在容器中，远程目标必须是 SSH 主机可达的端口；主机的 localhost 不一定是容器的 localhost。

### 3. 连接 App

```sh
curl --fail http://127.0.0.1:18188/queue
```

将 **ComfyUI 地址** 设为 `http://127.0.0.1:18188`，点击 **连接**，核对队列与历史，再点击 **监控此服务器**。独立的隧道端口不影响本机 `8188` 的 ComfyUI。App 不保存 SSH 凭据或自动重建 SSH 隧道，也不会让远程机器一直保持唤醒；隧道中断后需自行重开。

### 4. 安装远程进度扩展

Linux／macOS 服务器上执行：

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash install-comfyui-extension.sh /path/to/ComfyUI
```

也可以把本机的 `comfyui_extension/ComfyQueueBarProgress/` 复制到远程 `ComfyUI/custom_nodes/`。服务器不需要 Swift。目标文件应是 `ComfyUI/custom_nodes/ComfyQueueBarProgress/__init__.py`，不要多加一层目录。

Windows 请通过文件资源管理器把同一文件夹复制到实际安装位置的 `custom_nodes`；portable 版通常位于其 `ComfyUI` 子目录。手动复制不需要 Bash；只有选择 SSH 隧道时才需要 Windows SSH 服务器。

等待当前生成结束，再重新启动**该套** ComfyUI。从 Mac 通过同一隧道验证：

```sh
curl --fail http://127.0.0.1:18188/comfyqueuebar/queue-progress
```

## 直接使用局域网或 HTTPS

可信任局域网可使用 `http://192.0.2.10:8188` 一类地址，请换成真实地址。服务器须监听正确接口，防火墙与 macOS 本地网络权限须允许连接。

HTTPS 反向代理可使用 `https://comfy.example.com` 或 `https://comfy.example.com/comfy` 路径前缀，并转发 ComfyUI API 和 `/comfyqueuebar/queue-progress`；证书必须受 macOS 信任。非本机 HTTP 可能受系统传输安全限制，SSH loopback 隧道通常更容易配合现有 App 设置。

内置浏览器登录当前只针对 GPUtw。其他主机若需要自定义验证 header 或 query token，请使用兼容的 SSH 或已有可信任访问方式。不要仅为连接 App 就把 ComfyUI 公开到互联网。

自动测试使用模拟 API 和本机 UDP 接收器，不能证明每个 GPUtw 账号均可登录，或每种 Mac／网络都能实际唤醒。

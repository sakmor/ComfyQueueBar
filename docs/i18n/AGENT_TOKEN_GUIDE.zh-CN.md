# 把视频进度监控交给 App：Agent 省 token 实操教程

[English](../AGENT_TOKEN_GUIDE.md) · [简体中文](AGENT_TOKEN_GUIDE.zh-CN.md) · [繁體中文](AGENT_TOKEN_GUIDE.zh-TW.md) · [日本語](AGENT_TOKEN_GUIDE.ja.md)

视频生成可能需要数分钟甚至更久。如果 Agent 每隔几秒就发起新的模型回合、查询进度、解读回复，等待期间也会累积 token 消耗。ComfyQueueBar 让 App 持续监控指定任务，Agent 只在设置订阅、收到事件或你返回会话时处理结果。

**适合的场景：你已有 ComfyUI 视频任务，想知道何时完成，又不想让 Agent 反复查询进度。** 图片任务也适用。

## 1. 安装 App、MCP 和 skill

1. 从 [GitHub Release](https://github.com/sakmor/ComfyQueueBar/releases/latest) 下载最新版 Apple Silicon App。需要 macOS 13 以上；Intel Mac 请按 [README](../../README.md#build-from-source) 自行构建。
2. 打开 App，在齿轮设置中填写 ComfyUI 地址并连接。远程服务器可使用 [SSH 转发](../REMOTE_SETUP.md)。
3. 启用 **AI Agent 集成**，点击 **一键配置 Claude／Codex**。MCP adapter 需要 Python 3.9 以上；Codex 自动注册需要可用的 Codex CLI。
4. 查看设置结果。MCP 注册与 skill 安装分别报告，skill 安装成功不代表 MCP 已连接。
5. 重新打开 Agent 会话；若仍看不到工具，重启代理桌面 App。

设置会安装 adapter 与共享 skill，并备份被替换的配置／skill。升级 ComfyQueueBar 后，再次执行一键配置并重开会话。

App 必须持续运行，Mac 必须保持唤醒。休眠、关闭 App 或禁用集成期间不会继续监控。

## 2. 先确认连接

在 Codex 粘贴：

```text
$comfyqueuebar 检查连接，告诉我 App、ComfyUI 和历史记录是否可用。
```

Claude Code 使用：

```text
/comfyqueuebar 检查连接，告诉我 App、ComfyUI 和历史记录是否可用。
```

正常应报告 App 可用、ComfyUI 已连接、历史可用，以及运行中／等待中数量。零个任务可能只是空队列，请依据连接状态判断。

这一步只读取一次状态，不会提交任务或创建订阅。

## 3. 获取正确的 prompt ID

`prompt_id` 是 ComfyUI 为一次提交分配的完整标识符，不是工作流名称、文件名、节点 ID 或生成提示词。

- **Agent 或程序提交：** 使用 `/prompt` 响应中的完整 `prompt_id`。同一会话已有本次提交 ID 时，可让 Agent 直接使用。
- **ComfyUI 界面提交：** 在浏览器开发者工具的 Network 面板找到本次 `/prompt` 请求，查看 JSON 响应中的 `prompt_id`。确认提交时间与任务相符。
- **正在运行或排队：** `/queue` 中 `queue_running`、`queue_pending` 的每个任务数组，第二个字段是完整 ID。先确认是哪一个任务，不要默认第一条就是你的任务。

App 可能只显示缩短的 ID，不能用缩短版本订阅。将下方 `YOUR_PROMPT_ID` 替换为真实完整 ID。

## 4. 订阅一次，让 App 接手

在 Codex 粘贴：

```text
$comfyqueuebar 确认我已提交的 ComfyUI 视频任务，prompt ID 是 YOUR_PROMPT_ID。
只订阅这个任务，等待一次，不要反复查询进度。
报告实际状态与 subscription_id，方便我之后继续查询。
```

Claude Code 将第一行 `$comfyqueuebar` 改为 `/comfyqueuebar`。

Agent 确认连接，使用 App 返回的服务器地址创建订阅，并保存 `subscription_id`。若已有终态结果，直接处理；否则通常等待一次、最长 45 秒，主机限制可能让等待更短。

等待期间由程序检查事件，不会每秒调用模型。工具返回后，Agent 仍需使用模型解读结果。

| 状态 | 含义 | 下一步 |
| --- | --- | --- |
| queued | 正在排队 | 保存订阅 ID，稍后查询 |
| running | 正在执行 | 让 App 持续监控，稍后查询 |
| completed | 明确完成 | 请求输出引用或检查视频 |
| failed / interrupted | 明确失败或中断 | 查看错误，再决定后续操作 |
| unknown | 尚未确认 | 检查 ID、历史和服务器，不要视为成功 |

超时、断线、历史不可用属于等待／监控状态，不能直接推断成功或失败。订阅 ID 标识保存的监控记录，prompt ID 标识 ComfyUI 任务。

## 5. 收到 App 通知后再查询

在 App 设置中开启需要的完成／失败通知，并允许 macOS 通知。通知用于提醒你返回会话；App 通知遵循队列与通知设置，仍需读取订阅结果确认指定任务。

**标准 MCP 不会在视频完成时自动唤醒空闲的 Codex 或 Claude 会话。** App 会保存结果，等待你回来读取。不要让 Agent 每隔 45 秒重复等待，也不要创建每分钟唤醒模型的自动化。

稍后在 Codex 粘贴：

```text
$comfyqueuebar 继续查询订阅 YOUR_SUBSCRIPTION_ID。
读取已保存结果；如果尚未完成，只等待一次，不要循环查询。
```

重开会话后也可提供保存的 ID。Skill 通过 `resume_subscription` 接回原订阅，无需为同一查询重新创建订阅。

只读当前记录、不等待：

```text
$comfyqueuebar 读取订阅 YOUR_SUBSCRIPTION_ID 的已保存结果，这次不要等待。
```

## 6. 获取输出或安排下一步

Skill 默认简短报告状态。需要视频输出信息时明确请求：

```text
$comfyqueuebar 查询订阅 YOUR_SUBSCRIPTION_ID，若任务已完成，列出视频输出引用。
```

引用包含 ComfyUI 文件名、子文件夹和 `/view` URL，不代表视频已下载到 Agent 本机。也可在 App 完成历史中使用 **Preview & download…** 预览与下载。

后续处理请给出具体任务，例如“确认完成后，将视频下载到指定文件夹并检查时长”。下载、剪辑或再次提交需要相应工具和明确任务；skill 本身只查询既有任务。

完成、失败或中断后，本流程创建的验证订阅会结束监控，记录仍保留；从其他流程恢复的订阅不会随意取消。取消监控订阅不会停止 ComfyUI 任务。

## token 具体省在哪里？

| 阶段 | Agent 反复查询进度 | 使用 ComfyQueueBar |
| --- | --- | --- |
| 设置 | Agent 决定如何查询 | 确认连接并订阅一次 |
| 等待生成 | 模型回合查询、解读进度并决定再次查询 | App 定时器与 MCP 程序化等待监控，不调用语言模型 |
| 结果处理 | Agent 解读完成或错误 | 事件返回或你继续查询时解读结果 |

例如，视频生成需要 10 分钟，若每 10 秒发起一个模型回合检查，可能累积约 60 次检查。改为一次订阅、一次有界等待，再在完成后查询，可以避免这些重复进度回合。这是流程示例，**不是 token 基准测试或固定节省比例**；事件也可能提前结束等待。

减少的是等待期间重复的模型工作。订阅设置、工具结果、失败处理和后续视频处理仍使用 token。原本就由普通程序监控、没有模型反复参与时，额外节省可能很少。

## 常见问题

| 问题 | 处理方式 |
| --- | --- |
| 找不到 skill | 重新配置，确认安装成功，重开会话 |
| 有 skill 但没有 MCP 工具 | 查看注册结果与代理 MCP 列表；Claude Code 可用 `/mcp` |
| App 不可用 | 确认 App 运行、集成启用、Mac 未休眠；心跳过期会报告不可用 |
| 任务始终 unknown | 检查完整 ID、服务器和历史；删除历史不能证明完成 |
| 切换服务器后不更新 | 切回原服务器；旧订阅会暂停，不会自动迁移 |
| 优先执行后原任务消失 | Prioritize 重新提交并改变 prompt ID，确认新 ID 后订阅 |
| 等待超时 | 保存订阅 ID，收到通知后或稍后手动查询，不循环唤醒模型 |
| 想要自动继续 | 标准 MCP 不支持空闲唤醒；实验性 Claude Channels 需要验证入站推送，注册成功不等于可用 |

手动设置、传递模式和数据保存细节见 [完整集成文档（英文）](../AGENT_INTEGRATION.md)。查看 [skill 源文件](../../.agents/skills/comfyqueuebar/SKILL.md)。

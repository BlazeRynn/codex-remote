# Codex Remote

[English README](README.md)

`Codex Remote` 是一个面向本地 Codex 会话的 Flutter 客户端。你可以用它在桌面端或移动端查看线程、跟踪实时更新、继续对话、处理审批请求，以及对正在运行的会话进行 steer 或 interrupt。

## 仓库内容

- `app/`：Flutter 客户端，支持 Android、iOS、Windows、macOS、Linux
- `proxy/`：本地 `stdio tee` 代理，把 VS Code 中的 Codex 会话镜像到 WebSocket，供其他客户端接入

## 使用前准备

- 本地可用的 `codex` CLI
- Flutter，以及你要运行的平台对应的工具链
- 如果使用 `proxy/` 里的源码启动脚本，需要确保 `dart` 已加入 `PATH`

## 选择连接方式

### 1. 直连 App-Server

适用于客户端可以直接连接 Codex `app-server` 的场景。

1. 启动本地 app-server：

   ```bash
   codex app-server --listen ws://127.0.0.1:8766
   ```

2. 运行 Flutter 客户端：

   ```bash
   cd app
   flutter pub get
   flutter run
   ```

3. 在应用设置页填写 Codex app-server URL：

| 运行目标 | URL |
| --- | --- |
| 桌面端 / iOS 模拟器 | `ws://127.0.0.1:8766` |
| Android 模拟器 | `ws://10.0.2.2:8766` |

### 2. 共享 VS Code 当前会话

适用于你希望客户端接入 VS Code Codex 扩展正在使用的同一个实时会话。

1. 将 VS Code 配置项 `chatgpt.cliExecutable` 指向以下任一启动器：

   - Windows 源码启动器：`proxy/codex-proxy.cmd`
   - Windows 已构建可执行文件：`proxy/build/codex-proxy.exe`
   - macOS / Linux 源码启动器：`proxy/codex-proxy`

2. 在 VS Code 里完成配置：

   - 打开设置，搜索 `chatgpt.cliExecutable`
   - 或者直接编辑 `settings.json`

   示例：

   ```json
   {
     "chatgpt.cliExecutable": "<你的仓库路径>\\proxy\\codex-proxy.cmd"
   }
   ```

3. 不要在这个配置项里自己追加 `app-server` 或 `--listen`。当前 proxy
   只会接管 VS Code 正常发起的 `codex app-server` 启动流程。

4. 在 macOS 或 Linux 上，先给源码启动器增加可执行权限：

   ```bash
   chmod +x proxy/codex-proxy
   ```

5. 如果真实的 `codex` 可执行文件不在 `PATH` 中，需要在启动 VS Code 之前
   先设置 `CODEX_PROXY_REAL_CLI`，让 proxy 能找到它。

6. 像平常一样在 VS Code 中使用 Codex。代理会把同一条会话镜像到：

   ```text
   ws://127.0.0.1:8767
   ```

7. 在应用设置页填写 Codex app-server URL：

| 运行目标 | URL |
| --- | --- |
| 桌面端 / iOS 模拟器 | `ws://127.0.0.1:8767` |
| Android 模拟器 | `ws://10.0.2.2:8767` |

## 软件使用

### 首次进入

1. 先启动本地 `app-server`，或者启动 VS Code 共享会话对应的 `proxy`。
2. 打开应用，进入 `Codex 设置`。
3. 填写 Codex app-server URL，然后点击 `保存配置`。
4. 返回主页面后，如果线程列表没有立即出现，可以手动点一次 `刷新`。

### 线程列表页

主页面就是会话列表。顶部操作包括：

- `刷新`：重新加载线程列表和当前连接状态
- `新建会话`：创建新的 Codex 会话
- `App-server 日志`：查看实时 RPC 请求、返回、错误和事件
- `Codex 设置`：修改连接地址、主题、语言和通知设置

点击任意会话可以进入详情页。列表中也支持对会话做归档和恢复。

### 新建会话

1. 点击 `新建会话`。
2. 输入这个会话的首条提示词。
3. 按需选择模型。
4. 选择会话模式：

   - `不修改文件`
   - `仅当前项目`
   - `包含项目外路径`

5. 选择工作区来源：

   - provider 默认工作区
   - 当前已有会话使用过的工作区
   - 目录树中选择的路径

6. 点击 `创建`。

### 在会话里操作

会话详情页会显示消息内容、操作时间线、实时连接状态，以及当前等待处理的请求。

底部输入区可以执行这些操作：

- 输入下一条提示词
- 切换模型
- 切换后续提示词的权限模式
- 添加图片或文件附件
- 从剪贴板粘贴受支持的内容
- 发送提示词

如果当前 turn 还在运行，并且输入框为空，发送按钮会自动变成 `Stop response`，用于中断当前输出。

### 处理请求与排查问题

- approval、user-input、MCP 请求会出现在会话底部的待处理区域。
- 简单请求可以直接点按钮处理；结构化请求会打开表单弹窗，填写后点击 `Submit` 提交。
- 如果请求里带有 URL，应用可以直接复制到剪贴板。
- `App-server 日志` 提供实时 RPC 追踪，支持搜索和按调用、返回、错误、事件过滤；当会话行为异常时，这里是最直接的排查入口。

### VS Code Proxy 自查项

如果应用没有接入 VS Code 正在使用的同一条会话，优先检查：

- `chatgpt.cliExecutable` 是否真的指向了 `proxy/codex-proxy.cmd`、
  `proxy/codex-proxy` 或你自己构建出的 proxy 可执行文件
- 这个配置项里是否错误地追加了 `app-server` 或 `--listen`
- 真实 `codex` CLI 是否在 `PATH` 中，或者是否设置了 `CODEX_PROXY_REAL_CLI`
- 应用里填写的是否是 `ws://127.0.0.1:8767`，或者你自定义后的镜像地址
- `App-server 日志` 和 proxy 的 `stderr` 输出里是否能看到 proxy 已正常启动

## 应用可以做什么

- 查看线程列表和线程详情
- 跟踪实时更新和操作时间线
- 创建线程并继续发送 follow-up prompt
- 对活动 turn 执行 steer 或 interrupt
- 处理 approval、user-input、MCP 请求
- 切换主题、语言，并开启 approval、final answer、realtime error 通知

## Proxy 可选项

代理默认镜像地址为 `ws://127.0.0.1:8767`。

可选环境变量：

- `CODEX_PROXY_MIRROR_WS`：覆盖镜像 WebSocket 地址
- `CODEX_PROXY_REAL_CLI`：显式指定真实 `codex` 可执行文件路径
- `CODEX_PROXY_DEBUG=1`：向 `stderr` 输出代理日志

## 更多模块说明

- [`app/README.md`](app/README.md)
- [`proxy/README.md`](proxy/README.md)

## 说明

- 客户端通过 WebSocket JSON-RPC 与 Codex 通信。
- 这个仓库本身不提供 relay server，也不负责公网暴露。
- 如果你需要远程访问，请在本地端点前面自行加上网络边界，例如 `frp`。

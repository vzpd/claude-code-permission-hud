# claude-code-permission-hud

[English](README.md) · **中文**

一个极小的 macOS 弹窗工具，**只在 Claude Code 真正需要你授权时才弹出**，避免你切到别的窗口时错过权限请求。

## 为什么做这个

Claude Code 内置的权限提示在终端里。如果你切走做别的事，根本察觉不到它在等你 —— Claude 就一直干瞪眼，直到你切回来才发现。

macOS 系统通知好一点，但会自动消失，也很容易错过。这个工具展示一个**一直停留、点击才关闭的 HUD**，浮在所有空间最上层，还有提示音；只在 Claude 真会弹权限提示的那一刻触发 —— allowlist 命中或 auto 模式自动放行的调用都静默，不打扰。

## 环境要求

- macOS（在 Apple Silicon 上测过；Intel 理论上也能跑）
- Xcode Command Line Tools（`xcode-select --install`），提供 `swiftc`
- 已安装 Claude Code，且 `~/.claude/settings.json` 可写

## 安装

```bash
git clone https://github.com/vzpd/claude-code-permission-hud.git
cd claude-code-permission-hud
./install.sh
```

脚本会编译二进制，复制到 `~/.claude/hooks/claude-notify`，并打印一段需要合并到 `~/.claude/settings.json` 的 JSON 配置。

## 配置

把下面这段合并进 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/claude-notify notify '需要你的授权批准' &"
          }
        ]
      }
    ]
  }
}
```

- `matcher: "permission_prompt"` 是 Claude Code 专门给"我需要授权"这个场景的信号。在 `default` 和 `auto` 两种模式下都只在真会弹权限时触发。
- 命令末尾的 `&` 让 HUD 进程后台化，hook 立即返回。
- 引号里的字符串是 HUD 正文，可以改成任何你想要的。

## 验证

```bash
~/.claude/hooks/claude-notify notify "hello from claude-notify"
```

屏幕右上角应该出现一个小 HUD，伴随 Glass 提示音。任意点击关闭。

## 环境变量配置

所有行为都通过环境变量控制（在 hook 命令字符串里设置）。全都是可选的 —— 默认值开箱即用。

| 变量 | 可选值 | 默认 | 作用 |
|---|---|---|---|
| `CLAUDE_NOTIFY_LANG` | `zh*` / `en*` | 跟随系统 locale | UI 语言。不是 `zh` 或 `en` 开头就回退英文。 |
| `CLAUDE_NOTIFY_SOUND` | 任意 NSSound 名字 / `none` / `off` / `0` | `Glass` | HUD 提示音。设 `none` 静音。 |
| `CLAUDE_NOTIFY_DEBUG` | `1` | 未设 | 把解析的 stdin、当前 locale、决策输出打到 stderr。 |

组合示例：

```json
"command": "CLAUDE_NOTIFY_LANG=en CLAUDE_NOTIFY_SOUND=none /Users/you/.claude/hooks/claude-notify notify &"
```

欢迎 PR 给 `src/main.swift` 里的 `L10n` 加更多语言。

## 查看版本

```bash
claude-notify --version
```

版本号是编译时从 `git describe` 注入的（带 tag 的正式版显示像 `v0.2.0`，本地构建显示像 `a65168d-dirty`）。

## 自定义界面

颜色、尺寸、位置、标题、字体都硬编码在 `src/main.swift` 里。改完重编：

```bash
make install
```

## 卸载

```bash
make uninstall
```

然后把 `~/.claude/settings.json` 里对应的 hook 条目删掉。

## 开发

```bash
make build      # 编译到 build/claude-notify（当前架构）
make test       # 非交互式回归测试
make run        # 编译 + 显示一个示例 HUD
make install    # 编译 + 复制到 ~/.claude/hooks/
make universal  # 打包成 arm64 + x86_64 的 fat binary，用于发布
make clean      # 清理 build/
```

## 疑难排查

### HUD 不出现

1. 手动跑一下：`~/.claude/hooks/claude-notify notify "test"`。如果什么都没出，问题出在二进制本身或 macOS 权限。
2. 检查可执行权限：`ls -l ~/.claude/hooks/claude-notify`。
3. Hook 没触发？开调试日志：让 Claude Code 做一件需要授权的事，然后看 Claude Code 终端的 stderr —— 应该能看到 `[claude-notify] debug: startup: args=...`。

### HUD 出了但没声音

- 是不是设了静音？检查 `CLAUDE_NOTIFY_SOUND`。
- macOS 提示音音量是不是关了？系统设置 → 声音 → 声音效果。

### HUD 出在错的屏幕

HUD 始终渲染在 `NSScreen.main` 上 —— macOS 定义为"当前活跃应用所在的屏幕"。如果 Claude Code 在副屏，HUD 就跟过去。

### `approve` 模式卡住 / Claude Code 超时

- 确认 hook 命令**没有**末尾的 `&`。有 `&` 的话 hook 立刻返回，Claude Code 拿不到决策 JSON。
- 打开 `CLAUDE_NOTIFY_DEBUG=1` 看 stderr 日志 —— HUD 渲染了吗？stdin 解析失败了吗？
- 如果 HUD 进程被你或 macOS 杀掉，内置的 SIGTERM handler 应该会自动输出一个 fallback `ask` 决策。验证方法：`echo '{"tool_name":"Bash"}' | ~/.claude/hooks/claude-notify approve &` 然后 `kill -TERM <pid>`，stdout 应该有一条合法的 `ask` JSON。

### `approve` 模式下连 allowlist 里的工具也弹 HUD

这是 Claude Code 的设计约束，不是 bug。`PreToolUse` 对所有匹配的工具都会触发，不看 allowlist。请收窄 `matcher` 正则 —— 见下面的 **进阶：approve 模式**。

### `make build` 报 "statements are not allowed at the top level"

你把源文件改了名或加了额外的 Swift 文件。入口必须是 `src/main.swift`，Makefile 依赖这个约定。

---

## 进阶：approve 模式

二进制还带了第二种模式 —— `claude-notify approve` —— 会弹出一个**更大的 HUD，带三个按钮（允许 / 问我 / 拒绝）**，直接把你的选择作为权限决策返回给 Claude Code。不用切回终端，点一下就完事。

**代价：** `approve` 挂在 `PreToolUse` hook 上，它会对**每一次**匹配到的工具调用触发 —— 包括已经在 `permissions.allow` 里的工具。Claude Code 没提供"只在会弹提示时触发"的信号，所以你必须把 matcher 写得足够窄，避免 HUD 疲劳。

### 配置

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/claude-notify approve",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

- **不要加 `&`** —— hook 必须一直活着等你点按钮，它的 stdout 是你的决策要回传给 Claude Code。
- `matcher` 是一个匹配工具名的正则。按需放宽或收窄。写成 `""` 或 `".*"` 意味着每次工具调用都弹 HUD，通常太激进。
- `timeout` 单位是秒。

### 按钮

| 按钮 | 键盘 | 结果 |
|---|---|---|
| 允许 / Allow | Return | `permissionDecision: "allow"` —— 工具立刻执行 |
| 问我 / Ask | Esc | `permissionDecision: "ask"` —— 回退到 Claude Code 的原生提示 |
| 拒绝 / Deny | — | `permissionDecision: "deny"` —— 阻止工具执行，Claude 收到拒绝原因 |
| ✕ 关闭 | — | 同 **问我 / Ask** |

### 手动测试

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | ~/.claude/hooks/claude-notify approve
# 点一个按钮，stdout 会打印决策 JSON。
```

### 注意

即使你点了允许，Claude Code 仍然会尊重 `permissions.deny`。HUD 的允许盖不过 denylist，这是有意设计。

---

## Roadmap

- CLI flag 定制位置 / 声音 / 颜色
- Deny 时可填自由文本原因
- 可选：hook 里镜像 `permissions.allow`，让 `approve` 模式对 allowlist 工具自动放行，接近"只在会弹时才触发"的效果
- Linux / Windows 移植

欢迎 PR。

## License

MIT —— 见 [LICENSE](LICENSE)。

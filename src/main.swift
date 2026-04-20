import Cocoa
import Darwin
import Foundation

// MARK: - Protocol types

// PreToolUse decision values Claude Code accepts. Kept strict so typos fail at compile time.
enum PermissionDecision: String {
    case allow
    case ask
    case deny
}

// MARK: - Logging

// Writes to stderr so hook output (stdout) stays clean for Claude Code's JSON parser.
func log(_ msg: String) {
    FileHandle.standardError.write(Data("[claude-notify] \(msg)\n".utf8))
}

// Opt-in verbose logging via CLAUDE_NOTIFY_DEBUG=1. Noise-free by default.
let isDebug = ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_DEBUG"] == "1"

func debug(_ msg: @autoclosure () -> String) {
    guard isDebug else { return }
    log("debug: \(msg())")
}

// MARK: - Localization

struct L10n {
    let name: String
    let defaultNotifyMsg: String
    let unparsableInput: String
    let noCommand: String
    let unknownArgs: String
    let btnAllow: String
    let btnAsk: String
    let btnDeny: String
    let titlePrefix: String

    static let zh = L10n(
        name: "zh",
        defaultNotifyMsg: "需要你的授权批准",
        unparsableInput: "(无法解析工具参数，请在终端确认)",
        noCommand: "(无命令)",
        unknownArgs: "(未知参数)",
        btnAllow: "允许",
        btnAsk: "问我 (esc)",
        btnDeny: "拒绝",
        titlePrefix: "⚡ Claude Code · "
    )

    static let en = L10n(
        name: "en",
        defaultNotifyMsg: "Claude Code needs your approval",
        unparsableInput: "(Could not parse tool args; confirm in terminal)",
        noCommand: "(no command)",
        unknownArgs: "(unknown args)",
        btnAllow: "Allow",
        btnAsk: "Ask (esc)",
        btnDeny: "Deny",
        titlePrefix: "⚡ Claude Code · "
    )
}

// CLAUDE_NOTIFY_LANG overrides the system locale. Accepts "zh", "en", or any
// locale code starting with those prefixes.
func resolveLocale() -> L10n {
    let env = ProcessInfo.processInfo.environment
    let raw = env["CLAUDE_NOTIFY_LANG"]
        ?? Locale.preferredLanguages.first
        ?? "en"
    let lower = raw.lowercased()
    if lower.hasPrefix("zh") { return .zh }
    return .en
}

let l10n = resolveLocale()

// MARK: - Sound

// NSSound name resolved from CLAUDE_NOTIFY_SOUND; "none"/"off"/"0"/"" disable audio.
func playHUDSound() {
    let raw = ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_SOUND"] ?? "Glass"
    let normalized = raw.lowercased()
    if normalized.isEmpty || ["none", "off", "0", "silent", "mute"].contains(normalized) {
        debug("sound disabled (CLAUDE_NOTIFY_SOUND=\(raw))")
        return
    }
    NSSound(named: raw)?.play()
}

// MARK: - Windows

// Borderless windows don't become key by default, which blocks NSButton keyEquivalents.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ClickToDismissView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {
        fadeAndTerminate(window: self.window)
    }
}

func fadeAndTerminate(window: NSWindow?) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        window?.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

// MARK: - Entry

let args = CommandLine.arguments
debug("startup: args=\(args) locale=\(l10n.name) version=\(CLAUDE_NOTIFY_VERSION)")

if args.count >= 2 && (args[1] == "--version" || args[1] == "-v") {
    print(CLAUDE_NOTIFY_VERSION)
    exit(0)
}

if args.count >= 2 && args[1] == "approve" {
    runApproveMode()
} else {
    let msg: String
    if args.count >= 2 && args[1] == "notify" {
        msg = args.count >= 3 ? args[2] : l10n.defaultNotifyMsg
    } else if args.count >= 2 {
        msg = args[1]
    } else {
        msg = l10n.defaultNotifyMsg
    }
    runNotifyMode(message: msg)
}

// MARK: - Notify mode

func runNotifyMode(message: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    guard let screen = NSScreen.main else { exit(0) }
    let w: CGFloat = 320
    let h: CGFloat = 56
    let x = screen.visibleFrame.maxX - w - 16
    let y = screen.visibleFrame.maxY - h - 8

    let window = NSWindow(
        contentRect: NSRect(x: x, y: y, width: w, height: h),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let visual = ClickToDismissView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    visual.material = .hudWindow
    visual.state = .active
    visual.wantsLayer = true
    visual.layer?.cornerRadius = 12
    visual.layer?.masksToBounds = true
    window.contentView = visual

    let title = NSTextField(labelWithString: "⚡ Claude Code")
    title.font = NSFont.boldSystemFont(ofSize: 13)
    title.textColor = .white
    title.frame = NSRect(x: 16, y: 28, width: w - 50, height: 18)
    visual.addSubview(title)

    let body = NSTextField(labelWithString: message)
    body.font = NSFont.systemFont(ofSize: 12)
    body.textColor = NSColor.white.withAlphaComponent(0.7)
    body.frame = NSRect(x: 16, y: 10, width: w - 50, height: 16)
    visual.addSubview(body)

    let close = NSTextField(labelWithString: "✕")
    close.font = NSFont.systemFont(ofSize: 14)
    close.textColor = NSColor.white.withAlphaComponent(0.5)
    close.frame = NSRect(x: w - 30, y: 18, width: 20, height: 20)
    visual.addSubview(close)

    window.alphaValue = 0
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)

    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        window.animator().alphaValue = 1
    }

    playHUDSound()
    app.run()
}

// MARK: - Approve mode

final class ApproveController: NSObject {
    let window: NSWindow
    var didDecide = false

    init(window: NSWindow) {
        self.window = window
    }

    @objc func allowClicked() { decide(.allow, reason: "Approved via HUD") }
    @objc func askClicked()   { decide(.ask,   reason: "Deferred to default prompt via HUD") }
    @objc func denyClicked()  { decide(.deny,  reason: "Denied via HUD") }
    @objc func closeClicked() { decide(.ask,   reason: "HUD dismissed without explicit choice") }

    private func decide(_ decision: PermissionDecision, reason: String) {
        guard !didDecide else { return }
        didDecide = true
        emitDecision(decision, reason: reason)
        fadeAndTerminate(window: window)
    }
}

// Keep the controller alive for the full lifetime of the run loop. NSButton.target
// is weak, so a function-local ref could be released early under -O.
var approveController: ApproveController?

// Best-effort guard for racing between a button click and a termination signal.
// Not strictly atomic; worst case is a duplicate write Claude Code's parser
// discards, or a truncated write that falls back to the default prompt.
nonisolated(unsafe) var responseAlreadyWritten: Int32 = 0

// Signal-safe fallback: if Claude Code's hook timeout kills us before the user
// clicks, emit an "ask" decision so the default prompt still runs. Uses only
// async-signal-safe calls (write, strlen, _exit).
@_cdecl("handleTermSignal")
func handleTermSignal(_ sig: Int32) {
    if responseAlreadyWritten != 0 { _exit(0) }
    responseAlreadyWritten = 1
    let payload = "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"HUD terminated by signal\"}}\n"
    payload.withCString { ptr in
        _ = write(STDOUT_FILENO, ptr, strlen(ptr))
    }
    _exit(0)
}

func runApproveMode() {
    // Register before reading stdin so a fast timeout still gets a response.
    signal(SIGTERM, handleTermSignal)
    signal(SIGHUP,  handleTermSignal)

    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    debug("approve: stdin=\(stdinData.count) bytes")

    // If stdin is empty or unparseable, there's nothing useful to show — defer
    // to Claude Code's built-in prompt instead of trapping the user in a HUD
    // with no context.
    guard !stdinData.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any],
          let toolName = json["tool_name"] as? String
    else {
        log("approve: empty or unparseable stdin, deferring to default prompt")
        emitDecision(.ask, reason: "HUD: no parseable PreToolUse input; deferring")
        exit(0)
    }
    let toolInput = json["tool_input"] as? [String: Any] ?? [:]
    debug("approve: tool_name=\(toolName) tool_input=\(toolInput)")
    let preview = formatToolInput(toolName: toolName, toolInput: toolInput)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    guard let screen = NSScreen.main else {
        log("approve: NSScreen.main unavailable, deferring")
        emitDecision(.ask, reason: "No main screen available")
        exit(0)
    }
    let w: CGFloat = 440
    let h: CGFloat = 180
    let x = screen.visibleFrame.maxX - w - 16
    let y = screen.visibleFrame.maxY - h - 8

    let window = KeyableWindow(
        contentRect: NSRect(x: x, y: y, width: w, height: h),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    visual.material = .hudWindow
    visual.state = .active
    visual.wantsLayer = true
    visual.layer?.cornerRadius = 12
    visual.layer?.masksToBounds = true
    window.contentView = visual

    let controller = ApproveController(window: window)
    approveController = controller

    let title = NSTextField(labelWithString: "\(l10n.titlePrefix)\(toolName)")
    title.font = NSFont.boldSystemFont(ofSize: 13)
    title.textColor = .white
    title.frame = NSRect(x: 16, y: h - 30, width: w - 50, height: 18)
    visual.addSubview(title)

    let close = NSButton(title: "✕", target: controller, action: #selector(ApproveController.closeClicked))
    close.isBordered = false
    close.bezelStyle = .regularSquare
    close.attributedTitle = NSAttributedString(
        string: "✕",
        attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            .font: NSFont.systemFont(ofSize: 14),
        ]
    )
    close.frame = NSRect(x: w - 32, y: h - 32, width: 22, height: 22)
    visual.addSubview(close)

    // Body sizes to its content (capped at 3 lines by maximumNumberOfLines)
    // so a one-line command doesn't leave a big empty band.
    let body = NSTextField(wrappingLabelWithString: truncateForDisplay(preview))
    body.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    body.textColor = NSColor.white.withAlphaComponent(0.85)
    body.lineBreakMode = .byTruncatingTail
    body.maximumNumberOfLines = 3
    body.preferredMaxLayoutWidth = w - 32
    let bodyHeight = min(body.fittingSize.height, 66)
    body.frame = NSRect(x: 16, y: h - 30 - bodyHeight - 4, width: w - 32, height: bodyHeight)
    visual.addSubview(body)

    let btnY: CGFloat = 16
    let btnH: CGFloat = 28
    let btnW: CGFloat = 104
    let spacing: CGFloat = 12
    let totalBtnW = btnW * 3 + spacing * 2
    let startX = (w - totalBtnW) / 2

    let allowBtn = makeButton(title: l10n.btnAllow, key: "\r",
                              target: controller, action: #selector(ApproveController.allowClicked))
    allowBtn.frame = NSRect(x: startX, y: btnY, width: btnW, height: btnH)
    allowBtn.bezelColor = NSColor.systemBlue
    visual.addSubview(allowBtn)

    let askBtn = makeButton(title: l10n.btnAsk, key: "\u{1b}",
                            target: controller, action: #selector(ApproveController.askClicked))
    askBtn.frame = NSRect(x: startX + btnW + spacing, y: btnY, width: btnW, height: btnH)
    visual.addSubview(askBtn)

    let denyBtn = makeButton(title: l10n.btnDeny, key: "",
                             target: controller, action: #selector(ApproveController.denyClicked))
    denyBtn.frame = NSRect(x: startX + (btnW + spacing) * 2, y: btnY, width: btnW, height: btnH)
    denyBtn.bezelColor = NSColor.systemRed
    visual.addSubview(denyBtn)

    window.alphaValue = 0
    // makeKeyAndOrderFront (not orderFrontRegardless used in notify mode) so
    // Return/Esc keyEquivalents on the buttons fire — they require a key window.
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(allowBtn)
    NSApp.activate(ignoringOtherApps: true)

    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        window.animator().alphaValue = 1
    }

    playHUDSound()
    app.run()
}

func makeButton(title: String, key: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action)
    b.bezelStyle = .rounded
    b.keyEquivalent = key
    return b
}

// Emit the PreToolUse decision JSON to stdout (Claude Code reads this back).
func emitDecision(_ decision: PermissionDecision, reason: String) {
    debug("emit: decision=\(decision.rawValue) reason=\(reason)")
    let payload: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision.rawValue,
            "permissionDecisionReason": reason,
        ]
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
        log("emitDecision: JSON serialization failed for decision=\(decision.rawValue)")
        return
    }
    // Claim the response slot before writing so the signal handler doesn't
    // double-emit on a concurrent SIGTERM.
    responseAlreadyWritten = 1
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// Map common tool inputs to a one-glance preview string; unknown tools get pretty JSON.
func formatToolInput(toolName: String, toolInput: [String: Any]) -> String {
    switch toolName {
    case "Bash":
        return (toolInput["command"] as? String) ?? l10n.noCommand
    case "Edit":
        return "Edit: \((toolInput["file_path"] as? String) ?? "?")"
    case "Write":
        return "Write: \((toolInput["file_path"] as? String) ?? "?")"
    case "Read":
        return "Read: \((toolInput["file_path"] as? String) ?? "?")"
    case "Glob":
        return "Glob: \((toolInput["pattern"] as? String) ?? "?")"
    case "Grep":
        return "Grep: \((toolInput["pattern"] as? String) ?? "?")"
    default:
        if let data = try? JSONSerialization.data(withJSONObject: toolInput, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return l10n.unknownArgs
    }
}

func truncateForDisplay(_ s: String, limit: Int = 240) -> String {
    if s.count <= limit { return s }
    let idx = s.index(s.startIndex, offsetBy: limit)
    return String(s[..<idx]) + "…"
}

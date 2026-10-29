---
name: chatgpt-dot-fix
description: Fix the ChatGPT Windows desktop app (OpenAI Codex MSIX) "Messaging account changed" failure — clicking a dot/thread in the sidebar shows a full-window "ChatGPT 遇到了问题 / 出了点问题。请重试以继续" error boundary. Detect via GUI sampling, recover by cold-restarting the app through its normal AUMID, then verify the dot view with continuous dot-tab + message-editor sampling. Use when any dot/thread page in the ChatGPT desktop app breaks with the retry/update error screen, when "Messaging account changed" (AbortError, errorCode 20) appears in Codex desktop logs, or when HTTP 432 "Workspace routing is unavailable" bursts show up.
---

# ChatGPT desktop dot 修复（Messaging account changed）

2026-10-29/30 在 ChatGPT 桌面版（OpenAI.Codex MSIX 26.1023 / 26.1027，Win10/11）上闭环验证。
症状固定：点侧栏 dot → 整窗错误边界「ChatGPT 遇到了问题 / 出了点问题。请重试以继续」。

## 根因链（源码级已证，勿再走弯路）

1. 主进程 `getBackendRequestAuth({refreshToken:false})` 失败 → 本地合成 HTTP 432
   `"Workspace routing is unavailable"`（发出请求前，early-bootstrap L761）。
2. 432 打到 `/accounts/check` 等 → 渲染层 react-query `['accounts','check']` 进入 error
   （其 retry 只覆盖一次 5xx，432 不重试）→ `Ob=false` → `IC=false`。
3. dot 视图 `assertCurrent()` 抛 `DOMException("Messaging account changed","AbortError")`
   （app-initial L354，该字面量全文唯一）→ AppRoute 错误边界。
4. 关键死锁：原生账号订阅 `e_='error'` 时，queryFn **第一行**就 throw
   `Account input subscription unavailable` —— 因此 focus / reconnect / 手动 refetch /
   错误页 Retry / Ctrl+R **全部源码级无效**（均已实测失败）。
5. 唯一可靠恢复 = 冷启动应用（新进程重建原生订阅）。多次重启实例当场恢复；
   应用内手段从未恢复过。

## 已证无效的手法（别再试）

- 错误页「重试」按钮、Ctrl+R、窗口重新聚焦、navigate_to_codex_page（返回 window not ready）。
- hosts 固定正确 A 记录 — 未防复发。
- 给 ChatGPT.exe 挂本地代理（ProxiFyre）— 无效果。
- 等待 — durable WS 会自愈，但 UI 错误态不会消失。

背景噪音：日志里 `artifact_session_host_start_deferred`（每 5.5s 一次的守护进程崩溃循环）
与此故障**无关**（dot 正常期同样在刷）。复发规律：启动后约 1–2 小时被 432 突发打死，
属上游客户端/服务端缺陷，重启只是恢复不是根治。

## 修复流程（主会话驱动，集中控制 GUI）

前置：Windows；目标 dot 的侧栏完整名字（必传 `-DotName`，如 `'🔴你的dot名🔴'`）。
找进程：

```powershell
Get-Process ChatGPT | ? { $_.Path -like '*WindowsApps\OpenAI.Codex_*' -and $_.MainWindowHandle -ne 0 } | Select Id,MainWindowHandle,Path
```

1. **检测**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dot-verify.ps1 `
  -TargetPid <pid> -Handle <hwnd> -Action OpenDot -ObserveSeconds 8 `
  -DotName '<你的dot名>' -Out <本轮新json绝对路径>
```

   exit 0 = 健康（dotTab+editor 连续可用且无错误）→ 结束。exit 2（errorSeen）= 本故障。

2. **重启**：`scripts/restart-app.ps1 -TargetPid <pid> -Out <new.json>`。
   先 CloseMainWindow 15s，未退则 `taskkill /T /F`（仅该 PID 树），再用
   `explorer.exe shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App` 正常身份重启，
   等新主窗口 ≤150s + 静置 10s。
3. **验证 ×2**：约 25s 后 OpenDot 15s 观测；再约 75s 后重复（都要带 `-DotName`）。
   两次 exit 0 才算恢复。可用 `-Action Capture -Image <new.png>` 留图给用户目视。
4. 所有动作走 evidence-gate（`gate.py run`），每次全新 Out/Image，禁止覆盖；
   collector exit 0 ≠ 业务成功，必须读 JSON 核 `dotTab/editorEnabled/errorSeen/finalWindowOk`。

## 边界（硬性）

- 不 patch 账号一致性守卫、不伪造 IC/Ob、不注入 always-allow。
- 不碰 auth.json/token/cookie/账号 ID，不改模型/绑定，不重装代理/hosts。
- 恢复期间不向任何线程发消息。
- 重启会丢失未发送的输入框草稿 —— 执行前告知用户。
- 每次恢复后如实说明"已恢复，但上游缺陷未修，约 1–2 小时后可能复发，复发即重跑本 skill"。

## 脚本

- `scripts/dot-verify.ps1` — 检测+验收（dot-cycle/v2 血统，`-DotName` 必传；
  UTF-8 BOM，AST 0 错，真实实例冒烟 exit 0）。
- `scripts/restart-app.ps1` — 冷启动重启（restart-app/v1，实测 taskkill exit 0 +
  AUMID 拉起 + 14.2s 出窗）。

## 证据与同步

闭环证据（2026-10-29/30，两轮 15s 连续 green + 证据链 validate 通过）保存在本机
evidence 目录，未入库。仓库即本地技能目录原地 init（单源），改完直接 `git push` 同步。

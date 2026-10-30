---
name: chatgpt-dot-fix
description: Fix the ChatGPT Windows desktop app (OpenAI Codex MSIX) "Messaging account changed" / "ChatGPT 遇到了问题" / "hit a snag" failure and its hourly recurrence. Two-layer repair proven 2026-10-30 - (1) prune stale thread-index rows in the shared CODEX_HOME state db that make the app-server choke every hour, (2) cold-restart recovery via the app's normal AUMID when a window still kills the view. Includes detection script, restart script, and the full root-cause chain. Use when any dot/thread page in the ChatGPT desktop app breaks with the retry/update error screen, when "Messaging account changed" (AbortError, errorCode 20) or "Workspace routing is unavailable" (local 432) appear in Codex desktop logs, or when the app crashes/flashes around :23 past each hour.
---

# ChatGPT desktop dot 修复（Messaging account changed / 每小时闪崩）

2026-10-29/30 在 ChatGPT 桌面版（OpenAI.Codex MSIX 26.1023/26.1027，Win10/11）闭环验证。
症状三面孔（同一根因链）：
- 中文全窗错误：「ChatGPT 遇到了问题 / 出了点问题。请重试以继续」；
- 英文全窗错误："ChatGPT hit a snag / Something went wrong. Try again to continue"（UIA 树可能整个为空）；
- 顶部橙色警告条：「账户身份验证不可用 - 桌面端无法从本地 Codex 服务 (app-server) 获取可用的账户身份验证信息」。

## 根因链（2026-10-30 全链实证）

1. **桌面每小时主动 recycle app-server**（设计内行为：日志里 `app_server_connection.closed code=0`
   与同毫秒 `Starting app-server connection`；并非外部进程所为——曾误判"外部定时器"，父进程
   监视证实重启实例的父进程就是 ChatGPT.exe 自己）。
2. recycle 交接瞬间，新 app-server 实例重读/重写 **CODEX_HOME**：
   `Invalid configuration; using defaults`、`failed to write models cache: 拒绝访问 (os error 5)`、
   `failed to reload config ... os error 5`——与前任实例的文件句柄/并发写互撞。
3. **本机放大器（已修）**：共享 CODEX_HOME 的 `state_5.sqlite` `threads` 表里存在**孤儿索引行**
   （rollout_path 指向多次 home 迁移后已不存在的文件，如 `C:\Users\<u>\.codex\archived_sessions\`、
   旧 home 路径）。上游 `codex-rs/rollout/src/state_db.rs` 的 `list_threads_db` 扫到即报
   `state db discrepancy ... stale_db_path_retained`，把每次 recycle 恋成灾难：
   **修复前每窗口 88 条本地 432 + 渲染层永久死；prune 后 6 条 + 闪崩自愈**。
4. 主进程 `getBackendRequestAuth` 失败 → 本地合成 HTTP 432 `"Workspace routing is unavailable"`
   → 渲染层 `['accounts','check']` 查询 error（432 不重试）→ `Ob/IC=false` →
   `assertCurrent()` 抛 `Messaging account changed`（该字面量全文唯一，不可能来自 abort reason）。
5. 渲染层一旦缓存 error query，focus/reconnect/错误页 Retry/Ctrl+R **全部源码级无效**；
   唯一可靠恢复 = 冷启动。

## 修复

### 第一层：prune state_5.sqlite 孤儿行（根治"永久死"）

前置：停 ChatGPT（整树），确认无 codex.exe 存活。对 `state_5.sqlite`：
1. `PRAGMA wal_checkpoint(TRUNCATE)` 后整库备份到 `backups/state_5-before-prune-<ts>.sqlite`；
2. 在一个事务里删除 `threads` 中 rollout_path 指向不存在文件（含 .gz/.zst 变体判定）的行；
   2026-10-30 实测删 2002/8747 行；
3. `PRAGMA integrity_check` 必须 ok；重启应用。
效果判据：日志再无新增 `stale_db_path_retained`；每小时窗口从"错误页永久死"变为
"闪崩数秒~数分钟自愈"；432 从 ~88/窗口 降至个位数。

### 第二层：冷启动恢复（窗口期闪崩/残留死态时）

1. **检测**：`scripts/dot-verify.ps1 -Action OpenDot -ObserveSeconds 8 -DotName '<dot名>'`。
   exit 0 = 健康；exit 2（errorSeen）或反复 exit 3 = 需要重启。
   注意：错误页期间 UIA 树可能整体为空（"no matching Button"），需 FocusCapture 截图
   + 肉眼/视觉模型判读真实画面，不能只信 UIA。
2. **重启**：`scripts/restart-app.ps1 -TargetPid <pid> -Out <new.json>`（CloseMainWindow 15s →
   仅该 PID 树 taskkill /T /F → `explorer.exe shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App`
   正常身份重启 → 等新窗口 ≤150s）。
3. **验证**：启动后渲染需 1-4 分钟才出侧栏（首次 OpenDot 报 no matching Button 属未就绪，
   等 60-120s 重试）；OpenDot 15s 观测两轮（间隔 ≥75s）exit 0 才算恢复。

## 已证无效（别再走弯路）

错误页 Retry、Ctrl+R、窗口重新聚焦、navigate_to_codex_page（window not ready）、等待自愈（修复前）、
hosts 固定 DNS、给 ChatGPT.exe 挂代理（ProxiFyre）、换代理出口节点、重装应用（社区 3 次负面确认）、
杀毒/Defender 定时排查、mihomo 订阅/切换排查（10 天日志无 :23 事件）。背景噪音勿追：
`artifact_session_host_start_deferred` 每 5.5s 的守护崩溃循环、每分钟的
`Failed to report desktop readiness / thread placement not found`——均与本故障无关。

## 剩余已知（上游缺陷，本机不可修）

桌面每小时 recycle app-server 的交接竞态仍会闪崩一次（约 :23，各机相位不同）；
官方未修（截至 2026-10-30 无修复版本；openai/codex 相关 issue 52996/46382/46812/53337 等
同症状集群，无维护者回复）。prune 后闪崩可自愈；若不能，跑第二层冷启动。

## 边界（硬性）

- 不 patch 账号一致性守卫、不伪造 IC/Ob、不注入 always-allow。
- 不碰 auth.json/token/cookie/账号 ID；prune 只动 threads 索引行，rollout 正文全保留，先备份。
- 恢复期间不向任何线程发消息。
- 重启会丢失未发送草稿——执行前告知用户。
- 所有动作走 evidence-gate（`gate.py run`），全新 Out/Image，禁止覆盖；
  collector exit 0 ≠ 业务成功，必须读 JSON 核 `dotTab/editorEnabled/errorSeen/finalWindowOk`，
  UIA 空树时以真实截图为准。

## 脚本

- `scripts/dot-verify.ps1` — 检测+验收（dot-cycle/v2 血统，`-DotName` 必传；中/英错误白名单；
  UTF-8 BOM，AST 0 错）。
- `scripts/restart-app.ps1` — 冷启动重启（restart-app/v1）。

## 证据与同步

闭环证据（2026-10-29/30：prune 前后跨窗口对照 88→6 条 432、死亡循环→闪崩自愈、
双备份与 integrity 记录）保存在本机 evidence 目录，未入库。仓库即本地技能目录原地 init
（单源），改完直接 `git push` 同步。

---
name: chatgpt-dot-fix
description: Fix ChatGPT desktop dots on Windows when a connected computer cannot execute commands with "windows sandbox backend cannot enforce" / "refusing to run unsandboxed", or when "Messaging account changed", "Workspace routing is unavailable" (432), a retry error page, or hourly flashing breaks the UI. Routes execution failures to verified MXC recovery and UI failures to the historical index/cold-start procedure.
---

# ChatGPT desktop dot 修复

先按当前症状选分支；两类故障的处理不能互相替代。

| 当前证据 | 分支 |
| --- | --- |
| 电脑 connected，但创建进程报 Windows sandbox cannot enforce / refusing to run unsandboxed | A：本机执行沙箱 |
| Messaging account changed、local 432、错误页或每小时闪崩 | B：历史 UI/索引故障 |
| Dot 只分析不实施、承诺稍后检查却没有后续结果 | C：任务执行与结果回收 |
| Dot 根标识可读，但发送报 thread not found | C：先核实目标类型和发送接口 |
| 只有工具未发现、连接瞬断或旧错误转述 | 先重新查询原 Dot 的环境和实际工具 schema，保留“未确认” |

## C：任务执行与结果回收

- **先分清对象。** TBO Dot 的个人标识、消息房间、durable 根线程不等于普通
  ChatGPT Work 聊天。读到根线程概要不代表 `send_message_to_thread` 支持发送；
  当前接口缺少房间发送能力时，不猜 ID、不盲目 navigate/retry。
- **先程序后界面。** 用 [codex-dot-bus](https://github.com/tcflying/codex-dot-bus)
  的最小路由核实接口。程序无法确认送达或回复时才用已登录正常客户端；需要新消息
  ID/request ID 和对应回复。填入草稿、点击提示、操作者亲自点发送均不能冒充自动送达。
  不跳过正常发送的 app-attest/Sentinel 完整性流程。
- **执行原文。** 官方委派包装会编码 XML 实体；提取 `<input>` 时只解码一层，再
  使用原代码。不要把 `&amp;`、`&gt;=` 当运算符，也不要反复反转义原始源码。
- **用结果结束任务。** 已授权的本地实现可一次性交给该仓库的
  [持久执行器](https://github.com/tcflying/codex-dot-bus#durable-local-execution)：
  明确目标、工作目录、模型和外部验收，持久记录尝试，失败后有界修复，恢复时先收回
  原结果。分析、建议、ACK 都不能替代验收。它解决本地执行连续性，不新增 Dot 房间 API。
- **核实唤醒证据。** 规则保存、调度登记、实际触发、完成回执是四件事。旧自动化均停用
  不足以证明某次一次性/临时计时未创建；房间的 `turn_trigger=clock` 才是该次实际触发
  的证据之一。不能由一次成功推定每次云端唤醒可靠。原始记录缺失时保留这个具体缺口，
  不靠重复加规则或创建循环提醒冒充修复。

进度只报正在执行的步骤、已完成结果和具体阻塞。完整验收应包含一次实际失败后的
自动修复、控制程序重启后的同一尝试回收，以及独立验收成功；清楚区分夹具测试、
真实模型执行、Dot 消息回传和生产发布，勿把其中一项替代其余项。

## A：电脑在线但无法执行命令（2026-11-16）

### 适用证据

典型错误：

```text
windows sandbox backend cannot enforce file_system=Unrestricted,
network=Enabled, permission_profile=Disabled; refusing to run unsandboxed
```

旧 WindowsRestrictedToken 后端（包括 `elevated`）会拒绝这一组合。
MXC 是另一种官方原生实现，支持转换完整写权限；不能把旧后端限制套到 MXC。
电脑在线、attach 成功、沙箱服务 Running/ready 都不等于命令已成功。
先核对本次错误与实际配置；历史错误只能作为线索。

### 修复步骤

1. **确认目标与基线。** 使用用户指定的原 Dot 和电脑，读取当前连接、执行工具 schema、
   有效权限及失败回执。区分本地 app-server、Dot exec-server 与其他客户端。
   记录当前官方应用/CLI 路径和版本、Windows build/UBR、实际 CODEX_HOME、
   `config.toml` 原始字节与 SHA256，以及托管策略是否允许 MXC。
   用户已授权的修复在原范围内继续；如需改变权限范围或影响其他任务，先说明具体影响。

2. **先做一次官方 MXC 能力测试。** 截至本次验证，CLI 0.162.0+ 提供下列命令；
   Windows 11 24H2 `26100.9278` / 25H2 `26200.9278` 起具备版本前提，
   仍须实际测试，不能只凭版本判定可用。以当前应用配套的官方 CLI 在新建空诊断目录执行：

   ```powershell
   codex -c windows.sandbox=mxc sandbox --include-managed-config --permission-profile :workspace -- cmd.exe /d /c echo MXC_OK
   $LASTEXITCODE
   ```

   限时 30 秒，保存原始 stdout/stderr/exit；`MXC_OK` 与 exit 0 同时出现才通过。
   命令中的 `codex` 必须解析到已核实的当前官方可执行文件。
   不支持、策略拒绝或超时就记录原错并停止这条候选，不绕过托管限制。

3. **仅切换 Windows 后端。** 能力测试通过后，备份原配置并验证待修改文件仍与基线一致。
   在已有 `[windows]` 表中只把 `sandbox` 改为 `"mxc"`；没有该表才创建一次：

   ```toml
   [windows]
   sandbox = "mxc"
   ```

   保留既有 `sandbox_mode`、`approval_policy`、模型及其他字段，解析校验并回读 diff/hash。
   本次原值 `danger-full-access` / `never` 均保留；这不是要求给其他用户新增完整访问权限。
   该设置作用于共享 CODEX_HOME 下随后采用此配置的 Windows 命令，不是单 Dot 开关。
   优先重新附加环境，不为这一步重启共享应用、执行器或服务。

4. **在原 Dot 的全新上下文验收。** 新建独立诊断子任务并重新 attach 指定电脑，
   不恢复旧诊断子任务。只用实际 schema，不能猜测 attach 支持 cwd/profile 参数。
   先执行一次 `Get-Location`，核对原始输出和 exit 0；再由同一 Dot 在授权隔离目录
   用 `CreateNew` 新建唯一文件、写入新 nonce 并读回，文件已存在则停止，不能覆盖。
   本机独立核对文件路径、字节内容与 SHA256，保留证据文件并结束诊断子任务。
   attach 未返回后端字段时，用本机配置回读与已通过的能力测试判断是否可开始这一次测试；
   不能把缺字段写成失败，也不能把本地 CLI 成功当成原 Dot 成功。

5. **失败时精确回滚。** 恢复本次拥有的 `windows.sandbox` 原值；若原键不存在则移除本次新增键。
   保留期间其他人的配置改动。没有并发改动时，恢复后的整文件 SHA256 应与基线一致。
   只终止可由路径、创建时间和父子关系确认的诊断进程，不终止共享执行器或其他任务。
   旧 setup 已写入的 ACL/防火墙规则不会随配置恢复自动撤销，不能声称全机零改动或批量删除它们。

### 避免重复试错

- **旧子任务缓存：** 本次临时只读上下文成功后，修改 Work“本地文件访问”仍可在旧子任务执行；
  全新子任务却继续收到 Disabled。它没有证明 Work 默认修复了 Dot，测试设置已恢复。
  以后也须用全新子任务验证设置的实际传播。
- **Home 写权限：** 临时全局 `workspace-write` 曾对用户 Home 展开大量可写 ACL 并挂起。
  `exec_command.workdir` 只改变进程 cwd，不等于改变策略 cwd/workspace roots。
  遇到这类挂起，保存日志、恢复临时配置，仅取消归属明确的诊断 helper。
- **配置与工具：** 本次 CLI 拒绝旧式顶层 `profile`；当前 Dot 未暴露 `request_permissions`。
  不把虚构 attach 参数、本地 feature 开关或未验证 profile 拆分当作修复。
- **保持执行边界：** 不使用 `require_escalated` 或关闭沙箱来绕过旧后端拒绝，
  不修改会话数据库伪造成功，也不因这一执行故障运行 B 分支的索引清理。
- **MXC 限制：** 前台命令结束会终止其余子进程；依赖脱离子进程的服务必须另行验证。
  托管网络要求有效 `allow_local_binding=true`；不为测试擅自放宽网络策略。

### 本次验证范围与来源

2026-11-16：Windows 11 25H2 `26200.9711`、应用 `26.1111.2228.0`、
CLI `0.169.0-alpha.11.1`。仅切换后端后，原 Dot 的全新任务执行命令及创建/读回文件均 exit 0，
本机独立内容与摘要核对一致。未完整捕获该次 MXC 进程链；业务流程与后台服务未验收。
旧临时配置和 Work 设置已恢复；本次旧 setup 留下的 ACL/防火墙副作用如实记录。

官方依据（后续运行仍核对当前版本）：
- [Windows sandbox 与 MXC 能力测试](https://learn.chatgpt.com/docs/windows/windows-sandbox)
- [exec-server 后端选择](https://github.com/openai/codex/blob/main/codex-rs/exec-server/src/sandbox_selection.rs)
- [MXC 权限转换](https://github.com/openai/codex/blob/main/codex-rs/mxc-sandbox/src/policy.rs)

## B：错误页、账户路由与每小时闪崩（历史验证）

2026-10-29/30 在 ChatGPT 桌面版（OpenAI.Codex MSIX 26.1023/26.1027，Win10/11）闭环验证。
症状三面孔（同一根因链）：
- 中文全窗错误：「ChatGPT 遇到了问题 / 出了点问题。请重试以继续」；
- 英文全窗错误："ChatGPT hit a snag / Something went wrong. Try again to continue"（UIA 树可能整个为空）；
- 顶部橙色警告条：「账户身份验证不可用 - 桌面端无法从本地 Codex 服务 (app-server) 获取可用的账户身份验证信息」。

### 根因链（2026-10-30 全链实证）

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

### 修复

#### 第一层：prune state_5.sqlite 孤儿行（根治"永久死"）

前置：停 ChatGPT（整树），确认无 codex.exe 存活。对 `state_5.sqlite`：
1. `PRAGMA wal_checkpoint(TRUNCATE)` 后整库备份到 `backups/state_5-before-prune-<ts>.sqlite`；
2. 在一个事务里删除 `threads` 中 rollout_path 指向不存在文件（含 .gz/.zst 变体判定）的行；
   2026-10-30 实测删 2002/8747 行；
3. `PRAGMA integrity_check` 必须 ok；重启应用。
效果判据：日志再无新增 `stale_db_path_retained`；每小时窗口从"错误页永久死"变为
"闪崩数秒~数分钟自愈"；432 从 ~88/窗口 降至个位数。

#### 第二层：冷启动恢复（窗口期闪崩/残留死态时）

1. **检测**：`scripts/dot-verify.ps1 -Action OpenDot -ObserveSeconds 8 -DotName '<dot名>'`。
   exit 0 = 健康；exit 2（errorSeen）或反复 exit 3 = 需要重启。
   注意：错误页期间 UIA 树可能整体为空（"no matching Button"），需 FocusCapture 截图
   + 肉眼/视觉模型判读真实画面，不能只信 UIA。
2. **重启**：`scripts/restart-app.ps1 -TargetPid <pid> -Out <new.json>`（CloseMainWindow 15s →
   仅该 PID 树 taskkill /T /F → `explorer.exe shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App`
   正常身份重启 → 等新窗口 ≤150s）。
3. **验证**：启动后渲染需 1-4 分钟才出侧栏（首次 OpenDot 报 no matching Button 属未就绪，
   等 60-120s 重试）；OpenDot 15s 观测两轮（间隔 ≥75s）exit 0 才算恢复。

### 已证无效（别再走弯路）

错误页 Retry、Ctrl+R、窗口重新聚焦、navigate_to_codex_page（window not ready）、等待自愈（修复前）、
hosts 固定 DNS、给 ChatGPT.exe 挂代理（ProxiFyre）、换代理出口节点、重装应用（社区 3 次负面确认）、
杀毒/Defender 定时排查、mihomo 订阅/切换排查（10 天日志无 :23 事件）。背景噪音勿追：
`artifact_session_host_start_deferred` 每 5.5s 的守护崩溃循环、每分钟的
`Failed to report desktop readiness / thread placement not found`——均与本故障无关。

### 剩余已知（截至历史验证日期）

桌面每小时 recycle app-server 的交接竞态仍会闪崩一次（约 :23，各机相位不同）；
官方未修（截至 2026-10-30 无修复版本；openai/codex 相关 issue 52996/46382/46812/53337 等
同症状集群，无维护者回复）。prune 后闪崩可自愈；若不能，跑第二层冷启动。

### B 分支边界（硬性）

- 不 patch 账号一致性守卫、不伪造 IC/Ob、不注入 always-allow。
- 不碰 auth.json/token/cookie/账号 ID；prune 只动 threads 索引行，rollout 正文全保留，先备份。
- B 分支的 UI/索引恢复期间不向任何线程发消息；A 分支只向用户指定的 Dot 发送已授权诊断。
- 重启会丢失未发送草稿——执行前告知用户。
- B 分支原流程使用本机已有 evidence-gate（`gate.py run`）；仓库未打包它，不能假定可用。
  缺失时保留独立原始回执与截图，按同样标准核验。使用全新 Out/Image，禁止覆盖；
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

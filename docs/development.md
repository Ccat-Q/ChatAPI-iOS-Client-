# 开发与验证

## 编译约定

所有 Swift 编译、测试可执行程序编译和 iOS 归档均通过 GitHub Actions 完成。本地只进行源码审阅、脚本语法、JSON/plist 结构与 diff 检查。

工作流：[Build unsigned IPA](../.github/workflows/build-unsigned-ipa.yml)。

- 触发：推送 `main`、创建/更新 PR，或手动 `workflow_dispatch`。
- 环境：`macos-26`，首先输出 Xcode 和 SDK，并检查 iOS SDK 主版本至少 26。
- 三个 macOS 任务并行：`regressions` 执行回归，`archive` 归档并上传 IPA/dSYM，`screenshots` 构建/截取或精确复用固定预览截图。`build` 在 Ubuntu 汇总，任何子任务失败或取消都不能通过；保留原检查名称，避免分支规则只检查成功的归档。
- 同一分支的新运行取消旧运行，各 macOS 任务上限 15 分钟，汇总上限 2 分钟，仓库权限只有 `contents: read`。并行需要三个 macOS runner，额度不足时会排队；降低墙钟时间不等于降低总 runner 分钟数。
- 不需要 Apple 签名凭据，不自动分发、发布或合并 PR。

开发时先在修复分支更新文件并建立 PR，在 Checks 查看结果。验证未完成前保持 Draft；不要把过去一次绿灯当成当前提交已经通过。

## 缓存与耗时

缓存分别保存在 `.ci-cache/regressions`、`.ci-cache/archive`、`.ci-cache/screenshots`，已加入 gitignore。键包含任务类型、CPU、Xcode/Swift、iOS/模拟器 SDK、macOS build、runner image 版本和相关源码/工程/脚本/工作流的哈希，工具链升级不会恢复旧编译产物。文档不参与编译输入哈希。

- 回归程序只在**精确命中**且可执行文件存在时复用，每次仍启动全新的模拟服务器并运行全部断言。未命中重新编译，不用旧输入的程序代替新代码。
- 归档始终执行 xcodebuild 和打包。持久 DerivedData 可复用编译缓存，部分命中只供 Xcode 检查依赖并重建，不能跳过归档。
- 截图缓存同时保存模拟器 DerivedData 和完整的五张固定样例 PNG。只有相关源码、资源与环境完全一致且五张 PNG 存在、头部与尺寸有效时才复用；摘要明确标注“复用，无新模拟器运行”。部分命中或缺图会清除旧图并重新生成，不能把旧界面冒充新界面。
- 需要新截图时先构建再启动模拟器。首轮尝试重叠二者时，冷模拟器迁移阻塞了 Xcode 的目标查询，已据实测撤回。只编译 runner 本机架构，关闭截图构建的优化、索引和 dSYM；Release 仍生成 dSYM。IPA、dSYM ZIP 和 PNG 上传关闭二次压缩。

缓存仅含构建输出与固定预览图片，不包含 Keychain、Cookie、实例配置、整个模拟器设备或其系统数据。缓存未命中、损坏或不可写时按脚本重建；若需强制重新截图，可删除对应 Actions 缓存或递增工作流键中的版本。所有任务仍默认运行，未用路径过滤隐藏必需检查。

性能基线为 [Actions #40](https://github.com/Ccat-Q/ChatAPI-iOS-Client-/actions/runs/39901737408)：串行 job 4 分 37 秒，其中回归 21 秒、归档 25 秒、截图 3 分 35 秒；缓存恢复约 1 秒、保存约 2 秒。新方案须分别测量首次未命中和精确命中的运行；排队和 runner 启动时间独立于编译耗时。

## 自动回归

Actions 调用 `bash scripts/ci-regressions.sh`：未精确命中时编译项目实际模型、APIClient、KeychainStore、InstanceStore、WorkspaceConnection 、AppSettings、AppLock 和辅助模型服务，再运行 `Tests/CoreRegressions.swift`。不复制一份实现进行测试，临时模块缓存与服务状态在退出时清理。

Python 标准库模拟服务 `Tests/Fixtures/server.py` 只监听 runner 的 `127.0.0.1` 随机端口，提供 Cookie REST 和 WebSocket 协议。不依赖生产实例、Bark 密钥或第三方账号。退出时关闭服务、删除临时目录；涉及会话恢复的测试还原共享实例记录。

覆盖：

- 显式线上键、缩写 ID、可选字段、ISO 8601 小数秒、结构化 JSON、大数显示。
- 设置只提交变更、跳过只读/未知/不支持字段，拒绝非法数字。
- 根 URL 校验、草稿按实例/用户/请求隔离。
- Keychain 新增与更新、Cookie 登录与 TOTP 请求、`ok:false`、401/403 区分。
- GET/DELETE 无请求体、204 成功响应、响应大小限制、Origin、同源/跨源重定向。
- 工具调用协议、匹配确认、错误确认、断线、重连订阅、分页和取消中的连接。
- 会话恢复先验证、临时服务故障保留标记、过期清理、跨实例异步结果不能串写。

模拟服务验证客户端契约，不替代与真实服务器的集成验收。生产协议应核对 [功能与协议](features-and-protocol.md) 中固定版本的服务端源码。

回归任务先运行 `python3 Tests/CICacheGuards.py`，验证精确/部分/损坏截图缓存的处理及缓存测试程序仍被每轮执行。该脚本只以临时命令替身检查缓存控制流，不把替身结果当作 Swift 回归或真实截图；实际 133 项 Swift 断言另行运行。

认证与 AI 回归还覆盖：认证取消后不自动循环、后台遮挡与旧认证回调失效；独立 API 凭据且无 Cookie、两种协议、工具 schema、网络取消、旧建议隔离、自动建议去抖与模式草稿迁移。

连接与应用锁回归还检查：应用锁默认值与持久化、关闭后的后台行为和敏感操作认证、开关变化前的旧回调；连接请求计数以确认无重复 REST 验证、首快照超时、手动重试取消退避、握手 401/403、复用 APIClient 及旧客户端 401 隔离。

Actions 还运行 `scripts/ci-screenshots.sh`，编译 Debug 模拟器应用，使用只存在于 Debug 的固定样例路由截取锁屏、回复、工具调用、工具结果与深色界面。截图保存为 `ChatAPIAdmin-UI-screenshots` artifact；Release 没有预览入口。截图不触发真实模型调用或系统生物识别。

## 构建产物

在成功运行的 Actions 页面下载 `ChatAPIAdmin-unsigned` artifact，包含：

- `ChatAPIAdmin-unsigned.ipa`
- `ChatAPIAdmin.dSYM.zip`

IPA 中为 `Payload/ChatAPIAdmin.app`。安装前使用自己的合法签名工具与设备配置完成签名。dSYM 用于对应版本崩溃符号化；归档显式设置 `dwarf-with-dsym`。

## 真机验收

以下项目需要 iOS 26+ 真机与测试服务器；CI 通过不表示这些项目已验收：

1. 首次解锁、取消、Face ID/Touch ID 与设备密码，切后台和应用切换器遮挡。
   在“更多 → 应用安全”关闭应用锁后重启与切后台，确认不再弹启动认证、后台仍遮挡且服务器会话仍验证；重新开启立即认证。敏感管理操作在关闭应用锁时仍需独立验证。
2. 原生密码/TOTP、启用验证码的网页登录、OIDC 回调后导入 Cookie；测试实际身份提供方是否允许 WKWebView。
3. 重启应用后按服务器 Cookie 有效期恢复，离线重试与服务器会话撤销。
4. 真实请求的文本、工具参数与结果；断网时草稿保留，恢复后核对时间线再重试。
5. 多实例切换、同用户多请求草稿、超过 30 条会话的分页。
   切换标签和打开详情应保留同一连接；模拟无首个快照、401/403 和“立即重连”，确认超时、退避、权限错误与订阅恢复。
6. 普通用户无管理入口；管理员用户分页搜索、启用/禁用、请求中止。
7. 修改敏感/只读/数字设置，确认与设备认证、服务器规范化结果及重启提示。
8. 在兼容服务器配置 Bark，再测试通知；上游无扩展服务器不显示 Bark 入口。

## 修改约束

继续遵循三份 ADR。新 Swift 文件加入 Xcode Sources；新资源加入 Resources。更改 wire key、命令类型、设置元数据或恢复状态时，同步更新测试和文档。不要用吞掉错误、伪造认证令牌、自动重发非幂等命令或无条件提交整个设置文档来绕过失败。

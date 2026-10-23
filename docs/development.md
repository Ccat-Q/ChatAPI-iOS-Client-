# 开发与验证

## 编译约定

所有 Swift 编译、测试可执行程序编译和 iOS 归档均通过 GitHub Actions 完成。本地只进行源码审阅、脚本语法、JSON/plist 结构与 diff 检查。

工作流：[Build unsigned IPA](../.github/workflows/build-unsigned-ipa.yml)。

- 触发：推送 `main`、创建/更新 PR，或手动 `workflow_dispatch`。
- 环境：`macos-26`，首先输出 Xcode 和 SDK，并检查 iOS SDK 主版本至少 26。
- 顺序：回归测试 → Release unsigned archive → IPA/dSYM 打包 → artifact 上传 → Debug 模拟器界面截图。
- 同一分支的新运行取消旧运行，单次上限 25 分钟，仓库权限只有 `contents: read`。
- 不需要 Apple 签名凭据，不自动分发、发布或合并 PR。

开发时先在修复分支更新文件并建立 PR，在 Checks 查看结果。验证未完成前保持 Draft；不要把过去一次绿灯当成当前提交已经通过。

## 自动回归

Actions 调用 `bash scripts/ci-regressions.sh`：在 runner 的临时目录编译项目实际模型、APIClient、KeychainStore、InstanceStore、WorkspaceConnection 、AppSettings、AppLock 和辅助模型服务，再运行 `Tests/CoreRegressions.swift`。不复制一份实现进行测试。

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

认证与 AI 回归还覆盖：认证取消后不自动循环、后台遮挡与旧认证回调失效；独立 API 凭据且无 Cookie、两种协议、工具 schema、网络取消、旧建议隔离、自动建议去抖与模式草稿迁移。

Actions 还运行 `scripts/ci-screenshots.sh`，编译 Debug 模拟器应用，使用只存在于 Debug 的固定样例路由截取锁屏、回复、工具调用、工具结果与深色界面。截图保存为 `ChatAPIAdmin-UI-screenshots` artifact；Release 没有预览入口。截图不触发真实模型调用或系统生物识别。

## 构建产物

在成功运行的 Actions 页面下载 `ChatAPIAdmin-unsigned` artifact，包含：

- `ChatAPIAdmin-unsigned.ipa`
- `ChatAPIAdmin.dSYM.zip`

IPA 中为 `Payload/ChatAPIAdmin.app`。安装前使用自己的合法签名工具与设备配置完成签名。dSYM 用于对应版本崩溃符号化；归档显式设置 `dwarf-with-dsym`。

## 真机验收

以下项目需要 iOS 26+ 真机与测试服务器；CI 通过不表示这些项目已验收：

1. 首次解锁、取消、Face ID/Touch ID 与设备密码，切后台和应用切换器遮挡。
2. 原生密码/TOTP、启用验证码的网页登录、OIDC 回调后导入 Cookie；测试实际身份提供方是否允许 WKWebView。
3. 重启应用后按服务器 Cookie 有效期恢复，离线重试与服务器会话撤销。
4. 真实请求的文本、工具参数与结果；断网时草稿保留，恢复后核对时间线再重试。
5. 多实例切换、同用户多请求草稿、超过 30 条会话的分页。
6. 普通用户无管理入口；管理员用户分页搜索、启用/禁用、请求中止。
7. 修改敏感/只读/数字设置，确认与设备认证、服务器规范化结果及重启提示。
8. 在兼容服务器配置 Bark，再测试通知；上游无扩展服务器不显示 Bark 入口。

## 修改约束

继续遵循三份 ADR。新 Swift 文件加入 Xcode Sources；新资源加入 Resources。更改 wire key、命令类型、设置元数据或恢复状态时，同步更新测试和文档。不要用吞掉错误、伪造认证令牌、自动重发非幂等命令或无条件提交整个设置文档来绕过失败。

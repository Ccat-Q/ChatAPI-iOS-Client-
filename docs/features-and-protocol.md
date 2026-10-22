# 功能与协议

## 功能范围

| 功能 | 普通 Operator | 管理员 | 实现边界 |
| --- | --- | --- | --- |
| 本地密码、TOTP、网页登录 / SSO | 可用 | 可用 | 网页流程由服务器提供；部分身份提供方可能限制内嵌浏览器 |
| 工作台、时间线、历史分页 | 可用 | 可用 | owner 范围，`/api/ws` |
| 助手回复、工具调用、工具结果 | 可用 | 可用 | 工具参数先验证为 JSON 对象，服务端继续执行协议校验 |
| 应用密钥、模型密钥、虚拟模型 | 可用 | 可用 | 显示与撤销密钥需要设备认证 |
| 自动化规则 | 可用 | 可用 | schema 3 的基础文本、工具动作与播放参数；高级动作只读 |
| Bark 配置与测试 | 按能力显示 | 按能力显示 | 仅服务端能力声明包含 `bark` 时出现 |
| 请求记录与中止 | 无入口 | 可用 | 管理员接口；中止需明确确认 |
| 用户启用 / 禁用 | 无入口 | 可用 | 管理员接口；修改需明确确认 |
| 系统设置 | 无入口 | 可用 | 按元数据编辑，敏感字段需设备认证与确认 |
| 审计日志 | 无入口 | 可用 | 最近 50 条，可刷新 |
| 多实例、语言 | 可用 | 可用 | 英文、简体中文、跟随系统 |

客户端隐藏入口不代替服务端鉴权。服务端角色和能力始终是最终依据。

## REST

| 方法与路径 | 作用 / 响应关键字段 |
| --- | --- |
| `POST /api/auth/login` | `username`, `password`, 可选 `totp`；成功 `ok` 与 Set-Cookie |
| `GET /api/auth/session` | `authenticated`, `user` |
| `GET /api/user/api-keys` | 应用密钥列表 `api_keys` |
| `POST /api/user/api-keys` | 创建；`api_key.api_key` 为新密钥 |
| `DELETE /api/user/api-keys/{id}` | 撤销 |
| `GET /api/user/api-keys/{id}/secret` | `api_key` 明文 |
| `GET/POST /api/user/model-keys` | 列表 `items`；创建响应 `model_key` |
| `DELETE /api/user/model-keys/{id}` | 撤销 |
| `GET /api/user/model-keys/{id}/secret` | `api_key` 明文 |
| `GET/POST /api/user/virtual-models` | 列表 `items`；创建响应 `item` |
| `DELETE /api/user/virtual-models/{id}` | 删除 |
| `GET/POST /api/automation/rules` | 列表 `rules`；创建响应 `rule` |
| `PUT/DELETE /api/automation/rules/{id}` | 保存 / 删除 |
| `GET /api/admin/requests` | 请求记录 `items` |
| `POST /api/admin/conversations/{id}/abort` | 中止关联会话 |
| `GET /api/admin/users` | 用户 `items`；客户端支持服务端分页和搜索 |
| `POST /api/admin/users/{id}/enable` 或 `/disable` | 修改用户状态 |
| `GET /api/admin/settings/catalog` | `catalog.groups` 含域和字段 |
| `GET /api/admin/settings/{domain}` | `document.values`, `document.fields` |
| `PATCH /api/admin/settings/{domain}` | 请求 `{values: patch}`；响应 `result.document`, `restart_required`, `warnings` |
| `GET /api/admin/audit/logs?limit=50` | 最近审计记录 `items` |
| `GET /api/mobile/v1/capabilities` | `{version: 1, features: ["bark"]}`；此扩展可缺省 |
| `GET/PUT /api/mobile/v1/notifications/bark` | 个人通知策略；写入 `device_key`, `pending_work` 等蛇形键 |
| `POST /api/mobile/v1/notifications/bark/test` | 对已保存的目标发送测试通知 |

GET 与 DELETE 不发送 JSON 请求体；空的 2xx 响应只可用于无需返回实体的成功响应。模型显式声明线上字段名，解码器不再进行全局蛇形转换；时间接受带与不带小数秒的 ISO 8601。

## WebSocket

客户端连接 `wss://<instance>/api/ws` 并使用现有 Cookie。处理 `workspace.snapshot`、`conversation.upsert/remove`、`timeline.reset/append`、`workspace.command_ack/error` 和分页事件。订阅使用 `timeline.subscribe`，取消订阅使用 `timeline.unsubscribe`，分页使用 `conversation.page.get` 与 `command_id`、`cursor`。

发送统一使用：

```json
{
  "type": "workspace.command",
  "command": {
    "command_id": "unique-id",
    "kind": "stream_complete",
    "conversation_id": "conversation-id",
    "request_id": "request-id",
    "mode": "assistant_message",
    "text": "reply"
  }
}
```

工具调用使用 `mode: tool_call`，附 `tool_name`、`tool_call_id`，参数 JSON 放在 `text`；工具结果使用 `mode: tool_result`，附 `tool_call_id`、`output`。工具名称不是 `kind`。自动化也沿用这些动作类型，播放模式为 `recorded` 或 `fixed`，不是 `once` 或 `fixed_interval`。

## 尚未完整实现的能力

- 没有 QR 导入、原生媒体上传、内建工具控制、录制自动化或完整管理控制台。
- 图像可按时间线 URL 显示；其他媒体显示附件标签。R2 私有上传与签名 URL 由服务端规划，当前能力端点不声明该能力。
- 工具参数只做 JSON 对象语法验证；没有根据请求工具 schema 生成表单或在本地完成 schema 验证。
- 高级自动化（内建工具、终止等）可读取但不能在此编辑，避免丢弃不支持的配置；在服务器 Web 控制台修改。
- 审计只读取最新 50 条；用户列表使用服务端分页与搜索。

协议核对依据：[兼容服务 f777d9f](https://github.com/Ccat-Q/ChatAPI-iOS-Client-Compatibility/tree/f777d9f9c13c1c7715947537d05aac6920744478)，重点为 router、user handler、workspace types/service、settingscore 与 mobile handler。服务器版本不同应重新核对契约，不能仅凭此表推断兼容。

# 项目文档

本仓库只实现 iOS 客户端。服务器部署、权限执行和兼容扩展属于独立服务仓库。

| 文档 | 内容 |
| --- | --- |
| [架构与状态](architecture.md) | 组件职责、会话恢复、实时连接、数据保存 |
| [功能与协议](features-and-protocol.md) | 角色入口、接口、工作台命令与当前功能边界 |
| [AI 自动补全与编辑区](ai-assist.md) | 辅助模型配置、数据范围、建议采纳、认证页与玻璃布局 |
| [开发与验证](development.md) | GitHub Actions 编译、回归测试、IPA 与真机验收 |
| [故障排查](troubleshooting.md) | 登录、连接、设置、通知和构建问题 |
| [本次审查](reviews/2026-10-22-project-audit.md) | 问题证据、修复、验证与未覆盖项 |
| [领域术语](../CONTEXT.md) | Operator、Workspace、Request 等术语 |

现有架构决策继续有效：

- [ADR 0001](adr/0001-separate-compatibility-server.md)：服务端扩展独立且保持兼容。
- [ADR 0002](adr/0002-native-mobile-authentication.md)：复用 Cookie，会话恢复必须向服务器验证，只在 Keychain 保存会话标记。
- [ADR 0003](adr/0003-catalog-driven-settings.md)：设置由服务端字段目录驱动，只允许编辑声明可编辑的字段，敏感更改需要本地验证与确认。

文档描述当前代码，不把规划中的能力标记为已经支持。协议变更应同时修改模型、回归样例和对应文档。

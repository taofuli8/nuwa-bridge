# Nuwa Bridge 使用说明书

## 1. 首次使用

1. 打开应用，进入 `模型配置` 页。
2. 确认默认配置（推荐）：
   - Base URL：`https://api.deepseek.com`
   - Model：`deepseek-chat` 或 `deepseek-reasoner`
3. 填写你的 `API Key`。
4. 点击 `测试连接`，确认返回成功提示。
5. 回到 `人物` 页，选择任意角色开始对话。

## 2. 人物列表使用

- 顶部可筛选：`全部 / 仅内置 / 仅自定义`
- 列表展示：`名字 + 领域 + 版本`
- 鼠标悬停名字：显示人物简介
- 长按条目：查看来源、版本、简介

## 3. 外部 Skill 导入

支持两种导入方式：

1. GitHub 仓库链接  
   例如：`https://github.com/alchaincyf/trump-skill`
2. 直接 raw SKILL.md 链接  
   例如：`https://raw.githubusercontent.com/<owner>/<repo>/<branch>/SKILL.md`

说明：

- 程序会自动处理常见分支（`main/master`）
- 同名人物默认锁定版本，避免风格漂移

## 4. 聊天页操作

- `Enter`：发送消息
- `Shift + Enter`：换行
- 流式输出：边生成边显示
- Markdown 渲染：列表、标题、代码块自动格式化
- 复制消息：
  - 长按消息复制
  - Windows 右键菜单复制

## 5. 会话管理

聊天页右上角菜单支持：

- 新建会话
- 清空当前会话（有二次确认）
- 导出备份（JSON）

聊天页顶部时钟图标支持切换历史会话。

## 6. 导出备份

导出后会提示文件保存路径，默认在应用文档目录，文件名格式类似：

`nuwa_backup_<personaId>_<timestamp>.json`

## 7. 常见问题

### Q1：测试连接失败怎么办？

- 检查 Base URL 是否正确
- 检查 API Key 是否有效
- 检查 model 是否在服务商可用列表中
- 点击 `加载模型列表` 后再选择模型

### Q2：导入 GitHub 失败怎么办？

- 检查网络是否可访问 GitHub / raw.githubusercontent.com
- 确认仓库包含 `SKILL.md`
- 尝试直接粘贴 raw `SKILL.md` 链接

### Q3：消息样式显示异常怎么办？

- 重启应用后重试
- 确认返回内容是标准 Markdown

## 8. 版本建议

- 对外分发推荐使用 `build/windows/x64/runner/Release/nuwa_bridge.exe`
- Android 安装推荐使用 `build/app/outputs/flutter-apk/app-release.apk`

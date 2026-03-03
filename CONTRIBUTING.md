# 贡献指南 📘
  🇨🇳简体中文 | [🇬🇧English](/doc/CONTRIBUTING_en.md)

#### 欢迎你为 SwiftCraftServerLauncher 贡献！谢谢你愿意参与 🙌。请先看这份指南，可以让我们协作更顺畅，也能让你的贡献更容易被接纳。

### 1. 行为准则 （Code of Conduct）✨

尊重他人：保持友善、建设性、不攻击。

开放与包容：欢迎各种背景的贡献者。

清晰沟通：Issue、PR 描述要尽量清楚，避免误解。

---

### 2. 如何报告问题（Issue）🐞

当你发现 bug 或者有改进建议：

在 GitHub 上的 Issues 里新开一个 issue。

标题要简洁醒目，比如：

“[BUG] 启动时崩溃在 macOS 14.1 – Java 路径未找到”

内容包含：

操作系统版本（macOS + 版本号）

SwiftCraftServerLauncher 的版本（release 或者 commit hash）

你做了什么 → 期望是什么 → 实际发生什么

如果可以的话，附上 error log 或者截图

---

### 3. 贡献代码（Pull Request）流程 🚀

贡献代码流程统一为：

Fork `dev` 分支 → 创建功能分支（命名建议：`feat/...`、`fix/...`、`docs/...`、`chore/...` 等）→
如果远程 `dev` 有更新，优先把 `origin/dev` 合并到你的功能分支，解决冲突后再继续开发 →
发起 PR（目标分支必须是 `dev`），并在 PR 描述中说明改动内容与验证方式 →
通过 `dev` 分支的 CI/校验后再合并。

---

### 4. 代码风格和质量 🌱

语言是 Swift，UI 用 SwiftUI。请遵守 Swift 的命名规范（CamelCase、清晰的变量／函数名）

注释要合理：公共 API／复杂逻辑最好有注释

遵守已有的项目结构，不要把文件乱放

写测试（如果合适），确保改动没有破坏已有功能

注意处理 edge cases，异常情况不要崩溃

---

### 5. Commit 规范 📝

Commit message 由三部分组成：`Header`、`Body`、`Footer`。

```
<type>(<scope>): <subject>

<body>

<footer>
```

其中 `Header` 必填，`Body/Footer` 可选。建议单行不超过 72 字符，最长不超过 100 字符。

`Header` 格式：

`<type>(<scope>): <subject>`

`type` 仅允许：

- `feat` 新功能
- `fix` 修复 bug
- `docs` 文档
- `style` 格式调整（不影响运行）
- `refactor` 重构
- `test` 测试
- `chore` 构建或辅助工具改动

`scope` 可选，用于说明影响范围（例如 `cli`、`tui`、`log`、`server`）。

`subject` 规则：

- 动词开头，第一人称现在时（例如 `change`，不是 `changed`）
- 首字母小写
- 末尾不加句号
- 建议不超过 50 字符

`Footer` 仅用于以下场景：

- 不兼容改动：`BREAKING CHANGE: <reason>`
- 关闭 Issue：`Closes #123` 或 `Closes #123, #245`

`revert` 提交格式：

```
revert: <original header>

This reverts commit <hash>.
```

可选使用 Commitizen 交互生成 Commit message：

```bash
npm install -g commitizen
commitizen init cz-conventional-changelog --save --save-exact
```

---

### 6. 分支管理规则 🌲

dev 是开发主分支，日常功能开发与修复都合并到 dev

main 是稳定分支，仅用于发布稳定版本

新功能／修复请都基于 dev 分支创建功能分支（如 `feat/...`、`fix/...`、`docs/...`、`chore/...`）

PR 永远以 dev 为 base 分支提交

---

### 7. 本地开发环境 💻

使用 Xcode（版本 >= 项目要求）

确保本地 Swift 版本符合项目要求

可能要安装对应的 Java 版本（若启动器相关功能依赖）

编译、运行、手动测试功能是否一切正常

---

### 8. 合并与发布 📦

项目维护者会 Review PR，如果通过，会合并到 dev

当准备发布稳定版本时，将 dev 合并到 main，并在 main 上创建 release tag

发布版本前会进行测试确认，无重大 BUG

---

### 9. 感谢你！💖

感谢你愿意贡献时间、精力。每一个 issue、每一个 PR、每一点建议都很宝贵。

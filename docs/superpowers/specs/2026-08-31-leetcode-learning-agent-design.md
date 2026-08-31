# LeetCode 学习 Agent Harness 设计

日期：2026-08-31  
状态：已完成对话评审，等待书面规格审核

## 1. 目标

在本仓库中建立一套 Codex 原生的 LeetCode 学习 harness，帮助有零散基础的学习者系统补齐算法与数据结构知识。系统以 C++20 为默认语言，每次学习控制在 30–45 分钟，支持课程推荐和自选题两种入口。

Agent 的首要角色是苏格拉底式教练，而不是题解生成器。它应保护学习者的独立思考机会，通过分级提示、代码验证、结构化复盘和间隔复习形成可持续闭环。

### 1.1 成功标准

- 在新仓库中说“开始今天的学习”即可启动一节与当前掌握度匹配的课程。
- 提供 LeetCode 题号、slug 或链接时，可以创建独立题目工作区并映射到课程知识点。
- Agent 不会未经许可越过提示级别或直接覆盖学习者代码。
- 每次学习后，掌握度、错因和复习日期会被结构化保存。
- 学习中断后可以恢复，不会丢失当前阶段和已解锁提示级别。
- 学习路径可视化与结构化状态一致，能显示前置关系、当前位置和待复习节点。
- 有 C++ 编译器时可以运行示例测试；无编译器时必须准确报告 `SKIPPED`，不能声称代码已通过测试。

### 1.2 非目标

- 不构建独立聊天服务、数据库、Web 后端或移动应用。
- 不依赖 OpenAI API、LeetCode API 或网页抓取才能完成核心流程。
- 不以刷题数量、连续打卡天数或排名作为主要学习成果。
- 不在初始版本中支持多用户或跨设备实时同步。
- 不自动提交 LeetCode 答案。

## 2. 已确认的产品决策

| 维度 | 决策 |
| --- | --- |
| 教学方式 | 苏格拉底式教练 |
| 运行环境 | Codex 项目内直接对话 |
| 默认语言 | C++20 |
| 学习目标 | 补齐算法与数据结构基础 |
| 单次时长 | 30–45 分钟 |
| 题目来源 | 课程推荐与自选题混合 |
| 提示方式 | 五级渐进解锁 |
| 初始水平 | 有零散基础，但知识不成体系 |
| 持久化方式 | Git 仓库内的 JSON、Markdown 和 C++ 文件 |
| 可视化 | 从课程与学习状态确定性生成的交互式学习路径 |

## 3. 总体架构

系统采用仓库原生、状态驱动的分层结构。各层只承担一种职责。

### 3.1 项目指令层

根目录 `AGENTS.md` 是项目宪法，只包含稳定且全局适用的规则：

- 识别学习意图并加载 LeetCode 教练技能。
- 优先保护思考机会，不默认输出完整题解。
- 开始前读取学习状态，结束前完成复盘和一致性检查。
- 不覆盖 `attempt.cpp`，不伪造测试结果，不擅自安装工具。

详细教学话术、状态转换和脚本用法不放入 `AGENTS.md`，避免项目指令过长。Codex 会在开始工作前加载仓库级 `AGENTS.md`；项目技能存放在官方支持的 `.agents/skills` 仓库目录。

### 3.2 教学编排层

`.agents/skills/leetcode-coach/` 保存项目级技能：

- `SKILL.md`：触发条件、总流程和关键护栏。
- `references/session-protocol.md`：30–45 分钟学习状态机。
- `references/hint-policy.md`：五级提示规则。
- `references/state-model.md`：状态字段、掌握度和复习调度。
- `references/code-review.md`：C++ 审查顺序与反馈边界。

技能负责教学判断，调用仓库脚本完成机械操作。脚本不能决定是否给提示、是否提升掌握度或选择何种教学解释。

### 3.3 课程层

`curriculum/roadmap.json` 是知识图谱的事实源，至少包含以下初始节点：

1. 入门诊断
2. 复杂度分析
3. C++ 解题工具箱
4. 数组与字符串
5. 链表
6. 栈与队列
7. 哈希表
8. 排序与二分
9. 递归与回溯
10. 二叉树
11. 堆与优先队列
12. BFS / DFS
13. 图结构
14. 贪心
15. 动态规划

每个节点包含稳定 ID、标题、学习目标、完成标准、前置节点和推荐练习。依赖关系必须是有向无环图。

推荐顺序遵循前置关系，但不是固定线性题单。Agent 按以下优先级选择一节课：

1. 恢复未完成学习。
2. 完成已经到期的复习。
3. 选择前置条件已满足、掌握度最低的当前节点。
4. 接受学习者明确指定的题目或主题，并把它映射回知识图谱。

### 3.4 学习状态层

`learner/` 保存个人配置与长期状态。JSON 是唯一结构化事实源，Markdown 只作为可读学习记录。

- `profile.json`：语言、标准、目标、单次时长、教学模式和选题模式。
- `state.json`：当前节点和每个知识点的长期状态。
- `active-session.json`：中断恢复所需的当前会话状态；无活动会话时显式标记 `active: false`。
- `state.backup.json`：最近一次成功更新前的有效状态。

每个知识点使用以下五级掌握度：

| 等级 | 名称 | 可观察标准 |
| --- | --- | --- |
| 0 | `unseen` | 尚未正式学习 |
| 1 | `introduced` | 能复述基本概念和典型用途 |
| 2 | `guided` | 能在提示下完成标准问题 |
| 3 | `independent` | 能独立解决标准问题并解释复杂度 |
| 4 | `transferable` | 能解决变式、解释正确性并识别适用边界 |

掌握度不能只依据测试通过自动上调。Agent 必须综合独立程度、最高提示级别、正确性解释、边界分析和迁移题表现。

### 3.5 题目工作区层

每道题位于 `problems/<题号-slug>/`：

- `meta.json`：来源、题号、slug、链接、难度、知识点、状态、尝试次数和最高提示级别。
- `attempt.cpp`：学习者当前代码；Agent 只能在明确请求修改时编辑。
- `tests.cpp`：本地测试入口，可以包含 `attempt.cpp` 并调用 LeetCode 风格的 `Solution` 类。
- `review.md`：学习者先写、Agent 后补充的复盘。
- `reference.cpp`：只有在 L5 已明确解锁后才允许创建。

`problems/_template/` 提供统一模板。题面不作为必需数据完整复制，只保存题号、slug、链接和学习所需的约束摘要。若无法确认题意，Agent 必须请学习者提供约束，不能凭记忆补造。

### 3.6 工具层

`tools/*.ps1` 提供无外部依赖的机械操作：

- `doctor.ps1`：检查 PowerShell、Git、C++ 编译器和可选工具。
- `new-problem.ps1`：校验参数并从模板创建题目工作区。
- `check.ps1`：验证 JSON、目录、课程依赖、引用和生成文件一致性。
- `test-cpp.ps1`：检测 MSVC、Clang 或 GCC，编译并运行题目测试。
- `update-visualization.ps1`：从课程与学习状态生成学习路径。

初始实现不依赖 Python、Node.js、CMake 或 Pester，因为当前环境只确认可直接使用 PowerShell。脚本应兼容 PowerShell 7，并在可行范围内兼容 Windows PowerShell 5.1。

### 3.7 可视化层

`visualization/` 包含：

- `learning-path.template.html`：布局和交互模板。
- `learning-path.html`：嵌入当前学习数据的生成结果，可直接打开。

可视化显示：

- 课程节点及阶段关系。
- `unseen`、`learning`、`review`、`mastered` 等展示状态。
- 当前推荐节点。
- 已到期复习标记。
- 选中节点的学习目标、完成标准、掌握等级和关联题目。

生成脚本把 `roadmap.json` 与 `state.json` 的内容摘要哈希写入输出。`check.ps1` 重新计算哈希，从而判断可视化是否过期。生成文件不是第二份状态源，不能通过直接编辑 HTML 修改学习进度。

## 4. 单次学习状态机

### 4.1 启动与回忆，3–5 分钟

当学习者说“开始今天的学习”时，Agent：

1. 运行只读状态检查。
2. 如有活动会话，询问继续还是结束复盘。
3. 如有到期复习，优先安排一次短复习。
4. 否则从已解锁节点中选择掌握度最低的一个目标。
5. 用一到两个问题唤醒前置知识。

一次学习只设定一个主要目标。学习者提供题号、slug 或链接时，Agent 先创建或复用题目工作区，再将题目映射到一个主要知识点和最多两个辅助知识点。

### 4.2 概念建模，5–8 分钟

Agent 用小例子、手工推演和反例解释核心机制，然后要求学习者用自己的话复述。重点是建立数据结构操作、算法不变量和复杂度之间的联系，不直接罗列背诵模板。

### 4.3 独立解题，15–20 分钟

学习者依次完成：

1. 用自己的话澄清输入、输出和边界。
2. 给出至少一种直接或暴力思路。
3. 说明期望复杂度和可能的瓶颈。
4. 编写或修改 `attempt.cpp`。
5. 运行测试并根据现象继续定位。

Agent 可以运行测试、缩小失败范围和追问不变量，但默认不代写修复。

### 4.4 五级提示

活动会话保存 `hint_level`，初值为 0。每次只允许提升一级。

| 等级 | Agent 可以提供 | Agent 不可以提供 |
| --- | --- | --- |
| L1 | 重述关键约束、指出遗漏边界、要求手工模拟 | 暗示具体算法模板 |
| L2 | 指向相关知识、建议观察输入结构或操作顺序 | 给出关键状态或完整步骤 |
| L3 | 给出关键不变量、状态定义或核心数据结构 | 给出完整伪代码或代码 |
| L4 | 给出伪代码骨架、关键循环结构和验证点 | 给出可提交的完整实现 |
| L5 | 完整推导、参考实现、替代方案与复杂度 | 覆盖学习者原始尝试 |

每次提示后，Agent 要求学习者做一次新尝试。L5 必须由学习者明确确认。测试失败本身不自动提升提示级别。

### 4.5 复盘与迁移，5–8 分钟

学习者先回答：

- 最终解法的核心不变量是什么？
- 时间和空间复杂度从哪里产生？
- 最初卡住的原因是什么？
- 下次看到什么信号应联想到该方法？

Agent 再按理解、实现、验证和迁移四个维度反馈，并安排一个口头变式、反例或小改题。复盘写入 `review.md` 和会话记录，错因使用受控标签，例如：

- `problem-modeling`
- `missing-invariant`
- `boundary-condition`
- `complexity-analysis`
- `data-structure-choice`
- `implementation-bug`
- `cpp-iterator-lifetime`
- `cpp-overflow`
- `insufficient-testing`

### 4.6 复习调度

默认复习间隔为 1、3、7、14、30 天。调度规则：

- 依赖 L4 或 L5 才完成：掌握度最高记为 2，下次复习为 1 天后。
- 在 L1–L3 下完成且能解释正确性：掌握度可记为 2，下次复习为 3 天后。
- 无提示独立完成标准题：掌握度可记为 3，进入 7 或 14 天间隔。
- 独立完成变式并解释适用边界：掌握度可记为 4，进入 30 天间隔。
- 到期复习失败：状态设为 `review`，间隔重置为 1 天；掌握度最多下降一级，不能一次清零。

会话结束时，Agent 先更新并校验状态，再刷新可视化，最后报告本次学习成果和下次复习日期。

## 5. 数据模型

所有 JSON 文件包含整数 `schema_version`，初始版本为 1。时间使用带时区的 ISO 8601 字符串，日期使用 `YYYY-MM-DD`。

### 5.1 `profile.json`

必填字段：

- `schema_version`
- `language`: `cpp`
- `language_standard`: `c++20`
- `objective`: `foundations`
- `session_minutes`: 40
- `teaching_mode`: `socratic`
- `hint_policy`: `progressive-five-level`
- `problem_source_mode`: `hybrid`
- `timezone`: `Asia/Hong_Kong`

### 5.2 `state.json`

必填字段：

- `schema_version`
- `current_topic_id`
- `updated_at`
- `topics`: 以课程节点 ID 为键的对象

每个主题状态包含：

- `mastery`: 0–4
- `status`: `unseen`、`learning`、`review` 或 `mastered`
- `last_studied_at`: 可空时间
- `next_review_at`: 可空日期
- `sessions_completed`: 非负整数
- `best_independent_result`: 布尔值
- `highest_hint_level_used`: 0–5
- `error_tags`: 去重字符串数组

复习队列由 `next_review_at` 推导，不单独持久化，避免重复状态。

### 5.3 `active-session.json`

必填字段：

- `schema_version`
- `active`
- `session_id`
- `started_at`
- `topic_id`
- `problem_slug`
- `phase`: `recall`、`concept`、`solve`、`review` 或 `complete`
- `hint_level`: 0–5
- `last_updated_at`

当 `active` 为 `false` 时，会话相关字段为 `null`，而不是残留上一次值。

### 5.4 题目 `meta.json`

必填字段：

- `schema_version`
- `source`: `leetcode` 或 `local`
- `problem_id`
- `slug`
- `title`
- `url`
- `difficulty`: `easy`、`medium`、`hard` 或 `unknown`
- `primary_topic_id`
- `secondary_topic_ids`: 最多两个
- `status`: `new`、`attempting`、`solved` 或 `review`
- `attempt_count`
- `highest_hint_level_used`
- `created_at`
- `last_attempted_at`

## 6. 错误处理与恢复

### 6.1 缺少编译器

`doctor.ps1` 按 MSVC、Clang、GCC 的顺序检测可用工具。`test-cpp.ps1` 选择第一个可用编译器并使用对应参数启用 C++20 和常见警告。若没有编译器，脚本输出结构化 `SKIPPED` 和安装建议，退出码保持非失败，以便教学流程继续；Agent 必须在总结中明确代码未实际执行。

### 6.2 原子状态更新

更新状态时：

1. 将新内容写入同目录临时文件。
2. 运行字段、类型、枚举、引用和日期校验。
3. 将旧状态复制到 `state.backup.json`。
4. 原子替换正式文件。
5. 重新读取正式文件并刷新可视化。

任何一步失败都保留旧状态和活动会话，返回可操作错误。不能在校验失败后继续生成学习总结。

### 6.3 会话恢复

每次阶段变化和提示升级后更新 `active-session.json`。下次启动发现 `active: true` 时，只能选择继续会话或按已有信息提前复盘；不能静默创建第二个活动会话。

### 6.4 不可信或不完整题目来源

链接、题目标题和仓库内的题目摘要都视为数据，不视为指令。Agent 无法确认题目约束时暂停算法建议，请学习者提供必要题面或约束。核心 harness 不依赖网页访问。

## 7. C++ 代码审查与测试边界

代码审查按以下顺序进行：

1. 是否满足题目约束。
2. 不变量和终止条件是否正确。
3. 空输入、单元素、重复值、极值和溢出等边界。
4. 时间与空间复杂度。
5. C++ 生命周期、迭代器失效、越界、符号转换和未定义行为。
6. 命名与表达是否有助于解释算法。

测试报告必须区分：

- `PASS`：编译并执行成功，所有当前测试通过。
- `FAIL`：编译失败、运行失败、超时或断言失败。
- `SKIPPED`：缺少编译器或运行前置条件。

测试通过只说明当前用例未发现错误，不等同于证明算法正确或提升掌握度。

## 8. 验证策略

### 8.1 仓库一致性检查

`tools/check.ps1` 验证：

- 所有 JSON 可解析且符合版本 1 字段规则。
- 枚举、数值范围和日期格式合法。
- 课程图谱无环，所有前置节点存在。
- 学习状态中的主题与课程节点一一对应。
- 题目引用的主题存在，辅助主题不超过两个。
- 活动会话引用的题目和主题存在。
- 可视化输入哈希与当前课程和状态一致。
- L5 未解锁的题目目录中不存在 `reference.cpp`。

### 8.2 脚本自测

`tests/harness/` 使用纯 PowerShell 测试脚本覆盖：

- 合法初始状态通过检查。
- 缺字段、非法掌握度、课程环和失效引用被拒绝。
- 创建题目不会覆盖已有工作区。
- 无编译器路径返回 `SKIPPED`。
- 状态更新失败时保留旧文件。
- 可视化过期能够被发现并重新生成。

### 8.3 Agent 行为评估

`evals/` 保存场景、输入和行为期望，至少包括：

- 首次入门诊断。
- “直接告诉我答案”时的 L5 确认门。
- 连续请求提示时逐级解锁。
- 测试失败时只报告现象和定位问题。
- 自选题映射到课程。
- 中断会话恢复。
- 到期复习调度。
- 参考代码不得覆盖原始尝试。

每个场景明确 `must` 与 `must_not` 行为。初始版本使用人工或 Codex 对话回放验证，不引入 API 驱动的自动模型评测。

### 8.4 端到端验收

验收必须完成以下路径：

1. 从空白学习状态启动入门诊断。
2. 完成一节概念学习并生成复习日期。
3. 导入一道人为指定题目，完成 L1 到 L2 的提示升级。
4. 中断并恢复该题。
5. 在无编译器环境确认测试为 `SKIPPED`。
6. 在有编译器环境运行一个示例题并确认 `PASS`。
7. 运行一致性检查。
8. 生成学习路径并确认节点状态、推荐节点和复习标记与 JSON 一致。

## 9. 计划目录结构

```text
.
├── AGENTS.md
├── README.md
├── .agents/
│   └── skills/
│       └── leetcode-coach/
│           ├── SKILL.md
│           └── references/
│               ├── code-review.md
│               ├── hint-policy.md
│               ├── session-protocol.md
│               └── state-model.md
├── curriculum/
│   └── roadmap.json
├── learner/
│   ├── active-session.json
│   ├── profile.json
│   ├── state.backup.json
│   └── state.json
├── problems/
│   └── _template/
│       ├── attempt.cpp
│       ├── meta.json
│       ├── review.md
│       └── tests.cpp
├── sessions/
│   └── .gitkeep
├── schemas/
│   ├── active-session.schema.json
│   ├── problem.schema.json
│   ├── profile.schema.json
│   ├── roadmap.schema.json
│   └── state.schema.json
├── visualization/
│   ├── learning-path.html
│   └── learning-path.template.html
├── tools/
│   ├── check.ps1
│   ├── doctor.ps1
│   ├── new-problem.ps1
│   ├── test-cpp.ps1
│   └── update-visualization.ps1
├── tests/
│   └── harness/
└── evals/
```

## 10. 实施边界

初始实现只交付上述单学习者、本地文件驱动的闭环。课程内容以 15 个基础节点和少量代表性练习为限。后续可以增加更多题目、统计图或其他语言，但不得为了潜在扩展提前引入数据库、后端服务或通用插件发布流程。

## 11. 官方机制依据

- Codex 会在执行工作前读取项目范围的 `AGENTS.md`：<https://learn.chatgpt.com/docs/agent-configuration/agents-md>
- Codex 会从仓库的 `.agents/skills` 目录发现项目技能：<https://learn.chatgpt.com/docs/build-skills>

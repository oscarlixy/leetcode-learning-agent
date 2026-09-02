# LeetCode 学习代理仓库

这个仓库把 LeetCode 练习拆成可追踪的学习过程：题目工作区、学习状态、复习节奏、可视化和自检脚本都放在同一个地方。当前这台机器没有检测到可用的 C++ 编译器，所以你现在可以先进行概念学习、提示升级和复盘；执行编译测试时会看到 `SKIPPED`，不是失败。

## 快速开始

直接对代理说下面这些话即可：

- `开始今天的学习`
- `继续上次的学习`
- `学习 LeetCode 1`
- `给我下一级提示`
- `复盘这道题并安排复习`

## 仓库结构

- `curriculum/`：学习路线和主题依赖。
- `learner/`：学习者画像、当前状态、活动会话和状态备份。
- `problems/`：每道题的独立工作区，包含 `attempt.cpp`、`tests.cpp`、`review.md` 和 `meta.json`。
- `tools/`：PowerShell 工具，负责建题、自检、状态更新、可视化和 C++ 测试。
- `visualization/`：学习路径模板和生成后的 `learning-path.html`。
- `tests/`：PowerShell 合约测试和 C++ 运行样例夹具。
- `evals/`：行为回放场景，用来检查教学守则有没有漂移。

## 一次学习如何进行

一次完整学习通常按这个节奏走：

1. 代理先读 `learner/state.json` 和 `learner/active-session.json`，判断是继续旧会话、做应复习内容，还是开启新学习。
2. 如果需要新题目，会用 `tools/new-problem.ps1` 建立工作区，并保留模板化的 `attempt.cpp`。
3. 学习过程中的阶段变化和提示升级会先写入候选 JSON，再用 `tools/update-state.ps1` 原子更新。
4. 学完后会安排下一次复习日期，并更新学习路径可视化。
5. 如果本机有编译器，再运行 C++ 测试；没有的话测试会返回 `SKIPPED`，学习流程仍可继续。

## 五级提示

- `L1`：只给方向，不给关键做法。
- `L2`：指出可以观察的变量、结构或不变量。
- `L3`：把解题思路拆成更具体的步骤。
- `L4`：几乎完整的方法，但仍保留最后的实现空间。
- `L5`：只有在你明确确认后才会解锁完整答案，并允许参考解出现。

如果你想逐级升级，直接说“`给我下一级提示`”即可。

## 常用 PowerShell 命令

```powershell
pwsh -NoProfile -File tools/check.ps1
pwsh -NoProfile -File tools/doctor.ps1
pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath tests/fixtures/cpp/pass
pwsh -NoProfile -File tools/update-visualization.ps1
```

- `check.ps1`：检查路线图、学习状态、题目元数据和可视化是否一致。
- `doctor.ps1`：检查本机是否能本地编译运行 C++。
- `test-cpp.ps1`：对某个题目目录执行编译和运行测试。
- `update-visualization.ps1`：重新生成 `visualization/learning-path.html`。

## 安装 C++ 编译器后的验证

这个仓库不要求你必须安装某一家厂商的编译器。只要系统里能找到 `cl.exe`、`clang++.exe` 或 `g++.exe` 之一，就可以启用本地编译测试。

建议安装后依次运行：

```powershell
pwsh -NoProfile -File tools/doctor.ps1
pwsh -NoProfile -File tools/test-cpp.ps1 -ProblemPath tests/fixtures/cpp/pass
```

预期是：

- `doctor.ps1` 末行从 `LIMITED` 变成 `READY`。
- `test-cpp.ps1` 从 `SKIPPED` 变成 `PASS`。

## 学习状态和可视化

- `learner/state.json` 保存每个主题的掌握度、复习日期和学习次数。
- `learner/active-session.json` 保存当前活动会话，支持下次继续。
- `learner/state.backup.json` 保留上一个稳定状态，方便恢复。
- `visualization/learning-path.html` 是由路线图和状态生成的静态页面，不要手改；修改状态后请重新运行 `pwsh -NoProfile -File tools/update-visualization.ps1`。

## 数据恢复

如果一次状态更新失败，`tools/update-state.ps1` 不应该覆盖现有正式状态。你可以：

1. 先运行 `pwsh -NoProfile -File tools/check.ps1` 看哪里不一致。
2. 对照 `learner/state.backup.json` 和 `learner/state.json`，确认要保留哪份内容。
3. 修正候选 JSON 后，再重新执行 `tools/update-state.ps1`。
4. 最后重新生成可视化并再次运行 `check.ps1`。

## 当前限制

- 当前机器未检测到 C++ 编译器，所以本地执行测试默认会显示 `SKIPPED`。
- 代理会保护学习者的 `attempt.cpp`，不会因为状态更新或可视化生成而覆盖它。
- 行为回放仍需要定期重跑，以确保教学提示、复习安排和代码评审语气没有漂移。

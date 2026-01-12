# 有谱AI 系统设计

## 一、核心认知

- **Less Magic, More Trust** — 用户需要实感，不是花哨功能
- **一个打磨好的工具 > 10个难用的工具**
- 基于 Claude Code 而非自建 agent 系统

---

## 二、核心痛点

| 痛点 | 本质 |
|------|------|
| 要当"监工"，陪着AI | 认知负担 |
| 多窗口切换、管session | 被动交互太多 |
| 想说话要等AI停下来 | 同步阻塞 |
| 必须坐电脑前 | 设备绑定 |
| 想到新想法但AI在忙 | 无法随时"交代" |

**一句话**：想像给助理发微信语音 — **说完就走，件件有着落**

---

## 三、四个流

系统的本质是四个流的交互：

| 流 | 是什么 | 属于谁 |
|----|--------|--------|
| Voice | 用户的世界的流动 | 你 |
| Chat | agent 的内部思绪 | 单个 agent |
| Memory | agent 间的思维共享 | 所有 agent |
| Git | 工作记录与共享 | 代码/产出 |
| **World** | **共享的当下** | **所有人** |

World = 会议室的白板，实时的协作共识

---

## 四、架构

### 三层 Agent

```
你 (Voice)
    ↓
Voice Agent ← 打包、判断、过滤
    ↓
World（共享的当下）
    ↓
Supervisor（三层）
├── L1: 进程级（机械监控）
├── L2: 规范级（规则检查）
└── L3: 智能级（可以有想法，但保守）
    ↓
Task Agent（每个只做一件事，独立 worktree）
    ↓
工具 AI（subagent，短任务）
    ↓
Git
```

### 三层 Supervisor

| 层级 | 职责 | 方式 |
|------|------|------|
| L1 | 进程活着吗？ | 检查 PID |
| L2 | 符合规范吗？ | hooks + 脚本 |
| L3 | 这样做对吗？ | AI 判断，但只建议 |

---

## 五、World 数据类型

```
World {
  event: [...]   # 发生了什么（过去）
  task: [...]    # 要做什么（现在/未来）
  agent: [...]   # 谁在做（实体）
}
```

### Event

```
Event {
  time: 时间戳
  type: output | process | status | error
  source: 来源
  content: 内容
}
```

### Task

```
Task {
  id: 唯一标识
  description: 描述
  status: pending | running | done | scheduled | pending_approval
  when: now | later | condition
  assignee: 谁来做
}
```

### Agent

```
Agent {
  id: 唯一标识
  name: 名字
  type: voice | task | supervisor
  status: idle | running | stuck
  current_task: 当前任务
  pid: 进程ID
  session_id: Claude session ID
  worktree: 工作目录
}
```

---

## 六、强制机制

**原则：不信任 AI 自觉，用代码强制**

| 要强制的事 | 实现方式 |
|-----------|----------|
| 使用 worktree | 脚本启动时自动创建 |
| 启动注册 | 脚本启动前写 world |
| 心跳（进程级） | 外部脚本定期检查 PID |
| 完成/错误 | 脚本检测进程退出码 |
| 禁用复杂工具 | --disallowedTools |
| edit 前必须 stage/discard | hooks |
| 每个完成要 commit | 规范约束 |

---

## 七、Git 与 World 联动

| World 概念 | Git 对应 |
|-----------|----------|
| 事件 | commit |
| 摘要 | commit message |
| 任务隔离 | worktree/branch |
| 任务完成 | merge |
| 回滚 | revert |

---

## 八、技术要点

- **CLI vs SDK** → 用 CLI（--print --stream-json）
- **并发写入** → flock 或单一 writer
- **心跳** → 进程级（PID检查）+ 活动级（hooks）
- **崩溃恢复** → 扫描 started 但没 done 的
- **归档** → 定期归档旧 event

---

## 九、迭代路径

| 版本 | 目标 |
|------|------|
| V0 | 脚本启动 task agent + world 通信 + 强制 worktree |
| V0.5 | session 管理 + 进程监控 + 崩溃恢复 |
| V1 | 任务看板 |
| V2 | 手机端语音入口 |

---

## 十、待完善

1. World 循环的实现
2. Event 创建机制（细节 vs 压缩）
3. L3 Supervisor 的边界
4. 多 agent 并发资源限制
5. worktree merge 流程

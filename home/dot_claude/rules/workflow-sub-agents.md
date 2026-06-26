# Sub-Agent Delegation Strategy

**Default: direct action.** Delegate only when overhead is justified.

---

## Decision framework

```
Can I do this in ≤ 5 tool calls?
├─ YES → Do it yourself
└─ NO  → Genuine parallelism or specialization benefit?
    ├─ YES → Delegate
    │   ├─ Other independent work to do? → background mode
    │   └─ No other work?               → sync mode (or just do it yourself)
    └─ NO  → Do it yourself
```

## Quick reference

| Task type | Tool calls | Recommendation |
|---|---|---|
| File read | 1–2 | Direct |
| Simple edit | 2–3 | Direct |
| Single search | 1–2 | Direct |
| Multi-file analysis | 5–10 | Direct with structured approach |
| Cross-module investigation | 10–15 | Explore agent if parallel work exists |
| Full feature implementation | 15+ | general-purpose agent with planning |
| Security / code review | Any | Specialized agent (high signal-to-noise) |

## When to delegate ✅

1. **True parallelism** — independent threads that can run simultaneously.
2. **Specialized expertise** — security review, performance profiling.
3. **Large-scale investigation** — cross-cutting concerns across many modules.
4. **Context isolation** — verbose output or experimental approaches that would pollute main context.

## When NOT to delegate ❌

1. Task accomplishable in ≤ 5 direct tool calls.
2. No real parallel work to do while waiting.
3. High context dependency — frequent back-and-forth with current state.
4. One-off trivial operations (formatting, one-liner fixes).

## Anti-patterns

| Anti-pattern | Bad | Good |
|---|---|---|
| Micro-delegation | Launch agent to read one file | `view` directly |
| Background polling | launch background → immediately `read_agent(wait=true)` | Continue own work; retrieve on notification |
| Deep chains | A → B → C → D | Keep depth ≤ 2 levels |
| Excessive context passing | Shuttle 200 KB between agents | Keep large context in main, delegate only independent pieces |

## Planner–Generator–Evaluator pattern

For features spanning 5+ files or with security-critical paths:

1. **Planner** (`general-purpose`): break down requirements into subtasks.
2. **Generator** (main agent or worker): implement each subtask.
3. **Evaluator** (`security-review` / `code-review`): verify correctness, security, performance.

## Sub-agent model selection

| Role | Model | Tools |
|---|---|---|
| Coordinator | Opus | All |
| Implementation worker | Sonnet | Write, Edit, Bash |
| Verification worker | Opus | Read, Grep, Bash |
| Discovery worker | Haiku | Read, Grep |

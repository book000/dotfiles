# Sub-Agent Delegation Strategy

This document defines when and how to delegate tasks to sub-agents (via the `task` tool). Based on research from multi-agent AI systems, Anthropic best practices, and empirical findings from production workflows.

## Core Principle

**Default to direct action.** Only delegate to sub-agents when the overhead is justified by genuine complexity or parallelism benefits.

---

## Task Complexity Assessment

Before delegating, assess task complexity:

| Complexity | Characteristics | Recommended Approach |
|------------|-----------------|---------------------|
| **Simple** | 1-5 tool calls, single file/module, well-defined scope | Direct execution (grep/glob/view/edit/bash) |
| **Medium** | 6-10 tool calls, multiple related files, requires investigation | Direct execution with structured approach |
| **Complex** | 10+ tool calls, multiple independent areas, benefits from specialization | Consider sub-agent delegation |

### Complexity Indicators

**Simple tasks (do yourself):**
- Reading 1-3 known files
- Single file edits
- Straightforward grep/glob searches
- Running a single command
- Applying a well-defined pattern

**Complex tasks (consider delegation):**
- Investigating multiple independent modules in parallel
- Tasks requiring specialized evaluation (security review, performance analysis)
- Long-running operations where you have other independent work
- Multi-step workflows with distinct phases (plan → implement → test)

---

## When to Use Sub-Agents

### ✅ Delegate When

1. **True Parallelism Exists**
   - You have independent work to do while the sub-agent runs
   - Multiple independent research threads can run simultaneously
   - Example: Analyze 5 unrelated services in parallel

2. **Specialized Expertise Needed**
   - Security review requiring deep analysis
   - Code review with high signal-to-noise ratio
   - Performance profiling across multiple components

3. **Large-Scale Investigation**
   - Cross-cutting concerns across many modules in a large codebase
   - Tracing complex data flows through multiple layers
   - Researching unfamiliar legacy systems

4. **Context Isolation Beneficial**
   - Testing or building with verbose output (use `task` agent to keep main context clean)
   - Experimental approaches that might pollute main conversation
   - Multiple alternative solution explorations

### Pattern: Planner-Generator-Evaluator

For truly complex features, the **planner → generator → evaluator** pattern is effective:

```
1. Planner: Break down requirements into detailed subtasks
2. Generator: Implement each subtask
3. Evaluator: Verify correctness, security, performance
4. [Iterate if needed]
```

**When to use this pattern:**
- Features spanning 5+ files
- Features requiring architectural decisions
- Features with multiple integration points
- Security-critical implementations

**Implementation:**
- Launch `general-purpose` agent as planner
- Use your own tools as generator (or delegate to another agent)
- Launch `security-review` or `code-review` agent as evaluator

---

## When NOT to Use Sub-Agents

### ❌ Do NOT Delegate When

1. **Task is Simple**
   - Accomplishable in 2-5 direct tool calls
   - Single file or module scope
   - Well-understood pattern application

2. **No Real Parallelism**
   - You're just waiting for sub-agent results
   - No independent work to do during delegation
   - Polling defeats the purpose (use sync mode if you must wait)

3. **High Context Dependency**
   - Subtask requires full understanding of current conversation
   - Frequent back-and-forth with existing context needed
   - State must be synchronized continuously

4. **Trivial Operations**
   - Formatting, logging, simple transformations
   - One-liner fixes or adjustments
   - Style-only changes

5. **One-Off Tasks**
   - Unlikely to recur
   - No reusability benefit
   - No clear modularity advantage

### Example: Simple Discover-Read-Edit (Do It Yourself)

```
❌ Bad: Launch explore agent to find config file
✅ Good: Use grep/glob directly, read file, make edit

# Direct approach (3 tool calls, ~10 seconds):
1. glob pattern="**/config*.json"
2. view path="/found/config.json"
3. edit path="/found/config.json" old_str="..." new_str="..."
```

---

## Anti-Patterns

### 1. Micro-Delegation
**Problem:** Delegating tiny tasks where overhead exceeds benefit.
```
❌ Bad: Launch agent to read a single file
❌ Bad: Launch agent to run one grep command
✅ Good: Do it yourself in one tool call
```

### 2. Premature Sub-Agentization
**Problem:** Breaking up tasks too early, causing unnecessary complexity.
```
❌ Bad: Create 5 agents for a 10-line change across 2 files
✅ Good: Make the change directly
```

### 3. Excessive Context Passing
**Problem:** Shuttling large context between agents repeatedly.
```
❌ Bad: Pass 200KB of code to agent, get results, pass 200KB to next agent
✅ Good: Keep large context in main conversation, delegate only independent pieces
```

### 4. Background Polling
**Problem:** Launch background agent then immediately poll with read_agent.
```
❌ Bad:
  1. task(..., mode="background") → agent_id
  2. read_agent(agent_id, wait=true)  # This defeats background purpose

✅ Good (background):
  1. task(..., mode="background") → agent_id
  2. Continue your own independent work (grep, view, edit)
  3. Agent completes automatically, notification arrives
  4. read_agent(agent_id) to retrieve results

✅ Good (if no parallel work):
  1. task(..., mode="sync")  # Just block, it's faster
```

### 5. Delegation for Simple Searches
**Problem:** Using explore agent for straightforward code lookup.
```
❌ Bad: Launch explore agent to "find the User model"
✅ Good: grep pattern="class User" or glob pattern="**/User.{ts,js,py}"
```

### 6. Untraceable Delegation Chains
**Problem:** Sub-agents delegating to sub-agents, creating debugging nightmares.
```
❌ Bad: Agent A → Agent B → Agent C → Agent D (tracing failures is impossible)
✅ Good: Keep delegation depth ≤ 2 levels
```

---

## Decision Framework

Use this decision tree:

```
Can I do this in ≤5 tool calls?
├─ YES → Do it yourself
└─ NO → Is there genuine parallelism or specialization benefit?
    ├─ YES → Consider delegation
    │   ├─ Do I have other independent work? → Use background mode
    │   └─ No other work? → Use sync mode (or just do it yourself)
    └─ NO → Do it yourself
```

### Quick Reference

| Task Type | Tool Calls | Recommendation |
|-----------|-----------|----------------|
| File read | 1-2 | Direct (view) |
| Simple edit | 2-3 | Direct (view + edit) |
| Single search | 1-2 | Direct (grep/glob) |
| Multi-file analysis | 5-10 | Direct with structured approach |
| Cross-module investigation | 10-15 | Consider explore agent if parallel work exists |
| Full feature implementation | 15+ | Consider general-purpose agent with planning |
| Security review | Any | Consider security-review agent (specialized) |
| Code review of changes | Any | Consider code-review agent (high signal) |

---

## Performance Comparison

Based on research and empirical data:

### Iterative Refinement (Single Agent)
- **Speed:** Fast for simple/linear problems
- **Quality (simple tasks):** High
- **Quality (complex tasks):** Medium
- **Setup overhead:** Low
- **Best for:** Prototyping, bug fixes, straightforward features

### Multi-Agent Planning/Evaluation Loop
- **Speed:** Medium (coordination overhead)
- **Quality (simple tasks):** High (but overkill)
- **Quality (complex tasks):** High
- **Setup overhead:** High
- **Best for:** Production features, architecture-heavy projects, security-critical code

### Delegation Overhead

Each delegation incurs:
- Context serialization/deserialization
- Agent initialization
- Communication round-trips
- Result aggregation

**Rule of thumb:** Delegation overhead ≈ 3-5 tool calls equivalent.  
Only delegate if the task is 10+ tool calls AND benefits from specialization/parallelism.

---

## Practical Guidelines

### For Simple Tasks (90% of work)
1. Use grep/glob/view/edit/bash directly
2. Batch independent reads in parallel (multiple view calls in one response)
3. Chain related bash commands with `&&`
4. Keep it simple, keep it fast

### For Complex Tasks (10% of work)
1. Assess: Is this truly complex? Can I break it down myself?
2. Plan: What are the independent pieces?
3. Delegate: Only the pieces that benefit from separate context
4. Verify: Check results, iterate if needed

### For Background Agents
1. Only use when you have OTHER independent work to do
2. After launching, immediately continue with your own tools
3. Do NOT poll - wait for automatic notification
4. Retrieve results with read_agent after notification

---

## Summary

- **Default to direct action** - 90% of tasks are simple enough
- **Delegate strategically** - Only for genuine complexity or parallelism
- **Avoid anti-patterns** - No micro-delegation, no polling, no excessive context passing
- **Measure complexity** - Use the decision framework
- **Prefer sync over background** - Unless you have real parallel work

The goal is **effective task completion**, not agent orchestration for its own sake.

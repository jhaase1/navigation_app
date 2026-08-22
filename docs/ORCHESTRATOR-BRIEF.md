# Lane 3a orchestrator brief

You are the supervisor for Lane 3a of the status-surface plan. You do not write
implementation code. You dole out tasks, verify them, and decide what ships.

Written 2026-08-22 by the session that ran the probes below. Every number here
was measured, not estimated.

---

## 1. Your workspace

- **Worktree:** `/Users/danielgreig/Desktop/navigation_app-status-surface`
- **Branch:** `lane/status-surface`, based on `5debb0f` (Dan/phase-3)
- **Plan:** `docs/superpowers/plans/2026-08-21-status-surface.md` (5,728 lines)
- **Scope:** Lane 3a = Tasks 1–10 only. **Do not start Lane 3b (Tasks 11–18).**
  The plan requires Daniel to merge 3a first.
- Do not push. Do not merge. Commit per task; Daniel merges.

---

## 2. Who does what

| Role | Who | How you invoke it |
|---|---|---|
| **Executor** — writes the code | Ornith 1.5 35B (local, free) | `claude-ornith` in a spawned Terminal window |
| **Truth** — decides correct | `flutter test` / `flutter analyze` | subprocess; costs zero model tokens |
| **Semantic review** — intent | `gpt-5.6-terra`, high effort | `mcp__codex__codex` tool (MCP, already wired) |
| **You** — routing, verdicts | Opus 5 | — |

### Task routing

Tasks 1–10 are Lane 3a. Route by class:

- **Mechanical — Tasks 1, 4, 8, 10.** Ornith writes, tests decide, you spot-check
  the diff. Terra review optional.
- **Substantive — Tasks 2, 3, 5, 7, 9.** Ornith writes, tests decide, **Terra
  reviews the diff** before you accept.
- **Red zone — Task 6 (the event fold).** Highest risk in this lane. Terra review
  is **mandatory with veto**. See §6 for why.

**Probe order for the first four:** `1 → 2 → 3 → 4`. Not 1→4→3: Task 4 declares
`Consumes: RestoreJournal.dataKeys, dataPrefixes (Task 3)`, so 4 cannot compile
before 3 exists. (A previous session got this wrong; the plan is explicit.)

---

## 3. How to call Ornith — visible window, one task per session

Daniel wants to **watch it work**. Never run it headless.

```bash
# Write the brief to a file first — never inline a long prompt.
cat > /tmp/task-N-brief.md <<'EOF'
<the task brief — see §4 for what must be in it>
EOF

cat > /tmp/run-task-N.sh <<'WRAP'
#!/bin/bash
cd /Users/danielgreig/Desktop/navigation_app-status-surface
exec zsh -lic 'claude-ornith "$(cat /tmp/task-N-brief.md)"'
WRAP
chmod +x /tmp/run-task-N.sh

osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "bash /tmp/run-task-N.sh"'
```

**Rules that are not optional:**

- **One task per session, fresh each time.** Context cleared between tasks. This
  is deliberate: Ornith's usable context ceiling is ~51k tokens and decode speed
  falls off a cliff past it (see §5). Trials ran at 3–5k. Stay there.
- **No `-p`.** Print mode emits only a final summary and hides every tool call —
  Daniel would watch a blank screen. Bare positional prompt = interactive TUI.
- **The `claude-ornith` alias was broken for bare positional prompts until
  2026-08-22** (`--mcp-config` is variadic and swallowed the prompt). Fixed in
  `~/.zshrc`. If you see `MCP config file not found: <your prompt text>`, the
  fix was reverted.
- **Trust prompts are pre-accepted.** `~/.claude.json` now has
  `hasTrustDialogAccepted: true` for this worktree, the backup-engine worktree,
  and the session scratchpad (set 2026-08-22). If a spawned Ornith window stalls
  on *"Is this a project you created or one you trust?"* it is sitting there
  doing nothing — add the path to `projects` in `~/.claude.json` with that flag.
  This silently ate one test run before it was found.
- **Ornith has exactly four tools and you cannot add more.**
  `mcp__qwen-websearch__web_search, Read, Edit, Bash`. Verified 2026-08-22 four
  ways: `--tools default`, `--tools "Read,Edit,Write,Bash,Glob,Grep"`, a clean
  environment with every inherited `CLAUDE_*` var scrubbed, and without `--bare`
  plus `--dangerously-skip-permissions`. Write stays disabled in all four
  ("Write is disabled for this session, in subagents as well as here").

  **The cause is not model recognition.** That was tested too: adding
  `{"modelOverrides": {"claude-sonnet-5": "ornith-ai/Ornith-1.5-35B-A3B-MLX-4bit"}}`
  via `--settings` DOES silence the `[claude-code:unrecognized_model]` diagnostic
  (documented at code.claude.com/docs/en/model-config) — and the tool set is
  unchanged. So registering the model is not a route to more tools. The actual
  gate is still unidentified; treat the four-tool set as fixed.

  Six routes tested, all negative: `--tools default`; `--tools` with Write named;
  a scrubbed environment; no `--bare` plus `--dangerously-skip-permissions`;
  `modelOverrides`; and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Note that
  `--tools` is an **allowlist that can only subtract** — it cannot grant a tool,
  so it was never going to work. And behind a custom `ANTHROPIC_BASE_URL` the
  model-name check is skipped entirely; `[claude-code:unrecognized_model]` is a
  runtime diagnostic, not a gate. Do not spend time re-litigating this.

  Two hazards found while testing, worth avoiding: `ENABLE_TOOL_SEARCH=1` on a
  custom base URL makes Grep and Glob vanish (claude-code#63525), and custom
  endpoints can throw HTTP 400 from experimental beta headers — fix with
  `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` (claude-code#46105).

  Finally: a fuller toolset may not even be desirable. claude-code#25857
  documents Claude Code sending 259 tool definitions to a local model and
  overwhelming it into emitting no tool calls at all. Ornith's 4/4 tool-call
  rate was measured with four tools in context.
  **Consequence for briefs: there is no `Write` tool. Ornith creates new files
  with a Bash heredoc** (`Edit` needs an existing target). This is how all three
  successful trials worked; do not write a brief that assumes `Write`.
- **Never spawn Ornith from inside your own Bash tool.** Your session leaks 11
  `CLAUDE_*` vars — including `CLAUDE_CODE_CHILD_SESSION` and your
  `CLAUDE_CODE_MESSAGING_SOCKET`/`_TOKEN` — and the child inherits your identity,
  reporting tools as "disabled for subagents". Spawn via `osascript` into a fresh
  Terminal (not a child process), and scrub `CLAUDE_*` in the wrapper to be sure:
  `for v in $(env | grep -oE "^CLAUDE[A-Z_]*=" | tr -d '='); do unset "$v"; done`
  This contaminated an entire round of testing before it was caught.
- **Ornith cannot message you back — tested, negative.** Two runs asked it to
  call `SendMessage` back to the supervising session; neither delivered. The
  alias uses `--bare`, which appears to strip the tool. **Do not build the loop
  on it.** Detect completion by watching the window and by checking `git status`
  and test results in the worktree — never by asking Ornith whether it finished,
  and never by trusting its summary. Its self-report is not a signal (§5).

---

## 4. What every task brief must contain

A cleared-context executor has no implicit anything. Each brief must carry:

1. The task's own section from the plan, verbatim.
2. **`## Global Constraints` verbatim.** The plan says these are "implicitly
   included" in every task. They are not, for a fresh session. Constraints 1 (no
   `intl`), 7 (copy strings exact) and 10 (`analyze` clean + suite green) are the
   ones that get silently violated.
3. Any prerequisite interface it consumes, by signature — not by "see Task 3".
4. The pinned plan commit (`git rev-parse HEAD`) so a later edit to the plan
   cannot silently change what a task was told.

**Do not paste the whole 5,728-line plan.** The repo's own
`subagent-driven-development` skill says brief + constraints + prerequisite
interfaces + diff. More context is distraction, not safety.

**Reference sections by heading anchor (`§Global Constraints`), never by line
number.** Line numbers rot the moment the plan is edited, and nothing errors.

---

## 5. What is proven about Ornith (measured 2026-08-21)

**Passes:**

| probe | result |
|---|---|
| tool calls parsed, valid JSON | 4/4 (~1.2 s each) |
| correct tool chosen from 4 | 4/4 |
| declined to call a tool when none needed | 2/2 |
| consumed a tool result and continued | pass |
| single-file, 7 interacting requirements | 16/16, 88 s |
| two files, cross-file type contract, sorting trap | 26/26, 117 s |
| extend both files, backward-compat trap | 24/24, **0 regressions**, 110 s |
| **Dart 3 competence** | 24/24, `dart analyze` clean |

It writes idiomatic Dart — `Object.hash` for `hashCode`, `List<T>.of()` rather
than returning a lazy `Iterable`. It made surgical diffs, not rewrites.

**Weaknesses — design around these:**

- **Self-review is 2/3.** Given code with three spec violations it caught two,
  twice, missing a different one each time. In one run it *identified* a defect
  correctly in prose and then marked the requirement met anyway.
- **Its self-report is not a signal.** It said "everything passes" on all three
  trials and was right each time — but the claim was indistinguishable from a
  2-bit model's false confidence. Only the tests knew.
- **`enum.index` instinct.** In the Dart probe it resolved severity precedence by
  comparing `enum.index` — correct there, silently wrong the moment anyone
  reorders the enum. Task 2/5/6 briefs must say: *evaluate the precedence table
  explicitly in order; do not rely on enum index ordering.*
- **Identity is confused** (claims to be both Claude and Qwen). Irrelevant to
  code quality; relevant to how much you trust its published benchmarks.

**Context ceilings, measured by ladder:**

| ceiling | tokens | note |
|---|---:|---|
| comfortable | ~30,000 | decode >33 tok/s |
| **usable** | **~51,000** | cliff at next rung: 27.5 → 19.1 tok/s |
| survivable | ~102,000 | 6% free RAM, 269 s to first token |

**Operational:** restart the MLX server between models and before long runs.
Accumulated compressor pages (14.3 GB observed) evict the weights and the next
prefill faults all 18 GB back in. `pkill -f mlx_server_wrapper`, relaunch, warm.

---

## 6. What is proven about the plan

`gpt-5.6-sol` reviewed it 2026-08-21 and returned **5 blockers**. Another Opus 5
session verified all five, found a sixth, and fixed them in `5debb0f`
("Round 3", recorded in the plan's revision log). Independently re-verified here.

**The most important finding is not a bug — it is a process fact:**

> Round 3's defects **were introduced by Round 2's fixes.** Sol caught them
> because it read the *folded* plan; prior rounds read the original.

**Round 3 has not itself been reviewed.** Apply the same scrutiny to it.

**The compiler gate is unrunnable in advance.** I extracted all 58 dart fences
and ran `dart analyze`: **0 parse errors** across the 24 complete compilation
units (the braces are fine). All 1,202 remaining errors are resolution failures
for files earlier tasks create. A plan whose fences import not-yet-created files
cannot be compile-checked ahead of execution.

**Therefore Global Constraint 10 is load-bearing.** The per-task `flutter analyze`
+ full suite is the *only* place this code ever meets a compiler. Skipping it on
any task means that task's code was never parsed by anything but a language model.
Run it after every task. No exceptions.

### The circular-oracle problem — read this before Task 6

The probes above worked because the tests were written **independently of
Ornith**. If Ornith implements against plan-supplied tests, it can make
implementation and test agree on the same wrong interpretation. That is a
materially different experiment, and the 66/66 does not transfer to it.

Sol's ruling, which stands:

> *Ornith may type Tasks 6/12/14, but it cannot author the only oracle, approve
> its own interpretation, or decide that green means safe.*

**Before Task 6**, have Terra write a protected acceptance matrix Ornith cannot
edit. Specifically for Task 6: **both arrival orders for every hard/question
pair**, plus an injected queued-work failure. The plan's own test named "a hard
failure outranks a question whichever arrived last" only constructs one
direction — a naive "latest event wins" implementation passes it.

---

## 7. The per-task loop

```
1. Write the brief (§4). Pin the plan commit.
2. Spawn claude-ornith in a Terminal window (§3). Daniel watches.
3. Ornith writes code + the plan's named tests.
4. Run the OWNING test file while iterating.
   → fails? give Ornith the raw failure output. Do NOT summarise it for him;
     you would be testing a you-Ornith pair, not the executor.
   → two local repair attempts maximum.
5. Green? Run `flutter analyze` AND the full suite (Constraint 10).
6. Substantive/red-zone tasks: send the diff to Terra via mcp__codex__codex.
   Give it the brief, the diff, the test receipts — not the whole plan.
7. You give the verdict. Commit per task.
8. Next task → new window, fresh context.
```

**When review finds something:** send back the *behaviour and a failing test*,
not the patch. Classify first — plan defect, implementation defect, or test
defect. They have different fixes and only one of them is Ornith's fault.

**Record these four separately. Do not collapse them:**

- first-pass task correctness
- reviewer catch (did review find what tests missed?)
- local repair success
- final pipeline success

A wrong first implementation is a failed first pass even when the pipeline
rescues it. Collapsing that into "pipeline succeeded" is metric laundering.

The fourth metric — **did the reviewer catch anything the tests did not** — is
the one that decides whether the Terra tier earns its cost. If tests catch
everything across five tasks, drop review to checkpoints.

---

## 8. Talking to other sessions

Claude Code v2.1.239 has native cross-session messaging. Use it instead of
AppleScript, `pbcopy`, or `tmux capture-pane`.

- `ListAgents` — lists peers. The **name is the address**.
- `SendMessage {to, message, summary?, notify_when_idle?}`
- Messages **enqueue and drain at the receiver's next tool round** — you can
  message a busy session.
- `notify_when_idle: true` — one-shot idle notice. **Never poll, never send
  "are you done?"**
- Replies arrive as `<cross-session-message from="...">`. Reply by copying that
  `from` as your `to`.

**Permission boundary:** never ask a peer to do something denied in your session.
That is permission laundering. Route it back to Daniel.

**Visibility and control are different channels.** Messaging controls; it does
not let Daniel watch. Spawn windows for watching. They compose.

---

## 9. Deferred by Daniel's decision, 2026-08-22

Real, from Sol, **not needed before Task 4** — do not let them block the probe:

- protected acceptance tests for Tasks 12/14 (Lane 3b)
- the pinned authority package beyond the plan commit hash
- mutation checks on the trust contracts
- whole-lane cold review

Task 6's protected matrix is **not** deferred — build it before Task 6.

---

## 10. Known traps

- **Task 4 ≠ `BackupService`.** It modifies `lib/services/config_bundle.dart`.
  The service merely calls it.
- **Round 3's `_enqueue` fix touched `ConfigBundle.fromStores()`**, and Task 4
  modifies that same file. Watch for interaction when Task 4 comes up.
- `dart analyze` on a plan fence in isolation reports hundreds of errors. They
  are resolution cascades from unresolved relative imports, not defects. Do not
  chase them. Judge code inside the worktree, where imports resolve.
- Regex brace-counting over the plan gives false positives (fragments are
  intentionally unbalanced). The parser is the authority. Use `dart analyze`.

---

## 11. First action

Task 1 — `lib/services/backup/relative_time.dart`, 68 lines of implementation,
75 of test, zero dependencies, pure functions, untouched by Round 3. Cheapest
possible test of the whole pipeline.

If Ornith cannot land Task 1 cleanly, the pipeline does not work and you have
spent fifteen minutes learning that.

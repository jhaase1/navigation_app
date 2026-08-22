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

---

## 12. Review docket — open items from completed tasks

Findings that are real but were **not** fixed in the task that surfaced them,
because the plan is pinned and the tests in question are plan-supplied. Daniel
ruled 2026-08-22: carry the coverage gaps to the Task 10 sweep, neutralise the
enum-index hazard immediately.

### Task 2 — `gpt-5.6-terra`, high effort, reviewed the diff

Verdict on the code: **no plan defect, no implementation defect.** Green is
reachable only with no active condition AND `configured` AND `hasDurableHead`
AND not `isDirty`; every non-null condition blocks it. The precedence chain is
explicit first-match control flow. Neither `activeCondition!` in `label()` can
throw. `copyWith` has no inescapable state.

**CLOSED — the enum-index hazard.** The plan's own test asserted
`BackupPillState.failing.index < needsReview.index` under the comment *"Enum
order IS the precedence order, and the controller relies on it."* That is a
licence to do in Task 6 the exact thing §5 of this brief warns Ornith not to do.
Assertion removed in the Task 2 follow-up commit and replaced with a NOTE for
Task 6 stating that declaration order documents the table and is never the
mechanism. **Task 6's brief must repeat this.**

**OPEN — five test-coverage gaps, all in plan-supplied tests. For Task 10.**

1. D2's load-bearing case is untested: `pendingCount > 0` with `isDirty == false`
   must stay **green**. That combination is the operator-switch case D2 exists to
   handle — `OperatorStore.saveActiveId` bumps the generation without changing
   content. Nothing currently fails if someone makes the count alone turn the
   pill amber.
2. Neither clear path is tested — a failure or question cleared back to its
   underlying state, nor `clearLastSuccess` after a target removal or import.
3. The equality test only compares dirty vs. clean. It does not prove that a
   changed fault message, operation, or target triggers an AppBar rebuild —
   which is what `==` comparing by fingerprint + message is there to guarantee.
4. `adoptionChoice` being in `_needsHuman` is asserted nowhere;
   `test/backup/app_fault_test.dart` omits it.
5. "Every kind has copy" checks map presence only. A wrong exact string for any
   operator-visible failure label passes it — and Global Constraint 7 makes copy
   a spec surface.

### Task 3 — `gpt-5.6-terra`, high effort, reviewed the diff

**IMPLEMENTATION DEFECT: none.** The `lastSuccessKey` addition was the correct
correction to the plan's fence, and the `RestoreJournal` split is exactly the
old fixed-key list plus that one key — nothing that used to be journalled
stopped being journalled. JSON round-trips correctly (omitted `read` restores
`dismissed:false`, omitted `ok` restores `isFailure:true`); `toUtc()` then
`DateTime.parse()` preserves the instant, so the 14-day boundary does not shift.

**PLAN DEFECTS — five. This is the first time review caught what tests did not.**

Severity is mine, not Terra's, and reflects what an operator actually feels
during a service.

| # | Defect | Severity | Who must guard it |
|---|---|---|---|
| 3a | **Success and failure share one fingerprint namespace.** `recordSuccess(kind:'offline', operation:'push', targetIdentity:'drive:folder-1')` produces byte-for-byte the fingerprint of the matching `AppFault`. On collision `copyWith` keeps the ORIGINAL `isFailure`, so a "Backed up" row can stay flagged a failure — or a failure row can render as OK. | **HIGH — this is the green-over-broken family** | **Tasks 5 and 6**, which are the first callers of `recordSuccess`. Their briefs must forbid a success `kind` that collides with any `BackupFailureKind.name`. |
| 3b | **`load()` never re-bounds.** Age, row-cap, byte-cap and newest-first sorting are enforced only in `_record`. Open the app after 20 days away and expired rows load and stay visible until the next fault. | MEDIUM — user-visible, not dangerous | Task 10 sweep, or a `_bounded` call inside `load()`. |
| 3c | **The 64 KiB cap is not hard.** `_bounded`'s trim loop stops at `kept.length > 1`, and `_truncate` covers only `message`/`detail` — never the fingerprint, whose `operation` and `targetIdentity` are unbounded. One oversized row persists over the cap. | LOW in practice — those fields are engine-set, not operator input | Task 10 sweep. |
| 3d | **`lastDetail` is not "from the most recent occurrence"** as its doc comment claims. A later same-fingerprint fault carrying no `cause` keeps the old one, because `copyWith`'s null means "keep". Stale technical detail shown to the operator. | LOW | Task 10 sweep. |
| 3e | **`_persist()` can throw** despite the stated contract that it must not. A throwing `setString`, `getInstance` or `reload` escapes. The contract exists so a log write cannot take down the backup operation that produced the entry. | LOW — SharedPreferences rarely throws | Task 10 sweep. |

**Test gaps (all TEST DEFECTS):** the byte test uses 250 rows so it never
exercises one oversized row surviving the `length > 1` guard; no cold-load test
for reverse order, expired rows, or an over-cap stored log; no
success/fault collision test; no "new occurrence has no detail" test; restart
coverage checks only `dismissed`/`count`, not `isFailure`, `lastDetail` or
timestamps; nothing proves `backup_log` is deliberately left out of a rollback.

**Note the pattern.** 3a is the same shape as Task 2's enum-index assertion: not
a bug in the task that produced it, but a loaded gun aimed at a later task. Two
for two. Read every review for what it implies about the NEXT task, not just
this one.

### Metrics so far (do not collapse these — brief §7)

| task | first-pass | repairs used | reviewer caught a code defect tests missed | pipeline |
|---|---|---|---|---|
| 1 (mechanical) | pass | 0 | not reviewed | pass |
| 2 (substantive) | pass | 0 | **no** | pass |
| 3 (substantive) | pass | 0 | **YES — 5 plan defects** | pass |

Two clean transcriptions is not yet evidence about Ornith's judgment: Tasks 1
and 2 shipped code byte-identical to the plan's fences. The Terra tier has not
yet caught a code defect the tests missed. Do not retire it on a sample of one.

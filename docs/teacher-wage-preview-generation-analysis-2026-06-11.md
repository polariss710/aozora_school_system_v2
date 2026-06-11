# 老师工资课时预览到生成快照流程分析

Date: 2026-06-11
Scope: read-only analysis only. No feature code changes, no SQL/RPC file execution, no DB writes.

## Current Flow

```text
课时录入/编辑
  -> school_lesson_records actual completed / makeup_completed
  -> wage.html 候选课时预览
     - read-only loads actual lessons by teacher_settlement_month, with year_month fallback
     - shows only when the selected month has zero raw wage locks
  -> 生成老师工资
     - page calls API wrapper generateTeacherMonthlyWage({ yearMonth, teacherId })
     - RPC school_generate_teacher_monthly_wage writes wage locks/details
     - groups by teacher_id + business_entity_id + settlement_month
  -> wage.html 快照列表
  -> wage-detail.html 快照详情
     - reads saved lock/details/payment requests/adjustment audit
     - allows guarded adjustment only before any teacher_wage payment request exists
  -> 生成支付请求
  -> 支付确认
     - creates teacher_wage expense and account transaction
```

## Read-Only Facts Observed

- Current 2026-06 wage locks: `locked:1 / void:1`.
- Current 2026-06 wage side effects for those locks: payment requests `0`, expenses `0`, account transactions `0`.
- Current Wu峰 2026-06 actual candidates:
  - `个人名义`: 3 actual lessons, 360 minutes.
  - `青空进学塾`: 1 actual lesson, 120 minutes.
- Current Wu峰 2026-06 wage locks:
  - `2af31792` / `个人名义` / `void` / 3 details / JPY `0`.
  - `aa301221` / `青空进学塾` / `locked` / 1 detail / JPY `9000`.
- The void `个人名义` wage lock still has three wage detail rows pointing to actual lesson ids `ac79c9af`, `30a160f9`, and `01c14532`.
- Lesson edit guard rejects any actual lesson already referenced by `school_teacher_wage_lock_details`, regardless of whether the parent wage lock is `locked` or `void`.
- Wage generation RPC rejects duplicate generation if any same teacher + business entity + month wage lock exists, regardless of status.

## Current Display Behavior

### Month With No Raw Wage Locks

`wage.html` shows:

- Empty wage snapshot list message.
- `待生成候选课时` preview section.
- Existing `生成老师工资` button with lock warning.

### Month With Any Raw Wage Locks

`wage.html` hides candidate preview because `renderWageCandidates` uses:

```js
const shouldShowCandidates = loadedMonth && wageLocks.length === 0;
```

This counts all loaded wage locks, including `void`.

The wage snapshot list then applies the default filter that hides `status = void`. Therefore a month or filter state can have:

- Raw wage locks exist.
- Candidate preview hidden.
- Default visible wage rows exclude void.
- Result: the user sees only the remaining locked snapshots, or an empty list, without seeing remaining/blocked candidate lessons.

## Filter And Generation Scope

### Current Filters

- Month filter affects both snapshot load and candidate load.
- Teacher filter affects visible snapshots, visible candidate rows, and generation RPC through `p_teacher_id`.
- Business entity filter affects visible snapshots and visible candidate rows.
- Business entity filter does not affect generation RPC.
- Settlement type/status filters are snapshot-only concepts; they do not affect candidate generation.

### Why Filtering Wu峰 Generated Two Snapshots

`generateTeacherMonthlyWage({ yearMonth, teacherId })` passes only month and teacher id to RPC. The RPC then selects all matching actual candidates for that teacher/month and groups them by:

```text
teacher_id + business_entity_id + settlement_month
```

Wu峰 had 2026-06 actual candidates in two business entities:

- `个人名义`
- `青空进学塾`

So one click for Wu峰 generated two wage locks. This is current RPC behavior and is consistent with DB grouping, but the UI does not make it clear enough before generation.

## V1 / V2 Interaction

The observed v1撤销锁定 effect is visible in v2, so v1 and v2 are using the same underlying teacher wage lock data for this area.

The likely operation was:

- Mark one wage lock as `status = void`.
- Set `voided_at`.
- Preserve wage detail rows.
- Preserve source actual lessons.

That matches the current Wu峰 state: `个人名义` is `void` but its three details remain.

Implications:

- v2 default list hides the void row.
- v2 candidate preview is hidden because a raw wage lock still exists.
- v2 generation RPC still rejects regeneration for that same teacher/business/month because it checks existence of any wage lock, not only active locks.
- Actual lesson edit guard still rejects those three actual lessons because detail references remain.

This is a cross-version lifecycle mismatch, not a missing-lesson problem.

## Problem List By Severity

1. Generation scope ignores business entity filter.
   Root cause: `wage.html` has business entity filter, but `generateTeacherMonthlyWage` only accepts `yearMonth` and `teacherId`; RPC has no `p_business_entity_id`.
   Impact: filtering Wu峰 can generate multiple business-entity snapshots, surprising users and creating partial states.

2. Candidate preview disappears after partial generation or voided lock state.
   Root cause: preview visibility depends on raw `wageLocks.length === 0`, while the list hides void by default and generation/lesson guards still consider detail references.
   Impact: users cannot see remaining, blocked, or void-linked candidate lessons from the wage page.

3. v1 void/unlock and v2 snapshot lifecycle are not aligned.
   Root cause: v1 can mark a wage lock void while preserving details; v2 has no general guarded void/reissue lifecycle and default UI hides void records.
   Impact: v2 can show one remaining locked snapshot while another business entity is void/hidden but still blocks regeneration and actual editing.

4. Lesson detail return from wage candidate preview loses source context.
   Root cause: `buildLessonDetailHref` currently links `lesson-detail.html?id=...`; lesson detail only understands lesson-management return parameters.
   Impact: the top button says `返回课时管理`, not `返回老师工资结算`.

5. Generate confirmation does not preview exact output groups.
   Root cause: dialog only says month + teacher range and does not show candidate grouping by teacher/business, lesson count, minutes, or locked/void blockers.
   Impact: users cannot know that one click will create two snapshots or which lessons will become locked.

6. v2 has no general “撤销未支付工资快照” entry.
   Root cause: only one-time guarded SQL/RPC repairs exist for specific incidents; no reusable page/API/RPC lifecycle.
   Impact: mistaken generation requires manual guarded maintenance or v1 intervention, both risky for current/unclosed months.

## Recommended UI / Business Flow Optimizations

### Frontend / Copy Only

- Add source-aware return from candidate lesson detail:
  - Option A: pass `returnWageQuery` and render top return as `返回老师工资结算`.
  - Option B: add a second button `返回老师工资结算` while preserving current `返回课时管理`.
- Always show a wage-generation status panel for the current filters:
  - `未生成`
  - `部分已生成`
  - `已生成`
  - `已作废但仍有关联明细`
  - `已生成支付请求 / 已支付，只读`
- In the generation dialog, show explicit warning that teacher-only generation may create multiple business-entity wage snapshots if business filtering is not enforced.

### API / RPC / State Logic

- Add a read-only generation preview API/RPC or API helper that mirrors the generation grouping:
  - input: month, optional teacher, optional business entity
  - output: groups by teacher + business entity, lesson count, minutes, pay hours, estimated lesson wage, blocker state
  - no writes
- Extend generation RPC only after design review:
  - add optional `p_business_entity_id`
  - ensure existing page business filter and generation scope match
  - keep actual candidate and wage-rule validation in DB/RPC
- Rework candidate preview display:
  - show snapshots and candidate/blocker rows together
  - include already-generated/void-linked rows with reasons
  - do not hide candidate state just because some raw wage lock exists
- Consider a guarded `void unpaid wage snapshot` lifecycle:
  - allowed only when there is no teacher_wage payment request, no paid expense, no account transaction, and no adjustment dependency requiring preservation
  - should set status/audit, not hard-delete
  - must decide what happens to wage detail references because lesson edit/generation guards currently treat detail references as blocking even when the lock is void

## Suggested Minimum Next Change

1. Frontend-only navigation fix:
   - Preserve wage list query when opening `lesson-detail.html` from wage candidate preview.
   - Add `返回老师工资结算` behavior in lesson detail when source is wage.

2. Frontend/API read-only status fix:
   - Show candidate preview even when raw wage locks exist, but classify rows:
     - not generated
     - generated locked
     - generated void
     - blocked by detail reference
   - Show snapshot list and candidate/blocker list together.

3. Generation confirmation improvement:
   - Before calling generation RPC, show grouped candidate summary.
   - Explicitly show how many snapshots will be created and for which teacher/business entities.
   - Hard-block or warn if UI business filter is set but generation RPC cannot enforce it.

4. Separate guarded DB/RPC design:
   - Add `p_business_entity_id` to generation RPC, or create a new versioned RPC.
   - Design guarded unpaid-snapshot void/reissue lifecycle.

## Requires Hard Stop / Separate Authorization

- Regenerating any real current/unclosed month wage snapshot.
- Voiding, deleting, or repairing real wage snapshots/details.
- Removing wage detail references to unlock actual lessons.
- Changing generation grouping or amount formulas.
- Allowing regeneration after void without a clear DB/RPC lifecycle.
- Any operation after payment request generation or payment completion.
- Any cross-version cleanup of v1/v2 historical wage locks.

## Current Recommendation

Do not generate or repair real 2026-06 wage data from v2 until the preview/generation scope is corrected.

The next safe implementation should start with frontend/API read-only visibility and navigation fixes, then separately design the guarded RPC changes for business-entity-scoped generation and unpaid snapshot void/reissue.

## Implemented UI/API Checkpoint

2026-06-11 follow-up frontend/API work completed the first safe implementation slice:

- Candidate preview no longer hides just because raw `school_teacher_wage_locks` exists.
- Candidate rows now show whether a source actual is `未生成`, already covered by an effective wage snapshot, linked to a void wage snapshot, or blocked by a same teacher/business/month locked snapshot.
- The candidate summary and generation dialog show teacher + business entity grouping and explain that the current generation RPC groups by `teacher + business_entity + month`.
- Business-entity filter remains display-only for generation; the UI now warns that it does not constrain the current generation RPC.
- Candidate lesson links pass `from=wage` and wage filters to `lesson-detail.html`.
- `lesson-detail.html` shows `返回老师工资结算` only for wage-origin links and keeps the existing lesson-management return behavior for ordinary lesson entries.

Still not implemented in this checkpoint:

- No change to `school_generate_teacher_monthly_wage`.
- No business-entity scoped generation RPC.
- No general unpaid wage snapshot void/reissue RPC or UI.
- No real 2026-06 wage generation or repair.

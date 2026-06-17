# UI v10 Stable Node

## Stable Node

`v10.1.0-school-ui-base-stable`

## Confirmed Scope

- Income records page has completed the current round of fixes.
- The online income records page has been confirmed.
- The income records page can be used as the standard reference page for the next UI polish rollout.
- Expense records page has completed UI polish for:
  - list view
  - detail view
  - create expense dialog
  - Cash request dialogs

## Rollout Principles

- Use the income records page as the standard reference page.
- Roll out one page at a time.
- Do not perform a whole-site rewrite.
- Do not change business logic.
- Do not change SQL.
- Do not write database data during UI-only work.
- Do not modify core business flows.
- Settlement and Cash-related pages should be handled conservatively.
- Settings and management pages may reuse the UI pattern faster when the scope is low risk.

## Technical Direction

- During v2, continue using the current lightweight frontend approach.
- The v2 goal is business stability and usable UI, not frontend framework migration.
- Do not introduce React, Vue, Svelte, or other large frontend rewrites inside v2.
- React, Vue, Svelte, and other modern frameworks remain v3 candidates after v2 is complete.
- v3 framework selection should not be pre-locked to React.
- v3 evaluation should compare:
  - maintenance cost
  - component ecosystem
  - learning cost
  - Agent-assisted development stability
  - Supabase compatibility

## Avoiding v1-style Patch Stacking

- New CSS must be scoped to a page or component.
- Avoid broad selectors that affect unrelated pages.
- Do not duplicate equivalent style definitions.
- Do not add patch-style JavaScript.
- After a UI page is completed, run a style and duplicate-code self-check.

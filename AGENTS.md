# Codex Project Rules

- Default to Chinese for progress updates and final reports.
- Keep prompts, plans, and outputs concise. Prefer high-signal summaries over long history.
- Start each work turn by checking `git status --short`.
- For SQL/RPC work, follow this sequence before archiving: analysis, draft, static review, rollback test, commit test, then verified SQL commit.
- Page modules must not call Supabase `.rpc()` directly.
- Write operations must go through the API layer and/or verified RPCs. Page modules must not directly insert, update, delete, or upsert database rows.
- Never print, save, or commit `SUPABASE_DB_URL` or other secrets.
- Each turn report must state whether files were changed, whether SQL/RPC was executed, whether the database was written, and whether commit/push was performed.

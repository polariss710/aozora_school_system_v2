# R1D-D-B1-B0-X5 `btree_gist` installation report

Date: 2026-07-30

## Scope

This phase is limited to the persistent installation of `btree_gist` 1.7 in the `extensions` schema. It does not execute B1-B schema work or write business data.

## Authorized statement

```sql
CREATE EXTENSION btree_gist
WITH SCHEMA extensions
VERSION '1.7';
```

## Pre-deployment baseline

- Git branch: `main`
- HEAD / `origin/main`: `b31be4fe1e595ca99e00502083ff3e2e94cf1857`
- X4-C: `BTREE_GIST_REHEARSAL_PASS`
- Expected owner: `supabase_admin`
- Expected member count: 264
- R0 remains `validation_preview_only / blocked / blocked`
- Candidate function MD5: `8981a2ce07abf8c28231bfaf05451368`
- Planned five-field split: 118 / 279 / 0

## Execution result

- Install SQL executions: 1
- Install SQL errors: 0
- Transaction result: `COMMIT`
- Extension: `btree_gist` 1.7
- Schema: `extensions`
- Owner: `supabase_admin`
- Extension members: 264
- `extensions.gist_uuid_ops`: present, UUID GiST
- Built-in range GiST / overlap operator: present
- Database roles changed: no
- Persistent DDL: the single authorized `CREATE EXTENSION` statement
- Business DML / RPC: 0 / 0

## Post-deployment verification

- Postdeploy SQL executions: 1
- Postdeploy SQL errors: 0
- Read-only transaction result: explicit `ROLLBACK`
- `postdeploy_ok`: true
- Trusted / relocatable: true / true
- Frozen Event Trigger function-definition MD5 matches: 6 / 6
- B1-B target objects: 0
- R0: `validation_preview_only / blocked / blocked`
- Candidate function MD5: `8981a2ce07abf8c28231bfaf05451368`
- Planned / actual lessons: 397 / 233; actual is disclosure only
- Planned five-field split: 118 / 279 / 0
- Candidate aggregate: 118 rows / 254 hours / JPY 2,474,000
- Candidate UUID MD5: `77f697f82e547d84dcabf88a3c868aa1`
- Candidate manifest SHA-256: `f1d54bc3b9edb1e4a51b88fae670d6afa357202b520ec8cc1bd7d993469248b1`
- Legacy MD5: `0975fdc91b533680e5ccc909f076ac62`
- Tuition bills: 9 / `0f0323b79e7ff1c47ff6b90c75477a2d`
- Income records: 42 / `2a4897b752f272b1f192045418b4940c`
- Bill lessons: 121 / `09dfee7d8833e09384fb41a84f2959e0`
- Historical exclusions: 42 / `680b6e5aaa718569aee4c36fe1cdc058`
- Cash database connections: 0
- B1-B execution: none

## Rollback

The rollback SQL is created for review only and was not executed. It lists external dependencies and refuses execution when any exist. It may only be used before B1-B creates any dependency on `btree_gist`; after an exclusion constraint depends on the extension, it must not be executed directly.

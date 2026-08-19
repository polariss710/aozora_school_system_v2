# School V2 Phase 3D Fixed Approval Callback

Status date: 2026-08-19

## Outcome

Phase 3D deployed the closed production foundation for Cash fixed-request approval and School writeback. Home owns approval, schedule, fixed-item/projection creation and typed evidence. School accepts that evidence through one service-only writer and atomically updates the canonical expense plus its append-only attempt. Both fixed Gates remain closed and production contains no fixed request, attempt, projection, cycle or School fixed item.

## School Database Contract

- `school_mark_cash_fixed_expense_approved_v2(...)` is postgres-owned, `SECURITY DEFINER`, fixed `search_path=pg_catalog, public`, executable only by service_role.
- `school_apply_expense_cash_fixed_callback_v3(...)` and the transition core are owner-only.
- The attempt guard allows submitted→approved_fixed with version +1, and prepared callback recovery→approved_fixed with version +2 plus the existing recovery audit source. `approved_fixed` cannot transition to rejected.
- Approved evidence must exactly match attempt fingerprint, request/event/idempotency/source identity, original and settlement JPY amounts, card schedule, projection, item, payment group and timestamps. The fixed item must be School/JPY/expense/unpaid, and no transaction, funding account or funding transaction may exist.
- The School expense date must equal the original charge date. The approved transition marks the expense paid and Cash request approved in the same School transaction; it does not create a School account transaction.
- Exact replay returns idempotently. Any evidence or terminal-state mismatch is a conflict. Rejected prepared recovery remains supported independently of the fixed Gate.

Immediate-account confirmed/rejected functions retained definition MD5 `6165af79f45cd27da9415e76dd1f2caf` and `c63559b904f9bef9d2c593f576efb5de`.

## Edge Contract

Only `sync-cash-request-result` changed. For an approved fixed request it calls the Home service-only evidence reader, validates completeness, maps fields without calculating business values, and invokes the School approved writer. Incomplete evidence fails closed with `HOME_FIXED_APPROVAL_EVIDENCE_INCOMPLETE`. Immediate approved/rejected dispatch remains separate; fixed rejection remains supported.

Production deployment: `sync-cash-request-result` v11, ACTIVE, `verify_jwt=false`, bundle SHA-256 `e57db0b417d596879f5305a2e2cb977879a104dd669370b4bbbe184588f0a15f`. `request-cash-expense-confirmation` was not deployed and remains v6, ACTIVE, `verify_jwt=true`, original bundle `1f3b0464c062afe9d74671d9bcf9540a0e2f54a3ac93668fb3ff162a8e2df68c`. OPTIONS returned 204 and the updated Edge mock passed.

## Verification

The exact Home and School SQL bodies passed full production ROLLBACK rehearsals. Tests covered normal submitted and prepared-recovery approval, exact replay, mismatch, rejected/approved terminal conflicts, Gate independence for callbacks, immediate-path regression, ACLs and three Home forced-failure boundaries. An isolated two-session Home clone passed approve/approve and approve/reject races with one terminal chain only.

Formal postcheck:

- School: 53 expenses, 24 attempts, 0 fixed attempts and 0 approved_fixed attempts.
- Home: 50 requests, 0 fixed requests, 0 projections, 0 cycles, 0 School fixed items, 35 JPY transactions, 75 CNY transactions and 2 advances.
- Fingerprints unchanged: School expense `ab992261cb75923472a8e52f546cbe9c`, School attempt `54e997329f80bb423adb655f0e37fc7a`, Home request `7885061cf09eee37b62e39670286cc4e`, Home account `af7a367cfc163b1a5f4a053887ceb8ce`.
- Existing 202,991 JPY classroom-rent expense/request/transaction chain unchanged.

## Closed Boundary

School `cash_fixed_credit_card_route_enabled=blocked`; Home card route flag is false/version 1. No real fixed writer was invoked, no test identity persisted and no page/API/request Edge was changed. School page version remains `v10.5.54`. Gate activation, live fixed request, statement/funding and UI remain later separately authorized work.

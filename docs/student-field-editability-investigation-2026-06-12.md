# Student Field Editability Investigation

Date: 2026-06-12

Scope: design/investigation only. No SQL files, JavaScript, RPC definitions, or API code were changed in this pass.

## Inspection Scope

- DB schema: `public.school_students`, constraints, foreign keys to students, views referencing students, and RPC/function references to `school_students`.
- RPC/API boundary: `school_create_student_profile`, `school_update_student_profile`, `js/api/student-api.js`.
- Frontend: `student.html`, `js/pages/student-page.js`.
- Related chain surfaces: lesson, income, student settlement, wage rule, teacher wage, expense, payment, and account transaction references that read `student_id` or student display fields.

## Current Facts

- `school_students` columns are:
  `id`, `student_code`, `name`, `kana_name`, `display_name`, `gender`, `birthday`, `phone`, `email`, `wechat`, `parent_name`, `parent_phone`, `parent_wechat`, `business_entity_id`, `target_type`, `target_schools`, `entrance_date`, `status`, `default_currency`, `note`, `app_type`, `created_at`, `updated_at`, `preset_exchange_rate`, `previous_balance_cny`, `course_track`.
- Current student page fetches only:
  `id`, `student_code`, `name`, `display_name`, `kana_name`, `business_entity_id`, `target_type`, `target_schools`, `entrance_date`, `status`, `default_currency`, `course_track`, `preset_exchange_rate`, `note`, `app_type`, `created_at`, `updated_at`.
- Current student page does not fetch or render `gender`, `birthday`, `phone`, `email`, `wechat`, `parent_name`, `parent_phone`, `parent_wechat`, or `previous_balance_cny`.
- The edit dialog summary text still says these are not editable: `学生编号、余额、结算、学费规则、联系方式、家长信息、生日、历史财务链路`.
- RPCs referencing students include lesson creation/edit/import, income create/reverse, expense create, settlement preview/lock/unlock/relock/adjustment, wage rule create/update, and teacher wage generation.
- Student foreign-key dependents include lesson, income, expense, student settlement/month/payment, wage rule, teacher work/log tables, and schedule/planned/actual legacy tables.
- The only view found referencing `school_students` is `school_v_student_month_summary`, which uses `school_students.name` as display text.

## Student Page Field Inventory

| Field / label | DB source | Current edit state | Student master data? | Settlement/income/payment/lesson/wage/account chain? | Recommendation | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| 关键字筛选 | Composite: `student_code`, `name`, `display_name`, `kana_name`, `target_schools`, `note` in page JS | N/A | N/A | Indirect display/filter only | Keep as filter | It is not a persisted field. |
| 学生显示名称 / 学生姓名 | `school_students.display_name`, fallback `name` | Editable in create and edit | Yes | Used as display/lookup text in many modules; not an amount or lock input | Open edit | Safe master display field. Historical rows and snapshots are not rewritten. |
| 系统姓名 | `school_students.name` | Editable in create and edit | Yes | Used by `school_v_student_month_summary` and display joins; not an amount input | Open edit | Safe profile field, but changing it affects future/current display labels. |
| 读音 | `school_students.kana_name` | Editable in create and edit | Yes | No direct financial chain | Open edit | Search/display profile field. |
| 学生编号 | `school_students.student_code`; fallback short `id` when missing | Create editable; edit readonly in summary/list | Yes, but stable identifier | Used across detail displays and lookup/import-style matching; unique constraint | Keep readonly in basic edit; move to guarded identifier-correction flow if needed | Not a money field, but it is a stable external/audit identifier. Editing in the ordinary profile dialog can confuse cross-module evidence and historical references. |
| `id` fallback | `school_students.id` | Readonly; only short fallback may be displayed if `student_code` is empty | System field | FK target for all student-linked chains | Keep readonly | Primary key and FK anchor. |
| 状态 | `school_students.status` | Editable in create and edit; filterable | Yes | Used by lookup availability; not historical amount input | Open edit | Future-use availability/profile state. Existing historical records keep `student_id`. |
| 课程方向 | `school_students.course_track` | Editable in create and edit; filterable | Yes | Read in income/settlement detail display; no amount/lock calculation found | Open edit | Academic/profile classification. |
| 目标类型 | `school_students.target_type` | Editable in create and edit; filterable | Yes | Read in income/settlement detail display; no amount/lock calculation found | Open edit | Academic/profile classification. |
| 目标学校 | `school_students.target_schools` | Editable in create and edit; keyword-searchable | Yes | No direct financial chain | Open edit | Academic/profile note. |
| 业务归属 / 默认业务归属 | `school_students.business_entity_id` -> `school_business_entities.id` | Editable in create and edit; filterable | Yes, as default ownership | Used as fallback/default for future settlement candidates and some create forms; historical rows store their own `business_entity_id` | Open edit with active-entity guard | Safe as a future/default value. It must not rewrite lesson/income/settlement/wage/payment/account history. |
| 默认币种 | `school_students.default_currency` | Editable in create and edit; filterable | Yes, as default | Used by display/default behavior; not a historical transaction currency rewrite | Open edit | Safe future/default setting. Existing financial rows keep their own currency fields. |
| 预设汇率 | `school_students.preset_exchange_rate` | Editable in edit; shown in list | Yes, but settlement-linked default | Settlement preview/lock copies it into settlement snapshots as `preset_exchange_rate`; locked snapshots retain copied values | Open edit with wording that it affects future/unlocked settlement preview only | This is not a transaction row, but it can affect future settlement preview/lock/relock results. It should remain out of any real current/unclosed-month write validation. |
| 备注 | `school_students.note` | Editable in create and edit; keyword-searchable | Yes | No direct financial chain | Open edit | Safe profile note. |
| 更新时间 | `school_students.updated_at` | Readonly in list | System field | Audit/update metadata | Keep readonly | System-maintained timestamp. |
| 余额 | Mainly `school_students.previous_balance_cny` fallback; settlement snapshots also have carryover/balance fields | Not fetched by student page; mentioned only in readonly summary | No; financial opening/carryover state | Student settlement/carryover chain | Move to settlement/carryover adjustment module; keep readonly in student profile | `previous_balance_cny` is used by settlement preview as fallback carryover. Editing it from basic profile would change settlement outcomes without the settlement audit workflow. |
| 结算 | `school_student_monthly_settlements`, `school_student_settlement_adjustments`, drafts/carryovers; not a `school_students` profile field | Mentioned only in readonly summary | No | Direct settlement chain, locks, carryover, income/lesson guards | Keep in settlement module | Settlement writes already have dedicated RPC guards and audit semantics. |
| 学费规则 | No dedicated `school_students` column found. Current tuition comes from lesson fee fields, tuition income, settlement preview/snapshot, and possibly future dedicated rules | Mentioned only in readonly summary | Not currently represented as student master data | Direct billing/settlement/income chain if introduced | Move to dedicated billing/tuition-rule module; do not put in basic student edit now | The field does not exist as student profile data. Any new tuition default/rule would need separate schema/RPC design and settlement guard review. |
| 联系方式 | `school_students.phone`, `email`, `wechat` | Not fetched/rendered; mentioned only in readonly summary | Yes | No direct amount/lock/payment/lesson/wage/account calculation found | Open via dedicated student contact/profile edit, or add to profile after privacy/validation design | These are student master/contact fields, not financial chain fields. They should not be permanently classified as unsafe; the current block is a product/privacy/UI scope choice. |
| 家长信息 | `school_students.parent_name`, `parent_phone`, `parent_wechat` | Not fetched/rendered; mentioned only in readonly summary | Yes | No direct amount/lock/payment/lesson/wage/account calculation found | Open via dedicated student contact/guardian edit, or add to profile after privacy/validation design | Guardian/contact data is master data. It needs validation/privacy consideration, but not settlement/wage/account protection. |
| 生日 | `school_students.birthday` | Not fetched/rendered; mentioned only in readonly summary | Yes | No current financial-chain calculation found | Open via dedicated student profile edit if product needs it | Birthday is profile/demographic data. It is not currently a settlement/wage/account input. Future age/grade automation would need a separate rule review. |
| 历史财务链路 | Dependent tables: lessons, income, expenses, student payments/months/settlements, wage rules/details, payment/account transaction chains | Mentioned only in readonly summary | No | Direct chain | Keep readonly in profile; use owning modules | These are transactional/audit records, not student profile fields. |

## Schema Fields Not Actually Displayed On Student Page

| Field | Source | Current edit state | Student master data? | Chain involvement | Recommendation | Reason |
| --- | --- | --- | --- | --- | --- | --- |
| `gender` | `school_students.gender` | Not fetched/rendered | Yes | No current chain found | Consider opening in dedicated profile section | Demographic master data, but not currently part of student page UX. |
| `birthday` | `school_students.birthday` | Not fetched/rendered | Yes | No current chain found | Consider opening in dedicated profile section | See birthday row above. |
| `phone`, `email`, `wechat` | `school_students` | Not fetched/rendered | Yes | No current chain found | Consider opening in dedicated contact section | See contact row above. |
| `parent_name`, `parent_phone`, `parent_wechat` | `school_students` | Not fetched/rendered | Yes | No current chain found | Consider opening in dedicated guardian/contact section | See guardian row above. |
| `entrance_date` | `school_students.entrance_date` | API fetches it; page does not render it | Yes | No current chain found | Consider opening in academic profile section | It is profile/academic data. Add only when UI displays it and validation is designed. |
| `app_type` | `school_students.app_type` | API fetches it; not displayed | System partition field | Query partitioning/filtering | Keep readonly | System/app boundary. |
| `created_at` | `school_students.created_at` | API fetches it; not displayed | System field | Audit metadata | Keep readonly | System timestamp. |
| `previous_balance_cny` | `school_students.previous_balance_cny` | Not fetched/rendered; summary says balance readonly | No | Settlement/carryover fallback | Move to settlement/carryover adjustment module | It can affect settlement preview outcomes and needs audit. |

## Special Confirmations

- Contact fields should not be treated as financial-chain unsafe. `phone`, `email`, and `wechat` are student master/contact data. They are not currently fetched by the student page and were not found as calculation inputs in settlement, income, payment, lesson, wage, or account flows. Recommendation: open them only in a dedicated contact/profile section or a later student profile expansion with validation and privacy handling.
- Guardian fields should not be treated as financial-chain unsafe. `parent_name`, `parent_phone`, and `parent_wechat` are master/contact data. Recommendation: same as contact fields.
- Birthday should not be treated as financial-chain unsafe in the current codebase. It is not currently used in settlement/wage/account calculations. Recommendation: open in a dedicated profile section if operationally useful; keep readonly/hidden until UI and validation are designed.
- Tuition rule is different: no `school_students` tuition-rule column exists. Current tuition behavior is represented by lesson fee fields, tuition income records, and student settlement snapshots/previews. Recommendation: keep it out of student basic edit; design a dedicated tuition/billing-rule module only if the product needs persistent student-level tuition defaults.

## Suggested Next Design Direction

1. Remove or refine the broad edit-summary wording in a future implementation. It currently mixes true protected fields with profile fields that are merely out of current UI scope.
2. Keep `student_code`, `id`, timestamps, `app_type`, balance/carryover, settlement, tuition/billing, payment, wage, lesson, income, expense, and account chains out of ordinary student profile edit.
3. Treat contact, guardian, birthday, gender, and entrance date as a separate "student profile/contact" expansion candidate, not as historical-finance protected data.
4. If opening contact/profile fields later, route writes through a new or expanded API/RPC layer, preserve dialog failure behavior, and avoid any writes to settlement, income, payment, lesson, wage, expense, or account transaction tables.

# School V2 本机受信月结管理工具说明

工具：`scripts/manage-student-settlement.zsh`  
适用：V2 anon 页面只读 Preview 后，由本机受信业务负责人分步保存草稿和锁定月结。

## 安全合同

- 仅连接 `SCHOOL_SUPABASE_DB_URL`，不连接 Cash DB；凭证由既有 `load_both_db` 路径注入，不写文件、不打印、不提交。
- 不使用 `eval`，不直接 DML，不在 shell 计算结转或金额。
- `save-draft` 与 `lock` 是两个独立命令，默认 dry-run；只有显式 `--execute` 才写入。
- 所有金额、source、manifest、expected facts 均来自刚取得的正式 DB Preview。
- 真实写入只经 service-role-only wrapper，wrapper 再调用既有 P0-F/P0-B2 owner core。
- 网络结果不明确时先运行 `status`/`history`，不得盲目重试。
- 第一版没有 unlock/relock 命令。

## 命令

```text
scripts/manage-student-settlement.zsh status \
  --student UUID --entity UUID --month YYYY-MM

scripts/manage-student-settlement.zsh history \
  --student UUID --entity UUID --month YYYY-MM

scripts/manage-student-settlement.zsh preview \
  --student UUID --entity UUID --month YYYY-MM \
  --source-mode MODE --rate NUMERIC --rate-source TEXT \
  --rate-date YYYY-MM-DD --adjustment-mode MODE
```

`save-draft` 在上述 Preview 参数后必须追加：

```text
--preview-manifest SHA256 --lesson-manifest SHA256 --source-count N
--expected-unused-jpy NUMERIC --expected-overage-jpy NUMERIC
--expected-net-jpy NUMERIC --expected-net-cny NUMERIC
--expected-system-difference-cny NUMERIC
--expected-final-carryover-cny NUMERIC --reason TEXT
```

默认 dry-run 成功后，execute 还必须追加：

```text
--execute
--confirm 'SAVE STUDENT SETTLEMENT DRAFT <student> <month> MANIFEST <preview-manifest>'
```

`lock` 复用全部 Preview/expected facts，并追加两份草稿 exact version：

```text
--source-draft UUID --source-draft-updated-at TIMESTAMPTZ
--adjustment-draft UUID --adjustment-draft-updated-at TIMESTAMPTZ
```

默认 dry-run 成功后，execute 确认文本为：

```text
LOCK STUDENT SETTLEMENT <student> <month> MANIFEST <preview-manifest> CARRY <final-carryover>
```

`manual_adjustment` 是唯一允许传 `--explicit-amount-cny` 的模式；`carry_final_balance` 和 `clear_balance` 禁止该参数，金额继续由 DB resolver 决定。

## 返回和幂等

- `status`：scope、当前 settlement/draft、source mode/rate/source/date、adjustment mode、source count/manifest、unused/net/final carry、historical consumed blocker、active tuition claim 和 lock eligibility。
- `history`：按时间返回 settlement、source draft、adjustment draft、lesson variance claim。
- `preview`：正式 DB source 明细、expected facts、manifest、projected carry 和 eligibility。
- `save-draft`：返回两份 draft UUID/version 和 DB resolver 结果。
- `lock`：重新验证所有 facts 后返回 settlement、claim count、manifest 和 carry。
- 相同 exact facts 的重复 `lock --execute` 返回原 settlement，`idempotent=true`；草稿 UUID/version、manifest、source count、claim count或金额任一不一致则拒绝。

## 权限、测试与边界

wrapper `school_save_student_settlement_draft_local`、`school_lock_student_monthly_settlement_local` 均为 `SECURITY DEFINER`、固定 search path、仅 service_role EXECUTE，并在函数体再次验证 JWT role、operator authority和确认文本。anon/authenticated无execute，owner helper仍owner-only，业务表 DML 未开放。

固定 fixture `f0f40000-0000-4000-8000-00000000a001` 验证 status/preview/dry-run/错误确认/过期manifest/committed save/草稿复读/lock/claims/duplicate/ACL；committed save fixture已精确清理，最终 residue 0。lock 的不可删除 claim 生命周期使用 rollback 矩阵验证，随后真实彭宇晗获授权 lock 验证了 committed 路径。

静态、zsh syntax、API/page 边界、权限矩阵和多会话共享锁回归均通过。工具不会执行 Reissue、Cash、Gate、lesson mutation、unlock 或 relock。

Git：功能提交 `fb3812c`（parent `649c14e`），幂等与 history/status 收紧提交 `1d3e08c`（parent `fb3812c`），均随最终交付普通 push `origin/main`。

六份受保护 untracked 文件 SHA-256：`272d0853…8432`、`5b11f064…2093`、`b8e02481…b54f38d`、`5dc7c39c…fda1a`、`b9c13ddc…0773`、`7ed27844…f5939b`，完整值见权限冲突报告和真实操作报告，均未变化。

# Full verification run

One command, run from a clean shell, executes the whole chain and writes this table:

```bash
CHECO_ROOT=<delivery> python scripts/audit/run_full_verification.py
```

It exists because the individual results are reported in several files, and a reader
should be able to see that they all pass in one pass rather than trusting a summary.
The header audit dominates the wall clock at 35 minutes: it opens and reads all 21,110
layers. Everything after it finishes in about 12 minutes.

| Step | Result | Time | Last line of output |
|---|---|---:|---|
| header audit V1/V2 (21,110 layers) | pass | 2106 s | audit written to <delivery>/audit\layer_audit.csv |
| composition identities | pass | 598 s | written: <delivery>/audit\composition_identity.csv |
| focal nesting | pass | 2 s | written: <delivery>/audit\focal_nesting.csv |
| independent re-derivation (16 checks) | pass | 29 s | ================================================================ |
| provenance final (29 checks) | pass | 10 s | written: <delivery>/audit\provenance_check_results.csv |
| provenance columns (24) | pass | 8 s | written: <delivery>/audit\provenance_column_audit.csv |
| documentation consistency (18) | pass | 9 s | 文档数字与磁盘一致。 |
| temporal consistency (39) | pass | 53 s | =============================================================== |
| table layer counts (17) | pass | 1 s | 论文各行之和 21110 ; 磁盘 covariates 总数 21110  OK |
| cross-source numbers | pass | 1 s | all reachable sources agree |
| mutation tests (20 cases) | pass | 16 s | === 合计: 20/20 项符合预期 === |
| R checker self-tests | pass | 3 s | === 通过：0 项自测失败 === |
| manuscript documents (docx) | pass | 1 s | === 2 of 2 documents clean === |
| submission package | pass | 0 s | package written to: <delivery>/00_docs\SUBMISSION\SUBMISSION_PACKAGE |

**14 of 14 steps passed.**

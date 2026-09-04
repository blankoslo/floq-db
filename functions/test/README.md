# Function tests

`deploy.sh` only globs `*.sql` in `functions/`, so nothing in this folder is ever deployed.

Run against a throwaway database, never a shared one. The scripts create their own tables:

```bash
createdb floq_fn_test
psql -d floq_fn_test -v ON_ERROR_STOP=1 \
  -f test/schema.sql \
  -f employee_rate_periods.sql \
  -f company_week_revenue.sql \
  -f test/company_week_revenue_test.sql
dropdb floq_fn_test
```

An assertion that fails raises, so a green run ends with `NOTICE: ... ok` for each block and exit code 0.

`schema.sql` is the minimum shape the functions read, not a copy of production. Add columns here only when a function under test starts needing them.

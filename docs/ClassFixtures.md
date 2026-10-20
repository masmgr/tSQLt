# Class fixtures

```sql
EXEC tSQLt.RegisterClassFixture
  @TestClassName=N'OrderTests', @SetUpProcedure=N'OrderTests.ClassSetUp';
```

Registration is explicit; a helper named ClassSetUp alone has no effect.
The procedure must be parameterless T-SQL in the registered test class.
Re-registering replaces it; passing NULL unregisters it. DropClass removes the
registration. Reinstalling tSQLt resets registrations, as it does case registrations.

A fixture is prepared once for the selected tests in one class during one Run,
RunAll, RunNew or RunSelected invocation. Single tests and single cases also
prepare the fixture. Separate Run calls never share prepared state.
RunSelected groups each registered class's selected tests into one fixture scope.
Seed and TestOrder retain their procedure-order contracts.

Case providers execute before preparation. Each planned case then executes
independently against the prepared state. Each test uses its normal SetUp and
CleanUp; changes to fake data and spy logs roll back to the prepared state.
Finally, rolling back the fixture restores the original objects.

Fixtures require no caller transaction. A fixture execution plan containing
NoTransaction is rejected before preparation, even if that annotation belongs
to another class in the same selected/all/new plan. Nested public test runs are
rejected while preparing or running a fixture. ClassCleanUp is not provided.
The transaction-identity check uses `sys.dm_tran_current_transaction`; the
execution principal must have the permissions needed to read this DMV.

Preparation failure produces Error results for the planned tests, not an extra
synthetic test. Loss of transaction identity, an uncommittable transaction or
an unexpected transaction count produces Error for the current and remaining
tests in that class. Preparation is never retried. Other classes can continue.
Already completed results survive. Unexecuted cases have CaseState=NotRun.

ClassSetUp and tests must not commit or roll back the fixture transaction.
Violations are detected, including COMMIT followed by BEGIN. SQL already
committed by user code cannot be undone by the framework.

Results are buffered in coordinator-owned table variables and written to
TestResult after the fixture rollback. Formatters see the normal result schema.
The Windows LocalDB validation runs `Tests/ClassFixture.Client.sql` outside
any runner transaction to exercise this lifecycle, in addition to registration
unit tests. Unregistered classes continue through the existing runner.

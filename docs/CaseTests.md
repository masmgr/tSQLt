# Case execution and reporting

Case tests are opt-in. Unregistered procedures keep their existing execution,
transaction, annotation and result-formatting behavior. Register a test body and
a provider once, then use the usual `Run`, `RunAll` or `RunNew` entry points.

## Independent execution

```sql
EXEC tSQLt.NewTestClass N'PriceTests';
GO
CREATE PROCEDURE PriceTests.Cases
AS
BEGIN
  INSERT #tSQLt_CaseList(CaseId, DisplayName)
    VALUES(N'zero', N'Zero quantity'), (N'positive', N'Positive quantity');
END;
GO
CREATE PROCEDURE PriceTests.[test price] @CaseId NVARCHAR(128)
AS
BEGIN
  IF @CaseId = N'zero'
  BEGIN
    -- Arrange and assert the zero-quantity case.
    RETURN;
  END;
  -- Arrange and assert the positive-quantity case.
END;
GO
EXEC tSQLt.RegisterCaseTest
  @TestName = N'PriceTests.[test price]', @CaseProvider = N'PriceTests.Cases';

EXEC tSQLt.ListCases @TestName = N'PriceTests.[test price]';
EXEC tSQLt.Run @TestName = N'PriceTests.[test price]';
EXEC tSQLt.Run @TestName = N'PriceTests.[test price]', @CaseId = N'zero',
  @TestResultFormatter = N'tSQLt.XmlResultFormatter';
```

The provider inserts into the caller-owned temporary table
`#tSQLt_CaseList(CaseId NVARCHAR(MAX), DisplayName NVARCHAR(MAX))`. It must be
read-only apart from those inserts, return no result sets, and provide stable
IDs across discovery and subsequent executions. A provider should not have a
name beginning with `test`, since the usual class discovery would execute it.
Register again after dropping and recreating the body or provider.

`ListCases` returns `TestName`, `CaseId`, `DisplayName`, and `ExecutionMode`.
The identity is the qualified test procedure name plus `CaseId`. Display names
need not be unique and may change. IDs are compared by UTF-16 bytes and byte
length, independently of database collation, including case and trailing spaces.
IDs must be nonempty and at most 128 UTF-16 code units; display names must be
nonempty and at most 512. Empty lists, invalid metadata, duplicate IDs and
provider errors are errors. An unknown selector is an error. `Run @CaseId`
requires a specific registered procedure, rather than a class.

For each run, discovery happens once and the selected plan is frozen before
execution. Every planned case receives an initial `Error` / `NotRun` result.
For each case the framework then performs:

1. Create fresh assertion and expected-exception state and a transaction/savepoint.
2. Execute the class `SetUp`, if present.
3. Execute the body with a parameterized `@CaseId`.
4. Attempt the class `CleanUp`, if present, including after SetUp or body errors.
5. Roll back the case and finalize its result.

CleanUp executes before rollback and can inspect case-local changes. A cleanup
error makes the result an error while preserving previous failure information.
Timing includes annotation processing, SetUp, the body, CleanUp and rollback;
it excludes discovery. Explicitly skipped cases do not run these hooks.
`NoTransaction` is rejected for case tests. Transactions provide the usual tSQLt
database isolation; external effects and SQL Server state that transactions do
not roll back require application-specific cleanup.

Assertion failures and catchable SQL errors allow the next case to run once the
existing transaction lifecycle restores the connection state. Fatal execution or
isolation errors stop execution, leaving remaining planned cases unsuccessful.
Expected results are reconciled with recorded results; missing or additional
results produce an error. This reconciliation is scoped to the current plan.

## Reporting precomputed rows

An internal bulk `AssertCases` adapter can use `ReportCaseResults` after its one
bulk calculation has finished. This entry point appends to the current result
table; it does not execute a test body or call `Private_Init`. Call it from the
adapter/runner outside a test transaction that would roll back the reported
rows. The procedure named by `TestName` must exist, but need not be registered
as an independent case test.

```sql
CREATE TABLE #tSQLt_CaseResults
  (CaseId NVARCHAR(MAX), Result NVARCHAR(MAX), Msg NVARCHAR(MAX));
-- The adapter fills this table from its completed bulk calculation.
INSERT #tSQLt_CaseResults VALUES(N'zero', N'Success', NULL);

EXEC tSQLt.ReportCaseResults
  @TestName = N'PriceTests.[test price]', @CaseProvider = N'PriceTests.Cases';
EXEC tSQLt.XmlResultFormatter;
```

Allowed outcomes are `Success`, `Failure`, `Error`, and `Skipped`. The provider
supplies the full expected plan; missing reported rows become `Error` / `NotRun`.
Duplicate, unexpected or invalid reported rows produce a contract error.
Providers have the same read-only and stable-identity requirements as above.

Reported rows have `CaseExecutionMode = 'Reported'`, and provided rows have
`CaseState = 'Reported'`. They carry no measured case duration. Reporting does
not guarantee case isolation, per-case hooks, or continuation after a bulk
calculation throws. The adapter must retain enough of its own plan/results to
report such a failure; the reporting API cannot reconstruct calculations that
never completed.

## Results and XML

`tSQLt.TestResult` retains its existing columns and adds nullable `CaseId`,
`CaseDisplayName`, `CaseState` and `CaseExecutionMode` columns. Legacy rows have
NULL case metadata. Independent cases use mode `Independent` and states
`NotRun`, `Running`, or `Completed`. Outcome and lifecycle are separate: an
unexecuted case is `NotRun` with outcome `Error`, and an explicit skip is
`Completed` with outcome `Skipped`.

Case-aware text output includes the ID and display name. When any case rows
exist, `XmlResultFormatter` delegates to `CaseXmlResultFormatter`, producing one
JUnit-style `testcase` per row with `testname`, `caseid`, `displayname`,
`executionmode`, and `state` attributes. Failure, error and skipped elements and
suite totals reflect the outcomes. Case identity is in explicit attributes;
consumers must not parse the human-readable `name` to recover it. Reported and
unexecuted rows omit `time`. Runs containing only legacy rows retain their
existing XML format. Mixed runs include legacy and case rows together.

This is current-run result storage, not durable failure history. History,
automatic selection of failed cases, timeouts, and recording connection loss
belong to the runner. A runner can discover and persist the selected plan before
execution, select a case through `TestName` + `CaseId`, and consume the result
metadata or XML afterward. On fatal abort it may need to read results explicitly
because normal formatter execution can be interrupted. No disconnect-durability
guarantee is added to the existing result table.

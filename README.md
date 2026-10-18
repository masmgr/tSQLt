# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

## Asserting procedure calls

Apply `SpyProcedure` before exercising the code under test, then assert against
its call log:

```sql
EXEC tSQLt.SpyProcedure @ProcedureName = N'dbo.Target';
EXEC tSQLt.AssertProcedureNotCalled @ProcedureName = N'dbo.Target';

EXEC dbo.Target;
EXEC tSQLt.AssertProcedureCalled @ProcedureName = N'dbo.Target';
EXEC tSQLt.AssertProcedureCalled
    @ProcedureName = N'dbo.Target',
    @ExpectedCallCount = 1,
    @Message = N'Order submission: ';
```

`AssertProcedureCalled` takes `@ProcedureName NVARCHAR(MAX)`,
`@ExpectedCallCount BIGINT = NULL`, and `@Message NVARCHAR(MAX) = N''`, in that
order. An omitted or NULL count requires at least one call; a non-negative count
requires an exact match, including zero. `AssertProcedureNotCalled` takes
`@ProcedureName` and `@Message` and requires zero calls. Mismatches fail the test
and report the quoted procedure name, expected condition, and actual count,
preceded by the supplied message.

The procedure must have been spied on in the current database. Unqualified and
quoted names are supported, as is qualification with the current database name.
Server-qualified names, other databases, negative counts, unspied procedures,
and missing or invalid spy log tables raise severity-16 usage errors.

Counts reflect rows currently retained in the procedure's `_SpyProcedureLog`,
including when `@CommandToExecute` or `@CallOriginal = 1` is used. Logging occurs
before either behavior executes, so counts do not guarantee successful
completion. Deleting log rows changes the count; applying `SpyProcedure` again
starts a new log. These assertions do not compare arguments or execution order.

## Comparing numbers with a tolerance

Use `tSQLt.AssertAlmostEquals` to compare individual numeric values:

```sql
EXEC tSQLt.AssertAlmostEquals
    @Expected = 1.0,
    @Actual = 1.000001,
    @AbsoluteTolerance = 0.00001,
    @RelativeTolerance = 0,
    @Message = N'Calculation result';
```

Parameters, in order, are `@Expected FLOAT`, `@Actual FLOAT`,
`@AbsoluteTolerance FLOAT = 0`, `@RelativeTolerance FLOAT = 0`, and
`@Message NVARCHAR(MAX) = N''`. Tolerances must be non-NULL and non-negative;
invalid tolerances raise a severity-16 error, even when the values are equal.

Two NULL values compare equal; one NULL value compares unequal to any non-NULL
value. Non-NULL values pass if they are equal or either condition holds:

* `ABS(Expected - Actual) <= AbsoluteTolerance`
* `ABS(Expected - Actual) <= RelativeTolerance * MAX(ABS(Expected), ABS(Actual))`

Here `MAX` means the larger of the two magnitudes. Boundaries are inclusive,
and the relative comparison is symmetric. For example, a relative tolerance of
`0.01` permits a difference of up to 1% of the larger magnitude. An absolute
tolerance is useful near zero. Both tolerances default to zero, requiring exact
equality after conversion to `FLOAT(53)`.

All numeric inputs, including integers and DECIMAL values, are converted to
`FLOAT(53)` and compared with floating-point precision. Differences lost in that
conversion cannot be detected; use `AssertEquals` when exact numeric precision
is required. Failure messages include both values and tolerances in scientific
notation with 16 significant digits (the SQL Server 2005-compatible format).
This assertion compares single values; table assertions are unchanged.

## Exact string comparisons

Use `tSQLt.AssertEqualsStringExact` to compare `NVARCHAR(MAX)` values by their
complete storage bytes and lengths, including case, trailing spaces, line endings,
and Unicode representation. Two NULLs are equal; NULL and an empty string differ.
Failure messages show escaped values and the first differing UTF-16 code unit.
See [AssertEqualsStringExact](docs/AssertEqualsStringExact.md) for usage and
diagnostic details.

## Comparing tables by key

Use `tSQLt.AssertEqualsTableByKey` to match rows by an explicitly supplied unique
key and report changed columns, missing keys, and extra keys. Composite keys and
NULL key values are supported; duplicate keys are input errors. Actual columns
absent from Expected are ignored. See
[AssertEqualsTableByKey](docs/AssertEqualsTableByKey.md) for examples, supported
types, key syntax, and diagnostic output.

## Removing tSQLt

To remove tSQLt, run `Uninstall.sql` from the download in the database containing
tSQLt. This standalone script can also clean up an incomplete installation when
`tSQLt.Uninstall` or its dependencies are missing. It can be run repeatedly, even
if tSQLt is absent. Use an account with permission to drop the tSQLt objects,
assembly and database user. User test schemas and server settings are preserved;
external dependencies or database corruption may require manual intervention.

The standalone uninstaller tests require the `SqlServer` PowerShell module.
After building, extract `Build/output/tSQLt/public/tSQLt.zip` and
`Build/output/tSQLtCLR/tSQLtCLR.zip`. For Windows authentication, run:

```powershell
./Build/Tests/Test-Uninstall.ps1 -ServerName '.\SQLEXPRESS' `
  -UninstallScript '<package>/Uninstall.sql' `
  -InstallScript '<package>/tSQLt.class.sql' -AssemblyPath '<clr>/tSQLtCLR.dll'
```

For SQL authentication, also pass `-UserName` and a SecureString `-Password`.
Pass `-ResultFile` to save JUnit XML. The test creates and drops its own disposable
database, checks incomplete and complete installations, reruns removal, verifies
reinstallation, and preserves unrelated user objects. CI supplies both optional
fixture paths above and runs all eight scenarios on SQL Server 2017, 2019, and 2022.

## Development in the masmgr fork

`main` tracks the upstream tSQLt repository. `develop` integrates changes maintained
in this fork. Open pull requests for bug fixes and enhancements against `develop`;
keep each change in its own branch and validate it with CI before merging.

## Continuous integration

For `NoTransaction` tests, let tSQLt restore its bookkeeping tables and then undo
test doubles. Calling `tSQLt.UndoTestDoubles` inside a user cleanup procedure can
delete backups before the framework restores them. This remains a cleanup error;
the restore handler now resolves its transaction before reporting it. Committable
caller transactions retain their work through a restore savepoint. A doomed
caller transaction cannot be partially rolled back and is rolled back in full.
CI checks the issue #222 examples on fresh connections as well as the restore
success/failure and caller-transaction regression tests.

The GitHub Actions `CI` workflow runs on pushes to `develop` and `main`, pull
requests targeting either branch, and manual dispatch. It builds tSQLt with
`Build/LocalBuild.ps1` and runs the existing validation suite with
`Build/LocalValidate.ps1` against SQL Server 2017, 2019, and 2022 on Linux using
Ubuntu runners. No external service credentials or repository secrets are needed.
It also tests the standalone uninstaller from the built package using SQL
authentication. Dedicated results are included in the run summary and artifacts.

Open the PR checks or the repository's **Actions > CI** page to view each SQL
Server job. The run summary lists test counts, failures, errors, and skipped tests.
Validation fails on test failures or errors, missing expected result files, or an
empty test run.

Each job uploads `test-results-sql<version>` containing the result XML files,
validation output, and build/validation logs, including available files when a
step fails. These artifacts are retained for 30 days. Successful jobs also upload
`tSQLt-sql<version>` build artifacts, retained for 14 days.

CI uses a temporary self-signed key. Its build artifacts are for validation only
and must not be distributed as releases. This workflow covers Linux SQL Server;
it does not establish compatibility with Windows or other SQL Server versions.



# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

## Recording and replaying test execution order

Use an explicit class name with `tSQLt.Run` to reproduce a random test order:

```sql
DECLARE @Recorded XML;
EXEC tSQLt.Run
    @TestName = N'MyTests',
    @Seed = 12345,
    @ExecutedOrder = @Recorded OUTPUT;
SELECT @Recorded AS ExecutedOrder;

-- Save the XML outside this session, then supply it to another run.
EXEC tSQLt.Run @TestName = N'MyTests', @TestOrder = @Recorded;
```

The optional trailing parameters are `@Seed INT`, `@TestOrder XML`, and
`@ExecutedOrder XML OUTPUT`. Seed and replay input default to `NULL` and cannot
be combined. Supplying a seed, replay XML, or the output argument enables order
recording and requires an explicit class; individual tests and an omitted class
are rejected. To record the usual random order, pass only `@ExecutedOrder`.
`RunAll`, `RunNew`, and existing calls without these arguments keep their behavior.

The same seed produces the same order for the same test names. Version 1 orders
tests by SHA1 of the seed's four-byte binary representation followed by the test
name's UTF-16 bytes, with binary test-name order breaking ties. Object IDs and
procedure creation order do not affect the result. Different seeds can produce
the same permutation. Replay XML is the authoritative record when the test set
changes; a seed does not reproduce test bodies, data, or test outcomes.

```xml
<TestOrder version="1" class="MyTests">
  <Test ordinal="1" name="test B" />
  <Test ordinal="2" name="test A" />
</TestOrder>
```

Replay executes only the recorded tests, in ordinal order. Newly added tests
are excluded. Deleted or renamed tests, another class, unknown versions,
duplicate tests, and missing or invalid ordinals cause an error before any test
starts. Ordinals must be unique and consecutive from 1. An empty record executes
no tests. Names are stored separately from the class and safely quoted for
execution, including Unicode and punctuation.

Recording happens immediately before dispatch to the normal test runner. Skipped
tests are included because their skip condition is evaluated during dispatch.
On an execution abort, the record contains only the started prefix, including
the test that aborted; unstarted tests are absent. The results of the started
tests are still passed to the result formatter before the abort error is raised;
if the formatter also fails, the abort error is reported. SetUp, transactional rollback,
NoTransaction cleanup, and exception handling continue through the existing
runner. Nested runs have separate records.

When `Run` returns normally, retrieve XML through the output argument. SQL Server does not copy
OUTPUT arguments back when an error unwinds an EXEC into a caller's CATCH.
Therefore, on an execution or result-formatter error, recording-enabled runs
also emit a single-row result set named `ExecutedOrder` before raising the error.
Clients must consume that result set even when the command reports failure;
`INSERT ... EXEC` cannot retain it because the failed insert is rolled back.
For a T-SQL-only workflow with ordinary assertion failures, use
`tSQLt.SetSummaryError 0` to obtain the output argument without a summary error,
and inspect `tSQLt.TestResult` for failures. Connection loss or errors that prevent
SQL Server from continuing cannot guarantee a record.

Internally, the output argument's omitted default is the reserved XML value
`<NotRequested/>`; this distinguishes omission from an uninitialized XML variable
passed explicitly for capture. Do not use that value as an output variable's
initial value. Execution history is not persisted by tSQLt; save the XML in your
own storage or CI artifacts.

The SQL regression tests are in `ExecutionOrderTests`. To verify client receipt
of error result sets against a disposable database with tSQLt installed, run:

```powershell
./Tests/ExecutionOrder.Client.Tests.ps1 -ServerInstance '.\SQLEXPRESS' -Database 'tSQLt_OrderValidation'
```



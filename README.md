# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

## Selecting tests by tag and name

Add tags inside a test procedure definition using annotation comments:

```sql
CREATE PROCEDURE OrderTests.[test creates an order]
AS
--[@tSQLt:Tag]('smoke')
--[@tSQLt:Tag](N'integration')
BEGIN
  -- Test body
  RETURN;
END;
GO

EXEC tSQLt.ListTests @Tag = N'smoke', @NamePattern = N'OrderTests.test%';
EXEC tSQLt.RunSelected @Tag = N'smoke', @NamePattern = N'OrderTests.test%';
EXEC tSQLt.RunSelected @Tag = N'integration',
  @TestResultFormatter = N'tSQLt.XmlResultFormatter';
```

Both filters default to `NULL` (no restriction); providing both combines them
with AND. With neither filter, all tests registered in `tSQLt.Tests` are selected.
Names are matched as unquoted `schema.procedure` using SQL `LIKE` syntax,
including `%`, `_`, and bracket expressions. Tags are matched as complete values
using the database collation, with trailing spaces significant. Empty or
whitespace-only tag filters are errors.

A test can have multiple tag annotations and is selected only once. Each tag
annotation must contain one nonempty SQL string literal, optionally prefixed
with `N`; escape embedded quotes by doubling them. Expressions, additional
arguments, and trailing SQL are not supported. When filtering by tag, malformed
tag annotations in name-matching candidates raise an error identifying the test.
There are no tag expressions, exclusions, or inherited class tags.

`ListTests` returns `TestClassName`, `TestCaseName`, and a safely quoted `FullName`,
sorted by class and test name. It does not initialize the runner, execute tests,
evaluate other annotations, or change existing test results. Skipped tests are
included; skip conditions are evaluated only during execution. Listing order does
not guarantee execution order.

If no tests match, `ListTests` returns an empty result set. `RunSelected` raises a
severity 16 error and returns `-1` before initialization, preserving previous test
results. In CI, use an error-aware SQL client (for example, `sqlcmd -b`) so this
error fails the job. Existing `Run` and `RunAll` calls are unchanged, and tagged
tests can still be executed through either method.



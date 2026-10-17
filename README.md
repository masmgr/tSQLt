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



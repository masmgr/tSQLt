# Spy procedure assertions

`tSQLt.AssertProcedureCalls @ProcedureName, @Expected, @IgnoreOrder = 1, @Message = NULL`
compares the complete call log with an expected table. Each expected row represents
one call. Columns name the arguments to compare (without the leading `@`). Omitted
arguments are ignored; an explicit NULL expects NULL. Extra or missing calls,
including duplicate calls, fail the assertion.

```sql
EXEC tSQLt.SpyProcedure 'dbo.SendMessage';
EXEC dbo.SendMessage @RecipientId=7, @Body=N'hello';

CREATE TABLE #Expected(RecipientId INT);
INSERT #Expected VALUES(7);
EXEC tSQLt.AssertProcedureCalls 'dbo.SendMessage', '#Expected';
```

Order is ignored by default. To check order, add a unique, non-NULL `_id_`
column to the expected table and pass `@IgnoreOrder=0`. Its ascending order
defines the expected sequence; its numbers need not match the log identity values.
The `_id_` column is reserved metadata and is ignored when order is ignored.
An argument named `@_id_` cannot be selected with this API because that name is
reserved. Ordering uses the log's identity column even when SpyProcedure renames
it to avoid argument-name collisions; the identity column is not an argument.
A table containing only `_id_` can check call counts for procedures without
arguments. An empty expected table asserts that no calls occurred.

Failures display the selected argument values, with `<` for missing expected
calls, `>` for extra actual calls and `=` for matches. Ordered comparisons also
display the call position. `@Message` adds context to the failure. Argument data
types must be supported by `tSQLt.AssertEqualsTable`.
Text comparisons use each log column's collation, including case sensitivity,
even when an expected temporary table inherits a different tempdb collation.

Procedures must be spied on in the current database, with a valid marked log
table, as required by `AssertProcedureCalled` and `AssertProcedureNotCalled`.
Expected tables must be local temporary tables or tables in the current database.

`tSQLt.AssertProcedureCalledWith @ProcedureName, @Expected, @Message = NULL`
uses the same projection and comparison rules to assert that at least one call
matches the single row in the expected table. Other calls and repeated matches
are allowed. The expected table must contain exactly one row.

## Optional call limit

```sql
EXEC tSQLt.SpyProcedure 'dbo.SendMessage', @MaxCalls=10;
```

`@MaxCalls` defaults to NULL (unlimited). A nonnegative integer permits that many
logged calls; zero rejects every call. An excess call raises a severity 16 error
and returns before logging, running `@CommandToExecute`, or calling the original
procedure. The guard uses the current log row count, so deleting log rows or
rolling them back also resets the corresponding budget. The log should not be
modified while using the limit. Concurrent calls from multiple sessions are not
an atomic shared limit.

This is a guard for calls reaching the spy. General infinite-loop termination
is the responsibility of an external runner and its timeout/cancellation policy:
loops may never reach the spy, or may catch its errors and continue.

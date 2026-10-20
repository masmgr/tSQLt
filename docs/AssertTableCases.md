# AssertTableCases

```sql
EXEC tSQLt.AssertTableCases
  @TableName=N'#Cases', @CaseIdColumn=N'CaseId',
  @ExpectedColumn=N'Expected', @ActualColumn=N'Actual',
  @Message=NULL, @ExactStrings=0;
```

Compares one expected/actual pair per row without updating the input. Use a
current-database table or an unqualified local temporary table. Column arguments
are literal column names, not expressions or lists.

The string CaseId must contain 1–128 UTF-16 units after conversion to NVARCHAR.
NULL and empty IDs are invalid. Equality of IDs uses bytes and length, so case,
trailing spaces and Unicode representation distinguish IDs.

Expected and Actual must have the same SQL type (including alias type), length,
precision and scale. Supported types are integer, decimal, floating point,
money, bit, uniqueidentifier, date/time, binary and character types. Legacy LOB,
XML, sql_variant and CLR types are not supported for comparison. Ordinary
character comparisons also require matching collations. NULL equals NULL.
No FLOAT conversion is performed for numeric comparisons.

`@ExactStrings=1` requires character columns and compares their NVARCHAR(MAX)
representations using UTF-16 bytes and length. Otherwise ordinary SQL equality
applies, including its case and trailing-space rules.

Invalid input raises a usage error; differences call tSQLt.Fail. Diagnostics
show CaseId, Expected, Actual and descriptive input columns, at most 20 rows
and 16,000 UTF-16 units (excluding the caller's message). Values are abbreviated
and escaped for display only. Total mismatches and displayed rows are reported.
Unformattable descriptive values are marked `<unformatted>`.

This is one assertion inside one test. It does not insert per-case TestResult
rows. For independently executed case results use RegisterCaseTest; do not call
ReportCaseResults inside an assertion's transaction.

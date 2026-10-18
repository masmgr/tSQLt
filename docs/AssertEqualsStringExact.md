# AssertEqualsStringExact

```sql
EXEC tSQLt.AssertEqualsStringExact
     @Expected = N'expected',
     @Actual = N'actual',
     @Message = N'optional context';
```

Compares the complete `NVARCHAR(MAX)` storage bytes and byte lengths. Two NULLs
are equal; NULL and an empty string differ. Case, trailing spaces, full-width
spaces, line endings, embedded zero code units, and Unicode composition differences
are significant. No collation equivalence or normalization is applied.
`AssertEqualsString` retains its existing behavior.

On failure, the optional message is followed by escaped expected and actual values,
their byte lengths, the first differing position, and a small hexadecimal window
around that position. Positions are one-based UTF-16 code units, so a surrogate
pair occupies two positions. A missing suffix differs at the first missing unit;
a NULL versus non-NULL comparison reports position 1.

The display includes at most the first 128 code units of each value, followed by
`... (truncated)` when necessary. Printable ASCII is shown literally, with quotes
and backslashes escaped. Tab, CR, and LF appear as `\t`, `\r`, and `\n`; spaces,
other controls, and non-ASCII units appear as `\uXXXX`. Empty strings appear as
`""`, separately from `NULL`. This representation also preserves unpaired surrogates.
The hexadecimal window contains up to four units before the difference, the
differing unit, and four units after it, in SQL Server's little-endian storage
order. Its starting byte offset is one-based. A missing suffix has no bytes in
that position. Even when the displayed prefix is truncated, comparison uses the
entire value and the hexadecimal window follows the actual difference.

Internal helpers separate comparison (`Private_CompareStringExact`, returning
`IsEqual` and `FirstDifference`) from bounded value display
(`Private_FormatStringExact`). Equal values have a NULL `FirstDifference`.
These helpers can be reused by future assertions without changing this API.

Inputs have already been converted to `NVARCHAR(MAX)` by SQL Server. This assertion
does not validate their original encoding or apply character transformations.

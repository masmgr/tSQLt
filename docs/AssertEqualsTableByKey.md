# AssertEqualsTableByKey

The optional final parameter `@ExactStringColumns NVARCHAR(MAX) = NULL` selects
non-key character columns for exact comparison. For example,
`@ExactStringColumns=N'Name,[Description, detail]'` uses the same bracketed
identifier-list syntax as `@KeyColumns`. Empty, duplicate, unknown, non-character
or key column specifications are usage errors. Columns must exist on both sides.

Each selected value is converted to NVARCHAR(MAX) on its own input side before
common-type normalization. Its complete UTF-16 bytes and length are compared,
including case, width, trailing spaces, line endings and embedded zero units.
NULL equals NULL but differs from an empty string. Diagnostics escape values
and report the first differing UTF-16 unit (one-based); abbreviated displayed
values never drive equality. This does not compare original varchar encodings.
Keys and unspecified columns keep ordinary comparison semantics. Omitting the
parameter retains the existing diagnostic format and behavior.

Compares rows using an explicitly supplied unique key and reports individual
column changes. The existing `tSQLt.AssertEqualsTable` remains available for
comparisons that include duplicate rows and do not require a key.

```sql
EXEC tSQLt.AssertEqualsTableByKey
    @Expected = '#Expected',
    @Actual = '#Actual',
    @KeyColumns = 'OrderId,LineNo',
    @Message = N'Order lines differ'; -- optional
```

All four parameters are `NVARCHAR(MAX)`. The first three are required;
`@Message` defaults to `NULL` and prefixes the assertion failure message.
The assertion returns no result set.

## Comparison rules

- Tables can be local temporary tables or objects in the current database,
  optionally qualified by schema. Input tables are not modified.
- Every column in Expected must exist in Actual. Column order does not matter;
  extra columns in Actual are ignored, including their data types.
- `@KeyColumns` is an ordered, comma-separated list of column names. Whitespace
  around names is ignored. Brackets quote names containing commas, spaces, or
  special characters; escape a closing bracket as `]]`.
  For example, `[Order,Id], [Line]]No]` specifies two columns.
- Empty lists, empty elements, repeated names, unknown names, and malformed
  brackets are input errors. Names are resolved using the database collation;
  the list is never executed as SQL expressions.
- NULL matches NULL in each key component and in non-key values. A key containing
  NULL is permitted, but each key combination must occur at most once per table.
- Compatible differing column types use SQL Server's `UNION ALL` common-type
  rules, as in `AssertEqualsTable`. Uniqueness is checked after this conversion:
  Actual keys `'01'` and `'1'` are duplicates when Expected has an integer key.
  Incompatible types, values, or collations produce SQL errors.
- Non-key values are compared in their SQL types, before conversion to display
  text. String comparison follows SQL Server's collation and padding rules.
- Row order is ignored. Tables containing only key columns are supported.
  Changing a key is reported as one missing key and one extra key.

## Failure output

Changed non-key columns produce one diagnostic row per column. Missing and
extra rows produce one diagnostic row per key, regardless of their column count.
For example, given a changed quantity, a missing line, and an extra line:

```text
|Key1: OrderId|Key2: LineNo|DifferenceType|ColumnName|ExpectedValue|ActualValue|
|100         |1           |Changed       |Quantity  |2            |3          |
|100         |2           |Missing       |!NULL!    |<present>    |<missing>  |
|100         |3           |Extra         |!NULL!    |<missing>    |<present>  |
```

Keys appear in the specified order, followed by `DifferenceType`, `ColumnName`,
`ExpectedValue`, and `ActualValue`. Key headers have an ordinal prefix such as
`Key1: OrderId` so a key named `DifferenceType` cannot collide with the diagnostic
columns. Headers longer than SQL Server's 128-character identifier limit are
shortened. Rows are ordered by key, difference type, and Expected column order.
Unchanged columns and matching rows are omitted.

NULL values are displayed as `!NULL!`. Binary values are hexadecimal. Output uses
`tSQLt.TableToText`, including its existing column-width limits. The text
`!NULL!` in a string value can therefore look like a displayed NULL; it still
compares as a string.

Differences call `tSQLt.Fail`. Invalid key lists, missing Actual columns,
unsupported types, and duplicate keys raise severity-16 input errors instead.
Duplicate-key errors identify the offending table and show the key values and
`DuplicateCount`; Expected is validated first.

## Supported types

The supported type family matches `AssertEqualsTable`: types must support SQL
grouping and comparison. `text`, `ntext`, `image`, `xml`, `timestamp`/`rowversion`,
`geometry`, `geography`, and non-byte-ordered CLR types are unsupported, even
when the tables are empty. Types introduced after SQL Server 2005 require a
server that supports those types; this assertion adds no new server-version
requirement.

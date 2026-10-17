# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

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



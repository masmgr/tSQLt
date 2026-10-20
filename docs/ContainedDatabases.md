# Contained databases and metadata collation

tSQLt normalizes internal object-name comparisons and generated SQL to the
current database collation. This includes catalog names and definitions, and
temporary tables used to store metadata. It does not change the collation of
application data: FakeTable retains each source string column's collation, and
ordinary assertions retain SQL equality semantics.

On Windows, run `./Build/Tests/Invoke-LocalDBValidation.ps1` from PowerShell.
It builds a validation-only unsigned CLR assembly from source, trusts its hash
on the dedicated `tSQLtValidation` LocalDB instance, and creates disposable
Japanese-collation ordinary and partially contained databases. It does not
disable CLR strict security or require external collation patches. Databases
are removed even on failure unless `-KeepDatabases` is specified; the dedicated
instance is retained for reuse. Results are in `Build/output/LocalDB`.

Use `-TestClasses` to select additional repository test classes. This validation
requires SQL Server 2017 or later LocalDB and a .NET SDK capable of building
the repository's .NET Framework CLR project. Older engine compatibility is
covered separately; a LocalDB result is not evidence of testing older versions.

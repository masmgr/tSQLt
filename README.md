# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

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



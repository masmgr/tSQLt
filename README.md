# tSQLt

Download the latest version at [tSQLt.org](http://tsqlt.org/downloads/).

tSQLt is a unit testing framework for Microsoft SQL Server. 
It is compatible with SQL Server 2005 (service pack 2 required) and above on all editions.

tSQLt allows you to implement unit tests in T-SQL. This is important as you do not have to switch between various tools to create your code and your unit tests. tSQLt also provides the following features to make it easier to create and manage unit tests:

* Tests are automatically run within transactions – this keeps tests independent and reduces any cleanup work you need
* Tests can be grouped together within a schema – allowing you to organize your tests and use common setup methods
* Output can be generated in plain text or XML – making it easier to integrate with a continuous integration tool

tSQLt is licensed under Apache 2.0 (https://github.com/tSQLt-org/tSQLt/blob/master/Build/License.txt)

To remove tSQLt, run `Uninstall.sql` from the download in the database containing
tSQLt. This standalone script can also clean up an incomplete installation when
`tSQLt.Uninstall` or its dependencies are missing. It can be run repeatedly, even
if tSQLt is absent. Use an account with permission to drop the tSQLt objects,
assembly and database user. User test schemas and server settings are preserved;
external dependencies or database corruption may require manual intervention.

To test the standalone uninstaller against a local SQL Server with Windows
authentication, first run the build, then run:

```powershell
./Build/Tests/Test-Uninstall.ps1 -ServerName '.\SQLEXPRESS'
```

The test creates and drops its own database. Supply `-InstallScript` with the
built `tSQLt.class.sql` and `-AssemblyPath` with a built `tSQLtCLR.dll` to also
test a complete installation, reinstallation, and a leftover CLR assembly.



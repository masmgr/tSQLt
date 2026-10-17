[CmdletBinding()]
param(
    [string]$ServerName = '.\SQLEXPRESS',
    [string]$UninstallScript = (Join-Path $PSScriptRoot '../temp/tSQLtBuild/Uninstall.sql'),
    [string]$InstallScript,
    [string]$AssemblyPath
)

# Integration tests use a new disposable database, never an existing database.
# Generate Uninstall.sql with tSQLt_Build/CreateDropClassStatement.ps1 first.
# Optional InstallScript and AssemblyPath exercise a full install and a leftover
# CLR assembly respectively. AssemblyPath must be a SQL Server compatible DLL.
$ErrorActionPreference = 'Stop';
Add-Type -AssemblyName System.Data;
$UninstallSql = Get-Content -Raw -LiteralPath $UninstallScript;
$InstallSql = if ($InstallScript) { Get-Content -Raw -LiteralPath $InstallScript };
$AssemblySql = if ($AssemblyPath) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $AssemblyPath));
    'CREATE ASSEMBLY tSQLtCLR FROM 0x' + ([BitConverter]::ToString($bytes).Replace('-', '')) + ' WITH PERMISSION_SET = SAFE;';
};

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder;
$builder['Data Source'] = $ServerName;
$builder['Integrated Security'] = $true;
$builder['TrustServerCertificate'] = $true;
$builder['Initial Catalog'] = 'master';
$connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString);
$databaseName = 'tSQLt_UninstallTest_' + [Guid]::NewGuid().ToString('N');
$databaseCreated = $false;

function Invoke-TestSql([string]$Sql) {
    foreach ($batch in [regex]::Split($Sql, '(?im)^\s*GO\s*\r?$')) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            $command = $connection.CreateCommand();
            try {
                $command.CommandText = $batch;
                $command.CommandTimeout = 60;
                $null = $command.ExecuteNonQuery();
            }
            finally { $command.Dispose(); }
        }
    }
}

$fixtures = @(
    @{ Name = 'absent installation'; Sql = '' },
    @{ Name = 'schema only'; Sql = 'CREATE SCHEMA tSQLt;' },
    @{ Name = 'database user only'; Sql = 'CREATE USER [tSQLt.TestClass] WITHOUT LOGIN;' },
    @{ Name = 'incomplete installation without helpers'; Sql = @'
CREATE SCHEMA tSQLt;
GO
CREATE USER [tSQLt.TestClass] WITHOUT LOGIN;
CREATE TYPE tSQLt.PartialType FROM INT;
CREATE TABLE tSQLt.ParentTable(Id INT PRIMARY KEY);
CREATE TABLE tSQLt.ChildTable(Id INT REFERENCES tSQLt.ParentTable(Id));
GO
CREATE VIEW tSQLt.PartialView AS SELECT Id FROM tSQLt.ParentTable;
GO
CREATE PROCEDURE tSQLt.PartialProcedure AS SELECT 1;
GO
CREATE FUNCTION tSQLt.PartialFunction() RETURNS INT AS BEGIN RETURN 1; END;
'@ },
    @{ Name = 'broken installed helpers are never called'; Sql = @'
CREATE SCHEMA tSQLt;
GO
CREATE PROCEDURE tSQLt.Uninstall AS RAISERROR('Broken Uninstall called',16,1);
GO
CREATE PROCEDURE tSQLt.DropClass AS RAISERROR('Broken DropClass called',16,1);
GO
CREATE FUNCTION tSQLt.Private_GetDropItemCmd() RETURNS INT AS BEGIN RETURN 0; END;
'@ }
);
if ($AssemblySql) { $fixtures += @{ Name = 'leftover CLR assembly without schema'; Sql = $AssemblySql }; }
if ($InstallSql) { $fixtures += @{ Name = 'complete installation'; Sql = $InstallSql }; }

try {
    $connection.Open();
    Invoke-TestSql "CREATE DATABASE [$databaseName];";
    $databaseCreated = $true;
    $connection.ChangeDatabase($databaseName);
    if ($AssemblySql -or $InstallSql) {
        # Permit unsigned test assemblies only in this disposable database.
        # No server-level CLR or security configuration is changed.
        Invoke-TestSql "ALTER DATABASE [$databaseName] SET TRUSTWORTHY ON;";
    }
    Invoke-TestSql @'
CREATE SCHEMA UserTests;
GO
CREATE TABLE UserTests.Preserved(Id INT);
INSERT INTO UserTests.Preserved VALUES(42);
'@;
    foreach ($fixture in $fixtures) {
        Invoke-TestSql 'BEGIN TRAN;';
        try {
            Invoke-TestSql $fixture.Sql;
            # The second execution verifies rerunning after successful removal.
            Invoke-TestSql $UninstallSql;
            Invoke-TestSql $UninstallSql;
            Invoke-TestSql @'
IF SCHEMA_ID('tSQLt') IS NOT NULL
   OR USER_ID('tSQLt.TestClass') IS NOT NULL
   OR EXISTS(SELECT 1 FROM sys.assemblies WHERE name = 'tSQLtCLR')
  RAISERROR('tSQLt objects remain after uninstall.',16,1);
IF (SELECT COUNT(*) FROM UserTests.Preserved WHERE Id = 42) <> 1
  RAISERROR('User test data was changed.',16,1);
'@;
            if ($fixture.Name -eq 'complete installation') {
                Invoke-TestSql $InstallSql;
                Invoke-TestSql 'EXEC tSQLt.AssertEquals @Expected = 1, @Actual = 1;';
                Invoke-TestSql $UninstallSql;
            }
            Write-Host "PASS: $($fixture.Name)";
        }
        finally { Invoke-TestSql 'IF @@TRANCOUNT > 0 ROLLBACK;'; }
    }

    Invoke-TestSql 'BEGIN TRAN; CREATE USER [tSQLt.TestClass] WITHOUT LOGIN;';
    try {
        Invoke-TestSql 'CREATE SCHEMA DependentSchema AUTHORIZATION [tSQLt.TestClass];';
        $failed = $false;
        try { Invoke-TestSql $UninstallSql; }
        catch {
            if ($_.Exception.InnerException.Number -ne 15138) { throw; }
            $failed = $true;
        }
        if (-not $failed) { throw 'Expected an error for a database user that owns another schema.'; }
        Invoke-TestSql @'
IF SCHEMA_ID('DependentSchema') IS NULL
  RAISERROR('An external schema was removed.',16,1);
'@;
        Write-Host 'PASS: external dependency errors are reported without deleting its schema';
    }
    finally { Invoke-TestSql 'IF @@TRANCOUNT > 0 ROLLBACK;'; }
}
finally {
    if ($connection.State -eq 'Open' -and $databaseCreated) {
        Invoke-TestSql 'IF @@TRANCOUNT > 0 ROLLBACK;';
        $connection.ChangeDatabase('master');
        Invoke-TestSql "ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$databaseName];";
    }
    $connection.Dispose();
}

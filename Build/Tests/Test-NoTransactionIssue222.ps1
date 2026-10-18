[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServerName,
    [Parameter(Mandatory = $true)][string]$UserName,
    [Parameter(Mandatory = $true)][securestring]$Password,
    [Parameter(Mandatory = $true)][string]$InstallScript,
    [Parameter(Mandatory = $true)][string]$ResultFile
)

# Run the issue's public-API examples outside any test-runner transaction.
# Each example gets a fresh connection and a disposable database, including the
# invalid-cleanup example that deliberately leaves tSQLt in its FATAL state.
$ErrorActionPreference = 'Stop';
Import-Module SqlServer -ErrorAction Stop;
$installSql = Get-Content -LiteralPath $InstallScript -Raw;
$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new();
$builder['Data Source'] = $ServerName;
$builder['User ID'] = $UserName;
$builder['Password'] = [System.Net.NetworkCredential]::new('', $Password).Password;
$builder['TrustServerCertificate'] = $true;
$builder['Initial Catalog'] = 'master';
$builder['Pooling'] = $false;
$testResults = [System.Collections.Generic.List[object]]::new();

function Invoke-TestSql([string]$Sql) {
    foreach ($batch in [regex]::Split($Sql, '(?im)^\s*GO\s*\r?$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue; }
        $command = $connection.CreateCommand();
        try {
            $command.CommandText = $batch;
            $command.CommandTimeout = 120;
            $null = $command.ExecuteNonQuery();
        } finally { $command.Dispose(); }
    }
}

function Get-TestValue([string]$Query) {
    $command = $connection.CreateCommand();
    try {
        $command.CommandText = $Query;
        return $command.ExecuteScalar();
    } finally { $command.Dispose(); }
}

function Write-TestResults {
    $document = [System.Xml.XmlDocument]::new();
    $suite = $document.CreateElement('testsuite');
    $suite.SetAttribute('name', 'Issue222FreshConnection');
    $suite.SetAttribute('tests', [string]$testResults.Count);
    $suite.SetAttribute('failures', [string]@($testResults | Where-Object { $_.Failure }).Count);
    $suite.SetAttribute('errors', '0');
    $suite.SetAttribute('skipped', '0');
    foreach ($result in $testResults) {
        $case = $document.CreateElement('testcase');
        $case.SetAttribute('classname', 'Issue222FreshConnection');
        $case.SetAttribute('name', $result.Name);
        if ($result.Failure) {
            $failure = $document.CreateElement('failure');
            $failure.InnerText = $result.Failure;
            $null = $case.AppendChild($failure);
        }
        $output = $document.CreateElement('system-out');
        $output.InnerText = $result.Diagnostics;
        $null = $case.AppendChild($output);
        $null = $suite.AppendChild($case);
    }
    $null = $document.AppendChild($suite);
    $path = [IO.Path]::GetFullPath($ResultFile);
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));
    $document.Save($path);
}

$cases = @(
    @{ Name = 'original minimum with premature UndoTestDoubles reports FATAL without a transaction leak';
       CleanUp = 'EXEC tSQLt.UndoTestDoubles;'; Body = ''; Result = 'FATAL' },
    @{ Name = 'trivial NoTransaction test with empty cleanup succeeds';
       CleanUp = ''; Body = ''; Result = 'Success' },
    @{ Name = 'comment reproduction with FakeTable and empty cleanup succeeds and restores data';
       CleanUp = ''; Body = 'EXEC tSQLt.FakeTable @SchemaName=N''dbo'', @TableName=N''SomeExistingTable'';'; Result = 'Success' }
);
$setupTemplate = @'
EXEC tSQLt.NewTestClass 'MinRepro';
CREATE TABLE dbo.SomeExistingTable(Id INT);
INSERT INTO dbo.SomeExistingTable VALUES(42);
GO
CREATE OR ALTER PROCEDURE MinRepro.[CleanUp__trivial]
AS
BEGIN
  SET NOCOUNT ON;
  /*CLEANUP*/
END;
GO
CREATE OR ALTER PROCEDURE MinRepro.[test trivial no transaction]
--[@tSQLt:NoTransaction]('[MinRepro].[CleanUp__trivial]')
AS
BEGIN
  SET NOCOUNT ON;
  /*BODY*/
  EXEC tSQLt.AssertEquals @Expected=1, @Actual=1;
END;
GO
'@;

try {
    foreach ($case in $cases) {
        $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString);
        $databaseName = 'tSQLt_Issue222_' + [guid]::NewGuid().ToString('N');
        $databaseCreated = $false;
        $diagnostics = '';
        try {
            $connection.Open();
            Invoke-TestSql 'SET LANGUAGE us_english; SET QUOTED_IDENTIFIER ON; SET IMPLICIT_TRANSACTIONS OFF;';
            Invoke-TestSql "CREATE DATABASE [$databaseName];";
            $databaseCreated = $true;
            $connection.ChangeDatabase($databaseName);
            # Trust only this disposable database's CI-signed assembly.
            Invoke-TestSql "ALTER DATABASE [$databaseName] SET TRUSTWORTHY ON;";
            Invoke-TestSql $installSql;
            Invoke-TestSql ($setupTemplate.Replace('/*CLEANUP*/', $case.CleanUp).Replace('/*BODY*/', $case.Body));
            $runError = $null;
            try { Invoke-TestSql "EXEC tSQLt.Run 'MinRepro.[test trivial no transaction]';"; }
            catch { $runError = $_.Exception.InnerException; if (-not $runError) { throw; } }
            $count = Get-TestValue 'SELECT @@TRANCOUNT;';
            $state = Get-TestValue 'SELECT XACT_STATE();';
            $result = Get-TestValue 'SELECT Result FROM tSQLt.TestResult;';
            $diagnostics = "Result=$result; @@TRANCOUNT=$count; XACT_STATE=$state";
            if ($count -ne 0 -or $state -ne 0 -or $result -ne $case.Result) {
                throw "Unexpected state: $diagnostics";
            }
            if ($runError -and @($runError.Errors | Where-Object { $_.Number -in @(266,3930,3998) }).Count) {
                throw "Transaction error escaped: $runError";
            }
            if ($case.Result -eq 'Success' -and $runError) { throw $runError; }
            if ($case.Result -eq 'FATAL') {
                $message = Get-TestValue 'SELECT Msg FROM tSQLt.TestResult;';
                if (-not $runError -or $message -notlike '*Invalid object name*tSQLt_tempobject*') {
                    throw "Expected a reported missing-backup cleanup failure, got: $message";
                }
            }
            if ((Get-TestValue 'SELECT Id FROM dbo.SomeExistingTable;') -ne 42) {
                throw 'Original application data was not restored.';
            }
            $testResults.Add(@{ Name=$case.Name; Failure=$null; Diagnostics=$diagnostics });
            Write-Host "PASS: $($case.Name) ($diagnostics)";
        }
        catch {
            $testResults.Add(@{ Name=$case.Name; Failure=$_.Exception.ToString(); Diagnostics=$diagnostics });
            throw;
        }
        finally {
            try {
                if ($connection.State -eq 'Open' -and $databaseCreated) {
                    Invoke-TestSql 'IF @@TRANCOUNT > 0 ROLLBACK;';
                    $connection.ChangeDatabase('master');
                    Invoke-TestSql "ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$databaseName];";
                }
            } finally { $connection.Dispose(); }
        }
    }
} finally { Write-TestResults; }

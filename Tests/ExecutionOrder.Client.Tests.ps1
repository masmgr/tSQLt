<# Client tests are needed because INSERT ... EXEC rolls back captured rows on error. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ServerInstance,
    [Parameter(Mandatory=$true)][string]$Database,
    [string]$UserName,
    [securestring]$Password,
    [string]$InstallScript,
    [string]$ResultFile
)
$ErrorActionPreference = 'Stop'
Import-Module SqlServer -ErrorAction Stop
$connectionSettings = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$connectionSettings['Data Source'] = $ServerInstance
$connectionSettings['Initial Catalog'] = if ($InstallScript) { 'master' } else { $Database }
if ($UserName) {
    if ($null -eq $Password) { throw 'Password is required with UserName.' }
    $connectionSettings['User ID'] = $UserName
    $connectionSettings['Password'] = [System.Net.NetworkCredential]::new('', $Password).Password
} else { $connectionSettings['Integrated Security'] = $true }
$connectionSettings['TrustServerCertificate'] = $true
$connectionSettings['Pooling'] = $false
$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($connectionSettings.ConnectionString)
$databaseCreated = $false
$quotedDatabase = '[' + $Database.Replace(']', ']]') + ']'
$scenarioResults = [System.Collections.Generic.List[object]]::new()
$className = 'OrderClient_' + [Guid]::NewGuid().ToString('N')
$transaction = $null

function Invoke-OrderSql([string]$Sql) {
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandText = $Sql
    $command.CommandTimeout = 120
    try { [void]$command.ExecuteNonQuery() } finally { $command.Dispose() }
}

function Read-Order([string]$Sql, [int]$ExpectedCount, [string]$ExpectedError = '') {
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandText = $Sql
    $command.CommandTimeout = 120
    $reader = $null
    $record = $null
    $recordCount = 0
    $errorMessage = ''
    try {
        $reader = $command.ExecuteReader()
        do {
            while ($reader.Read()) {
                if ($reader.FieldCount -eq 1 -and $reader.GetName(0) -eq 'ExecutedOrder') {
                    $record = [xml]$reader.GetString(0)
                    $recordCount++
                }
            }
        } while ($reader.NextResult())
    } catch [Microsoft.Data.SqlClient.SqlException] {
        $errorMessage = $_.Exception.Message
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $command.Dispose()
    }
    if ($ExpectedError -eq '' -and $errorMessage -ne '') { throw $errorMessage }
    if ($ExpectedError -ne '' -and $errorMessage -notlike "*$ExpectedError*") {
        throw "Expected error '$ExpectedError', got '$errorMessage'."
    }
    if ($recordCount -ne 1 -or $null -eq $record -or $record.SelectNodes('/TestOrder/Test').Count -ne $ExpectedCount) {
        throw "Expected an execution-order result set containing $ExpectedCount tests."
    }
    $scenarioResults.Add([pscustomobject]@{Name="scenario $($scenarioResults.Count + 1)"; Failure=$null; Record=$record.OuterXml})
    return $record
}

try {
    $connection.Open()
    Invoke-OrderSql 'SET QUOTED_IDENTIFIER ON;'
    if ($InstallScript) {
        Invoke-OrderSql "CREATE DATABASE $quotedDatabase COLLATE SQL_Latin1_General_CP1_CS_AS;"
        $databaseCreated = $true
        $connection.ChangeDatabase($Database)
        foreach ($batch in [regex]::Split((Get-Content -LiteralPath $InstallScript -Raw), '(?im)^\s*GO\s*\r?$')) {
            if (-not [string]::IsNullOrWhiteSpace($batch)) { Invoke-OrderSql $batch }
        }
    }
    Invoke-OrderSql "CREATE SCHEMA [$className];"
    foreach ($name in @('A','B','C')) {
        Invoke-OrderSql "CREATE PROCEDURE [$className].[test $name] AS RETURN;"
    }
    $record = Read-Order "DECLARE @x XML; EXEC tSQLt.Run N'$className', N'tSQLt.NullTestResultFormatter', @Seed=0, @ExecutedOrder=@x OUTPUT; SELECT @x AS ExecutedOrder;" 3
    $savedXml = $record.OuterXml.Replace("'", "''")
    # The second connection proves replay does not rely on session-local state.
    $connection.Close()
    $connection.Open()
    $connection.ChangeDatabase($Database)
    Invoke-OrderSql 'SET QUOTED_IDENTIFIER ON;'
    $replayed = Read-Order "DECLARE @x XML; EXEC tSQLt.Run N'$className', N'tSQLt.NullTestResultFormatter', @TestOrder=N'$savedXml', @ExecutedOrder=@x OUTPUT; SELECT @x AS ExecutedOrder;" 3
    if ($record.OuterXml -ne $replayed.OuterXml) { throw 'Replay changed the recorded order.' }

    # Exercise the real NoTransaction cleanup without outer test doubles or transactions.
    Invoke-OrderSql "CREATE TABLE [$className].LifecycleLog(Phase NVARCHAR(20), TranCount INT); INSERT [$className].LifecycleLog VALUES('before',@@TRANCOUNT);"
    Invoke-OrderSql "CREATE PROCEDURE [$className].SetUp AS INSERT [$className].LifecycleLog VALUES('setup',@@TRANCOUNT);"
    Invoke-OrderSql "CREATE PROCEDURE [$className].CleanUp AS INSERT [$className].LifecycleLog VALUES('cleanup',@@TRANCOUNT);"
    Invoke-OrderSql "--[@tSQLt:NoTransaction](DEFAULT)`nALTER PROCEDURE [$className].[test A] AS INSERT [$className].LifecycleLog VALUES('body',@@TRANCOUNT);"
    $noTransaction = Read-Order "DECLARE @x XML; EXEC tSQLt.Run N'$className', N'tSQLt.NullTestResultFormatter', @TestOrder=N'<TestOrder version=""1"" class=""$className""><Test ordinal=""1"" name=""test A""/></TestOrder>', @ExecutedOrder=@x OUTPUT; SELECT @x AS ExecutedOrder;" 1
    Invoke-OrderSql "IF (SELECT COUNT(*) FROM [$className].LifecycleLog)<>4 OR (SELECT COUNT(DISTINCT TranCount) FROM [$className].LifecycleLog)<>1 OR NOT EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class=N'$className' AND TestCase=N'test A' AND Result='Success' AND TranName IS NULL) RAISERROR('NoTransaction lifecycle changed',16,10);"
    Invoke-OrderSql "DROP PROCEDURE [$className].SetUp; DROP PROCEDURE [$className].CleanUp;"
    Invoke-OrderSql "ALTER PROCEDURE [$className].[test A] AS RETURN;"

    $transaction = $connection.BeginTransaction()
    Invoke-OrderSql "ALTER PROCEDURE [$className].[test B] AS EXEC tSQLt.Fail 'client summary failure';"
    Invoke-OrderSql 'EXEC tSQLt.SetSummaryError 1;'
    # Real failing summaries must expose XML even when the caller catches the error.
    $record = Read-Order "BEGIN TRY EXEC tSQLt.Run N'$className', @Seed=0; END TRY BEGIN CATCH; THROW; END CATCH;" 3 'Test Case Summary:'
    $captured = Read-Order "DECLARE @x XML; EXEC tSQLt.Run N'$className', @ExecutedOrder=@x OUTPUT;" 3 'Test Case Summary:'

    Invoke-OrderSql "EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest', @CommandToExecute=N'IF @TestName=N''[$className].[test C]'' RAISERROR(''client abort'',16,10);';"
    $prefix = Read-Order "EXEC tSQLt.Run N'$className', @Seed=0;" 2 'client abort'
    if ($prefix.TestOrder.Test[0].name -ne 'test A' -or $prefix.TestOrder.Test[1].name -ne 'test C') {
        throw 'The abort record did not contain exactly the started prefix.'
    }
    Write-Output 'Execution-order client tests: 6 scenarios passed.'
} catch {
    $scenarioResults.Add([pscustomobject]@{Name='client integration failure'; Failure=$_.Exception.Message; Record=''})
    throw
} finally {
    if ($null -ne $transaction) { $transaction.Rollback(); $transaction.Dispose(); $transaction = $null }
    try {
        if ($databaseCreated) {
            if ($connection.State -ne [System.Data.ConnectionState]::Open) { $connection.Open() }
            $connection.ChangeDatabase('master')
            Invoke-OrderSql "ALTER DATABASE $quotedDatabase SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $quotedDatabase;"
        } elseif ($connection.State -eq [System.Data.ConnectionState]::Open) {
            Invoke-OrderSql "IF SCHEMA_ID(N'$className') IS NOT NULL EXEC tSQLt.DropClass N'$className';"
        }
    } finally {
        $connection.Dispose()
        if ($ResultFile) {
            $document = [xml]'<testsuite name="ExecutionOrderClient"/>'
            $suite = $document.DocumentElement
            $suite.SetAttribute('tests', [string]$scenarioResults.Count)
            $suite.SetAttribute('failures', [string]@($scenarioResults | Where-Object { $_.Failure }).Count)
            $suite.SetAttribute('errors', '0')
            $suite.SetAttribute('skipped', '0')
            foreach ($scenario in $scenarioResults) {
                $case = $document.CreateElement('testcase')
                $case.SetAttribute('classname', 'ExecutionOrderClient')
                $case.SetAttribute('name', $scenario.Name)
                if ($scenario.Failure) {
                    $failure = $document.CreateElement('failure')
                    $failure.InnerText = $scenario.Failure
                    $null = $case.AppendChild($failure)
                }
                $output = $document.CreateElement('system-out')
                $output.InnerText = $scenario.Record
                $null = $case.AppendChild($output)
                $null = $suite.AppendChild($case)
            }
            $resultPath = [IO.Path]::GetFullPath($ResultFile)
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resultPath))
            $document.Save($resultPath)
        }
    }
}

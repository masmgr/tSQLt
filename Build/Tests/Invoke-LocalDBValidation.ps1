[CmdletBinding()]
param(
    [string]$InstanceName = 'tSQLtValidation',
    [string[]]$TestClasses = @('CollationTests','AssertTableCasesTests','ExactTableStringTests','AssertEqualsTableByKeyTests','AssertEqualsStringExactTests','CaseTests','SelectedTestsTests'),
    [switch]$KeepDatabases
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output = Join-Path $root 'Build/output/LocalDB'
$null = New-Item -ItemType Directory -Force $output
if ($InstanceName -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid dedicated instance name.' }
& sqllocaldb create $InstanceName -s
if ($LASTEXITCODE) { throw 'Could not start validation LocalDB.' }
& dotnet build "$root/tSQLtCLR/tSQLtCLR/tSQLtCLR.csproj" -p:SignAssembly=false --nologo
if ($LASTEXITCODE) { throw 'CLR build failed.' }
$dll = "$root/tSQLtCLR/tSQLtCLR/bin/Debug/net40/tSQLtCLR.dll"
$bytes = [IO.File]::ReadAllBytes($dll)
$hex = '0x' + [BitConverter]::ToString($bytes).Replace('-','')
$sha = [Security.Cryptography.SHA512]::Create()
try { $hash = '0x' + [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') }
finally { $sha.Dispose() }
$version = [Reflection.AssemblyName]::GetAssemblyName($dll).Version.ToString()
& dotnet build "$root/tSQLtCLR/tSQLtTestUtilCLR/tSQLtTestUtilCLR.csproj" -p:SignAssembly=false --nologo
if ($LASTEXITCODE) { throw 'Test utility CLR build failed.' }
$utilBytes = [IO.File]::ReadAllBytes("$root/tSQLtCLR/tSQLtTestUtilCLR/bin/Debug/net40/tSQLtTestUtilCLR.dll")
$utilHex = '0x' + [BitConverter]::ToString($utilBytes).Replace('-','')
$sha = [Security.Cryptography.SHA512]::Create()
try { $utilHash = '0x' + [BitConverter]::ToString($sha.ComputeHash($utilBytes)).Replace('-','') }
finally { $sha.Dispose() }
$connection = [System.Data.SqlClient.SqlConnection]::new("Server=(localdb)\$InstanceName;Integrated Security=true;Initial Catalog=master;Pooling=false")
$connection.Open()
function Invoke-Sql([string]$sql) {
    foreach ($batch in [regex]::Split($sql,'(?im)^[\t ]*GO[\t ]*(?:--[^\r\n]*)?\r?$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $cmd = $connection.CreateCommand()
        try { $cmd.CommandText=$batch; $cmd.CommandTimeout=180; $null=$cmd.ExecuteNonQuery() }
        finally { $cmd.Dispose() }
    }
}
function Get-Value([string]$sql) {
    $cmd=$connection.CreateCommand()
    try { $cmd.CommandText=$sql; $cmd.CommandTimeout=180; return $cmd.ExecuteScalar() }
    finally { $cmd.Dispose() }
}
function Read-BuildSource([string]$path) {
    $text=[IO.File]::ReadAllText($path)
    $match=[regex]::Match($text,'(?s)---Build\+\s*(.*?)(?:---Build-|$)')
    if ($match.Success) { $text=$match.Groups[1].Value }
    return $text.Replace('$LATEST-BUILD-NUMBER$',$version)
}
try {
    Invoke-Sql "EXEC sp_configure 'show advanced options',1; RECONFIGURE;
        EXEC sp_configure 'clr enabled',1; RECONFIGURE;
        EXEC sp_configure 'contained database authentication',1; RECONFIGURE;
        IF NOT EXISTS(SELECT 1 FROM sys.trusted_assemblies WHERE hash=$hash)
          EXEC sys.sp_add_trusted_assembly @hash=$hash,@description=N'tSQLt local validation';"
    Invoke-Sql "IF NOT EXISTS(SELECT 1 FROM sys.trusted_assemblies WHERE hash=$utilHash)
          EXEC sys.sp_add_trusted_assembly @hash=$utilHash,@description=N'tSQLt test utility validation';"
    foreach ($contained in @(0,1)) {
        $db='tSQLt_LocalValidation_'+[Guid]::NewGuid().ToString('N')
        try {
            $containment=if ($contained) {'PARTIAL'} else {'NONE'}
            Invoke-Sql "CREATE DATABASE [$db] CONTAINMENT=$containment COLLATE Japanese_CI_AS;"
            $connection.ChangeDatabase($db)
            foreach ($entry in Get-Content "$root/Source/BuildOrder.txt") {
                if ($entry -match 'CreateAssembly.sql$') {
                    Invoke-Sql "CREATE ASSEMBLY tSQLtCLR FROM $hex WITH PERMISSION_SET=SAFE;"
                } elseif ($entry -match 'GetAssemblyKeyBytes.sql$') {
                    Invoke-Sql 'CREATE FUNCTION tSQLt.Private_GetAssemblyKeyBytes() RETURNS VARBINARY(MAX) AS BEGIN RETURN 0x; END;'
                } elseif ($entry -notmatch '^\.\.') {
                    try { Invoke-Sql (Read-BuildSource "$root/Source/$entry") }
                    catch { throw "Installing $entry (contained=$contained): $_" }
                }
            }
            Invoke-Sql ([IO.File]::ReadAllText("$root/TestUtil/tSQLt_testutil.class.sql"))
            Invoke-Sql "CREATE ASSEMBLY tSQLtTestUtilCLR FROM $utilHex WITH PERMISSION_SET=SAFE;"
            Invoke-Sql ([IO.File]::ReadAllText("$root/TestUtil/tSQLtTestUtilCLR_CreateItems.sql"))
            foreach ($class in $TestClasses) {
                if ($class -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid test class.' }
                Invoke-Sql ([IO.File]::ReadAllText("$root/Tests/$class.class.sql"))
                # SummaryError is disabled only to persist diagnostics before throwing below.
                Invoke-Sql "EXEC tSQLt.SetSummaryError 0; EXEC tSQLt.Run @TestName=N'$class';"
                $failures=Get-Value "SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result NOT IN('Success','Skipped');"
                $count=Get-Value 'SELECT COUNT(*) FROM tSQLt.TestResult;'
                $xml=Get-Value "SELECT CONVERT(NVARCHAR(MAX),(SELECT Class AS [@classname],TestCase AS [@name],Result AS [@result],Msg AS [message] FROM tSQLt.TestResult ORDER BY Id FOR XML PATH('testcase'),ROOT('testsuite'),TYPE));"
                [IO.File]::WriteAllText("$output/$class-contained$contained.xml",[string]$xml)
                if ($failures -or !$count) { throw "$class failed: $failures failures in $count tests (contained=$contained). See $output." }
                Write-Host "$class : $count passed (contained=$contained)"
            }
            Invoke-Sql 'EXEC tSQLt.Uninstall;'
            if ((Get-Value "SELECT COUNT(*) FROM sys.schemas WHERE name=N'tSQLt';") -ne 0) { throw 'Uninstall left tSQLt schema.' }
        } finally {
            $connection.ChangeDatabase('master')
            if (!$KeepDatabases) { Invoke-Sql "IF DB_ID(N'$db') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END;" }
        }
    }
} finally { $connection.Dispose() }

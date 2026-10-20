[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerName,
    [Parameter(Mandatory)][string]$UserName,
    [Parameter(Mandatory)][securestring]$Password,
    [Parameter(Mandatory)][string]$InstallScript,
    [Parameter(Mandatory)][string]$ResultFile
)
$ErrorActionPreference='Stop'
Import-Module SqlServer
$builder=[Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$ServerName
$builder['User ID']=$UserName
$builder['Password']=[Net.NetworkCredential]::new('',$Password).Password
$builder['TrustServerCertificate']=$true
$builder['Pooling']=$false
$builder['Initial Catalog']='master'
$connection=[Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$connection.Open()
$database='tSQLt_FixtureValidation_'+[Guid]::NewGuid().ToString('N')
function Invoke-Sql([string]$sql) {
    foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*\r?$')) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $command=$connection.CreateCommand()
        try { $command.CommandText=$batch; $command.CommandTimeout=300; $null=$command.ExecuteNonQuery() }
        finally { $command.Dispose() }
    }
}
$failure=$null
try {
    Invoke-Sql "CREATE DATABASE [$database]; ALTER DATABASE [$database] SET TRUSTWORTHY ON;"
    $connection.ChangeDatabase($database)
    Invoke-Sql ([IO.File]::ReadAllText((Resolve-Path $InstallScript)))
    Invoke-Sql ([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Tests/ClassFixture.Client.sql')))
    # Reinstall resets registrations and must recreate all fixture objects.
    Invoke-Sql ([IO.File]::ReadAllText((Resolve-Path $InstallScript)))
    Invoke-Sql "IF OBJECT_ID('tSQLt.Private_ClassFixture') IS NULL RAISERROR('Reinstall lost fixture registration table.',16,10); EXEC tSQLt.Uninstall;"
} catch {
    $failure=$_.Exception.Message
    throw
} finally {
    $document=[xml]'<testsuite name="ClassFixtureClient" tests="1" failures="0" errors="0"><testcase name="lifecycle and reinstall"/></testsuite>'
    if ($failure) {
        $document.testsuite.SetAttribute('failures','1')
        $node=$document.CreateElement('failure')
        $node.InnerText=$failure
        $null=$document.testsuite.testcase.AppendChild($node)
    }
    $path=[IO.Path]::GetFullPath($ResultFile)
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    $document.Save($path)
    try {
        $connection.ChangeDatabase('master')
        Invoke-Sql "IF DB_ID(N'$database') IS NOT NULL BEGIN ALTER DATABASE [$database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$database]; END;"
    } finally { $connection.Dispose() }
}

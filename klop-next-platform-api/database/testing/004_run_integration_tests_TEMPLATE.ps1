[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApprovalTicket,

    [Parameter(Mandatory = $true)]
    [switch] $ApprovePersistentTestData,

    [ValidateSet('IntegratedSecurity', 'ActiveDirectoryDefault', 'ActiveDirectoryManagedIdentity')]
    [string] $Authentication = 'IntegratedSecurity'
)

$ErrorActionPreference = 'Stop'
$server = 'DEV-PC\SQLEXPRESS'
$database = 'KlopPlatformDB_TEST'
$backendRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if ([string]::IsNullOrWhiteSpace($ApprovalTicket)) {
    throw 'An approved test/change ticket is required.'
}
if (-not $ApprovePersistentTestData.IsPresent) {
    throw 'Pass -ApprovePersistentTestData only after explicit database and test approval.'
}

$names = @(
    'KLOP_TEST_SQL_SERVER',
    'KLOP_TEST_SQL_DATABASE',
    'KLOP_TEST_SQL_AUTH',
    'KLOP_TEST_APPROVAL_TICKET',
    'KLOP_TEST_ALLOW_MUTATION'
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$exitCode = 1
try {
    $env:KLOP_TEST_SQL_SERVER = $server
    $env:KLOP_TEST_SQL_DATABASE = $database
    $env:KLOP_TEST_SQL_AUTH = $Authentication
    $env:KLOP_TEST_APPROVAL_TICKET = $ApprovalTicket
    $env:KLOP_TEST_ALLOW_MUTATION = 'I_UNDERSTAND_TEST_DATA_IS_PERSISTENT'

    $project = Join-Path $backendRoot 'tests\KLOP.Platform.IntegrationTests\KLOP.Platform.IntegrationTests.csproj'
    & dotnet test $project --configuration Release
    $exitCode = $LASTEXITCODE
}
finally {
    foreach ($name in $names) {
        if ($null -eq $previous[$name]) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

exit $exitCode

[CmdletBinding()]
param(
    [string]$Server = 'localhost',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Database,
    [switch]$TrustServerCertificate
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectRoot 'src\installer\Install_v1.3.2.sql'

if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer not found: $installer"
}

$sqlcmdArguments = @(
    '-S', $Server,
    '-E',
    '-I',
    '-d', $Database,
    '-b',
    '-r', '1',
    '-i', $installer
)
if ($TrustServerCertificate) {
    $sqlcmdArguments += '-C'
}

Write-Output "Installing Statistics Governance Engine into [$Database] on [$Server]."
& sqlcmd @sqlcmdArguments
if ($LASTEXITCODE -ne 0) {
    throw "Statistics Governance Engine installation failed with sqlcmd exit code $LASTEXITCODE."
}
Write-Output "Statistics Governance Engine installation completed in [$Database]."

param(
    [string]$Server = 'localhost',
    [string]$Database = 'DBAdmin'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmssZ')
$outputRoot = Join-Path $projectRoot "artifacts\live_inventory_$stamp"
$modulesDir = Join-Path $outputRoot 'live_modules'
New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null

$inventorySql = Join-Path $PSScriptRoot '00_ReadOnly_Live_Inventory.sql'
$inventoryOutput = Join-Path $outputRoot 'inventory.txt'

# Windows Authentication only. The source script consists of read-only metadata queries.
& sqlcmd -S $Server -E -C -I -d $Database -b -l 15 -w 65535 -y 0 -Y 0 -i $inventorySql -o $inventoryOutput
if ($LASTEXITCODE -ne 0) {
    throw "Read-only inventory failed. Inspect $inventoryOutput."
}

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = $Database
$builder['Integrated Security'] = $true
$builder['Encrypt'] = $false
$builder['TrustServerCertificate'] = $true
$builder['Connect Timeout'] = 15
$connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)

try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
SELECT s.name AS SchemaName, o.name AS ObjectName, o.type_desc AS ObjectType,
       o.modify_date AS ModifyDate, m.definition AS DefinitionText
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE s.name = N'dbo'
  AND (o.name LIKE N'%StatsGovernance%' OR o.name LIKE N'%DRE_Stats%')
ORDER BY s.name, o.name;
'@
    $reader = $command.ExecuteReader()
    $manifest = New-Object System.Collections.Generic.List[object]
    while ($reader.Read()) {
        $schemaName = $reader.GetString(0)
        $objectName = $reader.GetString(1)
        $objectType = $reader.GetString(2)
        $modifiedAt = $reader.GetDateTime(3)
        $definition = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
        $safeName = ($schemaName + '.' + $objectName + '.sql') -replace '[<>:"/\\|?*]', '_'
        if ($null -ne $definition) {
            [System.IO.File]::WriteAllText((Join-Path $modulesDir $safeName), $definition, [System.Text.Encoding]::UTF8)
        }
        $manifest.Add([pscustomobject]@{
            SchemaName = $schemaName
            ObjectName = $objectName
            ObjectType = $objectType
            ModifyDate = $modifiedAt.ToString('o')
            DefinitionAvailable = ($null -ne $definition)
            FileName = if ($null -ne $definition) { $safeName } else { '' }
        })
    }
    $reader.Close()
    $manifest | Export-Csv -LiteralPath (Join-Path $outputRoot 'modules.csv') -NoTypeInformation -Encoding UTF8
}
finally {
    $connection.Dispose()
}

Write-Output "Read-only inventory saved to $outputRoot"

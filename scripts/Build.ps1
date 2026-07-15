[CmdletBinding()]
param(
    [string] $RepoRoot,
    [string] $OutputDirectory
)

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}

Import-Module "$PSScriptRoot/lib/ToolsConfigGenerator.psm1" -Force
Import-Module "$PSScriptRoot/lib/ExtensionPackager.psm1" -Force

$managementTsPath = Join-Path $RepoRoot 'ThingShapes/VPS.Development.MCP.Management_TS.xml'
$entryPointPath   = Join-Path $RepoRoot 'Things/VPS.Development.MCP.EntryPoint.xml'
$projectPath      = Join-Path $RepoRoot 'Projects/VPS.Development.MCP.xml'

Write-Host "Regenerating ToolsConfiguration from $managementTsPath ..."
$services = Get-ManagementServiceDefinitions -Path $managementTsPath
$rows = $services | ForEach-Object {
    ConvertTo-ToolInfoRow -Service $_ -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'
}
Set-ToolsConfigurationTable -EntryPointPath $entryPointPath -Rows $rows
Write-Host "Wrote $($rows.Count) tool row(s) into $entryPointPath"

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$packageVersion = Get-ProjectPackageVersion -ProjectXmlPath $projectPath
$outputPath = Join-Path $OutputDirectory "VPS.Development.MCP-extension-$packageVersion.zip"

Write-Host "Packaging extension $outputPath ..."
New-ExtensionPackage -RepoRoot $RepoRoot -Name 'VPS.Development.MCP' -PackageVersion $packageVersion -MinimumThingWorxVersion '10.1.0' -OutputPath $outputPath -DependsOn '' -Vendor 'Derrick Swint'
Write-Host "Done: $outputPath"

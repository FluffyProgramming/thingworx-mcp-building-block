[CmdletBinding()]
param(
    [string] $RepoRoot,
    [string] $OutputDirectory,
    [string] $FileName,
    [string] $FolderName
)

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}

Import-Module "$PSScriptRoot/lib/ToolsConfigGenerator.psm1" -Force
Import-Module "$PSScriptRoot/lib/SourceControlPackager.psm1" -Force

$managementTsPath = Join-Path $RepoRoot 'ThingShapes/VPS.Development.MCP.Management_TS.xml'
$entryPointPath   = Join-Path $RepoRoot 'Things/VPS.Development.MCP.EntryPoint.xml'
$projectPath      = Join-Path $RepoRoot 'Projects/VPS.Development.MCP.xml'

Write-Host "Regenerating ToolsConfiguration from $managementTsPath ..."
$services = Get-ManagementServiceDefinitions -Path $managementTsPath
$rows = @($services | ForEach-Object {
    ConvertTo-ToolInfoRow -Service $_ -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'ThingWorx'
})
Set-ToolsConfigurationTable -EntryPointPath $entryPointPath -Rows $rows
Write-Host "Wrote $($rows.Count) tool row(s) into $entryPointPath"

[xml]$projectXml = Get-Content -Path $projectPath -Raw
$projectNode = $projectXml.SelectSingleNode('//Project')
if (-not $projectNode) {
    throw "PackageSourceControlZip: no <Project> element found in $projectPath"
}
$projectName = $projectNode.name

if (-not $FileName) {
    $FileName = "$projectName.zip"
}
if (-not $FolderName) {
    $FolderName = ($projectName -split '\.')[0].ToLower()
}

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$outputPath = Join-Path $OutputDirectory $FileName

Write-Host "Packaging source-control zip $outputPath ..."
$result = New-SourceControlZip -RepoRoot $RepoRoot -OutputPath $outputPath
Write-Host "Entity folders included: $($result.EntityFolders -join ', ')"
Write-Host "Zip:    $($result.ZipPath)"
Write-Host "Base64: $($result.Base64Path)"
Write-Host "For ImportEntityZip -> fileName: '$FileName'  folderName: '$FolderName'"

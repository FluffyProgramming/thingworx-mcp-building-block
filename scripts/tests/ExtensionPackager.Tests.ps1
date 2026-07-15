Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Import-Module "$PSScriptRoot/../lib/ExtensionPackager.psm1" -Force
Reset-TestResults

Test-Case 'New-ExtensionMetadataXml produces well-formed XML with the given name and version' {
    $content = New-ExtensionMetadataXml -Name 'VPS.Development.MCP' -PackageVersion '1.0.0' -MinimumThingWorxVersion '10.1.0'
    [xml]$xml = $content
    $pkg = $xml.SelectSingleNode('//ExtensionPackage')
    Assert-Equal -Actual $pkg.name -Expected 'VPS.Development.MCP'
    Assert-Equal -Actual $pkg.packageVersion -Expected '1.0.0'
    Assert-Equal -Actual $pkg.minimumThingWorxVersion -Expected '10.1.0'
}

Test-Case 'New-ExtensionMetadataXml defaults dependsOn to empty' {
    $content = New-ExtensionMetadataXml -Name 'X' -PackageVersion '1.0.0' -MinimumThingWorxVersion '10.1.0'
    [xml]$xml = $content
    Assert-Equal -Actual $xml.SelectSingleNode('//ExtensionPackage').dependsOn -Expected ''
}

Test-Case 'New-ExtensionMetadataXml sets the given vendor' {
    $content = New-ExtensionMetadataXml -Name 'X' -PackageVersion '1.0.0' -MinimumThingWorxVersion '10.1.0' -Vendor 'Derrick Swint'
    [xml]$xml = $content
    Assert-Equal -Actual $xml.SelectSingleNode('//ExtensionPackage').vendor -Expected 'Derrick Swint'
}

Test-Case 'New-ExtensionMetadataXml defaults vendor to empty' {
    $content = New-ExtensionMetadataXml -Name 'X' -PackageVersion '1.0.0' -MinimumThingWorxVersion '10.1.0'
    [xml]$xml = $content
    Assert-Equal -Actual $xml.SelectSingleNode('//ExtensionPackage').vendor -Expected ''
}

Test-Case 'Get-ProjectPackageVersion reads packageVersion from the Project entity XML' {
    $path = "$PSScriptRoot/fixtures/Project.sample.xml"
    Assert-Equal -Actual (Get-ProjectPackageVersion -ProjectXmlPath $path) -Expected '1.0.0'
}

Test-Case 'New-ExtensionPackage produces a zip containing metadata.xml and Entities/<folder> for each provided folder' {
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-mcp-test-" + [guid]::NewGuid())
    $repoRoot = Join-Path $workDir 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'Things') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'Things/Fixture.Thing.xml') -Value '<Entities></Entities>'

    try {
        $outputPath = Join-Path $workDir 'out.zip'
        New-ExtensionPackage -RepoRoot $repoRoot -Name 'Fixture' -PackageVersion '1.0.0' -MinimumThingWorxVersion '10.1.0' -OutputPath $outputPath -EntityFolders @('Things')

        Assert-True -Condition (Test-Path $outputPath)

        $extractDir = Join-Path $workDir 'extracted'
        Expand-Archive -Path $outputPath -DestinationPath $extractDir
        Assert-True -Condition (Test-Path (Join-Path $extractDir 'metadata.xml'))
        Assert-True -Condition (Test-Path (Join-Path $extractDir 'Entities/Things/Fixture.Thing.xml'))
    } finally {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-TestSummary

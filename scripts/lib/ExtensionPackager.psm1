function New-ExtensionMetadataXml {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $PackageVersion,
        [Parameter(Mandatory)] [string] $MinimumThingWorxVersion,
        [string] $DependsOn = ''
    )

    return @"
<?xml version="1.0" encoding="UTF-8"?>
<Entities xmlns:str="http://exslt.org/strings">
    <ExtensionPackages>
        <ExtensionPackage
         artifactId=""
         dependsOn="$DependsOn"
         groupId=""
         minimumThingWorxVersion="$MinimumThingWorxVersion"
         packageVersion="$PackageVersion"
         buildNumber=""
         haCompatible="true"
         description=""
         documentationContent=""
         homeMashup=""
         name="$Name"
         tags=""
         vendor=""/>
    </ExtensionPackages>
</Entities>
"@
}

function Get-ProjectPackageVersion {
    param(
        [Parameter(Mandatory)] [string] $ProjectXmlPath
    )

    [xml]$xml = Get-Content -Path $ProjectXmlPath -Raw
    $project = $xml.SelectSingleNode('//Project')
    if (-not $project) {
        throw "Get-ProjectPackageVersion: no <Project> element found in $ProjectXmlPath"
    }
    return $project.packageVersion
}

function New-ExtensionPackage {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $PackageVersion,
        [Parameter(Mandatory)] [string] $MinimumThingWorxVersion,
        [Parameter(Mandatory)] [string] $OutputPath,
        [string] $DependsOn = '',
        [string[]] $EntityFolders = @('DataShapes', 'Groups', 'Organizations', 'Projects', 'ThingShapes', 'ThingTemplates', 'Things')
    )

    $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-mcp-extension-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $stagingDir | Out-Null
    $entitiesDir = Join-Path $stagingDir 'Entities'
    New-Item -ItemType Directory -Path $entitiesDir | Out-Null

    try {
        foreach ($folder in $EntityFolders) {
            $sourceFolder = Join-Path $RepoRoot $folder
            if (Test-Path $sourceFolder) {
                Copy-Item -Path $sourceFolder -Destination $entitiesDir -Recurse
            }
        }

        $metadata = New-ExtensionMetadataXml -Name $Name -PackageVersion $PackageVersion -MinimumThingWorxVersion $MinimumThingWorxVersion -DependsOn $DependsOn
        Set-Content -Path (Join-Path $stagingDir 'metadata.xml') -Value $metadata -Encoding UTF8

        if (Test-Path $OutputPath) {
            Remove-Item -Path $OutputPath -Force
        }
        Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $OutputPath
    } finally {
        Remove-Item -Path $stagingDir -Recurse -Force
    }

    return $OutputPath
}

Export-ModuleMember -Function New-ExtensionMetadataXml, Get-ProjectPackageVersion, New-ExtensionPackage

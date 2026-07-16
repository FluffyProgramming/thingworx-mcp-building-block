Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Import-Module "$PSScriptRoot/../lib/SourceControlPackager.psm1" -Force
Reset-TestResults

function New-FixtureRepo {
    $repoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-scp-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'Things') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'Things/Fixture.Thing.xml') -Value '<Entities>Thing</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'DataShapes') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'DataShapes/Fixture.DataShape.xml') -Value '<Entities>DataShape</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'scripts') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'not an entity'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'dist') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'dist/output.zip') -Value 'not an entity'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'EmptyFolder') -Force | Out-Null
    return $repoRoot
}

Test-Case 'New-SourceControlZip includes non-empty, non-excluded folders and excludes empty/default-excluded ones' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        $result = New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath
        Assert-Contains -Collection $result.EntityFolders -Item 'Things'
        Assert-Contains -Collection $result.EntityFolders -Item 'DataShapes'
        Assert-True -Condition ($result.EntityFolders -notcontains 'scripts') -Message 'scripts should be excluded by default'
        Assert-True -Condition ($result.EntityFolders -notcontains 'dist') -Message 'dist should be excluded by default'
        Assert-True -Condition ($result.EntityFolders -notcontains 'EmptyFolder') -Message 'empty folders should be skipped'
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip writes forward-slash entry paths with entity folders at the zip root' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath | Out-Null

        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        } finally {
            $archive.Dispose()
        }

        Assert-Contains -Collection $entryNames -Item 'Things/Fixture.Thing.xml'
        Assert-Contains -Collection $entryNames -Item 'DataShapes/Fixture.DataShape.xml'
        foreach ($name in $entryNames) {
            Assert-True -Condition ($name -notmatch '\\') -Message "entry '$name' should not contain a backslash"
        }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip base64 output decodes back to byte-identical zip content' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        $result = New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath

        Assert-True -Condition (Test-Path $result.Base64Path)
        $expectedBytes = [System.IO.File]::ReadAllBytes($zipPath)
        $decodedBytes = [Convert]::FromBase64String((Get-Content -Path $result.Base64Path -Raw))
        Assert-Equal -Actual $decodedBytes.Length -Expected $expectedBytes.Length
        Assert-Equal -Actual ([System.BitConverter]::ToString($decodedBytes)) -Expected ([System.BitConverter]::ToString($expectedBytes))
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip throws when no entity folders are found' {
    $repoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-scp-test-empty-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'scripts') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'not an entity'
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        Assert-Throws -ScriptBlock { New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-TestSummary

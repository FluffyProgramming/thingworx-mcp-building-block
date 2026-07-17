Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Import-Module "$PSScriptRoot/../lib/SourceControlPackager.psm1" -Force
Reset-TestResults

function New-FixtureRepo {
    $repoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-scp-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'Things') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'Things/Fixture.Thing.xml') -Value '<Entities>Thing</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'Things/Sub') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'Things/Sub/Nested.Thing.xml') -Value '<Entities>NestedThing</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'DataShapes') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'DataShapes/Fixture.DataShape.xml') -Value '<Entities>DataShape</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'scripts') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'not an entity'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'dist') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'dist/output.zip') -Value 'not an entity'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'EmptyFolder') -Force | Out-Null
    return $repoRoot
}

function New-GitFixtureRepo {
    $repoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vps-scp-git-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
    git -C $repoRoot init --quiet | Out-Null

    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'Things') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'Things/Existing.Thing.xml') -Value '<Entities>Existing</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'ThingShapes') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'ThingShapes/ToDelete.ThingShape.xml') -Value '<Entities>ToDelete</Entities>'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'scripts') -Force | Out-Null
    Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'not an entity'
    Set-Content -Path (Join-Path $repoRoot 'README.md') -Value 'root file'

    git -C $repoRoot add -A | Out-Null
    git -C $repoRoot -c user.name=test -c user.email=test@test.com commit -m "initial" --quiet | Out-Null

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
        Assert-Contains -Collection $entryNames -Item 'Things/Sub/Nested.Thing.xml'
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

Test-Case 'Get-ChangedEntityFiles finds modified tracked and untracked new entity files, excludes deleted and excluded-folder changes' {
    $repoRoot = New-GitFixtureRepo
    try {
        Set-Content -Path (Join-Path $repoRoot 'Things/Existing.Thing.xml') -Value '<Entities>Modified</Entities>'
        New-Item -ItemType Directory -Path (Join-Path $repoRoot 'DataShapes') -Force | Out-Null
        Set-Content -Path (Join-Path $repoRoot 'DataShapes/New.DataShape.xml') -Value '<Entities>New</Entities>'
        Remove-Item -Path (Join-Path $repoRoot 'ThingShapes/ToDelete.ThingShape.xml') -Force
        Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'changed but excluded'

        $changed = Get-ChangedEntityFiles -RepoRoot $repoRoot

        Assert-Contains -Collection $changed -Item 'Things/Existing.Thing.xml'
        Assert-Contains -Collection $changed -Item 'DataShapes/New.DataShape.xml'
        Assert-True -Condition ($changed -notcontains 'ThingShapes/ToDelete.ThingShape.xml') -Message 'deleted file should not be included'
        Assert-True -Condition ($changed -notcontains 'scripts/Build.ps1') -Message 'excluded-folder change should not be included'
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Get-ChangedEntityFiles throws when nothing has changed' {
    $repoRoot = New-GitFixtureRepo
    try {
        Assert-Throws -ScriptBlock { Get-ChangedEntityFiles -RepoRoot $repoRoot }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Get-ChangedEntityFiles throws when changes exist but only in excluded folders' {
    $repoRoot = New-GitFixtureRepo
    try {
        Set-Content -Path (Join-Path $repoRoot 'scripts/Build.ps1') -Value 'changed but excluded'
        Assert-Throws -ScriptBlock { Get-ChangedEntityFiles -RepoRoot $repoRoot }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Get-ChangedEntityFiles excludes changed top-level files with no folder component' {
    $repoRoot = New-GitFixtureRepo
    try {
        Set-Content -Path (Join-Path $repoRoot 'Things/Existing.Thing.xml') -Value '<Entities>Modified</Entities>'
        Set-Content -Path (Join-Path $repoRoot 'README.md') -Value 'root file modified'

        $changed = Get-ChangedEntityFiles -RepoRoot $repoRoot

        Assert-Contains -Collection $changed -Item 'Things/Existing.Thing.xml'
        Assert-True -Condition ($changed -notcontains 'README.md') -Message 'top-level file with no folder component should not be included'
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip -Files zips exactly the given files with forward-slash entries' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        $result = New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath -Files @('Things/Fixture.Thing.xml', 'DataShapes/Fixture.DataShape.xml')

        Assert-Equal -Actual (@($result.EntityFolders) | Sort-Object) -Expected (@('DataShapes', 'Things') | Sort-Object)

        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        } finally {
            $archive.Dispose()
        }

        Assert-Equal -Actual (@($entryNames) | Sort-Object) -Expected (@('DataShapes/Fixture.DataShape.xml', 'Things/Fixture.Thing.xml') | Sort-Object)
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip -Files throws when a given file does not exist' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        Assert-Throws -ScriptBlock { New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath -Files @('Things/DoesNotExist.xml') }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'New-SourceControlZip -Files @() throws instead of falling back to full-tree discovery' {
    $repoRoot = New-FixtureRepo
    try {
        $zipPath = Join-Path $repoRoot 'out.zip'
        Assert-Throws -ScriptBlock { New-SourceControlZip -RepoRoot $repoRoot -OutputPath $zipPath -Files @() }
    } finally {
        Remove-Item -Path $repoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-TestSummary

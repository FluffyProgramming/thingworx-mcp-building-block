function New-SourceControlZip {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $OutputPath,
        [string[]] $ExcludeFolders = @('scripts', 'docs', 'dist', '.git', '.claude', '.worktrees'),
        [string[]] $Files
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    if ($Files) {
        foreach ($file in $Files) {
            $fullPath = Join-Path $RepoRoot $file
            if (-not (Test-Path $fullPath)) {
                throw "New-SourceControlZip: file not found: $file"
            }
        }
        $filesToZip = @($Files)
        $entityFolders = @($filesToZip | ForEach-Object { ($_ -split '/')[0] } | Select-Object -Unique)
    } else {
        $entityFolders = Get-ChildItem -Path $RepoRoot -Directory |
            Where-Object { $ExcludeFolders -notcontains $_.Name } |
            Where-Object { @(Get-ChildItem -Path $_.FullName -File -Recurse).Count -gt 0 } |
            Select-Object -ExpandProperty Name

        $entityFolders = @($entityFolders)
        if ($entityFolders.Count -eq 0) {
            throw "New-SourceControlZip: no entity folders found under $RepoRoot (all top-level folders were excluded or empty)."
        }

        $filesToZip = @()
        foreach ($folderName in $entityFolders) {
            $folderPath = Join-Path $RepoRoot $folderName
            $folderFiles = Get-ChildItem -Path $folderPath -File -Recurse
            foreach ($file in $folderFiles) {
                $relativePath = $file.FullName.Substring($folderPath.Length + 1) -replace '\\', '/'
                $filesToZip += "$folderName/$relativePath"
            }
        }
    }

    if (Test-Path $OutputPath) {
        Remove-Item -Path $OutputPath -Force
    }

    $fs = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relativeEntryPath in $filesToZip) {
            $fullPath = Join-Path $RepoRoot $relativeEntryPath
            $entry = $archive.CreateEntry($relativeEntryPath, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally {
                $entryStream.Close()
            }
        }
    } finally {
        $archive.Dispose()
        $fs.Dispose()
    }

    $zipBytes = [System.IO.File]::ReadAllBytes($OutputPath)
    $base64 = [Convert]::ToBase64String($zipBytes)
    $base64Path = "$OutputPath.b64.txt"
    [System.IO.File]::WriteAllText($base64Path, $base64)

    return [PSCustomObject]@{
        ZipPath       = $OutputPath
        Base64Path    = $base64Path
        EntityFolders = $entityFolders
    }
}

function Get-ChangedEntityFiles {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [string[]] $ExcludeFolders = @('scripts', 'docs', 'dist', '.git', '.claude', '.worktrees')
    )

    $modified = @(git -C $RepoRoot diff --name-only HEAD)
    $statusLines = @(git -C $RepoRoot status --porcelain --untracked-files=all)
    $untracked = @($statusLines | Where-Object { $_ -like '?? *' } | ForEach-Object { $_.Substring(3) })

    $allChanged = @($modified + $untracked | Select-Object -Unique)

    $changedFiles = @($allChanged | Where-Object {
        $topFolder = ($_ -split '/')[0]
        ($ExcludeFolders -notcontains $topFolder) -and (Test-Path (Join-Path $RepoRoot $_))
    })

    if ($changedFiles.Count -eq 0) {
        if ($allChanged.Count -eq 0) {
            throw "Get-ChangedEntityFiles: no changed entity files found under $RepoRoot (working tree matches HEAD)."
        }
        throw "Get-ChangedEntityFiles: no changed entity files found under $RepoRoot (all changes are in excluded folders: $($ExcludeFolders -join ', '))."
    }

    return $changedFiles
}

Export-ModuleMember -Function New-SourceControlZip, Get-ChangedEntityFiles

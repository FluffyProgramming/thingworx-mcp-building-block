$script:TestResults = [System.Collections.Generic.List[object]]::new()

function Reset-TestResults {
    $script:TestResults = [System.Collections.Generic.List[object]]::new()
}

function Test-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Test
    )

    try {
        & $Test
        $script:TestResults.Add([PSCustomObject]@{ Name = $Name; Passed = $true; Error = $null })
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:TestResults.Add([PSCustomObject]@{ Name = $Name; Passed = $false; Error = $_.Exception.Message })
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string] $Message = '')
    $actualJson = $Actual | ConvertTo-Json -Depth 10 -Compress
    $expectedJson = $Expected | ConvertTo-Json -Depth 10 -Compress
    if ($actualJson -ne $expectedJson) {
        throw "Assert-Equal failed. $Message Expected: $expectedJson Actual: $actualJson"
    }
}

function Assert-True {
    param($Condition, [string] $Message = 'Expected condition to be true')
    if (-not $Condition) {
        throw "Assert-True failed: $Message"
    }
}

function Assert-Contains {
    param([array] $Collection, $Item, [string] $Message = '')
    if (-not ($Collection -contains $Item)) {
        throw "Assert-Contains failed. $Message Expected collection to contain: $Item Actual: $($Collection -join ', ')"
    }
}

function Assert-Match {
    param([string] $Actual, [string] $Pattern, [string] $Message = '')
    if ($Actual -notmatch $Pattern) {
        throw "Assert-Match failed. $Message Expected '$Actual' to match pattern '$Pattern'"
    }
}

function Assert-Throws {
    param([Parameter(Mandatory)] [scriptblock] $ScriptBlock, [string] $Message = 'Expected an exception to be thrown')
    $threw = $false
    try {
        & $ScriptBlock
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        throw "Assert-Throws failed: $Message"
    }
}

function Write-TestSummary {
    $total = $script:TestResults.Count
    $failed = @($script:TestResults | Where-Object { -not $_.Passed }).Count
    $passed = $total - $failed
    Write-Host "`n$passed/$total passed, $failed failed"
    if ($failed -gt 0) {
        exit 1
    }
}

Export-ModuleMember -Function Test-Case, Assert-Equal, Assert-True, Assert-Contains, Assert-Match, Assert-Throws, Write-TestSummary, Reset-TestResults

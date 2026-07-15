Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Reset-TestResults

Test-Case 'Assert-Equal passes for equal values' {
    Assert-Equal -Actual 'x' -Expected 'x'
}
Test-Case 'Assert-Equal passes for equal ordered hashtables' {
    Assert-Equal -Actual ([ordered]@{ type = 'string' }) -Expected ([ordered]@{ type = 'string' })
}
Test-Case 'Assert-Equal throws for different values' {
    Assert-Throws { Assert-Equal -Actual 'x' -Expected 'y' }
}
Test-Case 'Assert-True throws for a false condition' {
    Assert-Throws { Assert-True -Condition $false }
}
Test-Case 'Assert-Contains passes when the item is present' {
    Assert-Contains -Collection @('a', 'b', 'c') -Item 'b'
}
Test-Case 'Assert-Contains throws when the item is absent' {
    Assert-Throws { Assert-Contains -Collection @('a', 'b', 'c') -Item 'z' }
}
Test-Case 'Assert-Match passes when the pattern matches' {
    Assert-Match -Actual 'hello world' -Pattern 'world'
}
Test-Case 'Assert-Match throws when the pattern does not match' {
    Assert-Throws { Assert-Match -Actual 'hello world' -Pattern 'goodbye' }
}
Test-Case 'Assert-Throws passes when the block throws' {
    Assert-Throws { throw 'boom' }
}

Write-TestSummary

Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Import-Module "$PSScriptRoot/../lib/BaseTypeMap.psm1" -Force
Reset-TestResults

Test-Case 'maps STRING to string' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'STRING').type -Expected 'string'
}
Test-Case 'maps THINGNAME to string' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'THINGNAME').type -Expected 'string'
}
Test-Case 'maps NUMBER to number' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'NUMBER').type -Expected 'number'
}
Test-Case 'maps INTEGER to integer' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'INTEGER').type -Expected 'integer'
}
Test-Case 'maps BOOLEAN to boolean' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'BOOLEAN').type -Expected 'boolean'
}
Test-Case 'maps DATETIME to string with date-time format' {
    $result = Convert-ThingworxBaseTypeToJsonSchema -BaseType 'DATETIME'
    Assert-Equal -Actual $result.type -Expected 'string'
    Assert-Equal -Actual $result.format -Expected 'date-time'
}
Test-Case 'maps JSON to object' {
    Assert-Equal -Actual (Convert-ThingworxBaseTypeToJsonSchema -BaseType 'JSON').type -Expected 'object'
}
Test-Case 'maps INFOTABLE without a DataShape to a generic array of objects' {
    $result = Convert-ThingworxBaseTypeToJsonSchema -BaseType 'INFOTABLE'
    Assert-Equal -Actual $result.type -Expected 'array'
    Assert-Equal -Actual $result.items.type -Expected 'object'
}
Test-Case 'maps INFOTABLE with a DataShape and notes the shape name in items.description' {
    $result = Convert-ThingworxBaseTypeToJsonSchema -BaseType 'INFOTABLE' -DataShapeName 'PDX.Datawatch.C110115Row_DS'
    Assert-Match -Actual $result.items.description -Pattern 'PDX.Datawatch.C110115Row_DS'
}
Test-Case 'falls back to string and warns for an unrecognized baseType' {
    $result = Convert-ThingworxBaseTypeToJsonSchema -BaseType 'BLOB' -WarningVariable warnings -WarningAction SilentlyContinue
    Assert-Equal -Actual $result.type -Expected 'string'
    Assert-True -Condition ($warnings.Count -gt 0)
}

Write-TestSummary

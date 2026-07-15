Import-Module "$PSScriptRoot/TestHarness.psm1" -Force
Import-Module "$PSScriptRoot/../lib/ToolsConfigGenerator.psm1" -Force
Reset-TestResults

$script:FixturePath = "$PSScriptRoot/fixtures/Management_TS.sample.xml"

Test-Case 'parses both services from the fixture' {
    $services = Get-ManagementServiceDefinitions -Path $script:FixturePath
    Assert-Equal -Actual $services.Count -Expected 2
    Assert-Contains -Collection $services.Name -Item 'GetWidget'
    Assert-Contains -Collection $services.Name -Item 'ImportWidgets'
}

Test-Case 'parses GetWidget parameters and result' {
    $services = Get-ManagementServiceDefinitions -Path $script:FixturePath
    $getWidget = $services | Where-Object Name -eq 'GetWidget'
    Assert-Equal -Actual $getWidget.Parameters.Count -Expected 2
    Assert-Equal -Actual ($getWidget.Parameters | Where-Object Name -eq 'widgetId').BaseType -Expected 'STRING'
    Assert-Equal -Actual ($getWidget.Parameters | Where-Object Name -eq 'maxResults').BaseType -Expected 'NUMBER'
    Assert-Equal -Actual $getWidget.ResultBaseType -Expected 'INFOTABLE'
    Assert-Equal -Actual $getWidget.ResultDataShapeName -Expected 'Fixture.Widget_DS'
}

Test-Case 'parses ImportWidgets INFOTABLE parameter with its DataShape aspect' {
    $services = Get-ManagementServiceDefinitions -Path $script:FixturePath
    $importWidgets = $services | Where-Object Name -eq 'ImportWidgets'
    Assert-Equal -Actual $importWidgets.Parameters.Count -Expected 1
    Assert-Equal -Actual $importWidgets.Parameters[0].BaseType -Expected 'INFOTABLE'
    Assert-Equal -Actual $importWidgets.Parameters[0].DataShapeName -Expected 'Fixture.Widget_DS'
    Assert-Equal -Actual $importWidgets.ResultBaseType -Expected 'NOTHING'
}

$script:Services = Get-ManagementServiceDefinitions -Path $script:FixturePath

Test-Case 'builds a row for GetWidget with correct provider and names' {
    $service = $script:Services | Where-Object Name -eq 'GetWidget'
    $row = ConvertTo-ToolInfoRow -Service $service -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'

    Assert-Equal -Actual $row.toolName -Expected 'GetWidget'
    Assert-Equal -Actual $row.serviceName -Expected 'GetWidget'
    Assert-Equal -Actual $row.serviceProviderName -Expected 'VPS.Development.MCP.Manager'
    Assert-Equal -Actual $row.serviceProviderType -Expected 'Thing'
    Assert-Equal -Actual $row.applicationName -Expected 'VPS.Development.MCP'
    Assert-Equal -Actual $row.description -Expected 'Gets a widget by id'
}

Test-Case 'builds an inputSchema with both parameters marked required' {
    $service = $script:Services | Where-Object Name -eq 'GetWidget'
    $row = ConvertTo-ToolInfoRow -Service $service -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'
    $schema = $row.inputSchema | ConvertFrom-Json

    Assert-Equal -Actual $schema.type -Expected 'object'
    Assert-Equal -Actual $schema.properties.widgetId.type -Expected 'string'
    Assert-Equal -Actual $schema.properties.maxResults.type -Expected 'number'
    Assert-Contains -Collection $schema.required -Item 'widgetId'
    Assert-Contains -Collection $schema.required -Item 'maxResults'
}

Test-Case 'builds an outputSchema of type array for an INFOTABLE result' {
    $service = $script:Services | Where-Object Name -eq 'GetWidget'
    $row = ConvertTo-ToolInfoRow -Service $service -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'
    $schema = $row.outputSchema | ConvertFrom-Json

    Assert-Equal -Actual $schema.type -Expected 'array'
}

Test-Case 'builds a null-type outputSchema for a NOTHING result' {
    $service = $script:Services | Where-Object Name -eq 'ImportWidgets'
    $row = ConvertTo-ToolInfoRow -Service $service -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'
    $schema = $row.outputSchema | ConvertFrom-Json

    Assert-Equal -Actual $schema.type -Expected 'null'
}

Test-Case 'includes an INFOTABLE parameter as an array in inputSchema' {
    $service = $script:Services | Where-Object Name -eq 'ImportWidgets'
    $row = ConvertTo-ToolInfoRow -Service $service -ManagerThingName 'VPS.Development.MCP.Manager' -ApplicationName 'VPS.Development.MCP'
    $schema = $row.inputSchema | ConvertFrom-Json

    Assert-Equal -Actual $schema.properties.widgets.type -Expected 'array'
}

function New-TempEntryPointCopy {
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("EntryPoint-" + [guid]::NewGuid() + ".xml")
    Copy-Item -Path "$PSScriptRoot/fixtures/EntryPoint.sample.xml" -Destination $tempPath
    return $tempPath
}

Test-Case 'writes one row per tool into the ToolsConfiguration table' {
    $tempPath = New-TempEntryPointCopy
    try {
        $rows = @(
            [ordered]@{
                toolName            = 'GetWidget'
                serviceProviderName = 'VPS.Development.MCP.Manager'
                serviceProviderType = 'Thing'
                serviceName         = 'GetWidget'
                description         = 'Gets a widget by id'
                title               = 'GetWidget'
                applicationName     = 'VPS.Development.MCP'
                meta                = '{}'
                toolAnnotations     = '{}'
                inputSchema         = '{"type":"object"}'
                outputSchema        = '{"type":"array"}'
            }
        )

        Set-ToolsConfigurationTable -EntryPointPath $tempPath -Rows $rows

        [xml]$result = Get-Content -Path $tempPath -Raw
        $tableNode = $result.SelectSingleNode("//ConfigurationTable[@name='ToolsConfiguration']")
        Assert-Equal -Actual @($tableNode.Rows.Row).Count -Expected 1
        Assert-Equal -Actual $tableNode.Rows.Row.toolName -Expected 'GetWidget'
        Assert-Equal -Actual $tableNode.Rows.Row.serviceProviderName -Expected 'VPS.Development.MCP.Manager'
    } finally {
        Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
    }
}

Test-Case 'replaces existing rows rather than appending to them' {
    $tempPath = New-TempEntryPointCopy
    try {
        $firstRows = @([ordered]@{ toolName = 'OldTool'; serviceProviderName = 'X'; serviceProviderType = 'Thing'; serviceName = 'OldTool'; description = ''; title = 'OldTool'; applicationName = 'X'; meta = '{}'; toolAnnotations = '{}'; inputSchema = '{}'; outputSchema = '{}' })
        Set-ToolsConfigurationTable -EntryPointPath $tempPath -Rows $firstRows

        $secondRows = @([ordered]@{ toolName = 'NewTool'; serviceProviderName = 'X'; serviceProviderType = 'Thing'; serviceName = 'NewTool'; description = ''; title = 'NewTool'; applicationName = 'X'; meta = '{}'; toolAnnotations = '{}'; inputSchema = '{}'; outputSchema = '{}' })
        Set-ToolsConfigurationTable -EntryPointPath $tempPath -Rows $secondRows

        [xml]$result = Get-Content -Path $tempPath -Raw
        $tableNode = $result.SelectSingleNode("//ConfigurationTable[@name='ToolsConfiguration']")
        Assert-Equal -Actual @($tableNode.Rows.Row).Count -Expected 1
        Assert-Equal -Actual $tableNode.Rows.Row.toolName -Expected 'NewTool'
    } finally {
        Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
    }
}

Test-Case 'writing zero rows leaves the table empty without error' {
    $tempPath = New-TempEntryPointCopy
    try {
        Set-ToolsConfigurationTable -EntryPointPath $tempPath -Rows @()

        [xml]$result = Get-Content -Path $tempPath -Raw
        $tableNode = $result.SelectSingleNode("//ConfigurationTable[@name='ToolsConfiguration']")
        Assert-Equal -Actual $tableNode.Rows.ChildNodes.Count -Expected 0
    } finally {
        Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
    }
}

Write-TestSummary

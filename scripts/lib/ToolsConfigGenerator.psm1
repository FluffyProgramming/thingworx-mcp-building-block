Import-Module "$PSScriptRoot/BaseTypeMap.psm1" -Force

function Get-ManagementServiceDefinitions {
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    [xml]$xml = Get-Content -Path $Path -Raw
    $serviceNodes = $xml.SelectNodes('//ServiceDefinition')

    $services = foreach ($node in $serviceNodes) {
        $parameters = foreach ($paramNode in $node.ParameterDefinitions.FieldDefinition) {
            [PSCustomObject]@{
                Name          = $paramNode.name
                BaseType      = $paramNode.baseType
                DataShapeName = $paramNode.'aspect.dataShape'
            }
        }

        [PSCustomObject]@{
            Name                = $node.name
            Description         = $node.description
            Parameters          = @($parameters)
            ResultBaseType      = $node.ResultType.baseType
            ResultDataShapeName = $node.ResultType.'aspect.dataShape'
        }
    }

    return @($services)
}

function ConvertTo-ToolInfoRow {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Service,
        [Parameter(Mandatory)] [string] $ManagerThingName,
        [Parameter(Mandatory)] [string] $ApplicationName
    )

    $properties = [ordered]@{}
    $required = @()
    foreach ($p in $Service.Parameters) {
        $properties[$p.Name] = Convert-ThingworxBaseTypeToJsonSchema -BaseType $p.BaseType -DataShapeName $p.DataShapeName -ContextLabel "$($Service.Name).$($p.Name)"
        $required += $p.Name
    }
    $inputSchema = [ordered]@{
        type       = 'object'
        properties = $properties
        required   = $required
    }

    $outputSchema = if ($Service.ResultBaseType -and $Service.ResultBaseType -ne 'NOTHING') {
        Convert-ThingworxBaseTypeToJsonSchema -BaseType $Service.ResultBaseType -DataShapeName $Service.ResultDataShapeName -ContextLabel "$($Service.Name).result"
    } else {
        [ordered]@{ type = 'null' }
    }

    return [ordered]@{
        toolName            = $Service.Name
        serviceProviderName = $ManagerThingName
        serviceProviderType = 'Thing'
        serviceName         = $Service.Name
        description         = $Service.Description
        title               = $Service.Name
        applicationName     = $ApplicationName
        meta                = '{}'
        toolAnnotations     = '{}'
        inputSchema         = ($inputSchema | ConvertTo-Json -Depth 10 -Compress)
        outputSchema        = ($outputSchema | ConvertTo-Json -Depth 10 -Compress)
    }
}

$script:JsonFieldNames = @('meta', 'inputSchema', 'outputSchema')
$script:InfoTableFieldNames = @('toolAnnotations')

function Set-ToolsConfigurationTable {
    param(
        [Parameter(Mandatory)] [string] $EntryPointPath,
        [Parameter()] [array] $Rows = @()
    )

    [xml]$xml = Get-Content -Path $EntryPointPath -Raw
    $tableNode = $xml.SelectSingleNode("//ConfigurationTable[@name='ToolsConfiguration']")
    if (-not $tableNode) {
        throw "Set-ToolsConfigurationTable: no ConfigurationTable named 'ToolsConfiguration' found in $EntryPointPath"
    }

    $rowsNode = $tableNode.SelectSingleNode('Rows')
    $rowsNode.RemoveAll() | Out-Null

    foreach ($row in $Rows) {
        $rowNode = $xml.CreateElement('Row')
        foreach ($fieldName in $row.Keys) {
            $fieldNode = $xml.CreateElement($fieldName)

            if ($script:InfoTableFieldNames -contains $fieldName) {
                # INFOTABLE fields (e.g. toolAnnotations, aspect.dataShape="MCPToolAnnotations") need a real
                # <infoTable><DataShape>...</DataShape><Rows>...</Rows></infoTable> structure, not JSON text.
                # No per-tool annotation data exists yet, so this always writes the empty-but-valid form
                # confirmed against a live ThingWorx 10.1 server (Composer round-trips an untouched
                # toolAnnotations field to exactly this shape).
                $infoTableNode = $xml.CreateElement('infoTable')
                $dataShapeNode = $xml.CreateElement('DataShape')
                $dataShapeNode.AppendChild($xml.CreateElement('FieldDefinitions')) | Out-Null
                $infoTableNode.AppendChild($dataShapeNode) | Out-Null
                $infoTableNode.AppendChild($xml.CreateElement('Rows')) | Out-Null
                $fieldNode.AppendChild($infoTableNode) | Out-Null
            } elseif ($script:JsonFieldNames -contains $fieldName) {
                # JSON-baseType fields need their CDATA wrapped in a <json> child element — confirmed
                # against a live ThingWorx 10.1 export; without it, Composer silently reads the field as empty.
                $jsonNode = $xml.CreateElement('json')
                $cdata = $xml.CreateCDataSection([string]$row[$fieldName])
                $jsonNode.AppendChild($cdata) | Out-Null
                $fieldNode.AppendChild($jsonNode) | Out-Null
            } else {
                $cdata = $xml.CreateCDataSection([string]$row[$fieldName])
                $fieldNode.AppendChild($cdata) | Out-Null
            }

            $rowNode.AppendChild($fieldNode) | Out-Null
        }
        $rowsNode.AppendChild($rowNode) | Out-Null
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $writer = [System.Xml.XmlWriter]::Create($EntryPointPath, $settings)
    try {
        $xml.Save($writer)
    } finally {
        $writer.Dispose()
    }
}

Export-ModuleMember -Function Get-ManagementServiceDefinitions, ConvertTo-ToolInfoRow, Set-ToolsConfigurationTable

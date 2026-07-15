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
            $fieldNode.InnerText = [string]$row[$fieldName]
            $rowNode.AppendChild($fieldNode) | Out-Null
        }
        $rowsNode.AppendChild($rowNode) | Out-Null
    }

    $xml.Save($EntryPointPath)
}

Export-ModuleMember -Function Get-ManagementServiceDefinitions, ConvertTo-ToolInfoRow, Set-ToolsConfigurationTable

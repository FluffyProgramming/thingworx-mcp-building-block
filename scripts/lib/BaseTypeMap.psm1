$script:BaseTypeMap = @{
    'STRING'     = 'string'
    'THINGNAME'  = 'string'
    'USERNAME'   = 'string'
    'GROUPNAME'  = 'string'
    'GUID'       = 'string'
    'HTML'       = 'string'
    'HYPERLINK'  = 'string'
    'IMAGELINK'  = 'string'
    'VIDEOLINK'  = 'string'
    'XML'        = 'string'
    'MASHUPNAME' = 'string'
    'NUMBER'     = 'number'
    'INTEGER'    = 'integer'
    'LONG'       = 'integer'
    'BOOLEAN'    = 'boolean'
    'JSON'       = 'object'
}

function Convert-ThingworxBaseTypeToJsonSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $BaseType,
        [string] $DataShapeName,
        [string] $ContextLabel = $BaseType
    )

    if ($BaseType -eq 'DATETIME') {
        return [ordered]@{ type = 'string'; format = 'date-time' }
    }

    if ($BaseType -eq 'INFOTABLE') {
        if ($DataShapeName) {
            return [ordered]@{
                type  = 'array'
                items = [ordered]@{ type = 'object'; description = "Rows conforming to DataShape $DataShapeName" }
            }
        }
        return [ordered]@{ type = 'array'; items = [ordered]@{ type = 'object' } }
    }

    if ($script:BaseTypeMap.ContainsKey($BaseType)) {
        return [ordered]@{ type = $script:BaseTypeMap[$BaseType] }
    }

    Write-Warning "Convert-ThingworxBaseTypeToJsonSchema: unrecognized baseType '$BaseType' for $ContextLabel, falling back to 'string'."
    return [ordered]@{ type = 'string' }
}

Export-ModuleMember -Function Convert-ThingworxBaseTypeToJsonSchema

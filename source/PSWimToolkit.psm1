. (Join-Path -Path $PSScriptRoot -ChildPath 'Private\00.Initialize-ToolkitEnvironment.ps1')

try {
    $classFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Classes') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $classFiles) {
        . $file.FullName
    }

    $privateFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $privateFunctions) {
        if ($file.Name -ne '00.Initialize-ToolkitEnvironment.ps1') {
            . $file.FullName
        }
    }

    $publicFunctions = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
    foreach ($file in $publicFunctions) {
        . $file.FullName
    }

    $publicFunctionNames = @()
    if ($publicFunctions) {
        $publicFunctionNames = $publicFunctions | ForEach-Object { $_.BaseName }
    }

    if ($publicFunctionNames.Count -gt 0) {
        Export-ModuleMember -Function $publicFunctionNames
    } else {
        Export-ModuleMember -Function @()
    }
}
catch {
    Write-Error -Message "Failed to initialize PSWimToolkit: $_"
    throw
}


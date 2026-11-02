param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH. Install Flutter first, then run this script again.'
}

$platforms = @('windows', 'android')
foreach ($platform in $platforms) {
    if (Test-Path (Join-Path $projectRoot $platform)) {
        throw "Refusing to overwrite the existing '$platform' folder. Native runners already exist."
    }
}

$tempRoot = Join-Path $env:TEMP ('nexuside-platforms-' + [guid]::NewGuid().ToString('N'))
$bootstrapProject = Join-Path $tempRoot 'bootstrap'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    Write-Host 'Generating Windows and Android runners in a temporary folder...'
    flutter create --project-name nexus_ide --org com.itsmemal --platforms=windows,android $bootstrapProject
    if ($LASTEXITCODE -ne 0) {
        throw 'flutter create failed. Check flutter doctor and try again.'
    }

    foreach ($platform in $platforms) {
        Copy-Item -Path (Join-Path $bootstrapProject $platform) -Destination (Join-Path $projectRoot $platform) -Recurse
    }

    & (Join-Path $PSScriptRoot 'configure_google_oauth.ps1')

    $metadataSource = Join-Path $bootstrapProject '.metadata'
    $metadataDestination = Join-Path $projectRoot '.metadata'
    if ((Test-Path $metadataSource) -and -not (Test-Path $metadataDestination)) {
        Copy-Item -Path $metadataSource -Destination $metadataDestination
    }

    Write-Host ''
    Write-Host 'Native runner folders created.'
    Write-Host 'Next run: flutter pub get'
    Write-Host 'Then run: flutter run -d windows'
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}

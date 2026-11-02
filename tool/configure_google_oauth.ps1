param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$manifestPath = Join-Path $ProjectRoot 'android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $manifestPath)) {
    throw "AndroidManifest.xml was not found at '$manifestPath'. Generate the Android runner first."
}

$content = Get-Content -Path $manifestPath -Raw
if ($content.Contains('com.linusu.flutter_web_auth_2.CallbackActivity')) {
    if ($content.Contains('android:scheme="nexuside"')) {
        Write-Host 'Google OAuth callback is already configured for NexusIDE.'
        return
    }
    throw 'CallbackActivity already exists but the nexuside scheme is missing. Inspect AndroidManifest.xml before editing it.'
}
if (-not $content.Contains('</application>')) {
    throw 'AndroidManifest.xml has no closing application tag; no changes were written.'
}

$activity = @'
        <activity
            android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
            android:exported="true"
            android:taskAffinity="">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="nexuside" />
            </intent-filter>
        </activity>
'@

$content = $content.Replace('</application>', $activity + [Environment]::NewLine + '    </application>')
[System.IO.File]::WriteAllText($manifestPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Google OAuth callback configured in AndroidManifest.xml.'

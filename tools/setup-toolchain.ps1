# Installeert JDK 17, Android SDK en Gradle in de gebruikersmap (geen admin nodig).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$base   = Join-Path $env:USERPROFILE ".android-build"
$jdkDir = Join-Path $base "jdk17"
$sdkDir = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$gradleDir = Join-Path $base "gradle"
New-Item -ItemType Directory -Force $base, $sdkDir | Out-Null
$tmp = Join-Path $base "downloads"
New-Item -ItemType Directory -Force $tmp | Out-Null

if (-not (Test-Path "$jdkDir\bin\java.exe")) {
    Write-Output "JDK 17 downloaden..."
    Invoke-WebRequest "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" -OutFile "$tmp\jdk.zip"
    Expand-Archive "$tmp\jdk.zip" "$tmp\jdk" -Force
    $inner = Get-ChildItem "$tmp\jdk" -Directory | Select-Object -First 1
    Move-Item $inner.FullName $jdkDir
}
$env:JAVA_HOME = $jdkDir
$env:Path = "$jdkDir\bin;$env:Path"
Write-Output "JDK OK"

$cmdline = Join-Path $sdkDir "cmdline-tools\latest"
if (-not (Test-Path "$cmdline\bin\sdkmanager.bat")) {
    Write-Output "Android command-line tools downloaden..."
    Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip" -OutFile "$tmp\cmdline.zip"
    Expand-Archive "$tmp\cmdline.zip" "$tmp\cmdline" -Force
    New-Item -ItemType Directory -Force (Split-Path $cmdline) | Out-Null
    Move-Item "$tmp\cmdline\cmdline-tools" $cmdline
}
Write-Output "SDK-licenties accepteren en pakketten installeren..."
$sdkm = "$cmdline\bin\sdkmanager.bat"
("y`n" * 20) | & $sdkm --sdk_root=$sdkDir --licenses | Out-Null
& $sdkm --sdk_root=$sdkDir "platform-tools" "platforms;android-35" "build-tools;35.0.0" | Out-Null
Write-Output "SDK OK"

if (-not (Test-Path "$gradleDir\bin\gradle.bat")) {
    Write-Output "Gradle downloaden..."
    Invoke-WebRequest "https://services.gradle.org/distributions/gradle-8.11.1-bin.zip" -OutFile "$tmp\gradle.zip"
    Expand-Archive "$tmp\gradle.zip" "$tmp\gradle" -Force
    Move-Item "$tmp\gradle\gradle-8.11.1" $gradleDir
}
Write-Output "Gradle OK"

[Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir, "User")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDir, "User")
Remove-Item $tmp -Recurse -Force
Write-Output "TOOLCHAIN KLAAR"

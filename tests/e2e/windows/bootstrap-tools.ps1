<#
 Copyright 2026 Han Li and contributors

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
#>

# Runs while the E2E image is built, under the Windows PowerShell of the base
# image (5.1): no syntax newer than that in this file.

$ErrorActionPreference = 'Stop'

# Local copy of the native-command guard. Fails unless the command exits 0.
function Invoke-Native {
    param(
        [Parameter(Mandatory)] [scriptblock] $Cmd,
        [Parameter(Mandatory)] [string] $What,
        [int[]] $Ok = 0
    )
    $prev = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    & $Cmd
    $code = $LASTEXITCODE
    $PSNativeCommandUseErrorActionPreference = $prev
    if ($null -eq $code) { throw "FAIL $What did not run" }
    if ($code -notin $Ok) { throw "FAIL $What exited with code $code" }
}

$isArm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
$pwshArch = if ($isArm) { 'arm64' } else { 'x64' }

# Both tools below are zips, not installers: installers took minutes here on
# arm64, while a zip only extracts, and leaves the machine PATH to us. No Git:
# vfox from main is built on the runner (setup.go), and nothing in the
# containers clones.

# PowerShell 7 drives every exec of the suite.
$pwshZip = "$env:TEMP\pwsh.zip"
$pwshUrl = "https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-$pwshArch.zip"
$pwshHome = 'C:\Program Files\PowerShell\7'

Invoke-Native { & curl.exe -fsSL --retry 3 --retry-delay 5 --retry-all-errors -o $pwshZip $pwshUrl } 'the PowerShell download'
New-Item -ItemType Directory -Force -Path $pwshHome | Out-Null
Invoke-Native { & tar.exe -xf $pwshZip -C $pwshHome } 'the PowerShell extraction'
Remove-Item $pwshZip
if (-not (Test-Path "$pwshHome\pwsh.exe")) { throw 'FAIL pwsh.exe is missing after the PowerShell extraction' }
[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ";$pwshHome", 'Machine')

# Gradle is a JVM program, so a JDK has to be there before vfox installs
# anything: Temurin 21, the Java the releases the suite installs run on (Gradle
# 9 needs 17 or later). It is the newest release that Adoptium has built for
# both architectures (jdk-21.0.12.1+1; the x64 zip of 21.0.13+9 is out, the
# aarch64 one was not on 2026-11-04), and its zip is checked against the SHA-256
# that Adoptium publishes next to it, as vfox checks what it installs. The
# image carries no Gradle: a gradle can only come from what vfox installs.
$jdkAsset = if ($isArm) { 'OpenJDK21U-jdk_aarch64_windows_hotspot_21.0.12.1_1.zip' } else { 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip' }
$jdkSha256 = if ($isArm) { 'ccf2e51f527d542a70ba5794a600d3aac04b4e967950e227834c7566cb1bec7b' } else { 'f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e' }
$jdkUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/$jdkAsset"
$jdkZip = "$env:TEMP\jdk.zip"
$jdkTemp = 'C:\jdk-extract'
$jdkHome = 'C:\jdk'

Invoke-Native { & curl.exe -fsSL --retry 3 --retry-delay 5 --retry-all-errors -o $jdkZip $jdkUrl } 'the JDK download'
$jdkActual = (Get-FileHash -Algorithm SHA256 -Path $jdkZip).Hash.ToLowerInvariant()
if ($jdkActual -ne $jdkSha256) { throw "FAIL the JDK download has the SHA-256 $jdkActual, not $jdkSha256" }
New-Item -ItemType Directory -Force -Path $jdkTemp | Out-Null
Invoke-Native { & tar.exe -xf $jdkZip -C $jdkTemp } 'the JDK extraction'
Remove-Item $jdkZip
# The zip holds one directory, jdk-21.0.12.1+1; the JDK goes to a path that does
# not depend on its name.
$jdkExtracted = Get-ChildItem -Path $jdkTemp -Directory | Select-Object -First 1
if (-not $jdkExtracted) { throw 'FAIL the JDK zip held no directory' }
Move-Item -LiteralPath $jdkExtracted.FullName -Destination $jdkHome
Remove-Item -Recurse -Force $jdkTemp
if (-not (Test-Path "$jdkHome\bin\java.exe")) { throw 'FAIL java.exe is missing after the JDK extraction' }
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkHome, 'Machine')
[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ";$jdkHome\bin", 'Machine')

# Long paths are on, so that the caches and builds of Gradle, which nest deeper
# than its distribution, cannot meet the 260 characters that Windows allows by
# default. The longest path in the distribution itself, below the home the suite
# gives vfox (setup.go), is 130 characters (9.2.0 and 9.2.1, 2026-11-04).
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force | Out-Null

<#
.SYNOPSIS
    Builds and packages Flutter Android and Windows releases matching the CI/CD workflow.

.DESCRIPTION
    Automates the full release build pipeline for Flutter projects:
    - Resolves dependencies via FVM or standard Flutter.
    - Configures Java (JDK / Android Studio JBR) automatically.
    - Builds Windows release binary, packages standalone ZIP, and compiles Inno Setup installer with smoke testing.
    - Builds Android Universal APK, split-per-ABI APKs, and Google Play App Bundle (AAB).
    - Zips native debug symbols.
    - Generates release_body.md with architecture download tables.
    - Outputs all final release artifacts to a specified directory.

.PARAMETER ProjectPath
    Path to the Flutter project (containing pubspec.yaml) or the repository root containing the Flutter app directory.
    Defaults to the current working directory.

.PARAMETER OutputDir
    Directory where release artifacts will be placed. Defaults to '<ProjectPath>\dist'.

.PARAMETER PackageName
    Android package name (e.g. com.hassaneltantawy.quran). Automatically detected from build.gradle if omitted.

.PARAMETER AppDisplayName
    Name shown in the Windows installer and Start menu. Automatically detected from pubspec.yaml if omitted.

.PARAMETER AppPublisher
    Publisher name shown in the Windows installer. Defaults to 'Hassan Eltantawy'.

.PARAMETER Platform
    Target platform to build: 'All' (default), 'Android', or 'Windows'.

.PARAMETER Flavor
    Product flavor for Android build (e.g. 'prod'). Set to empty string '' if your project does not use flavors.
    Defaults to 'prod'.

.PARAMETER NoFvm
    Switch to force standard 'flutter' instead of 'fvm flutter'.

.PARAMETER SkipPubGet
    Skip running 'flutter pub get'.

.PARAMETER SkipWindows
    Skip all Windows steps (compilation, zip packaging, Inno Setup installer).

.PARAMETER SkipAndroid
    Skip all Android steps (compilation, APKs, AAB, debug symbols).

.PARAMETER SkipUniversalApk
    Skip building universal APK.

.PARAMETER SkipSplitApk
    Skip building split-per-ABI APKs.

.PARAMETER SkipAppBundle
    Skip building Android App Bundle (AAB).

.PARAMETER SkipWindowsZip
    Skip packaging the Windows standalone ZIP.

.PARAMETER SkipWindowsInstaller
    Skip building the Inno Setup Windows installer.

.PARAMETER SkipTestInstaller
    Skip the silent install/uninstall smoke test for the Windows installer.

.PARAMETER SkipDebugSymbols
    Skip packaging native debug symbols.

.EXAMPLE
    .\build_release.ps1 -ProjectPath "D:\GitHub\quran-bloc\quran" -OutputDir "C:\Users\usr\Desktop\quran_output"

.EXAMPLE
    .\build_release.ps1 -ProjectPath "D:\GitHub\HisnElmoslem_App\hisnelmoslem" -Platform Android

.EXAMPLE
    .\build_release.ps1 -Platform Windows
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectPath = ".",

    [Parameter(Position = 1)]
    [string]$OutputDir,

    [string]$PackageName,
    [string]$AppDisplayName,
    [string]$AppPublisher = "Hassan Eltantawy",

    [ValidateSet("All", "Android", "Windows")]
    [string]$Platform = "All",

    [string]$Flavor = "prod",

    [switch]$NoFvm,
    [switch]$SkipPubGet,
    [switch]$SkipWindows,
    [switch]$SkipAndroid,
    [switch]$SkipUniversalApk,
    [switch]$SkipSplitApk,
    [switch]$SkipAppBundle,
    [switch]$SkipWindowsZip,
    [switch]$SkipWindowsInstaller,
    [switch]$SkipTestInstaller,
    [switch]$SkipDebugSymbols
)

$ErrorActionPreference = "Stop"

function Write-Header([string]$text) {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host " $text" -ForegroundColor Cyan
    Write-Host "========================================================`n" -ForegroundColor Cyan
}

function Write-Info([string]$text) {
    Write-Host "[INFO] $text" -ForegroundColor Gray
}

function Write-Success([string]$text) {
    Write-Host "[SUCCESS] $text" -ForegroundColor Green
}

function Write-Warn([string]$text) {
    Write-Host "[WARNING] $text" -ForegroundColor Yellow
}

function Write-Failure([string]$text) {
    Write-Host "[ERROR] $text" -ForegroundColor Red
}

# --- 1. Resolve Project Directory ---
$resolvedPath = Resolve-Path -Path $ProjectPath -ErrorAction Stop
$projectDir = $resolvedPath.Path

if (-not (Test-Path (Join-Path $projectDir "pubspec.yaml"))) {
    Write-Info "pubspec.yaml not found at root: $projectDir. Searching subdirectories..."
    $candidates = Get-ChildItem -Path $projectDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "pubspec.yaml")
    }

    if ($candidates.Count -eq 1) {
        $projectDir = $candidates[0].FullName
        Write-Info "Found Flutter project in subdirectory: $projectDir"
    } elseif ($candidates.Count -gt 1) {
        $names = ($candidates | ForEach-Object { $_.Name }) -join ", "
        throw "Multiple Flutter projects found ($names). Please specify -ProjectPath pointing to the specific app directory."
    } else {
        throw "Could not find a Flutter project (pubspec.yaml) in '$projectDir' or its direct child folders."
    }
}

Set-Location $projectDir
Write-Info "Working directory set to: $projectDir"

# --- 2. Parse pubspec.yaml & Project Metadata ---
$pubspecRaw = Get-Content (Join-Path $projectDir "pubspec.yaml") -Raw
if ($pubspecRaw -notmatch '(?m)^name:\s*([a-zA-Z0-9_-]+)') {
    throw "Could not read app 'name' from pubspec.yaml"
}
$appName = $Matches[1].Trim()

$version = "1.0.0"
if ($pubspecRaw -match '(?m)^version:\s*(\d+(?:\.\d+)*)') {
    $version = $Matches[1]
}

# Executable name from windows/CMakeLists.txt (defaults to $appName.exe)
$appExe = "$($appName).exe"
$cmakePath = Join-Path $projectDir "windows/CMakeLists.txt"
if (Test-Path $cmakePath) {
    $cmakeContent = Get-Content $cmakePath -Raw
    if ($cmakeContent -match '(?m)^\s*set\(BINARY_NAME\s+"([^"]+)"\)') {
        $appExe = "$($Matches[1]).exe"
    }
}

# Android package name
if (-not $PackageName) {
    $gradlePath = Join-Path $projectDir "android/app/build.gradle"
    $manifestPath = Join-Path $projectDir "android/app/src/main/AndroidManifest.xml"
    
    if (Test-Path $gradlePath) {
        $gradleContent = Get-Content $gradlePath -Raw
        if ($gradleContent -match '(?m)namespace\s*=?\s*["'']([^"'']+)["'']') {
            $PackageName = $Matches[1]
        } elseif ($gradleContent -match '(?m)applicationId\s*=?\s*["'']([^"'']+)["'']') {
            $PackageName = $Matches[1]
        }
    }
    
    if (-not $PackageName -and (Test-Path $manifestPath)) {
        $manifestContent = Get-Content $manifestPath -Raw
        if ($manifestContent -match 'package="([^"]+)"') {
            $PackageName = $Matches[1]
        }
    }

    if (-not $PackageName) {
        $PackageName = "com.hassaneltantawy.$appName"
        Write-Warn "Could not auto-detect package name. Defaulting to: $PackageName"
    }
}

# Display name
if (-not $AppDisplayName) {
    $AppDisplayName = (Get-Culture).TextInfo.ToTitleCase($appName.Replace("-", " ").Replace("_", " "))
}

# --- 3. Resolve Output Directory ---
if (-not $OutputDir) {
    $OutputDir = Join-Path $projectDir "dist"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

$flavorDisplay = $(if ($Flavor) { $Flavor } else { "(None)" })
Write-Header "Release Build Configuration"
Write-Host "App Name:        $appName" -ForegroundColor White
Write-Host "Version:         $version" -ForegroundColor White
Write-Host "Display Name:    $AppDisplayName" -ForegroundColor White
Write-Host "Package Name:    $PackageName" -ForegroundColor White
Write-Host "Publisher:       $AppPublisher" -ForegroundColor White
Write-Host "Platform Target: $Platform" -ForegroundColor White
Write-Host "Product Flavor:  $flavorDisplay" -ForegroundColor White
Write-Host "Output Dir:      $OutputDir" -ForegroundColor White

# --- 4. Toolchain Discovery ---

# Flutter command (FVM detection)
$flutterCmd = "flutter"
$hasFvm = (Get-Command fvm -ErrorAction SilentlyContinue) -ne $null
$hasFvmConfig = (Test-Path (Join-Path $projectDir ".fvmrc")) -or (Test-Path (Join-Path $projectDir ".fvm"))
if (-not $NoFvm -and $hasFvm -and $hasFvmConfig) {
    $flutterCmd = "fvm flutter"
    Write-Info "Using FVM Flutter: fvm flutter"
} else {
    Write-Info "Using standard Flutter: flutter"
}

# Java / JDK discovery
function Ensure-Jdk {
    $javaWorks = $false
    try {
        $null = & java -version 2>&1
        if ($LASTEXITCODE -eq 0 -or $? ) { $javaWorks = $true }
    } catch {}

    if (-not $javaWorks) {
        Write-Info "Locating Java JDK..."
        $jdkCandidates = @(
            "C:\Program Files\Android\Android Studio\jbr",
            "$env:LOCALAPPDATA\Programs\Android Studio\jbr",
            "C:\Program Files\Eclipse Adoptium",
            "C:\Program Files\Zulu",
            "C:\Program Files\Java"
        )
        $foundJdk = $null
        foreach ($candidate in $jdkCandidates) {
            if (Test-Path $candidate) {
                if (Test-Path (Join-Path $candidate "bin\java.exe")) {
                    $foundJdk = $candidate
                    break
                }
                $sub = Get-ChildItem -Path $candidate -Directory -Filter "jdk*" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($sub -and (Test-Path (Join-Path $sub.FullName "bin\java.exe"))) {
                    $foundJdk = $sub.FullName
                    break
                }
            }
        }

        if ($foundJdk) {
            Write-Info "Found JDK at: $foundJdk"
            $env:JAVA_HOME = $foundJdk
            $env:PATH = "$foundJdk\bin;$env:PATH"
        } else {
            Write-Warn "No local JDK automatically discovered. Android builds may fail if JAVA_HOME is not set."
        }
    } else {
        Write-Info "Java is ready."
    }
}

# Inno Setup discovery
function Find-Iscc {
    $roots = @(
        "$env:LOCALAPPDATA\Programs",
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles,
        "C:\ProgramData\chocolatey\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $found = Get-ChildItem -Path $root -Directory -Filter "Inno Setup*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "ISCC.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($found) { return $found }
    }

    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Ensure-Iscc {
    $iscc = Find-Iscc
    if (-not $iscc) {
        Write-Info "Inno Setup not found. Attempting installation via winget..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            & winget install JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements --silent
            $iscc = Find-Iscc
        }
    }
    if (-not $iscc) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Info "Attempting installation via chocolatey..."
            & choco install innosetup -y --no-progress
            $iscc = Find-Iscc
        }
    }
    if (-not $iscc) {
        throw "ISCC.exe could not be found or installed. Please install Inno Setup 6 manually."
    }
    return $iscc
}

# Helper to run Flutter commands
function Invoke-Flutter([string]$arguments) {
    Write-Info "Running: $flutterCmd $arguments"
    $parts = $arguments -split " "
    if ($flutterCmd -eq "fvm flutter") {
        & fvm flutter @parts
    } else {
        & flutter @parts
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed with exit code $LASTEXITCODE"
    }
}

# --- 5. Pub Get ---
if (-not $SkipPubGet) {
    Write-Header "Resolving Flutter Dependencies"
    Invoke-Flutter "pub get"
}

# --- 6. Windows Build ---
$buildWindowsAllowed = ($Platform -in @("All", "Windows")) -and (-not $SkipWindows)
if ($buildWindowsAllowed) {
    Write-Header "Building Windows Application"

    Remove-Item -Recurse -Force "windows/flutter/ephemeral" -ErrorAction SilentlyContinue

    Invoke-Flutter "build windows --release"

    $winReleaseDir = (Resolve-Path "build/windows/x64/runner/Release").Path
    if (-not (Test-Path (Join-Path $winReleaseDir $appExe))) {
        throw "Expected Windows executable '$appExe' not found in $winReleaseDir"
    }

    # Package Standalone ZIP
    if (-not $SkipWindowsZip) {
        Write-Header "Packaging Windows ZIP"
        $zipName = "$($appName)-windows.zip"
        $zipDest = Join-Path $OutputDir $zipName

        $tempPackDir = Join-Path $env:TEMP "flutter_win_pack_$appName"
        Remove-Item -Recurse -Force $tempPackDir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Join-Path $tempPackDir $appName) | Out-Null
        Copy-Item -Recurse (Join-Path $winReleaseDir "*") (Join-Path $tempPackDir $appName)

        Remove-Item -Force $zipDest -ErrorAction SilentlyContinue
        Compress-Archive -Path (Join-Path $tempPackDir $appName) -DestinationPath $zipDest -Force
        Remove-Item -Recurse -Force $tempPackDir -ErrorAction SilentlyContinue

        Write-Success "Created $zipDest"
    }

    # Inno Setup Installer
    if (-not $SkipWindowsInstaller) {
        Write-Header "Building Inno Setup Installer"
        $isccPath = Ensure-Iscc
        Write-Info "Using Inno Setup compiler: $isccPath"

        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($PackageName))
        $appId = "{{" + ([guid]::new([byte[]]$hash)).ToString().ToUpper() + "}"

        $iconPath = Join-Path $projectDir "windows/runner/resources/app_icon.ico"
        $iconLine = $(if (Test-Path $iconPath) { "SetupIconFile=$iconPath" } else { "" })

        $outputName = "$($appName)-windows-installer"

        $template = @'
[Setup]
AppId=@@APP_ID@@
AppName=@@APP_NAME@@
AppVersion=@@APP_VERSION@@
AppPublisher=@@APP_PUBLISHER@@
DefaultDirName={autopf}\@@APP_NAME@@
DisableProgramGroupPage=yes
OutputDir=@@OUTPUT_DIR@@
OutputBaseFilename=@@OUTPUT_NAME@@
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\@@APP_EXE@@
@@ICON_LINE@@

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "@@SOURCE_DIR@@\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\@@APP_NAME@@"; Filename: "{app}\@@APP_EXE@@"
Name: "{autodesktop}\@@APP_NAME@@"; Filename: "{app}\@@APP_EXE@@"; Tasks: desktopicon

[Run]
Filename: "{app}\@@APP_EXE@@"; Description: "{cm:LaunchProgram,@@APP_NAME@@}"; Flags: nowait postinstall skipifsilent
'@

        $issContent = $template
        $issContent = $issContent.Replace("@@APP_ID@@", $appId)
        $issContent = $issContent.Replace("@@APP_NAME@@", $AppDisplayName)
        $issContent = $issContent.Replace("@@APP_VERSION@@", $version)
        $issContent = $issContent.Replace("@@APP_PUBLISHER@@", $AppPublisher)
        $issContent = $issContent.Replace("@@OUTPUT_DIR@@", $OutputDir)
        $issContent = $issContent.Replace("@@OUTPUT_NAME@@", $outputName)
        $issContent = $issContent.Replace("@@APP_EXE@@", $appExe)
        $issContent = $issContent.Replace("@@SOURCE_DIR@@", $winReleaseDir)
        $issContent = $issContent.Replace("@@ICON_LINE@@", $iconLine)

        $issFile = Join-Path $env:TEMP "$appName-installer.iss"
        Set-Content -Path $issFile -Value $issContent -Encoding UTF8

        & $isccPath $issFile
        if ($LASTEXITCODE -ne 0) { throw "ISCC compilation failed with exit code $LASTEXITCODE" }

        $installerPath = Join-Path $OutputDir "$outputName.exe"
        if (-not (Test-Path $installerPath)) { throw "Expected installer not found at: $installerPath" }
        Write-Success "Created $installerPath"

        # Silent smoke test
        if (-not $SkipTestInstaller) {
            Write-Info "Running installer silent smoke test..."
            $testInstallDir = Join-Path $env:TEMP "installer-test-$appName"
            $testLog = Join-Path $env:TEMP "installer-test-$appName.log"
            Remove-Item -Recurse -Force $testInstallDir -ErrorAction SilentlyContinue

            $installProc = Start-Process -FilePath $installerPath -Wait -PassThru -ArgumentList @(
                "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/CURRENTUSER",
                "/DIR=`"$testInstallDir`"", "/LOG=`"$testLog`""
            )
            if ($installProc.ExitCode -ne 0) {
                if (Test-Path $testLog) { Get-Content $testLog | Write-Host }
                throw "Installer smoke test failed (ExitCode: $($installProc.ExitCode))"
            }

            if (-not (Test-Path (Join-Path $testInstallDir $appExe))) {
                throw "Executable '$appExe' was not found in test installation directory."
            }

            $uninstaller = Join-Path $testInstallDir "unins000.exe"
            if (-not (Test-Path $uninstaller)) {
                throw "Uninstaller unins000.exe not found at $uninstaller"
            }
            $unProc = Start-Process -FilePath $uninstaller -Wait -PassThru -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
            if ($unProc.ExitCode -ne 0) {
                throw "Uninstaller exited with code $($unProc.ExitCode)"
            }

            Remove-Item -Recurse -Force $testInstallDir -ErrorAction SilentlyContinue
            Remove-Item -Force $testLog -ErrorAction SilentlyContinue
            Write-Success "Installer smoke test passed."
        }
    }
}

# --- 7. Android Builds ---
$buildAndroidAllowed = ($Platform -in @("All", "Android")) -and (-not $SkipAndroid)
if ($buildAndroidAllowed) {
    Ensure-Jdk

    $flavorArg = $(if ($Flavor) { "--flavor $Flavor" } else { "" })

    # 1. Universal APK
    if (-not $SkipUniversalApk) {
        Write-Header "Building Android Universal APK"
        $argsList = "build apk $flavorArg --release"
        Invoke-Flutter $argsList.Trim()

        $apkDir = "build/app/outputs/flutter-apk"
        $apkSrc = Join-Path $apkDir "app-$Flavor-release.apk"
        if (-not (Test-Path $apkSrc)) {
            $apkSrc = Get-ChildItem -Path $apkDir -Filter "*.apk" |
                Where-Object { $_.Name -notmatch "arm" -and $_.Name -notmatch "x86" -and $_.Name -notmatch "sha1" } |
                Select-Object -First 1 -ExpandProperty FullName
        }

        if ($apkSrc -and (Test-Path $apkSrc)) {
            $destApk = Join-Path $OutputDir "$($appName)-android.apk"
            Copy-Item $apkSrc $destApk -Force
            Write-Success "Created $destApk"
        } else {
            throw "Universal APK was not found in $apkDir"
        }
    }

    # 2. Split-per-ABI APKs
    if (-not $SkipSplitApk) {
        Write-Header "Building Android Split-per-ABI APKs"
        $argsList = "build apk $flavorArg --release --split-per-abi"
        Invoke-Flutter $argsList.Trim()

        $apkDir = "build/app/outputs/flutter-apk"
        $splitAbis = @("armeabi-v7a", "arm64-v8a", "x86_64")
        $foundCount = 0

        foreach ($abi in $splitAbis) {
            $src = Get-ChildItem -Path $apkDir -Filter "*$abi*release.apk" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "sha1" } |
                Select-Object -First 1

            if ($src) {
                $target = Join-Path $OutputDir "$($appName)-android-$abi.apk"
                Copy-Item $src.FullName $target -Force
                Write-Success "Created $target"
                $foundCount++
            } else {
                Write-Warn "Split APK for $abi was not found in $apkDir"
            }
        }

        if ($foundCount -eq 0) {
            throw "No split-per-abi APKs were produced."
        }
    }

    # 3. Android App Bundle (AAB)
    if (-not $SkipAppBundle) {
        Write-Header "Building Android App Bundle (AAB)"
        $argsList = "build appbundle $flavorArg --release"
        Invoke-Flutter $argsList.Trim()

        $bundleDir = "build/app/outputs/bundle"
        $aabSrc = Join-Path $bundleDir "$($Flavor)Release/app-$Flavor-release.aab"
        if (-not (Test-Path $aabSrc)) {
            $aabSrc = Get-ChildItem -Path $bundleDir -Filter "*.aab" -Recurse | Select-Object -First 1 -ExpandProperty FullName
        }

        if ($aabSrc -and (Test-Path $aabSrc)) {
            $destAab = Join-Path $OutputDir "$($appName)-android.aab"
            Copy-Item $aabSrc $destAab -Force
            Write-Success "Created $destAab"
        } else {
            throw "App bundle (.aab) was not found in $bundleDir"
        }
    }

    # 4. Debug Symbols Zip
    if (-not $SkipDebugSymbols) {
        Write-Header "Packaging Native Debug Symbols"
        $flavorSuffix = $(if ($Flavor) { "$($Flavor)Release" } else { "release" })
        $capFlavorSuffix = $(if ($Flavor) {
            ([string]$Flavor[0]).ToUpper() + $Flavor.Substring(1) + "Release"
        } else {
            "Release"
        })

        $symbolDirCandidates = @(
            "build/app/intermediates/merged_native_libs/$flavorSuffix/merge${capFlavorSuffix}NativeLibs/out/lib",
            "build/app/intermediates/merged_native_libs/$flavorSuffix/out/lib",
            "build/app/intermediates/stripped_native_libs/$flavorSuffix/out/lib"
        )

        $foundSymbolDir = $null
        foreach ($cand in $symbolDirCandidates) {
            if (Test-Path $cand) {
                $foundSymbolDir = (Resolve-Path $cand).Path
                break
            }
        }

        if ($foundSymbolDir) {
            $symbolsZip = Join-Path $OutputDir "debug_symbols.zip"
            Compress-Archive -Path "$foundSymbolDir\*" -DestinationPath $symbolsZip -Force
            Write-Success "Created $symbolsZip"
        } else {
            Write-Info "No native debug symbols directory found; skipping debug_symbols.zip."
        }
    }
}

# --- 8. Generate release_body.md ---
function Format-LinkOrDash([string]$fileName, [string]$label) {
    $fullPath = Join-Path $OutputDir $fileName
    if (Test-Path $fullPath) {
        return "[$label]($fileName)"
    }
    return "-"
}

$playUrl = "https://play.google.com/store/apps/details?id=$PackageName"
$apkUniversal = Format-LinkOrDash "$($appName)-android.apk" "APK"
$apkX64 = Format-LinkOrDash "$($appName)-android-x86_64.apk" "APK"
$apkArm64 = Format-LinkOrDash "$($appName)-android-arm64-v8a.apk" "APK"
$apkArmV7 = Format-LinkOrDash "$($appName)-android-armeabi-v7a.apk" "APK"
$winInstaller = Format-LinkOrDash "$($appName)-windows-installer.exe" "Installer"
$winZip = Format-LinkOrDash "$($appName)-windows.zip" "ZIP"

$winX64Col = $(if ($winInstaller -ne "-" -or $winZip -ne "-") { "$winInstaller · $winZip" } else { "-" })

$releaseBody = @"
## Downloads

| Architecture | Windows | Android |
|---|---|---|
| Universal | - | $apkUniversal |
| x86-64 (64-bit) | $winX64Col | $apkX64 |
| AArch64 (ARM64) | - | $apkArm64 |
| ARMv7 (32-bit) | - | $apkArmV7 |

📱 Also available on [Google Play]($playUrl)

---
"@

$chPath1 = Join-Path $projectDir "CHANGELOG.md"
$parentDir = Split-Path -Parent $projectDir
$chPath2 = $(if ($parentDir) { Join-Path $parentDir "CHANGELOG.md" } else { "" })

$changelogCandidate = $null
if (Test-Path $chPath1) {
    $changelogCandidate = $chPath1
} elseif ($chPath2 -and (Test-Path $chPath2)) {
    $changelogCandidate = $chPath2
}

if ($changelogCandidate) {
    $releaseBody += "`r`n`r`n" + (Get-Content $changelogCandidate -Raw)
}

$releaseBodyPath = Join-Path $OutputDir "release_body.md"
Set-Content -Path $releaseBodyPath -Value $releaseBody -Encoding UTF8
Write-Success "Generated $releaseBodyPath"

# --- 9. Final Summary ---
Write-Header "Release Build Complete!"
Write-Host "Destination: $OutputDir`n" -ForegroundColor Green

Get-ChildItem -Path $OutputDir |
    Select-Object Name, @{Name="Size (MB)"; Expression={ "{0:N2} MB" -f ($_.Length / 1MB) }}, LastWriteTime |
    Format-Table -AutoSize

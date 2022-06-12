#requires -Modules cChoco
## 1. REQUIREMENTS ##
### Here are the requirements necessary to ensure this is successful.

### a. Internal/Private Cloud Repository Set Up ###
#### You'll need an internal/private cloud repository you can use. These are
####  generally really quick to set up and there are quite a few options.
####  Chocolatey Software recommends Nexus, Artifactory Pro, or ProGet as they
####  are repository servers and will give you the ability to manage multiple
####  repositories and types from one server installation.

### b. Download Chocolatey Package and Put on Internal Repository ###
#### You need to have downloaded the Chocolatey package as well.
####  Please see https://chocolatey.org/install#organization

### c. Other Requirements ###
#### i. Requires chocolatey\cChoco DSC module to be installed on the machine compiling the DSC manifest
#### NOTE: This will need to be installed before running the DSC portion of this script
if (-not (Get-Module cChoco -ListAvailable)) {
    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    if (($PSGallery = Get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    Install-Module -Name cChoco
    if ($PSGallery.InstallationPolicy -ne "Trusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy $PSGallery.InstallationPolicy
    }
}

#### ii. Requires a hosted copy of the install.ps1 script
##### This should be available to download without authentication.
##### The original script can be found here: https://community.chocolatey.org/install.ps1

Configuration ChocolateyConfig {
## 2. TOP LEVEL VARIABLES ##
    param(
### a. Your internal repository url (the main one). ###
####  Should be similar to what you see when you browse
#### to https://community.chocolatey.org/api/v2/
        $NugetRepositoryUrl      = "https://community.chocolatey.org/api/v2/",

### b. Chocolatey nupkg download url ###
#### This url should result in an immediate download when you navigate to it in
#### a web browser
        $ChocolateyNupkgUrl      = "https://community.chocolatey.org/api/v2//package/chocolatey.1.1.0.nupkg",

### c. Internal Repository Credential ###
#### If required, add the repository access credential here
#        $NugetRepositoryCredential = [PSCredential]::new(
#            "username",
#            ("password" | ConvertTo-SecureString -AsPlainText -Force)
#        ),

### d. Install.ps1 URL
#### The path to the hosted install script:
        $ChocolateyInstallPs1Url = "https://community.chocolatey.org/install.ps1"

### e. Chocolatey Central Management (CCM) ###
#### If using CCM to manage Chocolatey, add the following:
#### i. Endpoint URL for CCM
#        $ChocolateyCentralManagementUrl = "https://chocolatey-central-management:24020/ChocolateyManagementService",

#### ii. If using a Client Salt, add it here
#        $ChocolateyCentralManagementClientSalt = "clientsalt",

#### iii. If using a Service Salt, add it here
#        $ChocolateyCentralManagementServiceSalt = "servicesalt"
    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName cChoco

    Node 'localhost' {
## 3. ENSURE CHOCOLATEY IS INSTALLED ##
### Ensure Chocolatey is installed from your internal repository
        Environment chocoDownloadUrl {
            Name  = "chocolateyDownloadUrl"
            Value = $ChocolateyNupkgUrl
        }

        cChocoInstaller installChocolatey {
            DependsOn = "[Environment]chocoDownloadUrl"
            InstallDir = Join-Path $env:ProgramData "chocolatey"
            ChocoInstallScriptUrl = $ChocolateyInstallPs1Url
        }

## 4. CONFIGURE CHOCOLATEY BASELINE ##
### a. FIPS Feature ###
#### If you need FIPS compliance - make this the first thing you configure
#### before you do any additional configuration or package installations
#        cChocoFeature featureFipsCompliance {
#            FeatureName = "useFipsCompliantChecksums"
#        }

### b. Apply Recommended Configuration ###

#### Move cache location so Chocolatey is very deterministic about
#### cleaning up temporary data and the location is secured to admins
        cChocoConfig cacheLocation {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            ConfigName = "cacheLocation"
            Value      = "C:\ProgramData\chocolatey\cache"
        }

#### Increase timeout to at least 4 hours
        cChocoConfig commandExecutionTimeoutSeconds {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            ConfigName = "commandExecutionTimeoutSeconds"
            Value      = 14400
        }

#### Turn off download progress when running choco through integrations
        cChocoFeature showDownloadProgress {
            DependsOn   = "[cChocoInstaller]installChocolatey"
            FeatureName = "showDownloadProgress"
            Ensure      = "Absent"
        }

### c. Sources ###
#### Remove the default community package repository source
        cChocoSource removeCommunityRepository {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            Name       = "chocolatey"
            Ensure     = "Absent"
        }

#### Add internal default sources
#### You could have multiple sources here, so we will provide an example
#### of one using the remote repo variable here.
#### NOTE: This EXAMPLE may require changes
        cChocoSource addInternalSource {
            DependsOn  = "[cChocoInstaller]installChocolatey"
            Name        = "ChocolateyInternal"
            Source      = $NugetRepositoryUrl
            Credentials = $NugetRepositoryCredential
            Priority    = 1
        }

### b. Keep Chocolatey Up To Date ###
#### Keep chocolatey up to date based on your internal source
#### You control the upgrades based on when you push an updated version
####  to your internal repository.
#### Note the source here is to the OData feed, similar to what you see
####  when you browse to https://community.chocolatey.org/api/v2/
        cChocoPackageInstaller updateChocolatey {
            DependsOn   = "[cChocoSource]addInternalSource", "[cChocoSource]removeCommunityRepository"
            Name        = "chocolatey"
            AutoUpgrade = $true
        }

## 5. ENSURE CHOCOLATEY FOR BUSINESS ##
### If you don't have Chocolatey for Business (C4B), you'll want to remove from here down.

### a. Ensure The License File Is Installed ###
#### Create a license package using script from https://docs.chocolatey.org/en-us/how-tos/setup-offline-installation#exercise-4-create-a-package-for-the-license
        cChocoPackageInstaller chocolateyLicense {
            DependsOn = "[cChocoPackageInstaller]updateChocolatey"
            Name      = "chocolatey-license"
        }

### b. Disable The Licensed Source ###
#### The licensed source cannot be removed, so it must be disabled.
#### This must occur after the license has been set by the license package.
        Script disableLicensedSource {
            DependsOn  = "[cChocoPackageInstaller]chocolateyLicense"
            GetScript  = {
                $Source = choco source list --limitoutput | `
                    ConvertFrom-Csv -Delimiter '|' -Header Name, Source, Disabled | `
                    Where-Object Name -eq "chocolatey.licensed"

                return @{
                    Result = if ($Source) {
                        [bool]::Parse($Source.Disabled)
                    } else {
                        Write-Warning "Source 'chocolatey.licensed' was not present."
                        $true  # Source does not need disabling
                    }
                }
            }
            SetScript  = {
                $null = choco source disable --name "chocolatey.licensed"
            }
            TestScript = {
                $State = [ScriptBlock]::Create($GetScript).Invoke()
                return $State.Result
            }
        }

### c. Ensure Chocolatey Licensed Extension ###
#### You will have downloaded the licensed extension to your internal repository
#### as you have disabled the licensed repository in step 5b.

#### Ensure the chocolatey.extension package (aka Chocolatey Licensed Extension)
        cChocoPackageInstaller chocolateyLicensedExtension {
            DependsOn = "[Script]disableLicensedSource"
            Name      = "chocolatey.extension"
        }

#### The Chocolatey Licensed Extension unlocks all of the following, which also have configuration/feature items available with them. You may want to visit the feature pages to see what you might want to also enable:
#### - Package Builder - https://docs.chocolatey.org/en-us/features/paid/package-builder
#### - Package Internalizer - https://docs.chocolatey.org/en-us/features/paid/package-internalizer
#### - Package Synchronization (3 components) - https://docs.chocolatey.org/en-us/features/paid/package-synchronization
#### - Package Reducer - https://docs.chocolatey.org/en-us/features/paid/package-reducer
#### - Package Audit - https://docs.chocolatey.org/en-us/features/paid/package-audit
#### - Package Throttle - https://docs.chocolatey.org/en-us/features/paid/package-throttle
#### - CDN Cache Access - https://docs.chocolatey.org/en-us/features/paid/private-cdn
#### - Branding - https://docs.chocolatey.org/en-us/features/paid/branding
#### - Self-Service Anywhere (more components will need to be installed and additional configuration will need to be set) - https://docs.chocolatey.org/en-us/features/paid/self-service-anywhere
#### - Chocolatey Central Management (more components will need to be installed and additional configuration will need to be set) - https://docs.chocolatey.org/en-us/features/paid/chocolatey-central-management
#### - Other - https://docs.chocolatey.org/en-us/features/paid/

### d. Ensure Self-Service Anywhere ###
#### If you have desktop clients where users are not administrators, you may
#### to take advantage of deploying and configuring Self-Service anywhere
        cChocoFeature hideElevatedWarnings {
            DependsOn   = "[cChocoPackageInstaller]chocolateyLicensedExtension"
            FeatureName = "showNonElevatedWarnings"
            Ensure      = "Absent"
        }

        cChocoFeature useBackgroundService {
            DependsOn   = "[cChocoPackageInstaller]chocolateyLicensedExtension"
            FeatureName = "useBackgroundService"
            Ensure      = "Present"
        }

        cChocoFeature useBackgroundServiceWithNonAdmins {
            DependsOn   = "[cChocoPackageInstaller]chocolateyLicensedExtension"
            FeatureName = "useBackgroundServiceWithNonAdministratorsOnly"
            Ensure      = "Present"
        }

        cChocoFeature useBackgroundServiceUninstallsForUserInstalls {
            DependsOn   = "[cChocoPackageInstaller]chocolateyLicensedExtension"
            FeatureName = "allowBackgroundServiceUninstallsFromUserInstallsOnly"
            Ensure      = "Present"
        }

        cChocoConfig allowedBackgroundServiceCommands {
            DependsOn   = "[cChocoFeature]useBackgroundService"
            ConfigName = "backgroundServiceAllowedCommands"
            Value       = "install,upgrade,uninstall"
        }

### e. Ensure Chocolatey Central Management ###
#### If you want to manage and report on endpoints, you can set up and configure
### Central Management. There are multiple portions to manage, so you'll see
### a section on agents here along with notes on how to configure the server
### side components.
        if ($ChocolateyCentralManagementUrl) {
            cChocoPackageInstaller chocolateyAgent {
                DependsOn = "[cChocoPackageInstaller]chocolateyLicensedExtension"
                Name      = "chocolatey-agent"
            }

            cChocoConfig centralManagementServiceUrl {
                DependsOn   = "[cChocoPackageInstaller]chocolateyAgent"
                ConfigName = "CentralManagementServiceUrl"
                Value       = $ChocolateyCentralManagementUrl
            }

            if ($ChocolateyCentralManagementClientSalt) {
                cChocoConfig centralManagementClientSalt {
                    DependsOn  = "[cChocoPackageInstaller]chocolateyAgent"
                    ConfigName = "centralManagementClientCommunicationSaltAdditivePassword"
                    Value      = $ChocolateyCentralManagementClientSalt
                }
            }

            if ($ChocolateyCentralManagementServiceSalt) {
                cChocoConfig centralManagementServiceSalt {
                    DependsOn  = "[cChocoPackageInstaller]chocolateyAgent"
                    ConfigName = "centralManagementServiceCommunicationSaltAdditivePassword"
                    Value      = $ChocolateyCentralManagementServiceSalt
                }
            }

            cChocoFeature useCentralManagement {
                DependsOn   = "[cChocoPackageInstaller]chocolateyAgent"
                FeatureName = "useChocolateyCentralManagement"
                Ensure      = "Present"
            }

            cChocoFeature useCentralManagementDeployments {
                DependsOn   = "[cChocoPackageInstaller]chocolateyAgent"
                FeatureName = "useChocolateyCentralManagementDeployments"
                Ensure      = "Present"
            }
        }
    }
}

# If working this into an existing configuration with a good method for
$ConfigData = @{
    AllNodes = @(
        @{
            NodeName                    = "localhost"
            PSDscAllowPlainTextPassword = $true
        }
    )
}

try {
    Push-Location $env:Temp
    $Config = ChocolateyConfig -ConfigurationData $ConfigData
    Start-DscConfiguration -Path $Config.PSParentPath -Wait -Verbose -Force
} finally {
    Pop-Location
}


cChocoPackageInstaller googlechrome
{
    Name    = "googlechrome"
    Version = "102.0.5005.115"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller notepadplusplus.install
{
    Name    = "notepadplusplus.install"
    Version = "8.4.2"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller python
{
    Name    = "python"
    Version = "3.10.5"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller vlc
{
    Name    = "vlc"
    Version = "3.0.17.4"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller git.install
{
    Name    = "git.install"
    Version = "2.36.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller 7zip
{
    Name    = "7zip"
    Version = "21.7"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller notepadplusplus
{
    Name    = "notepadplusplus"
    Version = "8.4.2"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openssh
{
    Name    = "openssh"
    Version = "8.0.0.1"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller nodejs.install
{
    Name    = "nodejs.install"
    Version = "18.3.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller vscode
{
    Name    = "vscode"
    Version = "1.68.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller jdk8
{
    Name    = "jdk8"
    Version = "8.0.211"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller nodejs
{
    Name    = "nodejs"
    Version = "18.3.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller vscode.install
{
    Name    = "vscode.install"
    Version = "1.68.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller spotify
{
    Name    = "spotify"
    Version = "1.1.87.612"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller chocolateygui
{
    Name    = "chocolateygui"
    Version = "1.0.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller nodejs-lts
{
    Name    = "nodejs-lts"
    Version = "16.15.1"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openssl.light
{
    Name    = "openssl.light"
    Version = "3.0.3"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller wireshark
{
    Name    = "wireshark"
    Version = "3.6.5"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openssl
{
    Name    = "openssl"
    Version = "1.1.1.1500"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller anydesk
{
    Name    = "anydesk"
    Version = "7.0.10"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openjdk
{
    Name    = "openjdk"
    Version = "18.0.1.1"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller vlc.install
{
    Name    = "vlc.install"
    Version = "3.0.17.4"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openvpn
{
    Name    = "openvpn"
    Version = "2.5.7"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller anaconda3
{
    Name    = "anaconda3"
    Version = "2022.05"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openjdk11
{
    Name    = "openjdk11"
    Version = "11.0.15"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller vnc-viewer
{
    Name    = "vnc-viewer"
    Version = "6.22.315"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller openjdk8jre
{
    Name    = "openjdk8jre"
    Version = "8.332.09"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller pdfxchangeeditor
{
    Name    = "pdfxchangeeditor"
    Version = "9.3.361.20220508"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller telegram
{
    Name    = "telegram"
    Version = "3.7.3"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller bitwarden
{
    Name    = "bitwarden"
    Version = "2022.5.1"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller utorrent
{
    Name    = "utorrent"
    Version = "3.5.5.45271"
    Source  = "https://community.chocolatey.org/api/v2/"
}

cChocoPackageInstaller docker-desktop
{
    Name    = "docker-desktop"
    Version = "4.9.0"
    Source  = "https://community.chocolatey.org/api/v2/"
}

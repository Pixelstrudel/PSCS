#
#
#   PowerShell Container Script
#
#   Allows you to easily create/update/manage Dynamics 365 (NAV/BC) Docker containers
#
#

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {   
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

Set-StrictMode -Version Latest

$server = $null
$global:menuOptions = $null
$pscsFolder = $env:APPDATA + "\.pscs\"
$pscsTempFile = "templates.json"
$pscsTempPath = $pscsFolder + $pscsTempFile
$dockerNameRegex = '\/?[a-zA-Z0-9_-]+'
$repoList = @(
    [PSCustomObject]@{name = "OnPrem Versions of Business Central"; baseUrl = "mcr.microsoft.com/businesscentral/onprem"; tagsUrl = "https://mcr.microsoft.com/v2/businesscentral/onprem/tags/list" },
    [PSCustomObject]@{name = "SaaS Versions of Business Central"; baseUrl = "mcr.microsoft.com/businesscentral/sandbox"; tagsUrl = "https://mcr.microsoft.com/v2/businesscentral/sandbox/tags/list" },
    [PSCustomObject]@{name = "Old(er) versions of NAV"; baseUrl = "mcr.microsoft.com/dynamicsnav"; tagsUrl = "https://mcr.microsoft.com/v2/dynamicsnav/tags/list" }
)
$menuList = @(
    [PSCustomObject]@{desc = "create a new container"; func = "Menu.CreateContainer"; char = "1" },
    [PSCustomObject]@{desc = "remove an existing container"; func = "Menu.RemoveContainer"; char = "2" },
    [PSCustomObject]@{desc = "update user credentials (Windows User)"; func = "Menu.UpdateWindowsUser"; char = "3" },
    [PSCustomObject]@{desc = "update license"; func = "Menu.UpdateLicense"; char = "4" },
    [PSCustomObject]@{desc = "create a new template"; func = "Menu.CreateTemplate"; char = "5" }
)

Class Template {
    [String] $name
    [String] $prefix
    [String] $image
    [System.IO.FileInfo] $licenseFile
    [String] $authType
    [System.Collections.Generic.List[System.Object]] $containerList
    
    [Container] CreateContainer([string]$containerName, [System.IO.FileInfo]$dbFile) {
        $fullContainerName = $this.prefix + "-" + $containerName
        $params = @{
            'containerName'            = $fullContainerName;
            'imageName'                = $this.image;
            'auth'                     = $this.authType;
            'shortcuts'                = 'StartMenu';
            'accept_eula'              = $true;
            'accept_outdated'          = $true;
            'doNotCheckHealth'         = $true;
            'doNotExportObjectsToText' = $true;
            'alwaysPull'               = $true;
            'updateHosts'              = $true;
            'useBestContainerOS'       = $true;
            #'includeCSide'             = $true;
            #'enableSymbolLoading'      = $true;
        }

        $IncludeCSIDE = $false;
        Write-host "Include C/SIDE (and symbol loading)? [for versions below 15.0] (defaults to no)" -ForegroundColor Yellow 
        $ReadHost = Read-Host " ( y / n ) " 
        Switch ($ReadHost) { 
            Y { $IncludeCSIDE = $true } 
            N { $IncludeCSIDE = $false } 
            Default { $IncludeCSIDE = $false } 
        }
        if ($this.licenseFile) {
            if (Test-Path -path $this.licenseFile) {
                $params += @{'licenseFile' = $this.licenseFile }
            }
        }
        
        if ($IncludeCSIDE) {
            $params += @{'includeCSide' = $true; 'enableSymbolLoading' = $true; }
        }

        if ($dbFile) {
            if (!(Test-Path -path "C:\temp")) { New-Item "C:\temp" -Type Directory }
            if (!(Test-Path -path "C:\temp\navdbfiles")) { New-Item "C:\temp\navdbfiles" -Type Directory }
            Copy-Item $dbFile "C:\temp\navdbfiles\dbFile.bak"
            $params += @{'additionalParameters' = @('--volume c:\temp\navdbfiles:c:\temp', '--env bakfile="c:\temp\dbFile.bak"') }
        }

        New-NavContainer @params
        $container = New-Object Container
        $container.template = $this.prefix
        $container.name = $containerName
        $container.fullName = $fullContainerName
        $container.image = $this.image
        $container.status = Get-DockerContainer -Name $container.name | Select-Object Status
        return $container
    }
    ChangeLicense([System.IO.FileInfo] $newLicense) {
        if (!$newLicense) {
            $newLicense = Get-OpenFile "Pick license file for $($this.name)" "License files (*.flf)|*.flf" $PSScriptRoot
        }
        if ($newLicense) {
            $this.licenseFile = $newLicense
        }
    }
    ChangeImage([String] $newImage) {
        if (!$newImage) {
            $newImage = View.SelectImage($null);
        }
        if ($newImage) {
            $this.image = $newImage
        }
    }
}
Class Container {
    [String] $template
    [String] $name
    [String] $image
    [String] $fullName
    [String] $status
    UpdateLicense([System.IO.FileInfo] $license) {
        Import-NavContainerLicense -containerName $this.fullName -licenseFile $license
    }
    UpdateWindowsUser() {
        $username = '{0}\{1}' -f $this.fullName, $env:USERNAME
        $arguments = $username

        Invoke-ScriptInNavContainer -containerName $this.fullName -scriptblock { 
            Set-NAVServerUser -ServerInstance NAV -UserName $($args[0]) -NewWindowsAccount $($args[0])
        } -argumentList $arguments
    }
    ExportBackup() {
        Backup-NavContainerDatabases -containerName $this.fullName -bakfolder "c:\programdata\navcontainerhelper\extensions\"+$this.fullName
        Start-Process "c:\programdata\navcontainerhelper\extensions\"+$this.fullName
    }
}
Function Get-OpenFile($title, $filter, $initialDirectory) { 
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
    Out-Null

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = $filter
    $OpenFileDialog.title = $title
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
    $OpenFileDialog.ShowHelp = $true
}
Function GetTemplatesFromFile() {
    [cmdletbinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.IO.FileInfo] $jsonFile
    )

    #CheckFile $jsonFile ".json"
    $jsonEntries = $jsonFile | Get-Content -Raw | Out-String | ConvertFrom-Json | ForEach-Object { $_ }
    $tempList = @()
    foreach ($jsonEntry in $jsonEntries) {
        $temp = New-Object Template
        $temp.prefix = $jsonEntry.prefix
        $temp.name = $jsonEntry.name
        $temp.image = $jsonEntry.image
        $temp.licenseFile = $jsonEntry.licenseFile
        $temp.authType = "Windows"
        $tempList += $temp
    }
    return $tempList
}
Function GetAllContainersFromDocker {
    $containers = Get-DockerContainer | Where-Object { $_.Name -match "-" }
    $contObjList = @()
    foreach ($container in $containers) {
        $splitName = $container.Name.Split("-")
        $contObj = New-Object Container
        $contObj.template = $splitName[0]
        $contObj.name = $splitName[1]
        $contObj.fullName = $container.Name
        $contObj.status = $container.Status
        $contObjList += $contObj
    }
    return $contObjList
}
Function GetContainersFromDocker([string] $templateName) {
    $containers = Get-DockerContainer | Where-Object { $_.Name.StartsWith($templateName + "-") }
    $contObjList = @()
    foreach ($container in $containers) {
        $splitName = $container.Name.Split("-")
        $contObj = New-Object Container
        $contObj.template = $splitName[0]
        $contObj.name = $splitName[1]
        $contObj.fullName = $container.Name
        $contObj.status = $container.Status
        $contObjList += $contObj
    }
    return $contObjList
}
function View.SelectImage($registry) {
    if (!$registry) {
        $registry = View.SelectRegistry
    }
    $result = Invoke-WebRequest -Uri $registry.tagsUrl
    $JSON = ConvertFrom-Json -InputObject $result.Content
    $image = $JSON.tags | Out-GridView -OutputMode Single
    if ($image) {
        $imageUri = $registry.baseUrl + ":" + $image
    }
    else {
        $imageUri = $registry.baseUrl
    }
    return $imageUri
}
function View.SelectRegistry() {
    #if (Test-Path $pscsRegistryPath) {
    #    $registryList = Get-Content -Raw -Path $pscsRegistryPath | ConvertFrom-Json
    #    $registrySelection = $registryList | Out-GridView -OutputMode Single
    #}
    $registrySelection = $repoList | Out-GridView -Title "Select repository" -OutputMode Single
    return $registrySelection
}
function View.SelectTemplate() {
    $template = Get-Item -Path $pscsTempPath | GetTemplatesFromFile | Out-GridView -Title "Select template to create a new container" -OutputMode Single
    if ($template) {
        $containerName = Read-Host "Please enter a name"
        $template.CreateContainer($containerName)
    }
}
function Menu.Loop {
    param (
        [string]$Title = 'PowerShell Container Script'
    )
    #Clear-Host
    Write-Host "================ $Title ================"
    foreach ($menuItem in $menuList) {
        Write-Host "$($menuItem.char)" -NoNewline -ForegroundColor Yellow
        Write-Host ": Press '$($menuItem.char)' to " -NoNewline
        Write-Host "$($menuItem.desc)" -ForegroundColor Yellow
    }
    Write-Host "Q" -NoNewline -ForegroundColor Red
    Write-Host ": Press 'Q' to " -NoNewline
    Write-Host "quit" -ForegroundColor Red

    $input = Read-Host "Please select an option"
    if ($input -like "q") {
        return
    }
    $menuChoice = $menuList -match $input
    if ($menuChoice) {
        Clear-Host
        &$menuChoice.func
    }
    Menu.Loop
}
function Menu.CreateContainer() {
    $selection = Get-Item -Path $pscsTempPath | GetTemplatesFromFile | Out-GridView -Title "Select a template to create a new container" -OutputMode Single
    if ($selection) {
        $dbFile = $null
        $containerName = Read-Host "Please enter a name (e.g. 'TEST' or 'DEV')"
        Write-host "Use database backup? (defaults to no)" -ForegroundColor Yellow
        $ReadHost = Read-Host " ( y / n ) "
        Switch ($ReadHost) {
            Y { $UseBackup = $true }
            N { $UseBackup = $false }
            Default { $UseBackup = $false }
        }
        if ($UseBackup) { 
            $dbFile = Get-OpenFile "Pick database backup for $($containerName)" "Database Backup files (*.bak)|*.bak" $PSScriptRoot
        }
        $selection.CreateContainer($containerName, $dbFile)
    }
}
function Menu.RemoveContainer() {
    $container = GetAllContainersFromDocker | Out-GridView -Title 'Select container to remove' -OutputMode Single
    if ($container) {
        Remove-NavContainer -containerName $container.FullName
    }
}
function Menu.UpdateWindowsUser() {
    [Container]$container = GetAllContainersFromDocker | Out-GridView -Title 'Select container to update Windows User' -OutputMode Single
    if ($container) {
        $container.UpdateWindowsUser
    }
}
function Menu.UpdateLicense() {
    $selection = GetAllContainersFromDocker | Out-GridView -Title "Select a container to update its license" -OutputMode Single
    if ($selection) {
        $newLicense = Get-OpenFile "Pick new license file to upload" "License files (*.flf)|*.flf" $PSScriptRoot
        if (Test-Path -path $newLicense) {
            $selection.UpdateLicense($newLicense)
        }
    }
}
function Config.UpdateModule([string]$moduleName) {
    if (Get-Module -ListAvailable -Name $moduleName) {
        Write-Host "Checking for Updates [$($moduleName)]..." -ForegroundColor Yellow
        Update-Module -Name $moduleName
    } 
    else {
        Write-Host "$($moduleName) could not be found." -ForegroundColor Red
        Write-Host "Installing $($moduleName)..." -ForegroundColor Yellow
        Install-Module -Name $moduleName
    }
}
function Config.UpdateAllModules() {
    Config.UpdateModule("navcontainerhelper")
    Config.UpdateModule("DockerHelpers")
}
function Config.InvokeConfigPath() {
    Invoke-Item $pscsFolder
}

# Create settings folder if it doesn't exist
if (!(test-path $pscsFolder)) {
    New-Item -ItemType Directory -Force -Path $pscsFolder
}

# Update all Modules
Config.UpdateAllModules

# Create server file if it doesn't exist or update existing entries
if (!(Test-Path $pscsTempPath)) {
    $server = [PSCustomObject]@{ 
        prefix      = "BC365"
        name        = "Business Central"
        image       = "mcr.microsoft.com/businesscentral/onprem"
        licenseFile = $null
        authType    = "Windows"
    }
    ConvertTo-Json @($server) | Out-File -FilePath $pscsTempPath
}

function AddTemplateToJson([Template] $temp) {
    $jsonData = Get-Content -Path $pscsTempPath -Raw | ConvertFrom-Json
    $jsonData += @{
        prefix      = $temp.prefix
        name        = $temp.name
        image       = $temp.image
        licenseFile = $temp.licenseFile
        authType    = $temp.authType
    }
    ConvertTo-Json @($jsonData) | Out-File -FilePath $pscsTempPath
}

function Menu.CreateTemplate() {
    $prefix = Read-Host "Prefix [e.g.: 'BC365']"
    $name = Read-Host "Name [e.g. 'Business Central']"
    $authType = "Windows"
    $licenseFile = $null
    if (!$licenseFile) {
        $licenseFile = Get-OpenFile "Pick license file for $($prefix)" "License files (*.flf)|*.flf" $PSScriptRoot
    }
    $image = View.SelectImage
    
    $template = New-Object Template
    $template.prefix = $prefix
    $template.name = $name
    $template.authType = $authType
    $template.licenseFile = $licenseFile
    $template.image = $image
    
    Write-Host "Save the following template? (defaults to yes)" -ForegroundColor Yellow
    Write-Host "Prefix = " -NoNewline
    Write-Host $prefix -ForegroundColor Yellow
    Write-Host "Name = " -NoNewline
    Write-Host $name -ForegroundColor Yellow
    Write-Host "Auth Type = " -NoNewline
    Write-Host $authType -ForegroundColor Yellow
    Write-Host "License File = " -NoNewline
    Write-Host $licenseFile -ForegroundColor Yellow
    Write-Host "Image = " -NoNewline
    Write-Host $image -ForegroundColor Yellow
    
    $ReadHost = Read-Host " ( y / n ) "
    Switch ($ReadHost) {
        Y { $Save = $true }
        N { $Save = $false }
        Default { $Save = $false }
    }
    if ($Save) {
        AddTemplateToJson($template)
    }
}

Clear-Host
Menu.Loop
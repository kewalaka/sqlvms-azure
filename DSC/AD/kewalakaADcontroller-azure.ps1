$resourceGroupName = 'kewalakasqlvms'
$automationAccountName = 'kewalakasqlvms'
$DSCconfigurationName = 'kewalakaADcontroller'

$DSCFolder = '.'
. $DSCFolder\kewalakaADcontroller.ps1

# get credentials from Azure Automation
$Params = @{"safemodeAdminCred"="safemodeAdminCred";
            "domainAdminCred"="domainAdminCred"}

$ConfigData = @{
    AllNodes = @(

        @{
            Nodename = "*"
            DomainName = "kewalaka.nz"
            DomainNetBIOSName = "test"
            RetryCount = 20
            RetryIntervalSec = 30
            PSDscAllowDomainUser = $true
            PSDscAllowPlainTextPassword = $true  # DSC resources are encrypted on Azure, so this is OK
            RebootIfNeeded = $true
        },

        @{
            Nodename = "addc0"
            Role = "First DC"
            SiteName = "SouthEastAsia"
            # Networking details are set using ARM template
        },

        @{
            Nodename = "addc1"
            Role = "Additional DC"
            SiteName = "AustraliaEast"            
            # Networking details are set using ARM template
        }
    )
}


function New-AutomationModule
{
    param (
    [string]$moduleName,
    [string]$moduleURI,
    [string]$resourceGroupName,
    [string]$automationAccountName
)

    $modules = get-azurermautomationmodule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName

    if ($modules.Name -notcontains $modulename)
    {

        New-AzureRmAutomationModule -ContentLink $moduleURI `
                            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $moduleName

    }

}

<#
# use this approach for organisational accounts
if ( $AzureCred -eq $null )
{
    $AzureCred = Get-Credential -Message "Please enter your Azure Credentials" -UserName "azure1@kewalaka.me.uk"
}

$azureAccount = Login-AzureRmAccount -Credential $AzureCred #-SubscriptionName 'Visual Studio Enterprise'
#>

# use this hack for live accounts
if ((Get-AzureRmSubscription) -eq $null)
{
    # Add-AzureRmAccount will pop up a window and ask you to authenticate. Save-AzureRmContext will write it out in json format
    Save-AzureRmContext -Profile (Add-AzureRmAccount) -Path $env:TEMP\creds.json
    Import-AzureRmContext -Path $env:TEMP\creds.json   
}

New-AutomationModule -moduleName 'xActiveDirectory' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/xactivedirectory.2.17.0.nupkg' `
                     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
New-AutomationModule -moduleName 'xPendingReboot' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/xpendingreboot.0.3.0.nupkg' `
                     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
New-AutomationModule -moduleName 'xDnsServer' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/xdnsserver.1.9.0.nupkg' `
                     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
New-AutomationModule -moduleName 'xDhcpServer' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/xdhcpserver.1.6.0.nupkg' `
                     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
New-AutomationModule -moduleName 'xNetworking' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/xnetworking.5.5.0.nupkg' `
                     -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
#New-AutomationModule -moduleName 'cActiveDirectorySites' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/cactivedirectorysites.0.0.1.nupkg'

function New-AutomationCredentials
{
param (
    [string]$name,
    [string]$username
)

    if ((Get-AzureRmAutomationCredential -ResourceGroupName $resourceGroupName `
                                         -AutomationAccountName $automationAccountName `
                                         -Name $name -ErrorAction SilentlyContinue) -eq $null)
    { 
        $password = read-host "Please enter password for $username" -AsSecureString
        $creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username,$password

        New-AzureRmAutomationCredential -ResourceGroupName $resourceGroupName `
                                        -AutomationAccountName $automationAccountName `
                                        -Name $name -Value $creds
    }
    else
    {
        Write-Output "Credentials already exist for $name with username $username"
    }

}

New-AutomationCredentials -name "safemodeAdminCred" -username "kewalaka"
New-AutomationCredentials -name "domainAdminCred" -username "kewalaka"

#if ((Get-AzureRmAutomationDscConfiguration -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $DSCconfigurationName) -eq $null)
#{
    Import-AzureRmAutomationDscConfiguration -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName `
                                            -Published -SourcePath "$PSScriptRoot\$DSCconfigurationName.ps1" -Force
#}

Start-AzureRmAutomationDscCompilationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                                         -ConfigurationName $DSCconfigurationName -ConfigurationData $ConfigData `
                                         -Parameters $Params
#>
#Get-AzureRmAutomationDscCompilationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ConfigurationName $DSCconfigurationName

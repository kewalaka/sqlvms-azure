$resourceGroupName = 'kewalakasqlvms'
$automationAccountName = 'kewalakasqlvms'
$DSCconfigurationName = 'SQLServer'

<# Doesnt' work unless you're using an organisational account see https://github.com/Azure/azure-powershell/issues/3108
if ( $AzureCred -eq $null )
{
    $username = "azure1@kewalaka.me.uk"
    $password = read-host "Please enter password for $username" -AsSecureString
    $AzureCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username,$password
}

$azureAccount = Login-AzureRmAccount -Credential $AzureCred -
#>

if ( $azureAccount -eq $null )
{
    $azureAccount = Login-AzureRmAccount 
}

function New-AutomationModule
{
    param (
    [string]$moduleName,
    [string]$moduleURI
)

    $modules = get-azurermautomationmodule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName

    if ($modules.Name -notcontains $modulename)
    {

        New-AzureRmAutomationModule -ContentLink $moduleURI `
                            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $moduleName

    }

}

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

# add modules
New-AutomationModule -moduleName 'sqlserverdsc' -moduleURI 'https://devopsgallerystorage.blob.core.windows.net/packages/sqlserverdsc.11.0.0.nupkg' 

New-AutomationCredentials -name "domainAdminCred" -username "kewalaka\stu"
New-AutomationCredentials -name "storageAccount" -username "stulab"
New-AutomationCredentials -name "SQL engine service account" -username "kewalaka\svc_sqlengine"
New-AutomationCredentials -name "SQL agent service account" -username "kewalaka\svc_sqlagent"
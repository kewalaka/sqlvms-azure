# A configuration to Create High Availability Domain Controller
Configuration kewalakaADcontroller
{

   param
    (
        [Parameter(Mandatory)]
        [pscredential]$safemodeAdminCred,

        [Parameter(Mandatory)]
        [pscredential]$domainAdminCred
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration,xActiveDirectory,xPendingReboot,xDnsServer,xDhcpServer,xNetworking #,cActiveDirectorySites

    Node $AllNodes.Nodename
    {
        LocalConfigurationManager 
        { 
             CertificateId = $Node.Thumbprint 
             RebootNodeIfNeeded = $Node.RebootIfNeeded
        } 

        WindowsFeature ADDSInstall
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }

        WindowsFeature ADDSToolsInstall {
            Ensure = 'Present'
            Name = 'RSAT-ADDS-Tools'
        }

        xPendingReboot AfterADDSToolsinstall
        {
            Name = 'AfterADDSinstall'
            DependsOn = "[WindowsFeature]ADDSToolsInstall"
        }
<#
        cADSite DC1Site { 
            Name = $Node.SiteName
            DependsOn = "[xPendingReboot]AfterADDSToolsinstall"
            Credential = $domainAdminCred 
        }  

        cADSite DefaultSite { 
            Name = 'Default-First-Site-Name' 
            Ensure = 'Absent' 
            DependsOn = "[xPendingReboot]AfterADDSToolsinstall"
            Credential = $domainAdminCred 
        }#>
    }

    Node $AllNodes.Where{$_.IPAddress}.Nodename
    {
        $AddressFamily = 'IPv4'
        $InterfaceAlias = (Get-NetAdapter | Where-Object {$_.Status -eq "up"}).Name

        xDhcpClient DisabledDhcpClient
        {
            State          = 'Disabled'
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = $AddressFamily
        }

        xIPAddress NewIPAddress
        {
            IPAddress      = $Node.IPAddress
            InterfaceAlias = $InterfaceAlias          
            AddressFamily  = $AddressFamily
        }    

        xDefaultGatewayAddress SetDefaultGateway
        {
            Address        = $Node.Gateway
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = $AddressFamily
        }                
    }

    Node $AllNodes.Where{$_.Role -eq "First DC"}.Nodename
    {  
        xADDomain FirstDS
        {
            DomainName = $Node.DomainName
            DomainNetBIOSName = $Node.DomainNetBIOSName
            DomainAdministratorCredential = $domainAdminCred
            SafemodeAdministratorPassword = $safemodeAdminCred
            DependsOn = "[xPendingReboot]AfterADDSToolsinstall"
        }

        xPendingReboot AfterADDSinstall
        {
            Name = 'AfterADDSinstall'
            DependsOn = "[xWaitForADDomain]FirstDS"
        }   
    }

    Node $AllNodes.Where{$_.Role -eq "Additional DC"}.Nodename
    {
        xWaitForADDomain DscForestWait
        {
            DomainName = $Node.DomainName
            DomainUserCredential = $domainAdminCred
            RetryCount = $Node.RetryCount
            RetryIntervalSec = $Node.RetryIntervalSec
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        xADDomainController SecondDC
        {
            DomainName = $Node.DomainName
            DomainAdministratorCredential = $domainAdminCred
            SafemodeAdministratorPassword = $safemodeAdminCred
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        xPendingReboot AfterADDSinstall
        {
            Name = 'AfterADDSinstall'
            DependsOn = "[xADDomainController]SecondDC"
        }
    }

    Node $AllNodes.Nodename
    {
        xDnsServerForwarder SetForwarders
        {
            IsSingleInstance = 'Yes'
            IPAddresses = '8.8.8.8','8.8.4.4'
            DependsOn = "[xPendingReboot]AfterADDSinstall"
        }
    }

    Node $AllNodes.Where{$_.DHCPScopes}.Nodename
    {

        WindowsFeature DHCP
        {
            Ensure = "Present"
            Name = "DHCP"
        }

        xDhcpServerAuthorization "LocalServerActivation"
        {
            Ensure = 'Present'
            DependsOn = @('[WindowsFeature]DHCP') 
        }

        ForEach ($DHCPScope in $Node.DHCPScopes) {

            xDhcpServerScope "$DHCPScope-Scope"
            {
                Ensure = 'Present'
                IPEndRange = $DHCPScope.IPEndRange
                IPStartRange = $DHCPScope.IPStartRange 
                Name = $DHCPScope.Name
                SubnetMask = $DHCPScope.SubnetMask
                State = 'Active'
                AddressFamily = 'IPv4'
                DependsOn = @('[WindowsFeature]DHCP') 
            }

            xDhcpServerOption "$DHCPScope-Option"
            {
                Ensure = 'Present'
                ScopeID = $DHCPScope.ScopeID
                DnsDomain = $Node.DomainName
                DnsServerIPAddress = $DHCPScope.DNSServer
                AddressFamily = 'IPv4'
                Router = $DHCPScope.Router
                DependsOn = @('[WindowsFeature]DHCP') 
            }

        }
    }
}
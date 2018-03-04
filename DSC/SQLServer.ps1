<#
    .EXAMPLE
    .NOTES
        SQL Server setup is run using the SYSTEM account. Even if SetupCredential is provided
        it is not used to install SQL Server at this time (see issue #139).
#>
Configuration SQLServer
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]     
        $storageCredentials,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlInstallCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAdministratorCredential = $SqlInstallCredential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlServiceCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAgentServiceCredential = $SqlServiceCredential
    )

    Import-DscResource -ModuleName SqlServerDsc

    node localhost
    {
    
        #region Install prerequisites for SQL Server

        # fetch Windows SXS files required by .Net 3.5 install
        # fetch these from the ISO of the Windows Server version (\source\sxs\)
        # place on an accessible storage location (blob storage used below)
        $dotNetSXSfolder = "C:\Installs\dotNetsxs"
        
        # TODO  parameterise this
        $storageAccount  = "kewalakasqlvms"

        File dotNetSXSFolder
        {
            Type            = "directory"
            DestinationPath = $dotNetSXSfolder
            Ensure          = "Present"
        }

        File DotNet351SXS
        {
            Credential      = $storageCredentials
            SourcePath      = "\\$storageAccount\.file.core.windows.net\Microsoft\dotNet\3.5\SXS\2016\microsoft-windows-netfx3-ondemand-package.cab"
            DestinationPath = "$dotNetSXSfolder"
            Type            = "File"
            DependsOn       = "[File]dotNetSXSFolder"
        }

        # .Net frameworks required
        WindowsFeature 'NetFramework35'
        {
            Ensure    = "Present"
            Name      = "NET-Framework-Core"
            Source    = $dotNetSXSfolder
            DependsOn = "[File]DotNet351SXS"
        }

        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
        #endregion Install prerequisites for SQL Server

        #region Install SQL Server
        SqlSetup 'InstallDefaultInstance'
        {
            InstanceName         = 'MSSQLSERVER'
            Features             = 'SQLENGINE'
            SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSvcAccount        = $SqlServiceCredential
            AgtSvcAccount        = $SqlAgentServiceCredential
            SQLSysAdminAccounts  = 'COMPANY\SQL Administrators', $SqlAdministratorCredential.UserName
            InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir    = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
            SQLUserDBDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
            SQLUserDBLogDir      = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
            SQLTempDBDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
            SQLTempDBLogDir      = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
            SQLBackupDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup'
            SourcePath           = 'C:\InstallMedia\SQL2016RTM'
            UpdateEnabled        = 'True'
            UpdateSource         = 'C:\InstallMedia\SQL2016Updates'            
            ForceReboot          = $false
            PsDscRunAsCredential = $SqlInstallCredential

            DependsOn            = '[WindowsFeature]NetFramework35', '[WindowsFeature]NetFramework45'
        }
        #endregion Install SQL Server
    }
}
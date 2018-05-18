function Test-DbaDatabaseOwner {
    <#
        .SYNOPSIS
            Checks database owners against a login to validate which databases do not match that owner.

        .DESCRIPTION
            This function will check all databases on an instance against a SQL login to validate if that
            login owns those databases or not. By default, the function will check against 'sa' for
            ownership, but the user can pass a specific login if they use something else.

            Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

        .NOTES
            Tags:
            Author: Michael Fal (@Mike_Fal), http://mikefal.net
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .PARAMETER SqlInstance
            Specifies the SQL Server instance(s) to scan.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER TargetLogin
            Specifies the login that you wish check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed. This must be a valid security principal which exists on the target server.

        .PARAMETER Detailed
            Will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


        .LINK
            https://dbatools.io/Test-DbaDatabaseOwner

        .EXAMPLE
            Test-DbaDatabaseOwner -SqlInstance localhost

            Returns all databases where the owner does not match 'sa'.

        .EXAMPLE
            Test-DbaDatabaseOwner -SqlInstance localhost -TargetLogin 'DOMAIN\account'

            Returns all databases where the owner does not match 'DOMAIN\account'.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$TargetLogin ,
        [Switch]$Detailed,
        [Alias('Silent')]
        [Switch]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Parameter "Detailed"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # dynamic sa name for orgs who have changed their sa name
            if (Test-Bound -ParameterName TargetLogin -Not) {
                $TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Validate login
            if (($server.Logins.Name) -notmatch [Regex]::Escape($TargetLogin)) {
                Write-Message -Level Verbose -Message "$TargetLogin is not a login on $instance" -Target $instance
            }
        }
        #use online/available dbs
        $dbs = $server.Databases | Where-Object IsAccessible

        #filter database collection based on parameters
        if ($Database) {
            $dbs = $dbs | Where-Object { $Database -contains $_.Name }
        }

        if ($ExcludeDatabase) {
            $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
        }

        #for each database, create custom object for return set.
        foreach ($db in $dbs) {

            if ($db.IsAccessible -eq $false) {
                Stop-Function -Message "The database $db is not accessible. Skipping database." -Continue -Target $db
            }

            Write-Message -Level Verbose -Message "Checking $db"
            [pscustomobject]@{
                ComputerName = $server.NetName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Server       = $server.DomainInstanceName
                Database     = $db.Name
                DBState      = $db.Status
                CurrentOwner = $db.Owner
                TargetOwner  = $TargetLogin
                OwnerMatch   = ($db.owner -eq $TargetLogin)
            } | Select-DefaultView -ExcludeProperty Server
        }
    }
}
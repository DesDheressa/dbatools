function Rename-DbaLogin {
    <#
.SYNOPSIS
Rename-DbaLogin will rename login and database mapping for a specified login.

.DESCRIPTION
There are times where you might want to rename a login that was copied down, or if the name is not descriptive for what it does.

It can be a pain to update all of the mappings for a specific user, this does it for you.

.PARAMETER SqlInstance
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Login
The current Login on the server - this list is auto-populated from the server.

.PARAMETER NewLogin
The new Login that you wish to use. If it is a windows user login, then the SID must match.

.PARAMETER Confirm
Prompts to confirm actions

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER EnableException
By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


.NOTES
Tags: Login
Author: Mitchell Hamann (@SirCaptainMitch)

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
https://dbatools.io/Rename-DbaLogin

.EXAMPLE
Rename-DbaLogin -SqlInstance localhost -Login DbaToolsUser -NewLogin captain

SQL Login Example

.EXAMPLE
Rename-DbaLogin -SqlInstance localhost -Login domain\oldname -NewLogin domain\newname

Change the windowsuser login name.

.EXAMPLE
Rename-DbaLogin -SqlInstance localhost -Login dbatoolsuser -NewLogin captain -WhatIf

WhatIf Example
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [string]$Login,
        [parameter(Mandatory = $true)]
        [string]$NewLogin,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $Databases = $server.Databases | Where-Object IsAccessible
            $currentLogin = $server.Logins[$Login]

            if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing Login name from  [$Login] to [$NewLogin]")) {
                try {
                    $dbenums = $currentLogin.EnumDatabaseMappings()
                    $currentLogin.rename($NewLogin)
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $null
                        OldLogin     = $Login
                        NewLogin     = $NewLogin
                        Status       = "Successful"
                    }
                }
                catch {
                    $dbenums = $null
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $null
                        OldLogin     = $Login
                        NewLogin     = $NewLogin
                        Status       = "Failure"
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $login
                }
            }

            foreach ($db in $dbenums) {
                $db = $databases[$db.DBName]
                $user = $db.Users[$Login]
                Write-Message -Level Verbose -Message "Starting update for $db"

                if ($Pscmdlet.ShouldProcess($SqlInstance, "Changing database $db user $user from [$Login] to [$NewLogin]")) {
                    try {
                        $oldname = $user.name
                        $user.Rename($NewLogin)
                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            OldUser      = $oldname
                            NewUser      = $NewLogin
                            Status       = "Successful"
                        }

                    }
                    catch {
                        Write-Message -Level Warning -Message "Rolling back update to login: $Login"
                        $currentLogin.rename($Login)

                        [pscustomobject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            OldUser      = $NewLogin
                            NewUser      = $oldname
                            Status       = "Failure to rename. Rolled back change."
                        }
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $NewLogin
                    }
                }
            }
        }
    }
}
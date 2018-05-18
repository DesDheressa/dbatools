#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Set-DbaMaxMemory {
    <#
        .SYNOPSIS
            Sets SQL Server 'Max Server Memory' configuration setting to a new value then displays information this setting.

        .DESCRIPTION
            Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings.

            Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to
            determine the default optimum RAM to use, then sets the SQL max value to that number.

            Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may
            be going on in your specific environment.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER MaxMB
            Specifies the max megabytes

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            Shows what would happen if the cmdlet runs. The cmdlet is not run.

        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.

        .NOTES
            Tags: MaxMemory, Memory
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaMaxMemory

        .EXAMPLE
            Set-DbaMaxMemory sqlserver1

            Set max memory to the recommended MB on just one server named "sqlserver1"

        .EXAMPLE
            Set-DbaMaxMemory -SqlInstance sqlserver1 -MaxMB 2048

            Explicitly max memory to 2048 MB on just one server, "sqlserver1"

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver | Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory

            Find all servers in SQL Server Central Management server that have Max SQL memory set to higher than the total memory
            of the server (think 2147483647), then pipe those to Set-DbaMaxMemory and use the default recommendation.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer", "SqlServers", "ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Position = 1)]
        [int]$MaxMB,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -Not -Parameter SqlInstance) -and (Test-Bound -Not -Parameter Collection)) {
            Stop-Function -Category InvalidArgument -Message "You must specify a server list source using -SqlInstance or you can pipe results from Test-DbaMaxMemory"
            return
        }

        if ($MaxMB -eq 0) {
            $UseRecommended = $true
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!(Test-SqlSa -SqlInstance $server)) {
                Stop-Function -Message "Not a sysadmin on $server. Skipping." -Category PermissionDenied -ErrorRecord $_ -Target $server -Continue
            }

            try {
                $currentServer = Test-DbaMaxMemory -SqlInstance $server
                Add-Member -Force -InputObject $currentServer -NotePropertyName OldMaxValue -NotePropertyValue 0
                $currentServer.OldMaxValue = $currentServer.SqlMaxMB
            }
            catch {
                Stop-Function -Message "Issue collecting memory information on $server" -Target $server -ErrorRecord $_ -InnerException $_.Exception -Continue
            }

            try {
                if ($UseRecommended) {
                    Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($currentServer.SqlMaxMB) to $($currentServer.RecommendedMB) MB"

                    if ($currentServer.RecommendedMB -eq 0 -or $null -eq $currentServer.RecommendedMB) {
                        $maxMem = (Test-DbaMaxMemory -SqlInstance $server).RecommendedMB
                        Write-Message -Level VeryVerbose -Message "Max memory recommended: $maxMem"
                        $server.Configuration.MaxServerMemory.ConfigValue = $maxMem
                    }
                    else {
                        $server.Configuration.MaxServerMemory.ConfigValue = $currentServer.RecommendedMB
                    }
                }
                else {
                    Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($currentServer.SqlMaxMB) to $MaxMB MB"
                    $server.Configuration.MaxServerMemory.ConfigValue = $MaxMB
                }
                if ($PSCmdlet.ShouldProcess($server, "Change Max Memory from $($currentServer.OldMaxValue) to $($server.Configuration.MaxServerMemory.ConfigValue)")) {
                    try {
                        $server.Configuration.Alter()
                        $currentServer.SqlMaxMB = $server.Configuration.MaxServerMemory.ConfigValue
                    }
                    catch {
                        Stop-Function -Message "Failed to apply configuration change for $server" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }
            catch {
                Stop-Function -Message "Could not modify Max Server Memory for $server" -ErrorRecord $_ -Target $server -Continue
            }

            Add-Member -InputObject $currentServer -Force -MemberType NoteProperty -Name CurrentMaxValue -Value $currentServer.SqlMaxMB
            Select-DefaultView -InputObject $currentServer -Property ComputerName, InstanceName, SqlInstance, TotalMB, OldMaxValue, CurrentMaxValue
        }
    }
}
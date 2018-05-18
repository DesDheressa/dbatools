function Stop-DbaRunspace {
    <#
    .SYNOPSIS
        Stops a managed runspace

    .DESCRIPTION
        Stops a runspace that was registered to dbatools.
        Will not cause errors if the runspace is already halted.

        Runspaces may not automatically terminate immediately when calling this function.
        Depending on the implementation of the scriptblock, this may in fact take a little time.
        If the scriptblock hasn't finished and terminated the runspace in a seemingly time, it will be killed by the system.
        This timeout is by default 30 seconds, but can be altered by using the Configuration System.
        For example, this line will increase the timeout to 60 seconds:
        Set-DbaConfig Runspace.StopTimeout 60

    .PARAMETER Name
        The name of the registered runspace to stop

    .PARAMETER Runspace
        The runspace to stop. Returned by Get-DbaRunspace

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Stop-DbaRunspace -Name 'mymodule.maintenance'

        Stops the runspace registered under the name 'mymodule.maintenance'
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $Name,

        [Parameter(ValueFromPipeline = $true)]
        [Sqlcollaborative.Dbatools.Runspace.RunspaceContainer[]]
        $Runspace,

        [switch]
        [Alias('Silent')]$EnableException
    )

    process {
        foreach ($item in $Name) {
            # Ignore all output from Get-PSFRunspace - it'll be handled by the second loop
            if ($item -eq "Sqlcollaborative.Dbatools.Runspace.runspacecontainer") { continue }

            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces.ContainsKey($item.ToLower())) {
                try {
                    Write-Message -Level Verbose -Message "Stopping runspace: $($item.ToLower())" -Target $item.ToLower()
                    [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$item.ToLower()].Stop()
                }
                catch {
                    Stop-Function -Message "Failed to stop runspace: $($item.ToLower())" -EnableException $EnableException -Target $item.ToLower() -Continue
                }
            }
            else {
                Stop-Function -Message "Failed to stop runspace: $($item.ToLower()) | No runspace registered under this name!" -EnableException $EnableException -Category InvalidArgument -Target $item.ToLower() -Continue
            }
        }

        foreach ($item in $Runspace) {
            try {
                Write-Message -Level Verbose -Message "Stopping runspace: $($item.Name.ToLower())" -Target $item
                $item.Stop()
            }
            catch {
                Stop-Function -Message "Failed to stop runspace: $($item.Name.ToLower())" -EnableException $EnableException -Target $item -Continue
            }
        }
    }
}

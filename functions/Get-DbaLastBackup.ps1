#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaLastBackup {
    <#
        .SYNOPSIS
            Get date/time for last known backups of databases.

        .DESCRIPTION
            Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.

            Default output includes columns Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more database(s) to exclude from processing.

        .PARAMETER EnableException
            If this switch is enabled exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

        .NOTES
            Tags: DisasterRecovery, Backup
            Author: Klaas Vandenberghe ( @PowerDBAKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaLastBackup

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987

            Returns a custom object displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987

            Returns a custom object with Server name, Database name, and the date the last time backups were performed.

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select *

            Returns a custom object with Server name, Database name, and the date the last time backups were performed, and also recoverymodel and calculations on how long ago backups were taken and what the status is.

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select * | Out-Gridview

            Returns a gridview displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        function Get-DbaDateOrNull ($TimeSpan) {
            if ($TimeSpan -eq 0) {
                return $null
            }
            return $TimeSpan
        }
        $StartOfTime = [DbaTimeSpan](New-TimeSpan -Start ([datetime]0))
    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Message -Level Warning -Message "Can't connect to $instance"
                Continue
            }

            $dbs = $server.Databases | Where-Object { $_.name -ne 'tempdb' }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }
            # Get-DbaBackupHistory -Last would make the job in one query but SMO's (and this) report the last backup of this type irregardless of the chain
            $FullHistory = Get-DbaBackupHistory -SqlInstance $server -Database $dbs.Name -LastFull -IncludeCopyOnly -Raw
            $DiffHistory = Get-DbaBackupHistory -SqlInstance $server -Database $dbs.Name -LastDiff -IncludeCopyOnly -Raw
            $IncrHistory = Get-DbaBackupHistory -SqlInstance $server -Database $dbs.Name -LastLog -IncludeCopyOnly -Raw
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
                    Continue
                }
                $LastFullBackup = ($FullHistory | Where-Object Database -eq $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastFullBackup) {
                    $SinceFull_ = [DbaTimeSpan](New-TimeSpan -Start $LastFullBackup)
                }
                else {
                    $SinceFull_ = $StartOfTime
                }

                $LastDiffBackup = ($DiffHistory | Where-Object Database -eq $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastDiffBackup) {
                    $SinceDiff_ = [DbaTimeSpan](New-TimeSpan -Start $LastDiffBackup)
                }
                else {
                    $SinceDiff_ = $StartOfTime
                }

                $LastIncrBackup = ($IncrHistory | Where-Object Database -eq $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastIncrBackup) {
                    $SinceLog_ = [DbaTimeSpan](New-TimeSpan -Start $LastIncrBackup)
                }
                else {
                    $SinceLog_ = $StartOfTime
                }

                $daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

                if ($daysSinceDbCreated -lt 1 -and $SinceFull_ -eq 0) {
                    $Status = 'New database, not backed up yet'
                }
                elseif ($SinceFull_.Days -gt 0 -and $SinceDiff_.Days -gt 0) {
                    $Status = 'No Full or Diff Back Up in the last day'
                }
                elseif ($db.RecoveryModel -eq "Full" -and $SinceLog_.Hours -gt 0) {
                    $Status = 'No Log Back Up in the last hour'
                }
                else {
                    $Status = 'OK'
                }

                $result = [PSCustomObject]@{
                    ComputerName       = $server.NetName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.DomainInstanceName
                    Database           = $db.Name
                    RecoveryModel      = $db.RecoveryModel
                    LastFullBackup     = [DbaDateTime]$LastFullBackup
                    LastDiffBackup     = [DbaDateTime]$LastDiffBackup
                    LastLogBackup      = [DbaDateTime]$LastIncrBackup
                    SinceFull          = Get-DbaDateOrNull -TimeSpan $SinceFull_
                    SinceDiff          = Get-DbaDateOrNull -TimeSpan $SinceDiff_
                    SinceLog           = Get-DbaDateOrNull -TimeSpan $SinceLog_
                    DatabaseCreated    = $db.createDate
                    DaysSinceDbCreated = $daysSinceDbCreated
                    Status             = $status
                }
                Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Database, LastFullBackup, LastDiffBackup, LastLogBackup
            }
        }
    }
}
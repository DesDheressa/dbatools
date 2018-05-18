function Install-DbaFirstResponderKit {
    <#
        .SYNOPSIS
            Installs or updates the First Responder Kit stored procedures.

        .DESCRIPTION
            Downloads, extracts and installs the First Responder Kit stored procedures:
            sp_Blitz, sp_BlitzWho, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzCache and sp_BlitzTrace.

            First Responder Kit links:
            http://FirstResponderKit.org
            https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database to instal the First Responder Kit stored procedures into

        .PARAMETER Branch
            Specifies an alternate branch of the First Responder Kit to install. (master or dev)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Tara Kizer, Brent Ozar Unlimited (https://www.brentozar.com/)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Install-DbaFirstResponderKit

        .EXAMPLE
            Install-DbaFirstResponderKit -SqlInstance server1 -Database master

            Logs into server1 with Windows authentication and then installs the FRK in the master database.

        .EXAMPLE
            Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database DBA

            Logs into server1\instance1 with Windows authentication and then installs the FRK in the DBA database.

        .EXAMPLE
            Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database master -SqlCredential $cred

            Logs into server1\instance1 with SQL authentication and then installs the FRK in the master database.

        .EXAMPLE
            Install-DbaFirstResponderKit -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

        .EXAMPLE
            $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
            $servers | Install-DbaFirstResponderKit

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

        .EXAMPLE
            Install-DbaFirstResponderKit -SqlInstance sql2016 -Branch dev

            Installs the dev branch version of the FRK in the master database on sql2016 instance.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('master', 'dev')]
        [string]$Branch = "master",
        [object]$Database = "master",
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $url = "https://codeload.github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/zip/$Branch"

        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $zipfile = "$temp\SQL-Server-First-Responder-Kit-$Branch.zip"
        $zipfolder = "$temp\SQL-Server-First-Responder-Kit-$Branch\"

        if ($zipfile | Test-Path) {
            Remove-Item -Path $zipfile -ErrorAction SilentlyContinue
        }

        if ($zipfolder | Test-Path) {
            Remove-Item -Path $zipfolder -Recurse -ErrorAction SilentlyContinue
        }

        $null = New-Item -ItemType Directory -Path $zipfolder -ErrorAction SilentlyContinue

        Write-Message -Level Verbose -Message "Downloading and unzipping the First Responder Kit zip file."

        try {
            $oldSslSettings = [System.Net.ServicePointManager]::SecurityProtocol
            [System.Net.ServicePointManager]::SecurityProtocol = "Tls12"
            try {
                Invoke-WebRequest $url -OutFile $zipfile
            }
            catch {
                # Try with default proxy and usersettings
                (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                Invoke-WebRequest $url -OutFile $zipfile
            }
            [System.Net.ServicePointManager]::SecurityProtocol = $oldSslSettings

            # Unblock if there's a block
            Unblock-File $zipfile -ErrorAction SilentlyContinue

            # Unzip the files
            $shell = New-Object -ComObject Shell.Application
            $zip = $shell.NameSpace($zipfile)

            foreach ($item in $zip.items()) {
                $shell.Namespace($temp).CopyHere($item)
            }

            Remove-Item -Path $zipfile
        }
        catch {
            Stop-Function -Message "Couldn't download the First Responder Kit. Download and install manually from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/$Branch.zip." -ErrorRecord $_
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Output -Message "Starting installing/updating the First Responder Kit stored procedures in $database on $instance."
            $allprocedures_query = "select name from sys.procedures where is_ms_shipped = 0"
            $allprocedures = ($server.Query($allprocedures_query, $Database)).Name
            # Install/Update each FRK stored procedure
            foreach ($script in (Get-ChildItem $zipfolder -Filter sp_Blitz*.sql)) {
                $scriptname = $script.Name
                if ($scriptname -ne "sp_BlitzRS.sql") {
                    $sql = [IO.File]::ReadAllText($script.FullName)

                    if ($scriptname -eq "sp_BlitzQueryStore.sql") {
                        if ($server.VersionMajor -lt 13) { continue }
                    }

                    foreach ($query in ($sql -Split "\nGO\b")) {
                        $query = $query.Trim()
                        if ($query) {
                            try {
                                $null = $server.Query($query, $Database)
                            }
                            catch {
                                Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptname in $Database on $instance." -ErrorRecord $_
                            }
                        }
                    }
                }
                $baseres = @{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $Database
                    Name         = $scriptname.TrimEnd('.sql')
                }
                if ($scriptname.TrimEnd('.sql') -in $allprocedures) {
                    $baseres['Status'] = 'Updated'
                }
                else {
                    $baseres['Status'] = 'Installed'
                }
                [PSCustomObject]$baseres
            }
            Write-Message -Level Output -Message "Finished installing/updating the First Responder Kit stored procedures in $database on $instance."
        }
    }
}

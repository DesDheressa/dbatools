﻿$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $commonParamCount = ([System.Management.Automation.PSCmdlet]::CommonParameters).Count
        [object[]]$params = (Get-ChildItem function:\Get-DbaOrphanUser).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $commonParamCount | Should Be $paramCount
        }
    }
}


Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $loginsq = @'
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
'@
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
        $null = Invoke-DbaSqlQuery -SqlInstance $server -Query $loginsq
        $usersq = @'
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
'@
        Invoke-DbaSqlQuery -SqlInstance $server -Query $usersq -Database dbatoolsci_orphan
        $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
        Invoke-DbaSqlQuery -SqlInstance $server -Query $dropOrphan
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
    }
    It "shows time taken for preparation" {
        1 | Should -Be 1
    }
    $results = Get-DbaOrphanUser -SqlInstance $script:instance1 -Database dbatoolsci_orphan
    It "Finds two orphans" {
        $results.Count | Should -Be 2
        foreach ($user in $Users) {
            $user.User | Should -BeIn @('dbatoolsci_orphan1', 'dbatoolsci_orphan2')
            $user.DatabaseName | Should -Be 'dbatoolsci_orphan'
        }
    }
    It "has the correct properties" {
        $result = $results[0]
        $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,DatabaseName,User'.Split(',')
        ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
    }
}


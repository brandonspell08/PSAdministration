﻿<#
.Synopsis
   Query Local or Remote Computers for sChannel Settings
.DESCRIPTION
   Script to query local or remote computers for a clean list of SCHANNEL settings
.EXAMPLE
   get-content c:\computers.txt | .\Get-SChannelConfig.ps1

   This example will return the PROTOCOL settings for all computer objects in a text file called 'Computers.txt'
.EXAMPLE
   get-content c:\computers.txt | .\Get-SChannelConfig.ps1 -keys Protocols,Ciphers,Hashes,KeyExchangeAlgorithms

   This example will return all SCHANNEL settings for computers in the text file 'Computers.txt'.

.EXAMPLE
    .\Get-SChannelConfig.ps1 -ComputerName Server1 -Keys ciphers

    This example will get cipher settings for 'Server1'

.EXAMPLE
    .\Get-SChannelConfig.ps1 -Keys Protocols -ServerOnly

    This example will get only server-side settings for only the local computer
#>
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        # hostname of computers to query
        [Parameter(ValueFromPipeline,
                    ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Alias('Computer')]
        $ComputerName = $env:COMPUTERNAME,

        # Keys to be queried. The most commonly queried is 'Protocols', so it is set as default.
        [ValidateSet('Protocols','Ciphers','Hashes','KeyExchangeAlgorithms')]
        [string[]]$Keys = 'Protocols',

        # Slims the query to Server side settings only.
        [switch]$ServerOnly
    )

    Begin
    {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent()
		$admincheck = (New-Object Security.Principal.WindowsPrincipal $me).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

		if(!$admincheck)
		{
            Write-Warning ( "{0}: Please Close Powershell and run as Administrator." -f $me.Name	)
            exit
		}

        $results = New-Object System.Collections.ArrayList
        $ErrorActionPreference = 'stop'
        Function QueryReg($Comp, $key, $Reg)
        {
            Try {
                ForEach ($sub in $reg.OpenSubKey($key).GetSubKeyNames())
                {
                    $subkey = $registry.OpenSubKey("$($key)\$($sub)")
                    ForEach ($value in $subkey.GetValueNames())
                    {
                        $results = "" | select Computer,Key,ValueName,Value
                        $results.computer = $Comp
                        $subkeyname = $subkey.Name.Split('\')[-2] + '-' + $subkey.Name.Split('\')[-1]
                        $results.Key = $subkeyname
                        $results.ValueName = $value
                        [bool]$results.value = $subkey.GetValue($value)
                        $results
                    }
                    QueryReg -key "$key\$sub" -Reg $reg -Comp $Comp
                }
            } Catch [System.Security.SecurityException] {
                "Registry - access denied $($key)"
            } Catch {
                write-warning $_.Exception.Message
            }
        }#QueryReg

        $strprotocols = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
        $strkex = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms'
        $strhash = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes'
        $strciphers = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers'
        Write-Warning ( "Any Key Results that do not appear mean that the setting is not configured.`nThis does not mean that it is not enabled, just that it is using the OS Defaults.`nFor mor information on Default Cipher Configuration, please visit:`nhttps://docs.microsoft.com/en-us/windows/desktop/SecAuthN/cipher-suites-in-schannel`n`n" )

    }
    Process
    {
        foreach($Computer in $ComputerName)
        {
            try
            {
                $remoteregistrystatus = (Get-Service -Name RemoteRegistry -ComputerName "$computer").status
                if($remoteregistrystatus -ne 'started')
                {
                    Set-Service -Name RemoteRegistry -ComputerName $computer -StartupType Manual -Status "Running"
                }
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
                $temp = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows',$True)

                If (-NOT ($temp.GetSubKeyNames() -contains 'WindowsUpdate')) 
                {
                    #Build the required registry keys
                    $temp.CreateSubKey('WindowsUpdate\AU') | Out-Null
                }
            }
            catch
            {
                Write-Warning ( "{0}: Unable to communicate to establish Remote Registy Connection." -f $Computer)
                Write-Warning "Error:"
                Write-Warning $_.exception.message
                break
            }

            try
            {
                $registry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)

            }
            Catch [System.Security.SecurityException] {
                Write-Warning ( "{0}: Permission denied to Remote Registry" -f $computer)
                break
            }
            Catch
            [exception]{
                Write-Warning $_.exception.message
                break
            }

            switch($Keys)
            {
                'Protocols'
                {
                    $tmpresults = QueryReg -Comp $Computer -key $strprotocols -Reg $registry
                    if($null -eq $tmpresults)
                    {
                        $message = ( "{0}: No results found for PROTOCOLS. Machine is using default values." -f $Computer)
                        $results.add($message)|Out-Null
                    } else {
                        $tmpresults | ForEach-Object {$results.add([pscustomobject]$_) |Out-Null}
                    }
                }
                'KeyExchangeAlgorithms'
                {
                    $tmpresults += QueryReg -Comp $Computer -key $strkex -Reg $registry
                    if($null -eq $tmpresults)
                    {
                        Write-Warning ( "{0}: No results found for KEY EXCHANGE ALGORITHMS. Machine is using default values." -f $Computer)
                        $results.add($message)|Out-Null
                    } else {
                        $tmpresults | ForEach-Object {$results.add($_) |Out-Null}
                    }
                }
                'Hashes'
                {
                    $tmpresults += QueryReg -Comp $Computer -key $strhash -Reg $registry
                    if($null -eq $tmpresults)
                    {
                        Write-Warning ( "{0}: No results found for HASHES. Machine is using default values." -f $Computer)
                        $results.add($message)|Out-Null
                    } else {
                        $tmpresults | ForEach-Object {$results.add($_) |Out-Null}
                    }
                }
                'Ciphers'
                {
                    $tmpresults += QueryReg -Comp $Computer -key $strciphers -Reg $registry
                    if($null -eq $tmpresults)
                    {
                        Write-Warning ( "{0}: No results found for CIPHERS. Machine is using default values." -f $Computer)
                        $results.add($message)|Out-Null
                    } else {
                        $tmpresults | ForEach-Object {$results.add($_) |Out-Null}
                    }
                }
            }
            if($ServerOnly){$results = $results | Where-Object{$_.key -notmatch "Client"}}

        }# foreach Computer

    }
    End
    {
        $results | ForEach-Object{
            if($_.gettype() -eq [string])
            {
                Write-Host -ForegroundColor Red $_
            }

        } -ErrorAction SilentlyContinue
        return $($results | where{$_.psobject.typenames -contains 'System.Management.Automation.PSCustomObject'} -ErrorAction SilentlyContinue)
    }



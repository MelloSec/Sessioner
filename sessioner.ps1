[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ServerName,
    [Parameter(Mandatory = $false)]
    [string]$IPAddress,
    [Parameter(Mandatory = $false)]
    [string]$Username
)

# Check for existence of parameters specified on the command line, if not prompt user for what we need
if (-not $ServerName) {
    $ServerName = Read-Host "Enter Target IP/Hostname"
}

if (-not $IPAddress) {
    $IPAddress = Read-Host "Enter your IP/Hostname"
}

if (-not $Username) {
    $Username = Read-Host "Enter Administrators username in the 'username' or 'Domain\username' format"
}

# Take in password as secure string to create PSCredential object for use throughout. Re-use this Credential.
$Password = Read-Host "Enter password" -AsSecureString
$Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)

# Establish CIM sessions over DCOM to enable WinRm and quickconfig
function Invoke-CimCalls {
    $SessionArgs = @{
        ComputerName  = $ServerName
        Credential    = $Credential
        SessionOption = New-CimSessionOption -Protocol Dcom
    }

    $MethodArgs1 = @{
        ClassName     = 'Win32_Process'
        MethodName    = 'Create'
        CimSession    = New-CimSession @SessionArgs
        Arguments     = @{
            CommandLine = "powershell Set-Item wsman:\localhost\Client\TrustedHosts -Value $IPAddress -Force"
        }
    }

    # prob should copy the OG trusted Hosts to somewhere safe, but if WInRM disabled does it really matter?

    $MethodArgs2 = @{
        ClassName     = 'Win32_Process'
        MethodName    = 'Create'
        CimSession    = New-CimSession @SessionArgs
        Arguments     = @{
            CommandLine = "powershell Enable-PSRemoting -Force"
        }
    }

    $MethodArgs3 = @{
        ClassName     = 'Win32_Process'
        MethodName    = 'Create'
        CimSession    = New-CimSession @SessionArgs
        Arguments     = @{
            CommandLine = "winrm quickconfig -quiet"
        }
    }

    Invoke-CimMethod @MethodArgs1
    Invoke-CimMethod @MethodArgs2
    Invoke-CimMethod @MethodArgs3
}

# Start the srvice on our side if it's not running
function Start-WinRMService {
    $WinRMStatus = Get-Service WinRM
    
    if ($WinRMStatus.Status -ne "Running") {
        Start-Service WinRM
        Write-Host "WinRM service started."
    } else {
        Write-Host "WinRM service is running."
    }
}

# Keep track of the current executionpolicy on our target host so we can reset it when we're done
function Set-HostRemoting {
    Write-Output "Storing current execution policy on target and changing to unrestricted for our session.."
    $originalExecutionPolicy = Invoke-Command -ComputerName $ServerName -Credential $Credential -ScriptBlock {
        Get-ExecutionPolicy -Scope LocalMachine
    }
    Invoke-Command -ComputerName $ServerName -Credential $Credential -ScriptBlock {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
    }
}



# Actions performed on our system
Write-Output "Checking WinRM service locally.."
Start-WinRMService
Write-Output "Adding $ServerName to Trusted Hosts.."
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $ServerName -Force

# Actions performed on target
Write-Output "Preparing target for remoting"
Invoke-CimCalls
Set-HostRemoting
Write-Output "Entering interactive Session.."
$session = New-PSSession -ComputerName $ServerName -Credential $Credential
Enter-PSSession $session


# Functions for cleaning up a bit. There are more steps to fully disable, including stopping the service and re-firewalling WinRM ports
function Reset-PSRemoting {
    Write-Output "Disabling PSRemoting on remote server."
    $ScriptBlock = {
           Disable-PSRemoting -Force
           # Remove WinRM firewall rules
           Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" | Remove-NetFirewallRule
           Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" | Remove-NetFirewallRule
           # Stop  and Disable WinRM service
           Stop-Service -Name "WinRM"
           Set-Service -Name WinRM -StartupType Disabled
           Set-ExecutionPolicy $originalExecutionPolicy -Scope LocalMachine -Force
    }
    Invoke-Command -ComputerName $ServerName -Credential $Credential -ScriptBlock $ScriptBlock
}

function Reset-ExecutionPolicy {
    Write-Output "Resetting ExecutionPolicy to its original state."
    Invoke-Command -ComputerName $ServerName -Credential $Credential -ScriptBlock {
        Set-ExecutionPolicy $originalExecutionPolicy -Scope LocalMachine -Force
    }
}


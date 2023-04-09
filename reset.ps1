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
#//////////////////////////////////////////////////////////////////////////////////////////////////
#
#   watch-ups.ps1 - Ricardo Londono
#
#   This POSH script will monitor an APC brand UPS and alert as well as power off server(s).
#
#       Last Modified: 11/27/2020
#
#//////////////////////////////////////////////////////////////////////////////////////////////////
#
# Old method to get creds
# ESXi Creds ***
# Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File 'C:\Scripts\ESXi-Secret.txt'
#$ESXiSecret = get-content 'C:\Scripts\ESXi-Secret.txt' | ConvertTo-SecureString

#
# SendGrid Function
#
function Send-EmailWithSendGrid {
    Param
   (
       [Parameter(Mandatory=$true)]
       [string] $From,

       [Parameter(Mandatory=$true)]
       [String] $To,

       [Parameter(Mandatory=$true)]
       [string] $ApiKey,

       [Parameter(Mandatory=$true)]
       [string] $Subject,

       [Parameter(Mandatory=$true)]
       [string] $Body
   )

   $headers = @{}
   $headers.Add("Authorization","Bearer $apiKey")
   $headers.Add("Content-Type", "application/json")

   $jsonRequest = [ordered]@{
                           personalizations= @(@{to = @(@{email =  "$To"})
                               subject = "$SubJect" })
                               from = @{email = "$From"}
                               content = @( @{ type = "text/plain"
                                           value = "$Body" }
                               )} | ConvertTo-Json -Depth 10
   Invoke-RestMethod   -Uri "https://api.sendgrid.com/v3/mail/send" -Method Post -Headers $headers -Body $jsonRequest
}

# Get X-Vault-Token Function
function Get-X-Vault-Token {
    Param
   (
       [Parameter(Mandatory=$true)]
       [string] $CertPath
   )
   $AuthCert = Get-PfxCertificate -FilePath $CertPath
   # Auth to Vault using SSL Cert to get auth token
   $AuthToken = Invoke-RestMethod -SkipCertificateCheck -Uri 'https://vault.datawan.net:8200/v1/auth/cert/login' -Method Post -Body '{"name": "powershell"}' -Certificate $AuthCert
   # Get the client token from response to build auth header
   $MyToken = $AuthToken.auth.client_token
   $ClientHeader = @{"X-Vault-Token" = "$MyToken"}
   $ClientHeader
}

# Main script variables
$computer = "."
$namespace = "root\CIMV2"
$batstat= @{"1"="battery is discharging";"2"="On AC";"3"="Fully Charged";"4"=`
"Low";"5"="Critical";"6"="Charging";"7"="Charging and High";"8"="Charging and`
 Low";"9"="Charging and Critical";"10"="Undefined";"11"="Partially Charged";}

# SendGrid Variables
$From = "admin@datawan.net"
$To = "rick.londono@gmail.com"
$SendGridKey = $SendGridCredential
$Subject = "UPS Alert!"
$Body ="Power failure detected. Shutting down servers."

# Get Battery Status/Info
$batinfo = Get-CimInstance -class Win32_Battery -computername $computer -ErrorAction silentlycontinue -namespace $namespace

if ($? -and $batinfo)
{
     "Battery status on    : " + $computer +" status: "+ $batstat.Get_Item([string]$batinfo.BatteryStatus)
     "Percentage left      : " + $batinfo.EstimatedChargeRemaining
}
else
{
    if ($error)
    {
        "Could not find any battery/UPS information on system: " + $computer
        throw $error[0].Exception
    }
}
$wewereonbattery = $false
$powerstatus = $true
$percent = $batinfo.EstimatedChargeRemaining

# Never ending loop.
$batinfo = Get-CimInstance -class Win32_Battery -computername $computer -ErrorAction silentlycontinue -namespace $namespace
if ($?) # No error?
{
    # Write-Host $batstat.Get_Item([string]$batinfo.BatteryStatus)
    # Only check if we need to take action (BatteryStatus = 2 is on AC)
    if ($batinfo.BatteryStatus -ne 2)
    {
        $date = Get-Date
        if ($powerstatus -and $percent -le 95)
        {
            $powerstatus = $false

            # *** Connect to Vault and setup Auth Header ***
            # Setup Client Header
            $ClientHeader = Get-X-Vault-Token -CertPath "C:\Scripts\posh-vault-np.pfx"

            # *** SendGrid Login ***
            # Setup SendGrid Creds
            $SendGridLogin = Invoke-RestMethod -SkipCertificateCheck -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/SendGrid?version=1'
            $SendGridSecret = $SendGridLogin.data.data
            $SendGridSecret = ConvertTo-SecureString $SendGridSecret.apikey -AsPlainText -Force
            $SendGridKey = (New-Object PSCredential "user",$SendGridSecret).GetNetworkCredential().Password

            # Send email alert
            Send-EmailWithSendGrid -from $from -to $to -ApiKey $SendGridKey -Body $Body -Subject $Subject

            # *** vCenter Login ***
            # Get vCenter Login
            $vCenterLogin = Invoke-RestMethod -SkipCertificateCheck -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/vCenter?version=1'
            $vCenterSecret = $vCenterLogin.data.data
            # Setup Creds for vCenter
            $vCenterSecret = ConvertTo-SecureString $vCenterSecret.'Administrator@vsphere.local' -AsPlainText -Force
            $vCenterCredential = New-Object System.Management.Automation.PSCredential ('Administrator@vsphere.local', $vCenterSecret)

            # *** RL-XPX Login ***
            # Get RL-XP Login
            $RLXPLogin = Invoke-RestMethod -SkipCertificateCheck -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/RLXPS?version=1'
            $RLComputerSecret = $RLXPLogin.data.data
            # Setup RL XPS Creds
            $RLComputerSecret = ConvertTo-SecureString $RLComputerSecret.londonor -AsPlainText -Force
            $RLComputerCredential = New-Object System.Management.Automation.PSCredential ('londonor@ad.datawan.net', $RLComputerSecret)

            # *** NAS Login ***
            # Get NAS Login
            $NASLogin = Invoke-RestMethod -SkipCertificateCheck -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/NAS?version=1'
            $NASSecret = $NASLogin.data.data
            # Setup NAS Creds
            $NASSecret = ConvertTo-SecureString $NASSecret.root -AsPlainText -Force
            $NASCredential = New-Object System.Management.Automation.PSCredential ('root', $NASSecret)

            # ****************************
            # *** Shutdown all devices ***
            # ****************************

            # Shutdown NAS
            $remoteHost = "nas.ad.datawan.net"
            $command = "shutdown -P now"
            New-SSHSession -ComputerName $remoteHost -Credential $NAScredential -Port 2022
            Start-Sleep 5
            $mysession = Get-SSHSession
            Invoke-SSHCommand -Command $command -SSHSession $mysession

            # Shutdown RL XPS Computer
            Stop-Computer -ComputerName "RL-XPS.ad.datawan.net" -Force -Credential $RLComputerCredential

            # Connect to vCenter and Shutdown ESXi Server
            Connect-VIServer -Server vc-prod.ad.datawan.net -Credential $vCenterCredential
            Start-Sleep -Seconds 8
            Stop-VMHost -VMHost "vmhost.ad.datawan.net" -Force -RunAsync -Confirm:$False
        }
        $wewereonbattery = $true
    }
    else
    {
        if ($wewereonbattery)
        {
            $date = Get-Date
            if ($powerstatus -eq $false)
            {
                $ClientHeader = Get-X-Vault-Token -CertPath "C:\Scripts\posh-vault-np.pfx"
                # *** SendGrid Login ***
                # Setup SendGrid Creds
                $SendGridLogin = Invoke-RestMethod -SkipCertificateCheck -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/SendGrid?version=1'
                $SendGridSecret = $SendGridLogin.data.data
                $SendGridSecret = ConvertTo-SecureString $SendGridSecret.apikey -AsPlainText -Force
                $SendGridKey = (New-Object PSCredential "user",$SendGridSecret).GetNetworkCredential().Password

                # Send email
                Send-EmailWithSendGrid -from $from -to $to -ApiKey $SendGridKey -Body "AC power detected" -Subject $Subject
                $powerstatus = $true
            }
        }
    }
}
else
{
    $date = Get-Date
    "$date : No UPS system found - was it shut down?"
}
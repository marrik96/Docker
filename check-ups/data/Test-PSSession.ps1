#//////////////////////////////////////////////////////////////////////////////////////////////////
#
#   connect-admin.ps1 - Ricardo Londono
#
#   This POSH script will setup and test for remote PSSession
#
#       Last Modified: 11/25/2020
#
#//////////////////////////////////////////////////////////////////////////////////////////////////
#
# CheckSession
#
if (Get-PSSession | Select-Object state) {
    # Write-Host "Connection Exists"
    $AdminSession = Get-PSSession -name 'AdminSession'
    Invoke-Command -Session $AdminSession -FilePath '/home/watch-ups.ps1'
} else {
    # Get SSL Cert
    $AuthCert = Get-PfxCertificate -FilePath "/ssl/posh-vault-np.pfx"
    # Auth to Vault using SSL Cert to get auth token
    $AuthToken = Invoke-RestMethod -Uri 'https://vault.datawan.net:8200/v1/auth/cert/login' -Method Post -Body '{"name": "powershell"}' -Certificate $AuthCert
    # Get the client token from response to build auth header
    $MyToken = $AuthToken.auth.client_token
    $ClientHeader = @{"X-Vault-Token" = "$MyToken"}
    # Connect to Vault again using new header
    $adminLogin = Invoke-RestMethod -Headers $ClientHeader 'https://vault.datawan.net:8200/v1/PowerShell/data/Admin?version=1'
    $AdminSecret = $adminLogin.data.data
    # build posh creds
    $AdminSecret = ConvertTo-SecureString $AdminSecret.londonor_sys -AsPlainText -Force
    $AdminCredential = New-Object System.Management.Automation.PSCredential ('londonor_sys', $AdminSecret)
    # Setup PS Session to admin.ad.datawan.net VM using creds
    $AdminSession = New-PSSession -ComputerName "admin.ad.datawan.net" -Credential $ADMINcredential -Authentication Negotiate -ConfigurationName PowerShell.7.1.0 -Name AdminSession
    # Run script
    Invoke-Command -Session $AdminSession -FilePath '/home/watch-ups.ps1'
}
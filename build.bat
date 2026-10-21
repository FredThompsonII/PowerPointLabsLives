@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PPL_CREATOR=%~f0"
set "PPL_ROOT=%~dp0"
set "PPL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PPL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PPL_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { $s=[IO.File]::ReadAllText($env:PPL_CREATOR); & ([scriptblock]::Create(($s -split '(?m)^# POWERSHELL START\r?$',2)[1])) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
set "PPL_RC=%ERRORLEVEL%"
if not "%PPL_RC%"=="0" echo Build did not complete cleanly. See the error above.
pause
exit /b %PPL_RC%
# POWERSHELL START
# PowerPointLabs installer creator. Copyright (c) 2026 Fred Thompson. MIT license.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$root=$env:PPL_ROOT
$work=Join-Path ([IO.Path]::GetTempPath()) ('PowerPointLabs-build-'+[Guid]::NewGuid().ToString('N'))
$signing=Join-Path $root 'Signing'
$stage=Join-Path $work 'stage'
$cert=$null
$imported=@()
$rc=1
function Run([string]$exe,[string[]]$arguments) {
 & $exe @arguments | Out-Host
 if($LASTEXITCODE -ne 0){throw ((Split-Path $exe -Leaf)+' failed with exit code '+$LASTEXITCODE)}
}
function WriteFile([string]$path,[string]$text) {
 [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
}
function Download([string]$url,[string]$path,[string]$hash,[string]$algorithm='SHA256') {
 $wc=[Net.WebClient]::new()
 try {$wc.DownloadFile($url,$path)} finally {$wc.Dispose()}
 if((Get-FileHash -LiteralPath $path -Algorithm $algorithm).Hash -ine $hash){throw ('Download checksum mismatch: '+$url)}
}
try {
 [void](New-Item -ItemType Directory -Path $stage -Force)
 $env:TEMP=$work;$env:TMP=$work
 [void](New-Item -ItemType Directory -Path $signing -Force)
 $payload=Join-Path $root 'Application Files\PowerPointLabs_6_1_0_2'
 Copy-Item -LiteralPath (Join-Path $root 'PowerPointLabs.vsto') -Destination $stage
 Copy-Item -LiteralPath (Join-Path $payload 'PowerPointLabs.dll.manifest') -Destination $stage
 foreach($f in Get-ChildItem -LiteralPath $payload -Filter '*.deploy' -File) {
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $stage $f.BaseName)
 }
 $app=Join-Path $stage 'PowerPointLabs.dll.manifest'
 $deployment=Join-Path $stage 'PowerPointLabs.vsto'
 # The original post-action class is compiled into PowerPointLabs.dll.
 $xml=[Xml.XmlDocument]::new();$xml.PreserveWhitespace=$true;$xml.Load($app)
 $id=$xml.SelectSingleNode('//*[local-name()="postAction"]/*[local-name()="entryPoint" and @class="PowerPointLabs.PostInstall"]/*[local-name()="assemblyIdentity"]')
 if($null -eq $id){throw 'Missing PowerPointLabs post-install assembly reference.'}
 $id.SetAttribute('name','PowerPointLabs');$xml.Save($app)

 $pfx=Join-Path $signing 'CodeSigning.pfx'
 $secret=Join-Path $signing 'CodeSigning.password.dpapi'
 $thumbFile=Join-Path $signing 'CertificateThumbprint.txt'
 if((Test-Path -LiteralPath $pfx) -and (Test-Path -LiteralPath $thumbFile)) {throw 'Supply either CodeSigning.pfx or CertificateThumbprint.txt, not both.'}
 if(Test-Path -LiteralPath $thumbFile) {
  $thumb=(Get-Content -LiteralPath $thumbFile -Raw).Trim().Replace(' ','').Replace('-','')
  if($thumb -notmatch '^[a-fA-F0-9]{40}$'){throw 'Invalid certificate thumbprint.'}
  $cert=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$thumb)
 } elseif(Test-Path -LiteralPath $pfx) {
  if(Test-Path -LiteralPath $secret){$password=(Get-Content -LiteralPath $secret -Raw).Trim() | ConvertTo-SecureString}
  else {$password=Read-Host 'Password for Signing\CodeSigning.pfx' -AsSecureString}
  $before=@(Get-ChildItem Cert:\CurrentUser\My | ForEach-Object {$_.Thumbprint})
  $loaded=@(Import-PfxCertificate -FilePath $pfx -CertStoreLocation Cert:\CurrentUser\My -Password $password)
  $imported=@($loaded | Where-Object {$before -notcontains $_.Thumbprint})
  $keys=@($loaded | Where-Object {$_.HasPrivateKey})
  if($keys.Count -ne 1){throw 'PFX must contain exactly one signing private key.'}
  $cert=$keys[0]
 } else {
  $unknown=@(Get-ChildItem -LiteralPath $signing -Force | Where-Object {$_.Name -notin @('readme.txt','.gitkeep')})
  if($unknown.Count){throw 'Signing contains unrecognized files. Supply CodeSigning.pfx or CertificateThumbprint.txt.'}
  Write-Host 'Creating a reusable local signing certificate in Signing.'
  $cert=New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=PowerPointLabs Local Publisher' -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeyLength 3072 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(3)
  $random=New-Object byte[] 48;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try {$rng.GetBytes($random)} finally {$rng.Dispose()}
  $password=ConvertTo-SecureString ([Convert]::ToBase64String($random)) -AsPlainText -Force
  [Array]::Clear($random,0,$random.Length)
  # Store the password first; never leave an encrypted PFX without its password.
  WriteFile $secret (ConvertFrom-SecureString $password)
  Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $password -ChainOption EndEntityCertOnly | Out-Null
 }
 if(-not $cert.HasPrivateKey -or $cert.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1'){throw 'An accessible RSA signing private key is required.'}
 if($cert.NotBefore -gt (Get-Date) -or $cert.NotAfter -le (Get-Date)){throw 'Signing certificate is not currently valid.'}
 $codeSigning=$false
 foreach($extension in $cert.Extensions) {
  if($extension.Oid.Value -eq '2.5.29.37') {
   $eku=[Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($extension,$false)
   foreach($oid in $eku.EnhancedKeyUsages){if($oid.Value -eq '1.3.6.1.5.5.7.3.3'){$codeSigning=$true}}
  }
 }
 if(-not $codeSigning){throw 'Certificate must permit code signing.'}
 Write-Host ('Signing publisher: '+$cert.Subject+'; thumbprint: '+$cert.Thumbprint)

 Write-Host 'Downloading temporary .NET SDK, Microsoft Mage and WiX build tools...'
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $wc=[Net.WebClient]::new()
 try {$meta=$wc.DownloadString('https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json') | ConvertFrom-Json} finally {$wc.Dispose()}
 $version=[string]$meta.'latest-sdk'
 $rid=if([Environment]::Is64BitOperatingSystem){'win-x64'}else{'win-x86'}
 $release=@($meta.releases | Where-Object {$_.PSObject.Properties['sdk'] -and $_.sdk.version -eq $version})
 $artifact=@($release[0].sdk.files | Where-Object {$_.rid -eq $rid -and $_.name -eq ('dotnet-sdk-'+$rid+'.zip')})
 if($artifact.Count -ne 1 -or $artifact[0].hash -notmatch '^[a-fA-F0-9]{128}$'){throw 'Invalid Microsoft SDK download metadata.'}
 $sdkZip=Join-Path $work 'sdk.zip'
 Download $artifact[0].url $sdkZip $artifact[0].hash SHA512
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $sdk=Join-Path $work 'dotnet';[IO.Compression.ZipFile]::ExtractToDirectory($sdkZip,$sdk)
 $env:DOTNET_ROOT=$sdk;$env:PATH=$sdk+';'+$env:PATH
 $env:DOTNET_CLI_HOME=Join-Path $work 'dotnet-home'
 $env:NUGET_PACKAGES=Join-Path $work 'nuget'
 $env:NUGET_HTTP_CACHE_PATH=Join-Path $work 'nuget-http'
 $env:NUGET_PLUGINS_CACHE_PATH=Join-Path $work 'nuget-plugins'
 $env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
 $env:DOTNET_NOLOGO='true';$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
 $feed=Join-Path $work 'feed';[void](New-Item -ItemType Directory -Path $feed)
 Download 'https://api.nuget.org/v3-flatcontainer/microsoft.dotnet.mage/10.0.0/microsoft.dotnet.mage.10.0.0.nupkg' (Join-Path $feed 'microsoft.dotnet.mage.10.0.0.nupkg') 'BD880F060265B3318D93C8A6E9269A64C094569ACB9553CD168EAB5C1FE9E080'
 $config=Join-Path $work 'NuGet.Config'
 WriteFile $config ('<configuration><packageSources><clear/><add key="local" value="'+[Security.SecurityElement]::Escape($feed)+'"/></packageSources></configuration>')
 $mageDir=Join-Path $work 'mage'
 Run (Join-Path $sdk 'dotnet.exe') @('tool','install','Microsoft.DotNet.Mage','--version','10.0.0','--tool-path',$mageDir,'--configfile',$config)
 $mage=Join-Path $mageDir 'dotnet-mage.exe'
 $wixZip=Join-Path $work 'wix.zip'
 Download 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' $wixZip '6AC824E1642D6F7277D0ED7EA09411A508F6116BA6FAE0AA5F2C7DAA2FF43D31'
 $wix=Join-Path $work 'wix';[IO.Compression.ZipFile]::ExtractToDirectory($wixZip,$wix)

 # Sign the application first, update its reference, then sign the deployment.
 # Mage calculates the publisher/key identities and the final manifest hash.
 Run $mage @('-Sign',$app,'-CertHash',$cert.Thumbprint,'-Algorithm','sha256RSA')
 Run $mage @('-Update',$deployment,'-AppManifest',$app,'-AppCodeBase','PowerPointLabs.dll.manifest','-MapFileExtensions','false','-Publisher','PowerPointLabs','-Algorithm','sha256RSA')
 Run $mage @('-Sign',$deployment,'-CertHash',$cert.Thumbprint,'-Algorithm','sha256RSA')
 Export-Certificate -Cert $cert -FilePath (Join-Path $stage 'PowerPointLabs_PublicCertificate.cer') | Out-Null
 $trust=@'
param(
 [Parameter(Mandatory=$true)][Alias('C')][string]$Certificate,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][Alias('E')][string]$ExpectedThumbprint,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{32}$')][Alias('T')][string]$TransactionId,
 [Parameter(Mandatory=$true)][ValidateSet('Install','Repair','Uninstall','Rollback','Commit')][Alias('O')][string]$Operation
)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
function Require([bool]$condition,[string]$message) {if(-not $condition){throw $message}}
function CheckDotNet45 {
    $key='HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    $p=Get-ItemProperty -LiteralPath $key -Name Release -ErrorAction SilentlyContinue
    $release=0
    if($p -and $p.Release) {$release=[int]$p.Release}
    Require ($release -ge 378389) ('Requires .NET Framework 4.5 or a compatible newer .NET Framework. Release registry value is '+$release+'. Ask the administrator to install the Microsoft .NET Framework 4.8/4.8.1 runtime. Modern .NET 8/10 alone does not meet this requirement.')
}
function CheckVstoRuntime {
    $found=$false
    foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
        try {$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)}
        catch {continue}
        try {
            foreach($path in @('SOFTWARE\Microsoft\VSTO Runtime Setup\v4R','SOFTWARE\Microsoft\VSTO Runtime Setup\v4')) {
                $key=$base.OpenSubKey($path)
                if($null -eq $key) {continue}
                try {
                    $raw=[string]$key.GetValue('Version','')
                    $v=$null
                    if([Version]::TryParse($raw,[ref]$v) -and $v -ge [Version]'10.0.30319') {$found=$true}
                } finally {$key.Close()}
            }
        } finally {$base.Close()}
    }
    Require $found 'Microsoft Visual Studio Tools for Office (VSTO) Runtime 2010 or later was not detected. Ask your computer administrator to install the Microsoft VSTO Runtime before using PowerPointLabs: https://www.microsoft.com/en-us/download/details.aspx?id=56961 . Then rerun the installer.'
}

$rootStore=$null;$pubStore=$null
try {
 $base=Join-Path $env:LOCALAPPDATA 'PowerPointLabs\TrustTransactions'
 $journal=Join-Path $base ($TransactionId+'.journal.json')
 $ownership=Join-Path $base ($TransactionId+'.owned.json')
 if($Operation -eq 'Commit') {
  if(Test-Path -LiteralPath $journal) {Remove-Item -LiteralPath $journal -Force}
  exit 0
 }
 $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($Certificate)
 if($cert.Thumbprint -ine $ExpectedThumbprint){throw 'Public certificate differs from the approved MSI signer.'}
 if($cert.HasPrivateKey) {throw 'Private signing keys must not be installed.'}
 $selfIssued=($cert.Subject -ceq $cert.Issuer)
 $rootStore=[Security.Cryptography.X509Certificates.X509Store]::new('Root',[Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
 $pubStore=[Security.Cryptography.X509Certificates.X509Store]::new('TrustedPublisher',[Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
 $rootStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
 $pubStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
 function Has-Certificate($store) {
  return ($store.Certificates.Find([Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,$cert.Thumbprint,$false).Count -gt 0)
 }
 function Save-State([string]$path,$state) {
  $pending=$path+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
  try {
   [IO.File]::WriteAllText($pending,($state | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
   if(Test-Path -LiteralPath $path) {[IO.File]::Replace($pending,$path,[System.Management.Automation.Language.NullString]::Value)}
   else {[IO.File]::Move($pending,$path)}
  } finally {if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Force}}
 }
 function Read-State([string]$path) {
  $s=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if($s.Schema -ne 1 -or $s.Thumbprint -cne $cert.Thumbprint) {throw 'Unrecognized trust ownership/journal.'}
  return $s
 }
 function Restore-Transaction {
  if(-not (Test-Path -LiteralPath $journal)) {return}
  $j=Read-State $journal
  if($j.HadPublisher -isnot [bool] -or $j.HadRoot -isnot [bool]) {throw 'Invalid rollback flags.'}
  if($j.HadPublisher){$pubStore.Add($cert)}else{$pubStore.Remove($cert)}
  if($selfIssued) {if($j.HadRoot){$rootStore.Add($cert)}else{$rootStore.Remove($cert)}}
  if($null -eq $j.PreviousOwnership) {
   if(Test-Path -LiteralPath $ownership){Remove-Item -LiteralPath $ownership -Force}
  } else {Save-State $ownership $j.PreviousOwnership}
  Remove-Item -LiteralPath $journal -Force
 }
 if($Operation -eq 'Rollback') {Restore-Transaction;exit 0}
 if(Test-Path -LiteralPath $journal){throw 'Pending trust transaction exists; preserve it and resolve rollback before retrying.'}
 $old=$null
 if(Test-Path -LiteralPath $ownership) {
  $old=Read-State $ownership
  if($old.RootOwned -isnot [bool] -or $old.PublisherOwned -isnot [bool]) {throw 'Invalid ownership flags.'}
 }
 if($Operation -eq 'Repair' -and $null -eq $old){throw 'Repair has no recorded publisher approval/ownership. Reinstall with explicit consent.'}
 if($Operation -eq 'Uninstall' -and $null -eq $old) {exit 0}
 if($Operation -ne 'Uninstall') {
  CheckDotNet45
  CheckVstoRuntime
  $now=Get-Date
  if($cert.NotBefore -gt $now -or $cert.NotAfter -le $now){throw 'Certificate is not currently valid.'}
 }
 [void](New-Item -ItemType Directory -Path $base -Force)
 $hadRoot=Has-Certificate $rootStore;$hadPub=Has-Certificate $pubStore
 $j=[pscustomobject]@{Schema=1;Thumbprint=$cert.Thumbprint;HadRoot=[bool]$hadRoot;HadPublisher=[bool]$hadPub;PreviousOwnership=$old}
 Save-State $journal $j
 try {
  if($Operation -eq 'Uninstall') {
   if($old.PublisherOwned){$pubStore.Remove($cert)}
   if($old.RootOwned -and $selfIssued){$rootStore.Remove($cert)}
   Remove-Item -LiteralPath $ownership -Force
  } else {
   $ownRoot=($selfIssued -and -not $hadRoot);$ownPub=(-not $hadPub)
   if($null -ne $old){$ownRoot=($ownRoot -or $old.RootOwned);$ownPub=($ownPub -or $old.PublisherOwned)}
   if($selfIssued -and -not $hadRoot){$rootStore.Add($cert)}
   if(-not $hadPub){$pubStore.Add($cert)}
   Save-State $ownership ([pscustomobject]@{Schema=1;Thumbprint=$cert.Thumbprint;RootOwned=[bool]$ownRoot;PublisherOwned=[bool]$ownPub})
  }
 } catch {Restore-Transaction;throw}
 exit 0
} catch {
 [Console]::Error.WriteLine('Publisher trust '+$Operation+' failed: '+$_.Exception.Message)
 exit 1
} finally {
 if($null -ne $pubStore){$pubStore.Close()}
 if($null -ne $rootStore){$rootStore.Close()}
}
'@
 WriteFile (Join-Path $stage 'TrustPublisher.ps1') $trust
 $rows=@'
C_Deployment|{6373974C-ECD9-5DF7-BC85-EDBBEBD204D3}|F_Deployment|PowerPointLabs.vsto|PowerPointLabs.vsto|C_Deployment
C_PublicCert|{8F3149FF-88F0-5C89-9D8C-C59D455716D8}|F_PublicCert|PowerPointLabs_PublicCertificate.cer|PowerPointLabs_PublicCertificate.cer|C_PublicCert
C_TrustScript|{D43A7C52-E229-5DFC-A849-10073F68D08E}|F_TrustScript|PowerPointLabs_TrustPublisher.ps1|TrustPublisher.ps1|C_TrustScript
C_F01|{A145A56B-14DB-5A57-A403-37604B8D30FC}|F_F01|PowerPointLabs.dll.manifest|PowerPointLabs.dll.manifest|C_F01_R17
C_F02|{AB19BEA5-475F-54F4-8E71-7E16F367F450}|F_F02|EyeOpen.Imaging.Processing.dll|EyeOpen.Imaging.Processing.dll|C_F02_R17
C_F03|{B8D145DF-4E4C-5BCC-9B43-5E7F07BAB1CB}|F_F03|ImageProcessor.dll|ImageProcessor.dll|C_F03_R17
C_F04|{7B2422EC-5A85-5A7A-B872-A778AE36CE3E}|F_F04|MahApps.Metro.dll|MahApps.Metro.dll|C_F04_R17
C_F05|{605C81C4-7BCD-50FC-91E4-7F88FD2B3EFD}|F_F05|Microsoft.Office.Tools.Common.v4.0.Utilities.dll|Microsoft.Office.Tools.Common.v4.0.Utilities.dll|C_F05_R17
C_F06|{79DB25CF-1862-5759-A1CB-F3C8560B5389}|F_F06|Microsoft.Office.Tools.v4.0.Framework.dll|Microsoft.Office.Tools.v4.0.Framework.dll|C_F06_R17
C_F07|{A83821E5-8E13-5827-94D6-0503E8D38A9D}|F_F07|Microsoft.VisualStudio.Tools.Applications.Runtime.dll|Microsoft.VisualStudio.Tools.Applications.Runtime.dll|C_F07_R17
C_F08|{F7791A66-9173-5217-A38F-9606F0DC05F9}|F_F08|NAudio.dll|NAudio.dll|C_F08_R17
C_F09|{DB6A3DAF-ED8E-5715-901E-B942D0AF688C}|F_F09|Newtonsoft.Json.dll|Newtonsoft.Json.dll|C_F09_R17
C_F10|{2F6F1EE2-4C48-54C9-92E1-B95B0CA96D27}|F_F10|PowerPointLabs.dll.config|PowerPointLabs.dll.config|C_F10_R17
C_F11|{534CC86C-D4A9-586F-9D78-AA437CC3F2C7}|F_F11|PowerPointLabs.dll|PowerPointLabs.dll|C_F11_R17
C_F12|{8DB11AEE-BD11-575A-A726-D0DC6833D7AF}|F_F12|RestSharp.dll|RestSharp.dll|C_F12_R17
C_F13|{B813A80D-80D3-5375-B96F-36AF995B25C7}|F_F13|System.Net.Http.Extensions.dll|System.Net.Http.Extensions.dll|C_F13_R17
C_F14|{DDF482D0-5D51-5FB6-AA80-BB4D015CDFED}|F_F14|System.Net.Http.Formatting.dll|System.Net.Http.Formatting.dll|C_F14_R17
C_F15|{97917FDC-D156-5A73-BCFF-DDCD5AAE3C06}|F_F15|System.Net.Http.Primitives.dll|System.Net.Http.Primitives.dll|C_F15_R17
C_F16|{12CF8483-62DD-511A-8F0D-22D260F2BCCF}|F_F16|System.Windows.Interactivity.dll|System.Windows.Interactivity.dll|C_F16_R17
C_F17|{D6ED03A5-4AA5-59EF-B461-FB3586A16513}|F_F17|TestInterface.dll|TestInterface.dll|C_F17_R17
'@
 $files=foreach($row in ($rows -split '\r?\n')) {
  $f=$row.Split('|')
  '<Component Id="'+$f[0]+'" Guid="'+$f[1]+'"><File Id="'+$f[2]+'" Name="'+$f[3]+'" Source="'+$f[4]+'"/><RegistryValue Root="HKCU" Key="Software\PowerPointLabs\CommunityInstaller\ComponentMarkers" Name="'+$f[5]+'" Type="integer" Value="1" KeyPath="yes"/></Component>'
 }
 $wxs=@'
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
<Product Id="*" Name="PowerPointLabs 6.1.0.2 - Community Repackaging"
Language="1033" Version="6.1.28" Manufacturer="Fred Thompson (unofficial repackaging)"
UpgradeCode="{850BC663-3AF1-5E6A-A91D-995200DE88CB}">
<Package InstallerVersion="500" Platform="x86" Compressed="yes"
InstallScope="perUser" InstallPrivileges="limited"
Description="User-scoped PowerPointLabs VSTO add-in. Original GPLv2 code by PowerPointLabs contributors." />
<MajorUpgrade Schedule="afterInstallInitialize" AllowSameVersionUpgrades="yes" DowngradeErrorMessage="A later PowerPointLabs repackager is already installed." />
<MediaTemplate EmbedCab="yes" />
<Condition Message="Rollback must be enabled to install or remove publisher trust safely.">NOT RollbackDisabled</Condition>
<Directory Id="TARGETDIR" Name="SourceDir">
<Directory Id="LocalAppDataFolder">
<Directory Id="PPLDir" Name="Programs">
<Directory Id="PPLSubDir" Name="PowerPointLabs">
<Directory Id="INSTALLFOLDER" Name="6.1.0.2">
</Directory>
</Directory>
</Directory>
</Directory>
</Directory>
<DirectoryRef Id="INSTALLFOLDER">__FILES__</DirectoryRef>
<DirectoryRef Id="TARGETDIR">
<Component Id="C_UserRegistry" Guid="*">
<RemoveFolder Id="Cleanup_INSTALLFOLDER" Directory="INSTALLFOLDER" On="uninstall" />
<RemoveFolder Id="Cleanup_PPLSubDir" Directory="PPLSubDir" On="uninstall" />
<RemoveFolder Id="Cleanup_PPLDir" Directory="PPLDir" On="uninstall" />
<RegistryValue Root="HKCU" Key="Software\Microsoft\Office\PowerPoint\Addins\PowerPointLabs"
Name="Manifest" Type="string" Value="file:///[INSTALLFOLDER]PowerPointLabs.vsto|vstolocal" KeyPath="yes" />
<RegistryValue Root="HKCU" Key="Software\Microsoft\Office\PowerPoint\Addins\PowerPointLabs"
Name="FriendlyName" Type="string" Value="PowerPointLabs" />
<RegistryValue Root="HKCU" Key="Software\Microsoft\Office\PowerPoint\Addins\PowerPointLabs"
Name="Description" Type="string" Value="Original PowerPointLabs 6.1.0.2; repackaged by Fred Thompson and ChatGPT" />
<RegistryValue Root="HKCU" Key="Software\Microsoft\Office\PowerPoint\Addins\PowerPointLabs"
Name="LoadBehavior" Type="integer" Value="3" />
</Component>
</DirectoryRef>
<Property Id="PPL_CERT_CONSENT" Secure="yes" />
<UI>
<UIRef Id="WixUI_Common" />
<DialogRef Id="ErrorDlg" />
<DialogRef Id="FatalError" />
<DialogRef Id="FilesInUse" />
<DialogRef Id="MsiRMFilesInUse" />
<DialogRef Id="UserExit" />
<DialogRef Id="ExitDialog" />
<DialogRef Id="ProgressDlg" />
<DialogRef Id="PrepareDlg" />
<DialogRef Id="ResumeDlg" />
<Publish Dialog="ExitDialog" Control="Finish" Event="EndDialog" Value="Return">1</Publish>
<TextStyle Id="WixUI_Font_Normal" FaceName="Tahoma" Size="8" />
<TextStyle Id="WixUI_Font_Bigger" FaceName="Tahoma" Size="12" />
<TextStyle Id="WixUI_Font_Title" FaceName="Tahoma" Size="9" Bold="yes" />
<TextStyle Id="PPLFont" FaceName="Tahoma" Size="9" />
<Property Id="DefaultUIFont" Value="PPLFont" />
<Dialog Id="PublisherConsentDlg" Width="370" Height="270" Title="PowerPointLabs 6.1.0.2 - Publisher Approval">
<Control Id="Heading" Type="Text" X="18" Y="18" Width="334" Height="20" Text="Approve PowerPointLabs publisher certificate" />
<Control Id="Explanation" Type="Text" X="18" Y="47" Width="334" Height="40" Text="This is an unofficial PowerPointLabs installer. Certificate SHA-1 thumbprint: __SIGNER_THUMBPRINT__. The public certificate may not yet be trusted." />
<Control Id="Scope" Type="Text" X="18" Y="91" Width="334" Height="44" Text="Your approval adds this certificate to your Windows user's Trusted Publishers store. A self-signed certificate is also added to your Root store." />
<Control Id="Risks" Type="Text" X="18" Y="139" Width="334" Height="26" Text="Trust affects other programs signed with the same certificate. Office security settings will NOT be disabled." />
<Control Id="Consent" Type="CheckBox" X="18" Y="168" Width="330" Height="22" Property="PPL_CERT_CONSENT" CheckBoxValue="1" Text="I explicitly approve trusting this certificate." />
<Control Id="Cancel" Type="PushButton" X="235" Y="236" Width="56" Height="18" Cancel="yes" Text="Cancel">
<Publish Event="EndDialog" Value="Exit">1</Publish>
</Control>
<Control Id="Install" Type="PushButton" X="297" Y="236" Width="56" Height="18" Default="yes" Text="Install">
<Publish Event="EndDialog" Value="Return">PPL_CERT_CONSENT="1"</Publish>
</Control>
</Dialog>
<InstallUISequence><Show Dialog="PublisherConsentDlg" After="CostFinalize">NOT Installed</Show></InstallUISequence>
</UI>
<CustomAction Id="RejectMissingApproval" Error="This installer requires explicit publisher certificate approval in its interactive dialog. Administrative deployments must deliberately set PPL_CERT_CONSENT=1." />
<CustomAction Id="RollbackUserPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Rollback"
Execute="rollback" Impersonate="yes" Return="check" />
<CustomAction Id="ApplyUserPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Install"
Execute="deferred" Impersonate="yes" Return="check" />
<CustomAction Id="CommitUserPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Commit"
Execute="commit" Impersonate="yes" Return="ignore" />
<CustomAction Id="RollbackRemovedPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Rollback"
Execute="rollback" Impersonate="yes" Return="check" />
<CustomAction Id="RemoveUserPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Uninstall"
Execute="deferred" Impersonate="yes" Return="check" />
<CustomAction Id="RollbackRepairPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Rollback"
Execute="rollback" Impersonate="yes" Return="check" />
<CustomAction Id="RepairUserPublisherTrust" Directory="INSTALLFOLDER"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;[#F_TrustScript]&quot; -C &quot;[#F_PublicCert]&quot; -E __SIGNER_THUMBPRINT__ -T __TRUST_TRANSACTION_ID__ -O Repair"
Execute="deferred" Impersonate="yes" Return="check" />
<CustomAction Id="CommitRemovedPublisherTrust" Directory="TARGETDIR"
ExeCommand="&quot;[SystemFolder]WindowsPowerShell\v1.0\powershell.exe&quot; -NoProfile -NonInteractive -Command &quot;Remove-Item -LiteralPath ($env:LOCALAPPDATA+'\PowerPointLabs\TrustTransactions\__TRUST_TRANSACTION_ID__.journal.json') -Force -ErrorAction Stop&quot;"
Execute="commit" Impersonate="yes" Return="ignore" />
<InstallExecuteSequence>
<Custom Action="RejectMissingApproval" Before="InstallInitialize">NOT Installed AND PPL_CERT_CONSENT &lt;&gt; "1"</Custom>
<Custom Action="RollbackUserPublisherTrust" After="InstallFiles">NOT Installed AND PPL_CERT_CONSENT = "1"</Custom>
<Custom Action="ApplyUserPublisherTrust" After="RollbackUserPublisherTrust">NOT Installed AND PPL_CERT_CONSENT = "1"</Custom>
<Custom Action="RollbackRepairPublisherTrust" After="ApplyUserPublisherTrust">Installed AND REINSTALL AND NOT REMOVE</Custom>
<Custom Action="RepairUserPublisherTrust" After="RollbackRepairPublisherTrust">Installed AND REINSTALL AND NOT REMOVE</Custom>
<Custom Action="CommitUserPublisherTrust" After="RepairUserPublisherTrust">(NOT Installed AND PPL_CERT_CONSENT = "1") OR (Installed AND REINSTALL AND NOT REMOVE)</Custom>
<Custom Action="RollbackRemovedPublisherTrust" Before="RemoveUserPublisherTrust">Installed AND REMOVE = "ALL"</Custom>
<Custom Action="RemoveUserPublisherTrust" Before="RemoveFiles">Installed AND REMOVE = "ALL"</Custom>
<Custom Action="CommitRemovedPublisherTrust" After="RemoveUserPublisherTrust">Installed AND REMOVE = "ALL"</Custom>
</InstallExecuteSequence>
<Feature Id="Complete" Title="PowerPointLabs" Level="1">
<ComponentRef Id="C_Deployment" />
<ComponentRef Id="C_PublicCert" />
<ComponentRef Id="C_TrustScript" />
<ComponentRef Id="C_F01" />
<ComponentRef Id="C_F02" />
<ComponentRef Id="C_F03" />
<ComponentRef Id="C_F04" />
<ComponentRef Id="C_F05" />
<ComponentRef Id="C_F06" />
<ComponentRef Id="C_F07" />
<ComponentRef Id="C_F08" />
<ComponentRef Id="C_F09" />
<ComponentRef Id="C_F10" />
<ComponentRef Id="C_F11" />
<ComponentRef Id="C_F12" />
<ComponentRef Id="C_F13" />
<ComponentRef Id="C_F14" />
<ComponentRef Id="C_F15" />
<ComponentRef Id="C_F16" />
<ComponentRef Id="C_F17" />
<ComponentRef Id="C_UserRegistry" />
</Feature>
</Product>
</Wix>
'@
 $wxs=$wxs.Replace('__FILES__',($files -join "`r`n")).Replace('__SIGNER_THUMBPRINT__',$cert.Thumbprint).Replace('__TRUST_TRANSACTION_ID__',[Guid]::NewGuid().ToString('N'))
 WriteFile (Join-Path $stage 'installer.wxs') $wxs
 $msi=Join-Path $work 'PowerPointLabs.msi'
 Push-Location -LiteralPath $stage
 try {
  Run (Join-Path $wix 'candle.exe') @('-nologo','-arch','x86','-out',(Join-Path $work 'installer.wixobj'),'installer.wxs')
  Run (Join-Path $wix 'light.exe') @('-nologo','-ext','WixUIExtension','-b','.','-out',$msi,(Join-Path $work 'installer.wixobj'))
 } finally {Pop-Location}
 $signature=Set-AuthenticodeSignature -LiteralPath $msi -Certificate $cert -HashAlgorithm SHA256 -IncludeChain NotRoot
 # Self-signed publishers are not trusted until the installer asks for consent.
 if($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint -or $signature.Status -notin @('Valid','NotTrusted','UnknownError')){throw ('MSI signing failed: '+$signature.StatusMessage)}
 $output=Join-Path $root ('PowerPointLabs_6.1.0.2_Setup_'+[Guid]::NewGuid().ToString('N').Substring(0,8)+'.msi')
 Copy-Item -LiteralPath $msi -Destination $output
 Write-Host ('Created: '+$output)
 $rc=0
} catch {
 [Console]::Error.WriteLine($_.Exception.Message)
} finally {
 foreach($c in $imported) {
  try {Remove-Item -LiteralPath ('Cert:\CurrentUser\My\'+$c.Thumbprint) -Force} catch {Write-Warning $_.Exception.Message}
 }
 try {if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}}
 catch {Write-Warning ('Could not remove temporary build tools at '+$work+': '+$_.Exception.Message);$rc=1}
}
exit $rc

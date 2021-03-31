<#
.SYNOPSIS       Used to uninstall bomgar
.AUTHOR         Barry Ferguson
.LINK           mailto:barry.ferguson@countrymark.com
.VERSION        2.0
.DATE           02/18/2019
.NOTES          The problem here is that the Bomgar client doesn't remove its registry entry in all circumstances of uninstallation.
                As a result, we must clean the registry of any orphaned entries from old/manual installations, or MSIexec will code 0 abort,
                SCCM status 'Already Compliant'.
#>

function Remove-Bomgar {

    # Grab reg keys that remain after uninstalls. Search by key name and value DisplayName; by UninstallString .exe and msiexec
    $UnRegPath = Get-Item "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\"
    [PSObject[]]$Keys = Get-ChildItem "Registry::$UnRegPath" -Recurse | Get-ItemProperty | where {
        ($_.Name -like '*Jump Client*') -or ($_.DisplayName -like '*Jump Client*') }
    If ($Keys.Count -ne 0) {
        Write-Host "Found < $($Keys.Count) > Jump Client registry keys. Processing UninstallStrings" -ForegroundColor Cyan
        Select-Object -Property DisplayName, UninstallString
        Foreach ($Value in $Keys) {
            If ($Value.UninstallString -notmatch "msiexec") {
                # Uninstalls non-MSI clients, such as pinned sessions or .exe installs. We split the string on space character, then use index 0 to grab only the first "word".
                # This basically lets us target the path from registry but pass whatever arg we want in this script. To be sure this behavior remains consistent with BeyondTrust future updates,
                # We also dump the command to console for logging.
                $ExeArgs = $Value.UninstallString -split ' '
                Write-Host "Executing command: 'Execute-Process $($ExeArgs[0]) -uninstall silent'" -ForegroundColor Green
                Execute-Process -Path "$($ExeArgs[0])" -Parameters "-uninstall silent" -PassThru -WaitForMsiExec
            }
            If ($Value.UninstallString -match "msiexec") {
                Write-Host "Running PSADT function: Remove-MSIApplications" -ForegroundColor Green
                # Remove broken/nonstandard MSI installs (assuming $Detected is not $true when function is called)
                Remove-MSIApplications -Name 'Jump Client' -Wildcard -PassThru
            }
        }
        # Give post-uninstaller ops time to clear reg before kindly doing the needful.
        Start-Sleep -Seconds 5
        $PostScan = Get-ChildItem "Registry::$UnRegPath" -Recurse | Get-ItemProperty | where {
            ($_.Name -like '*Jump Client*') -or ($_.DisplayName -like '*Jump Client*') }
        Write-Host "Found < $($PostScan.Count) > orphaned registry keys to remove." -ForegroundColor Yellow
        foreach ($Orphan in $PostScan) {
            Write-Host "Deleting $($Orphan.DisplayName)" -ForegroundColor Yellow
            Remove-Item -LiteralPath $Orphan.PSPath -Force -Confirm:$false
        }
        $RegUninstall86 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\'
		$RegUninstall64 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
		# Grabing reg entries which contain 'Bomgar Jump Client' either as key name, or as property DisplayName, and delete them.
		$Keys86 = Get-ChildItem -Path $RegUninstall86 -Recurse | Get-ItemProperty | where { ($_.Name -like '*Jump Client*') -or ($_.DisplayName -like '*Jump Client*') }
		$Keys64 = Get-ChildItem -Path $RegUninstall64 -Recurse | Get-ItemProperty | where { ($_.Name -like '*Jump Client*') -or ($_.DisplayName -like '*Jump Client*') }
        # Could be a much more elegant array loop, but this is easier to read/maintain for the next guy.
        # Edit 3/31/21 I'm not actually sure this doesn't NEED to be a foreach loop, incase there is more than one key. Worked well enough in my prod, though...
		If ($NULL -ne $Keys86) {
			Remove-Item $Keys86 -Force -ErrorAction SilentlyContinue
			Write-Warning 'Deleted 32-bit reg entries'
		}
		If ($NULL -ne $Keys64) {
			Remove-Item $Keys64 -Force -ErrorAction SilentlyContinue
			Write-Warning 'Deleted 64-bit reg entries'
		}
		ElseIf ($NULL -eq $Keys86 -and $NULL -eq $Keys64) {
			Write-Host 'No registry keys to delete' -ForegroundColor Green
		}
    }
    ElseIf ($Keys.Count -eq 0) {
        Write-Host 'No registry entries found, proceeding to file cleanup.' -ForegroundColor Green
    }
    Get-ChildItem 'C:\ProgramData\' -Filter 'Bomgar*' | Remove-Item -Force -Recurse -Confirm:$false -ErrorAction Continue
}
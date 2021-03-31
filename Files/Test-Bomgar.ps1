<#
.SYNOPSIS       Used to detect acceptable baseline for Bomgar deployment
.AUTHOR         Barry Ferguson
.LINK           mailto:b.ferguson317@gmail.com
.VERSION        3.0
.DATE           01/15/2019
.NOTES          If SCCM sees anything on STDOUT, it perceives that as successful detection and sets 'Installed' status. Because of this we output 'something' when our deployment
                conditions are satisfied; and conversely output nothing to indicate no detection. In this case, out-of-date installs or those which are installed to the incorrect
                directory will be handled with the deployment script itself. This script just tells SCCM it needs to push the deployment at all.

                SCCM will record 'Unknown' status for deployment script results that have a non-zero exit code, or have output on STDERR and nothing on STDOUT. Results with output
                on STDERR but none on STDOUT and a 0 exit code result in 'Installed' status.
#>

function Test-Bomgar {
    # Test for installation directory's existence
    $PathScan = Test-Path -Path "$($env:ProgramFiles)\Bomgar\JumpClient"
    # Scan WMI for any jump client installs that meet or exceed baseline (NOTE: This WMI class is installed by/depends on CM client)
    $CIMScan = @(Get-CIMinstance -Namespace root/cimv2 -ClassName Win32Reg_AddRemovePrograms64 | Where-Object -FilterScript {$_.DisplayName -like "*Jump Client*" -and $_.Version -ge "19.2.1"})

    <#
    Not-so-fun-fact: some versions of jump client register multiple WMI objects, so would potentially return multiple values for $CIMScan.Version. This is
    incredibly annoying because it throws off the logic checks. Furthermore, single-entry machines only return a single object instead of an array. This
    means targeting $CIMScan.Version[0] for these machines only returns the first *character*. Wow, right? That means we have to splat the variable above,
    so we can use $CIMScan.Count to figure out whether the client has multiple entries (return 1 or >1), so we can determine whether to use
    $CIMScan.Version or $CIMScan.Version[0]. Otherwise our final check logic isn't reliable.
    Thanks BeyondTrust for being inconsistent.
    Thanks Microsoft for insane index behavior.

    Bonus points, this function can double as SCCM detection method. Probably want to strip all the comments and such to do so for readability.
    #>
    if ($CIMScan.Count -eq 1) {
        if (($CIMScan.Version -ge [version]"19.2.1") -and ($PathScan -eq $TRUE)) {
            $script:Detected = 'Yes'
            Write-Host "JumpClient detected. Version $($CIMScan.Version)" -ForegroundColor Cyan
        }
        else {}
    }
    elseif ($CIMScan.Count -gt 1) {
        if (($CIMScan.Version[0] -ge [version]"19.2.1") -and ($PathScan -eq $TRUE)) {
            $script:Detected = 'Yes'
            Write-Host "$($CIMScan.Count) JumpClients detected. Versions: $($CIMScan.Version[0]), $($CIMSCan.Version[1])" -ForegroundColor Cyan
        }
        else {}
    }
    else {}
}
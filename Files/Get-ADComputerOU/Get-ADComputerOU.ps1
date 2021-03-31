<#
.SYNOPSIS       Used to grab a computer's parent OU without Get-ADComputer cmdlet (installed w/Server Manager).
.AUTHOR         Barry Ferguson
.VERSION        1.0
.DATE           01/06/2020
.NOTES          Designed as part of a bomgar deployment; not designed to be run independently (yet). Not setting any speed records, but it works and I haven't figured a better way yet.
.CONTRIB        Thanks to /r/sysadmin discord powershell guys for help trimming some "replace" statements.
#>

function Get-ADComputerOU {
    $SysInfo = New-Object -ComObject "ADSystemInfo"
    $Computer = [ADSI]("LDAP://{0}" -f $SysInfo.GetType().InvokeMember("ComputerName", [System.Reflection.BindingFlags]::GetProperty, $null, $SysInfo, $null))
    $Script:ADPath = ([ADSI]$Computer.Parent).Path
    $Script:Return = ($ADPath.Split(",")[1]) -replace "ou="
    return $Return
}
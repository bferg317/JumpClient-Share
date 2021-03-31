<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false,
	[Parameter(Mandatory=$false)]
	[switch]$Force = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'BeyondTrust'
	[string]$appName = 'Remote Support Jump Client'
	[string]$appVersion = '21.1.1'
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.1.0'
	[string]$appScriptDate = '02/10/21'
	[string]$appScriptAuthor = 'Barry Ferguson'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.7.0'
	[string]$deployAppScriptDate = '02/13/2018'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	# Declare functions
    . ".\\Files\Test-Bomgar.ps1"
    . ".\\Files\Remove-Bomgar.ps1"
    . ".\\Files\Get-ADComputerOU\Get-ADComputerOU.ps1"

	If ($deploymentType -ine 'Uninstall') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================

		[string]$installPhase = 'Pre-Installation'

		<#
		The problem here is that the Bomgar client doesn't remove its registry entry in all circumstances of uninstallation.
		As a result, we must clean the registry of any orphaned entries from old/manual installations, or MSIexec will code 0 abort, SCCM status 'Already Compliant'.
		First, source the same detection script SCCM uses; this runs a 2-way baseline verification and sets $Detected var to $TRUE or $NULL (see Test-Bomgar
		for more). Then run every possible uninstall method assuming the current install does not fit standard config.
		#>

		Test-Bomgar
		Write-Host "Test-Bomgar returned: $script:Detected" -ForegroundColor Cyan
		if (($script:Detected -eq 'Yes') -and ($Force -ine $true)) {
			Write-Warning -Message "Compliant Bomgar installation detected. PSADT was instructed to install, but -Force was not specified. Aborting."
			Exit-Script -ExitCode 1638
		}
		else {
			Remove-Bomgar
		}
		Write-Host "Tests for baseline & removal complete. Proceeding with installation." -ForegroundColor Cyan
		Get-ADComputerOU
		foreach    ( $ADSite in $ADPath) {
		    if     ( $ADPath -like     '*Special OUs*')             { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $ADPath -like     '*Special OUs*')             { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $ADPath -like     '*Special OUs*')             { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $ADPath -like     '*Special OUs*')  			{ $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    elseif ( $Return -contains '2-letter site code')        { $SiteCode = 'Target bomgar group code'  }
		    else                                                    { $SiteCode = 'Default/catch-all bomgar group code'  }
		}
		Write-Host "Assigning to site code: $($SiteCode)" -ForegroundColor Green

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'
		Execute-MSI -Action Install -Path "installer.msi" -Parameters "KEY_INFO=################### jc_name=$(hostname) jc_jump_group=jumpgroup:$($SiteCode) INSTALLDIR=`"$($env:ProgramFiles)\Bomgar\JumpClient`" /qn"

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'
		Invoke-SCCMTask SoftwareInventory
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		Remove-Bomgar

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'


	}
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}
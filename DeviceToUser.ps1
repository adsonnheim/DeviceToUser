$EnvFilePath = "./.env.local"

If (-not (Test-Path $EnvFilePath -PathType Leaf)) {
	Write-Error "Error: .env.local file not found at $($EnvFilePath)"
	Exit 1
}

$Env = @{}
$EnvLines = Get-Content $EnvFilePath

ForEach ($Line in $EnvLines) {
	$TrimmedLine = $Line.Trim()
	
	If ([string]::IsNullOrEmpty($TrimmedLine) -or $TrimmedLine.StartsWith('#')) {
		Continue
	}
	
	$Name, $Value = $TrimmedLine -split '=', 2
	$Env.Add($Name, $Value)
}

$Raw = @(Invoke-Command -ComputerName $Env["REMOTE_COMPUTER"] -ScriptBlock { 
    Get-EventLog -LogName Security -Newest 10000 | Where-Object { $_.EventID -eq 4769 } | Select-Object -ExpandProperty Message # Use EventID 4624 instead?
})

$AccountNames = New-Object System.Collections.Generic.List[System.Object]
$DeviceNames = New-Object System.Collections.Generic.List[System.Object]
$UserDeviceMap = @{ }
$UserNames = @(Get-ADUser -Filter * -SearchBase $Env["SEARCH_BASE"] | Select-Object -ExpandProperty SamAccountName)

ForEach ($Output in $Raw) {
	$I = 82
	While ($Output[$I] -ne "`t") {
		$I++
	}
	
	$AccountName = $Output.SubString(82, $I - 82)
	
	$J = $Output.IndexOf("Service Name:") + 15
	While ($Output[$J] -ne "`t") {
		$J++
	}
	
	$DeviceName = $Output.SubString($Output.IndexOf("Service Name:") + 15, $J - ($Output.IndexOf("Service Name:") + 15)).Replace('$', '')
	
	$List = New-Object System.Collections.Generic.List[System.Object]
	
	$FormattedName = (($AccountName -split '@')[0]).Replace('$', '')
	
	If ((-not ($UserDeviceMap[$DeviceName] -contains $FormattedName)) -and ($UserNames -contains $FormattedName)) {
		If (-not ($UserDeviceMap.Keys -contains $DeviceName)) {
			$UserDeviceMap.Add($DeviceName, $List)
		}
		$UserDeviceMap[$DeviceName].Add($FormattedName)
	}
}

$FilteredAccountNames = New-Object System.Collections.Generic.List[System.Object]

ForEach ($AccountName in $AccountNames) {
	If ($UserNames -contains $FormattedName -and $FormattedName -ne "`r`n") {
		$FilteredAccountNames.Add($FormattedName)
	}
}

ForEach ($Device in $UserDeviceMap.Keys) {
	Write-Host " "
	Write-Host "----- DEVICE: $($Device)" -NoNewline
	ForEach ($User in $UserDeviceMap[$Device]) {
		Write-Host $User
	}
}
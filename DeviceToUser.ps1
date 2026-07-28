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

$Raw = New-Object System.Collections.Generic.List[System.Object]

ForEach ($DC in $Env["REMOTE_COMPUTERS"] -split ',') {
	$CDC = Invoke-Command -ComputerName $DC -ScriptBlock {
		Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4769 } | Select-Object Message
	}
	
	ForEach ($Item in $CDC) {
		$Raw.Add($Item)
	}
}

$AccountNames = New-Object System.Collections.Generic.List[System.Object]
$DeviceNames = New-Object System.Collections.Generic.List[System.Object]
$UserDeviceMap = @{ }
$UserNames = @(Get-ADUser -Filter * -SearchBase $Env["USER_BASE"] | Select-Object -ExpandProperty SamAccountName)
$ComputerNames = @(Get-ADComputer -Filter * -SearchBase $Env["COMPUTER_BASE"] | Select-Object -ExpandProperty Name)

ForEach ($Output in $Raw) {	
	$Output -match 'Account Name:\s*(\S+)' > $Null
	$AccountName = (($Matches[1] -split '@')[0]).Replace('$', '')
	
	$Output -match 'Service Name:\s*(\S+)' > $Null
	$DeviceName = $Matches[1].Replace('$', '')
	
	$List = New-Object System.Collections.Generic.List[System.Object]
	
	If (($UserDeviceMap.Keys -notcontains $DeviceName) -and ($ComputerNames -contains $DeviceName)) {
		$UserDeviceMap.Add($DeviceName, $List)
	}
	
	If (($UserNames -contains $AccountName) -and ($UserDeviceMap.Keys -contains $DeviceName) -and ($UserDeviceMap[$DeviceName] -notcontains $AccountName)) {
		$UserDeviceMap[$DeviceName].Add($AccountName)
	}
}

ForEach ($Device in $UserDeviceMap.Keys) {
	Add-Content -Path .\test.txt -Value " "
	Add-Content -Path .\test.txt -Value "----- DEVICE: $($Device)"
	ForEach ($User in $UserDeviceMap[$Device]) {
		Add-Content -Path .\test.txt -Value $User
	}
}
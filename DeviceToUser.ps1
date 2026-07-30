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

$Body = @{
	grant_type    = "client_credentials"
	client_id	  = $Env["CLIENT_ID"]
	client_secret = $Env["CLIENT_SECRET"]
	scope		  = "monitoring management control"
}

$TokenResponse = Invoke-RestMethod -Method POST -Uri ("$($Env["RMM_URL"])/ws/oauth/token") -ContentType "application/x-www-form-urlencoded" -Body $Body
$Token = $TokenResponse.access_token

$Headers = @{
	Authorization = "Bearer $Token"
	Accept	      = "application/json"
}

$Devices = Invoke-RestMethod -Method GET -Uri "$($Env["RMM_URL"])/v2/devices-detailed" -Headers $Headers
$DevicesJSON = $Devices | ConvertTo-Json
$DevicesArray = ConvertFrom-Json $DevicesJSON

$LowDevices = New-Object System.Collections.Generic.List[System.Object]

For ($Index = 0; $Index -lt $DevicesArray.Count; $Index++) {
	For ($Jndex = 0; $Jndex -lt $DevicesArray[$Index].volumes.Count; $Jndex++) {
		$DevicesArray[$Index].volumes[$Jndex] -match 'freeSpace=(\d+)' > $Null
		$FreeSpace = $Matches[1]
		
		$DevicesArray[$Index].volumes[$Jndex] -match 'capacity=(\d+)' > $Null
		$Capacity = $Matches[1]
		
		If ((($Capacity - $FreeSpace) / $Capacity) -gt 0.85) {
			$LowDevices.Add($DevicesArray[$Index].systemName)
		}
	}
}

$Raw = New-Object System.Collections.Generic.List[System.Object]

ForEach ($DC in $Env["REMOTE_COMPUTERS"] -split ',') {
	$CDC = Invoke-Command -ComputerName $DC -ScriptBlock {
		Get-WinEvent -FilterHashtable @{LogName = 'Security'; Id = 4769} | Select-Object Message
	}
	
	ForEach ($Item in $CDC) {
		$Raw.Add($Item)
	}
}

$UserNames = New-Object System.Collections.Generic.List[System.Object]

ForEach ($UserBase in ($Env["USER_BASE"] -split ';')) {
	$Users = Get-ADUser -Filter * -SearchBase $UserBase | Select-Object -ExpandProperty SamAccountName
	ForEach ($User in $Users) {
		$UserNames.Add($User)
	}
}

$ComputerNames = @(Get-ADComputer -Filter * -SearchBase $Env["COMPUTER_BASE"] | Select-Object -ExpandProperty Name)
$UserDeviceMap = @{}

ForEach ($Output in $Raw) {	
	$Output -match 'Account Name:\s*(\S+)' > $Null
	$AccountName = (($Matches[1] -split '@')[0]).Replace('$', '')
	
	$Output -match 'Service Name:\s*(\S+)' > $Null
	$DeviceName = $Matches[1].Replace('$', '')
	
	If ($LowDevices -notcontains $DeviceName) {
		Continue
	}
	
	$EmptyList = New-Object System.Collections.Generic.List[System.Object]
	
	If (($UserDeviceMap.Keys -notcontains $DeviceName) -and ($ComputerNames -contains $DeviceName)) {
		$UserDeviceMap.Add($DeviceName, $EmptyList)
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
#
<#
.Synopsis
    WebAutomation class managed module-level variables
.Description
    Provides access to hash tables Credentials and TempCurls
#>
class WebAutomation {
    static [hashtable] $Credentials = @{}
    static [hashtable] $TempCurls = @{}
}

<#
.Synopsis
    Makes a cURL command available to use with Get-CurlCommand and Invoke-AutoRequest
.Description
    Given a site name and action, adds provided cURL command to either curls.dat or the TempCurls hash table.
.Example
    'curl "https://...' | Add-AutoCurl -Action 'AddRow' -Permanent
.Parameter Action
    The action name (cannot contain an equal sign).
.Parameter Command
    The raw curl command copied and pasted from Firefox's Inspect Element > Network pane.
.Parameter DataDir
    The directory to contain the files curls.dat and cookies.txt. Defaults to Documents.
.Parameter Permanent
    Set this switch to add the command to curls.dat. Default behavior is to add to TempCurls hash table.
#>
filter Add-AutoCurl {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Action,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $Command,
        [string] $DataDir = "$env:USERPROFILE\Documents",
        [switch] $Permanent
    )
    # Error if duplicate site and action
    if ((Get-AutoCurl -Action $Action -DataDir $DataDir).Count -gt 0) {
        throw "A command for $Action is already defined."
    }
    if ($Permanent) {
        Add-Content -Path "$DataDir\curls.dat" -Value "$Action = $Command" | Out-Null
    } else {
        [WebAutomation]::TempCurls = @{$Action=$Command} + [WebAutomation]::TempCurls
    }
}

<#
.Synopsis
    Clears all cURL commands and credentials from temporary storage
#>
function Clear-TempAutoData {
    [CmdletBinding()]
    param (
        [string] $DataDir = "$env:USERPROFILE\Documents"
    )
    [WebAutomation]::TempCurls = @{}
    [WebAutomation]::Credentials = @{}
    if (Test-Path -Path "$DataDir\cookies.txt") { Remove-Item -Path "$DataDir\cookies.txt" }
}

<#
.Synopsis
    Retrieves properly sanitized cURL commands
.Description
    Retrieves all cURL commands in curls.dat and the TempCurls hash table. Before returning, sanitizes the headers
    and updates the cookie, if applicable.
.Parameter Action
    The action name (cannot contain equal signs). Can contain wildcards.
.Parameter DataDir
    The directory to contain the files curls.dat and cookies.txt. Defaults to Documents.
#>
filter Get-AutoCurl {
    [CmdletBinding()]
    param (
        [string] $Action = '*',
        [string] $DataDir = "$env:USERPROFILE\Documents"
    )
    # Put together object array of all cURL commands
    try {
        $FileCurlsHash = (Get-Content -Path "$DataDir\curls.dat") -join "`n" | ConvertFrom-StringData
    } catch [System.Management.Automation.ItemNotFoundException] {
        $FileCurlsHash = @{}
    }
    $Curls = [WebAutomation]::TempCurls + $FileCurlsHash
    $ProcCurls = @{}
    # Process each raw cURL command
    foreach ($Key in $Curls.Keys) {
        if ($Key -like $Action) {
            # Strip cookie
            $ProcCurls[$Key] = $Curls[$Key] -replace ' -H "Cookie:[^"]*"',''
            # Strip NTLM authorization
            $ProcCurls[$Key] = $ProcCurls[$Key] -replace ' -H "Authorization: NTLM [^"]*"',''
            # Process nested quotes
            $ProcCurls[$Key] = $ProcCurls[$Key] -replace '(?<!(`| -H |" --\w+ |^curl ))"(?!( -H | --|$))','`"'
            $ProcCurls[$Key] = $ProcCurls[$Key] -replace '(?<!`)\$','`$'
            # Add curl params
            $ProcCurls[$Key] = $ProcCurls[$Key] -replace '^curl ',
                "curl --silent --include --cookie '$DataDir\cookies.txt' --cookie-jar '$DataDir\cookies.txt' "
        }
    }
    return $ProcCurls
}

<#
.Synopsis
    Performs web request with a cURL as a template
.Description
    Retrieves a cURL command via Get-AutoCurl, updates its --data with contents of provided hash table, and
    invokes the request. Returns response as a custom object with Header and Body properties.
.Parameter Action
    The action name (cannot contain equal signs). Can contain wildcards.
.Parameter Data
    The hash table of keys and values which replace the corresponding keys/values in the --data string
.Parameter DataDir
    The directory to contain the files curls.dat and cookies.txt. Defaults to Documents.
.Parameter Ntlm
    Set this switch to use NLTM authentication. Requires username and password to be provided in the data.
.Parameter WhatIf
    Set this switch to just print the cURL about to be invoked instead of invoking it
#>
function Invoke-AutoRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Action,
        [Parameter(ValueFromPipeline=$true)]
        [hashtable] $Data,
        [string] $DataDir = "$env:USERPROFILE\Documents",
        [switch] $Ntlm,
        [switch] $WhatIf
    )
    begin {
        # Get the first matching command
        $CurlCommand = ([String[]](Get-AutoCurl -Action:$Action -DataDir:$DataDir).Values)[0]
	# Throw error if the command is null
	if ($CurlCommand -eq $null) { throw "No cURL command found for action '$Action'" }
    }
    process {
        # Replace the data
        $DataRegex =  '(?<=--data ").*(?="$)'
        $CurlCommand -Match $DataRegex | Out-Null
        if ($Matches -ne $null) {
            $DataString = $Matches[0]
            foreach ($Key in $Data.Keys) {
                $DataString = $DataString -replace "(?<=$Key=).*?(?=(&|$))", [uri]::EscapeDataString($Data[$Key])
            }
            $CurlCommand = $CurlCommand -replace $DataRegex,($DataString -replace '(?<!`)"','`"')
        }
        if ($Ntlm) {
            $CurlCommand = $CurlCommand -replace '^curl ',
                "curl --ntlm --user $($Data['username']):$($Data['password']) "
        }
        if ($WhatIf) {
            $CurlCommand
        } else {
            # Invoke the command
            $Response = Invoke-Expression -Command $CurlCommand
            # Convert response to object
            $ResponseObject = New-Object -TypeName PSCustomObject
            $ResponseObject | Add-Member -MemberType NoteProperty -Name Header -Value `
                $Response[0..($Response.IndexOf('')-1)]
            $ResponseObject | Add-Member -MemberType NoteProperty -Name Body -Value $Response[`
                ($Response.IndexOf('')+1)..($Response.Length-1)]
            # Return the response object
            $ResponseObject
	}
    }
}

<#
.Synopsis
    Adds login credentials to a data hashtable
.Description
    Given an arbitrary site name, looks up the username and password for that site in memory, and appends them to
    the provided hash table. If the username and password are not found, prompts the user for them.
.Parameter Site
    The site name - must be a valid hashtable key name
.Parameter Data
    The data to append the username and password to
#>
filter Add-Credentials {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Site,
        [Parameter(ValueFromPipeline=$true)]
        [hashtable] $Data
    )
    # Prompt for credentials if not already stored
    if ([WebAutomation]::Credentials[$Site] -eq $null) {
        [WebAutomation]::Credentials[$Site] = Get-Credential -Message "Please enter $Site credentials:"
    }
    # Return the updated data
    return $Data + @{username=[WebAutomation]::Credentials[$Site].UserName;
        password=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        [WebAutomation]::Credentials[$Site].Password))}
}

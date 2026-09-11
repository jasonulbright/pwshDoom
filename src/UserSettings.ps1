# SPDX-License-Identifier: GPL-2.0-or-later
# Input preferences are separate from saved worlds and recorded tic commands.
function New-DoomUserSettings { return @{Version=1;AlwaysRun=$false;TurnSpeed=100} }
function Copy-DoomUserSettings {
    param($Settings)
    if($Settings -isnot [Collections.IDictionary] -and $Settings -is [pscustomobject]){$fields=@{};foreach($property in $Settings.PSObject.Properties){$fields[$property.Name]=$property.Value};$Settings=$fields}
    if($Settings -isnot [Collections.IDictionary] -or $Settings.Count -ne 3 -or
        -not $Settings.Contains('Version') -or -not $Settings.Contains('AlwaysRun') -or -not $Settings.Contains('TurnSpeed')){throw 'Invalid settings fields.'}
    if(($Settings.Version -isnot [int] -and $Settings.Version -isnot [long]) -or $Settings.Version -ne 1 -or
        $Settings.AlwaysRun -isnot [bool] -or ($Settings.TurnSpeed -isnot [int] -and $Settings.TurnSpeed -isnot [long]) -or
        $Settings.TurnSpeed -notin 50,100,150){throw 'Unsupported settings values.'}
    return @{Version=1;AlwaysRun=[bool]$Settings.AlwaysRun;TurnSpeed=[int]$Settings.TurnSpeed}
}
function Read-DoomUserSettings {
    param([Parameter(Mandatory)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path)){return @{Values=(New-DoomUserSettings);Sha256=$null}}
    if((Get-Item -LiteralPath $Path).Length -gt 4096){throw 'Settings file is too large.'}
    $bytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
    if($bytes.Length -gt 4096){throw 'Settings file is too large.'}
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xfeff)
    $values=Copy-DoomUserSettings ($json|ConvertFrom-Json -AsHashtable -Depth 4)
    return @{Values=$values;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}
function Write-DoomUserSettings {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Settings,[AllowNull()][string]$ExpectedHash)
    $values=Copy-DoomUserSettings $Settings
    $current=Read-DoomUserSettings $Path
    if([string]$current.Sha256 -cne [string]$ExpectedHash){throw 'Settings changed on disk; restart before saving.'}
    $destination=[IO.Path]::GetFullPath($Path);$directory=[IO.Path]::GetDirectoryName($destination)
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary=Join-Path $directory ('.settings-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(([ordered]@{Version=1;AlwaysRun=$values.AlwaysRun;TurnSpeed=$values.TurnSpeed}|ConvertTo-Json))
    try{
        [IO.File]::WriteAllBytes($temporary,$bytes)
        # Publish a complete file in the same directory. Refuse an unexpected file
        # when creating; the hash check above also detects observed stale editors.
        [IO.File]::Move($temporary,$destination,[bool]$ExpectedHash)
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

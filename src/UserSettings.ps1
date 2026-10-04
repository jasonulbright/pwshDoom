# SPDX-License-Identifier: GPL-2.0-or-later
# Preferences are separate from saved worlds and recorded tic commands.
function New-DoomKeyBindings {
    return [ordered]@{Forward=87;Backward=83;StrafeLeft=65;StrafeRight=68;TurnLeft=37;TurnRight=39;Fire=17;Use=69;Run=16}
}
function Get-DoomKeyBindingNames {
    return @('Forward','Backward','StrafeLeft','StrafeRight','TurnLeft','TurnRight','Fire','Use','Run')
}
function Get-DoomReservedBindingKeys {
    return [int[]]@(9,13,16,19,27,32,37,38,39,40,43,45,49,50,51,52,53,54,55,67,70,77,78,80,89,107,109,112,113,114,121,187,189)
}
function Get-DoomKeyBindingLabel {
    param([int]$VirtualKey)
    if($VirtualKey -ge 48 -and $VirtualKey -le 57){return [string][char]$VirtualKey}
    if($VirtualKey -ge 65 -and $VirtualKey -le 90){return [string][char]$VirtualKey}
    if($VirtualKey -ge 112 -and $VirtualKey -le 123){return 'F'+($VirtualKey-111)}
    switch($VirtualKey){
        16 {return 'SHIFT'}
        17 {return 'CTRL'}
        18 {return 'ALT'}
        32 {return 'SPACE'}
        37 {return 'LEFT'}
        38 {return 'UP'}
        39 {return 'RIGHT'}
        40 {return 'DOWN'}
        8 {return 'BACKSPACE'}
        43 {return 'PLUS'}
        45 {return 'MINUS'}
        96 {return 'NUM0'}
        97 {return 'NUM1'}
        98 {return 'NUM2'}
        99 {return 'NUM3'}
        100 {return 'NUM4'}
        101 {return 'NUM5'}
        102 {return 'NUM6'}
        103 {return 'NUM7'}
        104 {return 'NUM8'}
        105 {return 'NUM9'}
        106 {return 'NUM MULTIPLY'}
        107 {return 'NUM PLUS'}
        109 {return 'NUM MINUS'}
        110 {return 'NUM DECIMAL'}
        111 {return 'NUM DIVIDE'}
        186 {return 'SEMICOLON'}
        187 {return 'EQUALS'}
        188 {return 'COMMA'}
        189 {return 'HYPHEN'}
        190 {return 'PERIOD'}
        191 {return 'SLASH'}
        192 {return 'BACKTICK'}
        219 {return 'LEFT BRACKET'}
        220 {return 'BACKSLASH'}
        221 {return 'RIGHT BRACKET'}
        222 {return 'QUOTE'}
        default {return "VK $VirtualKey"}
    }
}
function New-DoomUserSettings { return @{Version=4;AlwaysRun=$false;TurnSpeed=100;SoundVolume=100;MusicVolume=100;SoundMuted=$false;Bindings=(New-DoomKeyBindings)} }
function Copy-DoomUserSettings {
    param($Settings)
    if($Settings -isnot [Collections.IDictionary] -and $Settings -is [pscustomobject]){$fields=@{};foreach($property in $Settings.PSObject.Properties){$fields[$property.Name]=$property.Value};$Settings=$fields}
    if($Settings -is [Collections.IDictionary] -and $Settings.Contains('Bindings') -and $Settings.Bindings -isnot [Collections.IDictionary] -and $Settings.Bindings -is [pscustomobject]){$fields=@{};foreach($property in $Settings.Bindings.PSObject.Properties){$fields[$property.Name]=$property.Value};$Settings.Bindings=$fields}
    if($Settings -isnot [Collections.IDictionary] -or
        -not $Settings.Contains('Version') -or -not $Settings.Contains('AlwaysRun') -or -not $Settings.Contains('TurnSpeed')){throw 'Invalid settings fields.'}
    if(($Settings.Version -isnot [int] -and $Settings.Version -isnot [long]) -or $Settings.Version -notin 1,2,3,4 -or
        $Settings.AlwaysRun -isnot [bool] -or ($Settings.TurnSpeed -isnot [int] -and $Settings.TurnSpeed -isnot [long]) -or
        $Settings.TurnSpeed -notin 50,100,150){throw 'Unsupported settings values.'}
    if($Settings.Version -eq 1){
        if($Settings.Count -ne 3){throw 'Invalid legacy settings fields.'}
        return @{Version=4;AlwaysRun=[bool]$Settings.AlwaysRun;TurnSpeed=[int]$Settings.TurnSpeed;SoundVolume=100;MusicVolume=100;SoundMuted=$false;Bindings=(New-DoomKeyBindings)}
    }
    $expectedCount=switch($Settings.Version){2{5};3{6};4{7}}
    if($Settings.Count -ne $expectedCount -or -not $Settings.Contains('SoundVolume') -or -not $Settings.Contains('SoundMuted') -or
        ($Settings.SoundVolume -isnot [int] -and $Settings.SoundVolume -isnot [long]) -or $Settings.SoundVolume -lt 0 -or $Settings.SoundVolume -gt 100 -or $Settings.SoundMuted -isnot [bool]){throw 'Invalid sound preferences.'}
    if($Settings.Version -eq 2){return @{Version=4;AlwaysRun=[bool]$Settings.AlwaysRun;TurnSpeed=[int]$Settings.TurnSpeed;SoundVolume=[int]$Settings.SoundVolume;MusicVolume=[int]$Settings.SoundVolume;SoundMuted=[bool]$Settings.SoundMuted;Bindings=(New-DoomKeyBindings)}}
    if($Settings.Version -eq 3){
        if(-not $Settings.Contains('MusicVolume') -or ($Settings.MusicVolume -isnot [int] -and $Settings.MusicVolume -isnot [long]) -or $Settings.MusicVolume -lt 0 -or $Settings.MusicVolume -gt 100){throw 'Invalid music volume preference.'}
        return @{Version=4;AlwaysRun=[bool]$Settings.AlwaysRun;TurnSpeed=[int]$Settings.TurnSpeed;SoundVolume=[int]$Settings.SoundVolume;MusicVolume=[int]$Settings.MusicVolume;SoundMuted=[bool]$Settings.SoundMuted;Bindings=(New-DoomKeyBindings)}
    }
    if(($Settings.MusicVolume -isnot [int] -and $Settings.MusicVolume -isnot [long]) -or $Settings.MusicVolume -lt 0 -or $Settings.MusicVolume -gt 100){throw 'Invalid music volume preference.'}
    if($Settings.Bindings -isnot [Collections.IDictionary] -or $Settings.Bindings.Count -ne 9){throw 'Invalid key binding preferences.'}
    $bindings=[ordered]@{};$defaults=New-DoomKeyBindings;$reserved=Get-DoomReservedBindingKeys
    foreach($name in Get-DoomKeyBindingNames){
        if(-not $Settings.Bindings.Contains($name)){throw 'Invalid key binding preferences.'}
        $key=$Settings.Bindings[$name]
        if(($key -isnot [int] -and $key -isnot [long]) -or $key -lt 1 -or $key -gt 255){throw "Invalid virtual key for $name."}
        if($key -in $reserved -and [int]$key -ne [int]$defaults[$name]){throw "Reserved virtual key for $name."}
        if($bindings.Values -contains [int]$key){throw 'Two game actions cannot share a key.'}
        $bindings[$name]=[int]$key
    }
    return @{Version=4;AlwaysRun=[bool]$Settings.AlwaysRun;TurnSpeed=[int]$Settings.TurnSpeed;SoundVolume=[int]$Settings.SoundVolume;MusicVolume=[int]$Settings.MusicVolume;SoundMuted=[bool]$Settings.SoundMuted;Bindings=$bindings}
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
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(([ordered]@{Version=4;AlwaysRun=$values.AlwaysRun;TurnSpeed=$values.TurnSpeed;SoundVolume=$values.SoundVolume;MusicVolume=$values.MusicVolume;SoundMuted=$values.SoundMuted;Bindings=$values.Bindings}|ConvertTo-Json -Depth 4))
    try{
        [IO.File]::WriteAllBytes($temporary,$bytes)
        # Publish a complete file in the same directory. Refuse an unexpected file
        # when creating; the hash check above also detects observed stale editors.
        [IO.File]::Move($temporary,$destination,[bool]$ExpectedHash)
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

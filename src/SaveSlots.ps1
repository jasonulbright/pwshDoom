# SPDX-License-Identifier: GPL-2.0-or-later
# Slot paths and metadata are shared by the host and simulation. Game graph
# reconstruction stays in the simulation process, where engine types exist.
function Get-DoomSaveDirectory {
    param([string]$Root,[string]$WadSha256)
    if($WadSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid save IWAD key.'}
    if(-not $Root){$Root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'pwshDoom/saves'}
    return [IO.Path]::GetFullPath((Join-Path $Root $WadSha256.ToUpperInvariant()))
}
function Get-DoomSlotPath {
    param([string]$Directory,[ValidateRange(1,6)][int]$Slot)
    return Join-Path $Directory ('slot-{0:d2}.pds' -f $Slot)
}
function Get-DoomReplaySavePath {
    param([string]$Directory,[string]$Sha256)
    if($Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid replay save key.'}
    return Join-Path $Directory ('replay/'+$Sha256.ToUpperInvariant()+'.pds')
}
function Get-DoomSlotSummaries {
    param([string]$Directory,[string]$WadSha256)
    $source=Get-DoomReplaySourceFingerprint
    return @(foreach($slot in 1..6){
        $path=Get-DoomSlotPath $Directory $slot
        $summary=@{Slot=$slot;State='Empty';Sha256=$null;Episode=0;Map=0;Skill=0;Time='';SourceMatches=$true}
        if(Test-Path -LiteralPath $path){
            $summary.State='Unavailable'
            try{
                if((Get-Item -LiteralPath $path).Length -gt 64MB){throw 'Save is too large.'}
                $bytes=[IO.File]::ReadAllBytes($path);$summary.Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
                $d=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -Depth 4
                if($d.Format -ne 'pwshDoom.SaveState' -or $d.Version -isnot [long] -or $d.Version -ne 1 -or $d.WadSha256 -ne $WadSha256 -or
                    $d.Episode -isnot [long] -or $d.Episode -lt 1 -or $d.Episode -gt 4 -or $d.Map -isnot [long] -or $d.Map -lt 1 -or $d.Map -gt 9 -or
                    $d.Skill -isnot [long] -or $d.Skill -lt 1 -or $d.Skill -gt 5 -or $d.EngineSourceFingerprint -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid slot metadata.'}
                $summary.Episode=[int]$d.Episode;$summary.Map=[int]$d.Map;$summary.Skill=[int]$d.Skill
                # ConvertFrom-Json may already have parsed a UTC DateTime.
                # Passing that value through Parse(string) discards its Kind.
                $created=if($d.CreatedUtc -is [datetime]){[datetimeoffset]$d.CreatedUtc}else{[datetimeoffset]::Parse($d.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture)}
                $summary.Time=$created.ToLocalTime().ToString('HH:mm')
                $summary.SourceMatches=$source -eq $d.EngineSourceFingerprint;$summary.State='Ready'
            }catch{$summary.State='Unavailable'}
        }
        $summary
    })
}
function Write-DoomSessionPayload {
    param($View,[long]$Offset,$Data)
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Data|ConvertTo-Json -Depth 8 -Compress))
    if($bytes.Length -gt 32764){throw 'Session payload exceeds its bounded channel.'}
    $View.Write($Offset,[int]$bytes.Length);$View.WriteArray($Offset+4,$bytes,0,$bytes.Length)
}
function Read-DoomSessionPayload {
    param($View,[long]$Offset)
    $length=$View.ReadInt32($Offset)
    if($length -lt 2 -or $length -gt 32764){throw 'Invalid session payload length.'}
    $bytes=[byte[]]::new($length);[void]$View.ReadArray($Offset+4,$bytes,0,$length)
    return ([Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -Depth 8)
}

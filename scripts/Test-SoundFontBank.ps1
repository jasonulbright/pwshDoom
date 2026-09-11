#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SoundFontBank.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Bytes-Join([object[]]$Parts){$result=[Collections.Generic.List[byte]]::new();foreach($part in $Parts){$result.AddRange([byte[]]$part)};return ,$result.ToArray()}
function Chunk([string]$Name,[byte[]]$Data){
    $parts=@([Text.Encoding]::ASCII.GetBytes($Name),[BitConverter]::GetBytes([uint32]$Data.Length),$Data)
    if($Data.Length%2){$parts+=,([byte[]]@(0))};return ,(Bytes-Join $parts)
}
function Set-U16([byte[]]$Data,[int]$Offset,[uint16]$Value){[BitConverter]::GetBytes($Value).CopyTo($Data,$Offset)}
function Set-U32([byte[]]$Data,[int]$Offset,[uint32]$Value){[BitConverter]::GetBytes($Value).CopyTo($Data,$Offset)}
function Table-Offset([byte[]]$Data,[string]$Name){return [Text.Encoding]::ASCII.GetString($Data).IndexOf($Name,[StringComparison]::Ordinal)+8}
function Fixture {
    $phdr=[byte[]]::new(76);$phdr[0]=80;Set-U16 $phdr 20 7;Set-U16 $phdr 22 128;Set-U16 $phdr 62 1
    $inst=[byte[]]::new(44);$inst[0]=73;Set-U16 $inst 42 1
    $bag=[byte[]]@(0,0,0,0,1,0,0,0)
    $pgen=[byte[]]@(41,0,0,0,0,0,0,0);$igen=[byte[]]@(53,0,0,0,0,0,0,0)
    $shdr=[byte[]]::new(92);$shdr[0]=83;Set-U32 $shdr 24 48;Set-U32 $shdr 28 8;Set-U32 $shdr 32 40;Set-U32 $shdr 36 22050
    $shdr[40]=60;$shdr[41]=252;Set-U16 $shdr 44 1
    $samples=[byte[]]::new(188);([byte[]]@(0,128,255,255,0,0,1,0,255,127)).CopyTo($samples,0)
    $info=Chunk 'LIST' (Bytes-Join @([Text.Encoding]::ASCII.GetBytes('INFO'),(Chunk 'ifil' ([byte[]]@(2,0,1,0))),(Chunk 'INAM' ([byte[]]@(84,101,115,116,0))),(Chunk 'xtra' ([byte[]]@(1,2,3)))))
    $sdta=Chunk 'LIST' (Bytes-Join @([Text.Encoding]::ASCII.GetBytes('sdta'),(Chunk 'smpl' $samples)))
    $pdta=Chunk 'LIST' (Bytes-Join @([Text.Encoding]::ASCII.GetBytes('pdta'),(Chunk 'phdr' $phdr),(Chunk 'pbag' $bag),(Chunk 'pmod' ([byte[]]::new(10))),(Chunk 'pgen' $pgen),(Chunk 'inst' $inst),(Chunk 'ibag' $bag),(Chunk 'imod' ([byte[]]::new(10))),(Chunk 'igen' $igen),(Chunk 'shdr' $shdr)))
    return ,(Chunk 'RIFF' (Bytes-Join @([Text.Encoding]::ASCII.GetBytes('sfbk'),$info,$sdta,$pdta)))
}
try{
    $bytes=Fixture;$bank=ConvertFrom-DoomSoundFont $bytes
    Check 'Independent signed little-endian PCM vector' (($bank.Samples[0..4] -join ',') -ceq '-32768,-1,0,1,32767')
    Check 'Version, odd INFO padding and unknown INFO chunk' ($bank.Version[0] -eq 2 -and $bank.Version[1] -eq 1 -and $bank.Info.INAM -ceq 'Test')
    Check 'Independent preset to instrument to sample chain' ($bank.Tables.phdr[0].Program -eq 7 -and $bank.Tables.phdr[0].Bank -eq 128 -and $bank.Tables.pgen[0][0] -eq 41 -and $bank.Tables.igen[0][0] -eq 53 -and $bank.Tables.shdr[0].Name -ceq 'S')
    $s=$bank.Tables.shdr[0]
    Check 'Loop endpoints, source rate and signed pitch correction' ($s.Start -eq 0 -and $s.End -eq 48 -and $s.LoopStart -eq 8 -and $s.LoopEnd -eq 40 -and $s.Rate -eq 22050 -and $s.Correction -eq -4)
    foreach($case in 'short','signature','riffsize','chunkoverflow','version','tablewidth','missingtable','headerterminal','bagterminal','instrumentreference','samplereference','sampleend','looporder','zerorate','rom','stereolink','oddpcm'){
        $bad=$bytes.Clone()
        switch($case){
            short {$bad=[byte[]]::new(11)}
            signature {$bad[8]=0}
            riffsize {Set-U32 $bad 4 ($bad.Length-9)}
            chunkoverflow {Set-U32 $bad ((Table-Offset $bad 'xtra')-4) ([uint32]::MaxValue)}
            version {Set-U16 $bad (Table-Offset $bad 'ifil') 3}
            tablewidth {Set-U32 $bad ((Table-Offset $bad 'phdr')-4) 75}
            missingtable {$bad[(Table-Offset $bad 'pgen')-8]=120}
            headerterminal {Set-U16 $bad ((Table-Offset $bad 'phdr')+62) 0}
            bagterminal {Set-U16 $bad ((Table-Offset $bad 'pbag')+4) 0}
            instrumentreference {Set-U16 $bad ((Table-Offset $bad 'pgen')+2) 1}
            samplereference {Set-U16 $bad ((Table-Offset $bad 'igen')+2) 1}
            sampleend {Set-U32 $bad ((Table-Offset $bad 'shdr')+24) 1000}
            looporder {Set-U32 $bad ((Table-Offset $bad 'shdr')+28) 41}
            zerorate {Set-U32 $bad ((Table-Offset $bad 'shdr')+36) 0}
            rom {Set-U16 $bad ((Table-Offset $bad 'shdr')+44) 32769}
            stereolink {Set-U16 $bad ((Table-Offset $bad 'shdr')+44) 2;Set-U16 $bad ((Table-Offset $bad 'shdr')+42) 1}
            oddpcm {Set-U32 $bad ((Table-Offset $bad 'smpl')-4) 187}
        }
        $rejected=$false;try{$null=ConvertFrom-DoomSoundFont $bad}catch{$rejected=$true};Check "Reject malformed/unsupported $case" $rejected
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/SoundFontBank.ps1','scripts/Test-SoundFontBank.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent synthetic SF2 container, PCM and table values; malformed structure rejection. No synthesis or general SoundFont compliance claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) SoundFont reader checks."

#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SoundFontRegions.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Fixture {
    $pgen=@([int[]]@(43,25640),[int[]]@(48,20),[int[]]@(43,20530),[int[]]@(44,30730),[int[]]@(48,30),[int[]]@(52,5),[int[]]@(41,0),[int[]]@(43,28260),[int[]]@(41,0),[int[]]@(0,0))
    $igen=@([int[]]@(43,19230),[int[]]@(48,100),[int[]]@(34,64336),[int[]]@(43,16680),[int[]]@(44,25620),[int[]]@(48,200),[int[]]@(1,65535),[int[]]@(2,1),[int[]]@(3,65535),[int[]]@(58,61),[int[]]@(54,3),[int[]]@(52,65533),[int[]]@(53,0),[int[]]@(43,23100),[int[]]@(48,300),[int[]]@(53,0),[int[]]@(0,0))
    return @{SourceSha256='synthetic';Samples=[int16[]]::new(32);Tables=@{
        phdr=@(@{Name='Preset';Bank=0;Program=7;Bag=0},@{Name='EOP';Bank=0;Program=0;Bag=3});
        inst=@(@{Name='Instrument';Bag=0},@{Name='EOI';Bag=3});
        pbag=@([int[]]@(0,0),[int[]]@(2,1),[int[]]@(7,2),[int[]]@(9,2));pgen=$pgen;
        pmod=@([int[]]@(2,48,10,0,0),[int[]]@(2,48,20,0,0),[int[]]@(0,0,0,0,0));
        ibag=@([int[]]@(0,0),[int[]]@(3,1),[int[]]@(13,2),[int[]]@(16,2));igen=$igen;
        imod=@([int[]]@(2,48,100,0,0),[int[]]@(2,48,200,0,0),[int[]]@(0,0,0,0,0));
        shdr=@(@{Name='Sample';Start=2L;End=18L;LoopStart=6L;LoopEnd=14L;RootKey=60;Correction=-4;Rate=22050;Type=1;Link=0},@{Name='EOS'})
    }}
}
try{
    $inputBank=Fixture;$bank=ConvertTo-DoomSoundFontRegions $inputBank;$regions=Find-DoomSoundFontRegions $bank -Program 7 -Key 60 -Velocity 64;$r=$regions[0]
    Check 'Layering plus disjoint preset range exclusion' ($regions.Count -eq 2 -and $bank.Stats.EmptyIntersections -eq 2 -and $bank.Stats.Regions -eq 2)
    Check 'Local instrument overrides global and local preset adds once' ($r.Values[48] -eq 230 -and $regions[1].Values[48] -eq 330)
    Check 'Signed generators and inherited/default values' ($r.Values[52] -eq 2 -and $r.Values[34] -eq -1200 -and $r.Values[8] -eq 13500 -and $r.Values[56] -eq 100 -and $r.Values[46] -eq -1)
    Check 'Global key range replaced locally then intersected across levels' ($r.KeyLow -eq 50 -and $r.KeyHigh -eq 65 -and $regions[1].KeyHigh -eq 80)
    Check 'Velocity range intersection' ($r.VelocityLow -eq 20 -and $r.VelocityHigh -eq 100)
    Check 'Effective sample offsets and root override' ($r.Start -eq 2 -and $r.End -eq 17 -and $r.LoopStart -eq 7 -and $r.LoopEnd -eq 13 -and $r.LoopMode -eq 3 -and $r.RootKey -eq 61)
    Check 'Modulator local replacement retained separately at each level' ($r.InstrumentModulators.Count -eq 1 -and $r.InstrumentModulators[0][2] -eq 200 -and $r.PresetModulators.Count -eq 1 -and $r.PresetModulators[0][2] -eq 20)
    Check 'Input structures unchanged' ($inputBank.Tables.igen[5][1] -eq 200 -and $inputBank.Tables.pmod[0][2] -eq 10)
    Check 'Inclusive lower key and velocity endpoints' ((Find-DoomSoundFontRegions $bank -Program 7 -Key 50 -Velocity 20).Count -eq 1)
    Check 'Inclusive upper key and velocity endpoints' ((Find-DoomSoundFontRegions $bank -Program 7 -Key 65 -Velocity 100).Count -eq 2)
    Check 'Out of velocity range does not trigger split' ((Find-DoomSoundFontRegions $bank -Program 7 -Key 50 -Velocity 101).Count -eq 0)
    Check 'Out of key range is silent' ((Find-DoomSoundFontRegions $bank -Program 7 -Key 49 -Velocity 64).Count -eq 0)
    $rejected=$false;try{$null=Find-DoomSoundFontRegions $bank -Program 8}catch{$rejected=$true};Check 'Missing preset is explicit' $rejected
    $rejected=$false;try{$null=ConvertTo-DoomSoundFontRegions (Fixture) -MaxRegions 1}catch{$rejected=$true};Check 'Region expansion bound' $rejected
    $bad=Fixture;$bad.Tables.igen[6][1]=100;$rejected=$false;try{$null=ConvertTo-DoomSoundFontRegions $bad}catch{$rejected=$true};Check 'Effective end cannot escape sample pool' $rejected
    $bad=Fixture;$bad.Tables.igen[7][1]=20;$rejected=$false;try{$null=ConvertTo-DoomSoundFontRegions $bad}catch{$rejected=$true};Check 'Effective loop cannot escape sample span' $rejected
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/SoundFontRegions.ps1','scripts/Test-SoundFontRegions.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Synthetic independent region/generator/modulator precedence and boundary tests. Modulators are retained, not evaluated; no synthesis fidelity claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) region checks."

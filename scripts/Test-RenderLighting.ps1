#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle;. "$PSScriptRoot/../src/FastRenderer.ps1"
$sourceHash=(Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash
$lightingHash=(Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash
$content=$null;$failure=$null;$scaleChecks=0;$distanceChecks=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $screen=[DrawScreen]::new($content.Wad,320,200);$reference=[ThreeDRenderer]::new($content,$screen,7)
    $actual=New-FastLightingTables
    $maps=@($content.ColorMap.Data|ForEach-Object {[Convert]::ToBase64String($_)})
    for($level=0;$level -lt 16;$level++){
        for($i=0;$i -lt 48;$i++){
            $index=$actual.Scale[$level][$i]
            if($index -lt 0 -or $index -ge 32 -or $maps[$index] -cne [Convert]::ToBase64String($reference.diminishingScaleLight[$level][$i])){throw "Scale table differs at sector band $level, bin $i."}
            $scaleChecks++
        }
        for($i=0;$i -lt 128;$i++){
            $index=$actual.Distance[$level][$i]
            if($index -lt 0 -or $index -ge 32 -or $maps[$index] -cne [Convert]::ToBase64String($reference.diminishingZLight[$level][$i])){throw "Distance table differs at sector band $level, bin $i."}
            $distanceChecks++
        }
    }
    "PASS: $scaleChecks scale bins and $distanceChecks distance bins match the adopted reference palettes."
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;ScaleChecks=$scaleChecks;DistanceChecks=$distanceChecks;ComparedPaletteBytes=256*($scaleChecks+$distanceChecks);
        RendererSha256=$sourceHash;LightingSha256=$lightingHash;RendererChangedDuringRun=($sourceHash -cne (Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash -or $lightingHash -cne (Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash);
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Every generated numeric lighting-table bin selects exactly the palette bytes generated independently by the adopted PowerShell ThreeDRenderer at a 320x168 view. This verifies the tables, not all rasterizer bin selection, original-executable fidelity or performance.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}

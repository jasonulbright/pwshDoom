#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../local/line-flags.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$checks=[Collections.Generic.List[object]]::new()
$vertices=[Vertex[]]@([Vertex]::new([Fixed]::Zero,[Fixed]::Zero),[Vertex]::new([Fixed]::FromInt(128),[Fixed]::Zero))
$sides=[SideDef[]]::new(1)
foreach($rawFlags in 0,1,3,255,511,512,32768,65025,65535) {
    $record=@{Raw16Bits=$rawFlags;Passed=$false;Error=$null}
    try {
        $bytes=[byte[]]::new(14);$bytes[2]=1;$bytes[4]=$rawFlags -band 255;$bytes[5]=$rawFlags -shr 8;$bytes[12]=255;$bytes[13]=255
        $line=[LineDef]::FromData($bytes,0,$vertices,$sides)
        if(([int]$line.Flags -band 65535) -ne $rawFlags){throw 'Raw flag bits were lost.'}
        foreach($mask in 1,2,4,8,16,32,64,128,256){if(($line.Flags -band $mask) -ne ($rawFlags -band $mask)){throw 'Known flag test changed.'}}
        $line.Flags=$line.Flags -bor [LineFlags]::Mapped
        if(([int]$line.Flags -band 65535) -ne ($rawFlags -bor 256)){throw 'Marking a line mapped lost unknown flag bits.'}
        $record.Passed=$true
    } catch {$record.Error=$_.ToString()}
    $checks.Add($record)
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output)))
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();LineDefSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/Map/LineDef.sb.ps1").Hash;
    Meaning='Synthetic LINEDEFS records test raw 16-bit flag preservation, recognized masks, and setting the automap Mapped bit while retaining unknown bits. No IWAD assets included.'} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Output
if(@($checks | Where-Object {-not $_.Passed}).Count){throw 'Line flag cases failed; see the saved report.'}
"PASS: $($checks.Count) line flag bitfield cases."

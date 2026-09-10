# SPDX-License-Identifier: GPL-2.0-or-later
# Assemble PowerShell classes in one compilation unit for circular references.
[CmdletBinding()]
param(
    [string]$SourceRoot=(Join-Path $PSScriptRoot '../src/ManagedDoom'),
    [string]$Output=(Join-Path $PSScriptRoot '../local/engine-bundle.ps1')
)
$ErrorActionPreference='Stop'
$files=@(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter '*.ps1' | Sort-Object FullName)
if(-not $files.Count){throw 'No engine source files found.'}
$owners=@{};$sourceText=@{};$baseTypes=@{}
foreach($file in $files){
    $sourceText[$file.FullName]=[IO.File]::ReadAllText($file.FullName)
    foreach($definition in [regex]::Matches($sourceText[$file.FullName],'(?m)^\s*(?:class|enum)\s+(\w+)')){
        $owners[$definition.Groups[1].Value]=$file.FullName
    }
    $baseTypes[$file.FullName]=@([regex]::Matches($sourceText[$file.FullName],'(?m)^\s*class\s+\w+\s*:\s*([\w.]+)') | ForEach-Object {$_.Groups[1].Value})
}
$orderedFiles=[Collections.Generic.List[object]]::new();$emitted=@{}
while($orderedFiles.Count -lt $files.Count){
    $progress=$false
    foreach($file in $files){
        if($emitted.ContainsKey($file.FullName)){continue}
        $ready=$true
        foreach($base in $baseTypes[$file.FullName]){
            if($owners.ContainsKey($base) -and $owners[$base] -ne $file.FullName -and -not $emitted.ContainsKey($owners[$base])){$ready=$false;break}
        }
        if($ready){$orderedFiles.Add($file);$emitted[$file.FullName]=$true;$progress=$true}
    }
    if(-not $progress){throw 'Circular inheritance between engine source files.'}
}
$pieces=[Collections.Generic.List[string]]::new()
$pieces.Add('# Generated from the attributed GPL PowerShell source in src/ManagedDoom. Do not edit this cache.')
foreach($file in $orderedFiles){
    $pieces.Add("# Source: $([IO.Path]::GetRelativePath($SourceRoot,$file.FullName))")
    $pieces.Add($sourceText[$file.FullName])
}
$text=[string]::Join("`n",$pieces)
$parseTokens=$null;$parseIssues=$null
$null=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$parseTokens,[ref]$parseIssues)
if($parseIssues.Count){throw ($parseIssues | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" } | Out-String)}
$destination=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
[IO.File]::WriteAllText($destination,$text,[Text.UTF8Encoding]::new($false))
return $destination

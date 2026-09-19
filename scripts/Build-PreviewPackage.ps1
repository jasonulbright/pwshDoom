#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9.]+$')][string]$Version='0.1.0-preview.2',
    [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh package output directory.'}
$name='pwshDoom-'+$Version;$stage=Join-Path $output $name
[void][IO.Directory]::CreateDirectory($stage)
$files=[Collections.Generic.List[string]]::new()
foreach($path in 'Play.cmd','Play.ps1','Start-Doom.ps1','README.md','LICENSE','THIRD-PARTY-NOTICES.md','CHANGELOG.md'){$files.Add($path)}
foreach($directory in 'src','scripts','docs'){
    foreach($file in Get-ChildItem (Join-Path $root $directory) -Recurse -File){
        $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        if($file.Extension -notin '.ps1','.md','.json','.txt'){throw "Unexpected package input: $relative"}
        $files.Add($relative)
    }
}
$manifest=[Collections.Generic.List[object]]::new()
foreach($relative in ($files|Sort-Object)){
    $source=Join-Path $root $relative;$target=Join-Path $stage $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath $source -Destination $target
    $manifest.Add([ordered]@{Path=$relative;Bytes=(Get-Item -LiteralPath $target).Length;Sha256=(Get-FileHash -LiteralPath $target).Hash})
}
$commit=(& git -C $root rev-parse HEAD).Trim();if($LASTEXITCODE){throw 'Cannot identify source commit.'}
$dirty=@(& git -C $root status --porcelain).Count -gt 0
[ordered]@{Version=$Version;SourceCommit=$commit;WorkingTreeDirty=$dirty;Files=$manifest.ToArray();
    Meaning='Source-inclusive preview. Per-file hashes identify the packaged working tree; SourceCommit alone is insufficient when WorkingTreeDirty is true. No game assets, tools, local reports or recordings are included.'}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $stage 'package-manifest.json')
$zip=Join-Path $output ($name+'.zip');Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal
$hash=(Get-FileHash -LiteralPath $zip).Hash
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'),$hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zip)+"`n")
[pscustomobject]@{Zip=$zip;Sha256=$hash;Files=$manifest.Count;Bytes=(Get-Item $zip).Length;SourceCommit=$commit;WorkingTreeDirty=$dirty}

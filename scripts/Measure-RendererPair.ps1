#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Baseline,[Parameter(Mandatory)][string]$Output,
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,9)][int]$Map=1,[ValidateRange(2,20)][int]$Rounds=4,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$candidate="$PSScriptRoot/../src/FastRenderer.ps1"
$baselineHash=(Get-FileHash $Baseline).Hash;$candidateHash=(Get-FileHash $candidate).Hash
$lightingHash=(Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash
$tokens=$null;$errors=$null;$functions=@{}
foreach($path in $Baseline,$candidate){
    $ast=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($path),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Renderer parse failed.'}
    $mapFunctions=@{};foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){$mapFunctions[$f.Name]=$f.Body.Extent.Text.Replace("`r`n","`n")}
    $functions[$path]=$mapFunctions
}
foreach($name in $functions[$Baseline].Keys){
    if($name -notin @('Invoke-FastRender','New-FastRenderContext') -and $functions[$Baseline][$name] -cne $functions[$candidate][$name]){throw "Shared helper differs: $name. Use isolated runtimes for that comparison."}
}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle;. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null;$failure=$null;$samples=[Collections.Generic.List[object]]::new();$summary=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,$Episode,$Map);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    . $Baseline;$old=New-FastRenderContext $content $game.World;$oldRender=${function:Invoke-FastRender}
    . $candidate;$new=New-FastRenderContext $content $game.World;$newRender=${function:Invoke-FastRender}
    for($round=0;$round -lt $Rounds;$round++){
        foreach($angle in 0,37,90,180,270){
            $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=$angle*[Math]::PI/180
            Set-GameRenderSnapshot $old $snapshot;Set-GameRenderSnapshot $new $snapshot
            $order=if($round%2 -eq 0){@('Baseline','Candidate')}else{@('Candidate','Baseline')}
            foreach($version in $order){
                $ctx=if($version -eq 'Baseline'){$old}else{$new};$render=if($version -eq 'Baseline'){$oldRender}else{$newRender}
                $watch=[Diagnostics.Stopwatch]::StartNew();& $render $ctx;$watch.Stop()
                $samples.Add(@{Round=$round;Angle=$angle;Version=$version;First=($version -ceq $order[0]);Milliseconds=$watch.Elapsed.TotalMilliseconds;Profile=$ctx.Profile})
            }
        }
    }
    $summary=@{};foreach($version in 'Baseline','Candidate'){$summary[$version]=Get-SampleStats @($samples|Where-Object Version -eq $version|ForEach-Object {$_.Milliseconds})}
    $summary|ConvertTo-Json -Depth 4
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Episode=$Episode;Map=$Map;Rounds=$Rounds;Samples=$samples.ToArray();Summary=$summary;BaselineSha256=$baselineHash;CandidateSha256=$candidateHash;
      LightingSha256=$lightingHash;SourcesChangedDuringRun=($baselineHash -cne (Get-FileHash $Baseline).Hash -or $candidateHash -cne (Get-FileHash $candidate).Hash -or $lightingHash -cne (Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash);
      BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Alternating-order serial full-frame renders at five static map headings. Every timed call retained, including first calls; no warm-up exclusion. Shared helper bodies must match; each renderer has its own context. Context construction and snapshot setup are outside timed calls. Not live simulation, audio, worker scaling, encoding, terminal output or displayed FPS.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}

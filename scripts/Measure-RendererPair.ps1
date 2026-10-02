#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Baseline,[Parameter(Mandatory)][string]$Output,
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,9)][int]$Map=1,[ValidateRange(2,20)][int]$Rounds=4,
    [string]$CandidateRenderer="$PSScriptRoot/../src/FastRenderer.ps1",[switch]$Abba,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$candidate=$CandidateRenderer
$baselineHash=(Get-FileHash $Baseline).Hash;$candidateHash=(Get-FileHash $candidate).Hash
$lightingHash=(Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash
$gameHostPath=[IO.Path]::GetFullPath("$PSScriptRoot/../src/GameHost.ps1")
$gameHostHash=(Get-FileHash $gameHostPath).Hash
$tokens=$null;$errors=$null
foreach($path in $Baseline,$candidate){
    $ast=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($path),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Renderer parse failed.'}
}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle;. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameHost.ps1"
$baselineModule=$null;$candidateModule=$null;$content=$null;$failure=$null;$samples=[Collections.Generic.List[object]]::new();$summary=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,$Episode,$Map);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    $baselinePath=[IO.Path]::GetFullPath($Baseline);$candidatePath=[IO.Path]::GetFullPath($candidate)
    $baselineModule=New-Module -Name ('PwshDoomBaselineRenderer_'+[guid]::NewGuid().ToString('N')) -ArgumentList $baselinePath,$gameHostPath -ScriptBlock {
        param($RendererPath,$GameHostPath)
        . $RendererPath
        . $GameHostPath
        Export-ModuleMember -Function Invoke-FastRender,New-FastRenderContext
    }
    $candidateModule=New-Module -Name ('PwshDoomCandidateRenderer_'+[guid]::NewGuid().ToString('N')) -ArgumentList $candidatePath,$gameHostPath -ScriptBlock {
        param($RendererPath,$GameHostPath)
        . $RendererPath
        . $GameHostPath
        Export-ModuleMember -Function Invoke-FastRender,New-FastRenderContext
    }
    $old=& $baselineModule {param($Content,$World) New-FastRenderContext $Content $World} $content $game.World
    $new=& $candidateModule {param($Content,$World) New-FastRenderContext $Content $World} $content $game.World
    for($round=0;$round -lt $Rounds;$round++){
        foreach($angle in 0,37,90,180,270){
            $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=$angle*[Math]::PI/180
            & $baselineModule {param($Context,$Snapshot) Set-GameRenderSnapshot $Context $Snapshot} $old $snapshot
            & $candidateModule {param($Context,$Snapshot) Set-GameRenderSnapshot $Context $Snapshot} $new $snapshot
            $order=if($Abba){@('Baseline','Candidate','Candidate','Baseline')}elseif($round%2 -eq 0){@('Baseline','Candidate')}else{@('Candidate','Baseline')}
            $position=0
            foreach($version in $order){
                $ctx=if($version -eq 'Baseline'){$old}else{$new}
                $watch=[Diagnostics.Stopwatch]::StartNew()
                if($version -eq 'Baseline'){
                    & $baselineModule {param($Context) Invoke-FastRender $Context} $ctx
                }else{
                    & $candidateModule {param($Context) Invoke-FastRender $Context} $ctx
                }
                $watch.Stop()
                $samples.Add(@{Round=$round;Angle=$angle;Position=$position;Version=$version;First=($position -eq 0);Milliseconds=$watch.Elapsed.TotalMilliseconds;Profile=$ctx.Profile})
                $position++
            }
        }
    }
    $summary=@{};foreach($version in 'Baseline','Candidate'){$summary[$version]=Get-SampleStats @($samples|Where-Object Version -eq $version|ForEach-Object {$_.Milliseconds})}
    $summary|ConvertTo-Json -Depth 4
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    if($baselineModule){Remove-Module $baselineModule.Name -ErrorAction SilentlyContinue}
    if($candidateModule){Remove-Module $candidateModule.Name -ErrorAction SilentlyContinue}
    @{Error=$failure;Episode=$Episode;Map=$Map;Rounds=$Rounds;Abba=[bool]$Abba;IsolationMode='SeparatePowerShellModules';PowerShellVersion=$PSVersionTable.PSVersion.ToString();Samples=$samples.ToArray();Summary=$summary;BaselineSha256=$baselineHash;CandidateSha256=$candidateHash;
      LightingSha256=$lightingHash;SourcesChangedDuringRun=($baselineHash -cne (Get-FileHash $Baseline).Hash -or $candidateHash -cne (Get-FileHash $candidate).Hash -or $lightingHash -cne (Get-FileHash "$PSScriptRoot/../src/RenderLighting.ps1").Hash -or $gameHostHash -cne (Get-FileHash $gameHostPath).Hash);
      GameHostSha256=$gameHostHash;
      BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
      BaselinePath=[IO.Path]::GetFullPath($Baseline);CandidatePath=[IO.Path]::GetFullPath($candidate);
      Meaning='Serial full-frame renders at five static map headings; ABBA at each round/heading when Abba is true, otherwise alternating AB/BA. Baseline and candidate functions, including all private helpers, are loaded in separate PowerShell modules. Every timed call is retained, including first calls; no warm-up exclusion. Each renderer has its own context. Context construction and snapshot setup are outside timed calls. The per-call module-qualified command dispatch is included equally for both versions. Not live simulation, audio, worker scaling, encoding, terminal output or displayed FPS.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}

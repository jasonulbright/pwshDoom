#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output=(Join-Path $PSScriptRoot '../results/mobj-action-dispatch-checks.json'))
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh test receipt path.'}
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass,[object]$Expected,[object]$Actual){
    $checks.Add(@{Name=$Name;Pass=$Pass;Expected=$Expected;Actual=$Actual})
}
$rootPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$actionSource=Join-Path $rootPath 'src/ManagedDoom/Doom/Info/DoomInfo.MobjActions.ps1'
$stateSource=Join-Path $rootPath 'src/ManagedDoom/Doom/Info/DoomInfo.States.sb.ps1'
$mobjSource=Join-Path $rootPath 'src/ManagedDoom/Doom/World/Mobj.sb.ps1'
$dollar=[string][char]36
$methodPattern='(?m)^\s*\[void\]\s+(\w+)\('
$routePattern="(?m)^\s+'([^']+)'\s+\{\s+\$dollar"+'this\.(\w+)\('
$statePattern='\'+$dollar+'mobjActions\.(\w+)'
$actionText=[IO.File]::ReadAllText($actionSource)
$routerText=$actionText.Substring($actionText.IndexOf('[bool] InvokeStateAction'))
$methodNames=@([regex]::Matches($actionText,$methodPattern)|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique)
$routeMatches=[regex]::Matches($routerText,$routePattern)
$routePairs=@($routeMatches|ForEach-Object {@{Action=$_.Groups[1].Value;Method=$_.Groups[2].Value}})
$routedNames=@($routePairs|ForEach-Object Action|Sort-Object -Unique)
$referencedNames=@([regex]::Matches([IO.File]::ReadAllText($stateSource),$statePattern)|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique)
Check 'Every declared built-in action has a direct route' (($methodNames -join '|') -ceq ($routedNames -join '|')) $methodNames.Count $routedNames.Count
Check 'Every direct route invokes the same-named PowerShell method' (@($routePairs|Where-Object {$_.Action -cne $_.Method}).Count -eq 0) $routedNames.Count (@($routePairs|Where-Object {$_.Action -cne $_.Method}))
Check 'Every state-table action reference has a direct route' (@($referencedNames|Where-Object {$_ -notin $routedNames}).Count -eq 0) $referencedNames.Count $routedNames.Count
$bundle=& (Join-Path $PSScriptRoot 'Build-EngineBundle.ps1')
. $bundle
$vanillaNames=@([DoomInfo]::States.all|Where-Object {$null -ne $_.MobjAction}|ForEach-Object {$_.MobjAction.Name}|Sort-Object -Unique)
$unroutedVanilla=@($vanillaNames|Where-Object {$_ -notin $routedNames})
Check 'Loaded Ultimate Doom state table uses only routed actions' ($unroutedVanilla.Count -eq 0) $vanillaNames.Count $unroutedVanilla
$unknown=[DoomInfo]::MobjActions.InvokeStateAction('__not_a_vanilla_action__',$null,$null)
Check 'Unknown action reports generic fallback' ($unknown -eq $false) $false $unknown
$mobjText=[IO.File]::ReadAllText($mobjSource)
$fallbackPreserved=$mobjText.Contains('$st.MobjAction -is [scriptblock]') -and $mobjText.Contains('$st.ExecuteMobjAction($this.world, $this)') -and $mobjText.Contains('$st.MobjAction.Invoke($this.world, $this)')
Check 'SetState preserves scriptblock and generic PSMethod handling' $fallbackPreserved $true $fallbackPreserved
$sourcePaths=@($PSCommandPath,$actionSource,$stateSource,$mobjSource,(Join-Path $rootPath 'scripts/Build-EngineBundle.ps1'))
$report=@{
    Error=$null
    FinishedUtc=[DateTime]::UtcNow.ToString('o')
    PowerShell=$PSVersionTable.PSVersion.ToString()
    EngineBundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
    Sources=@(foreach($path in $sourcePaths){$relative=[IO.Path]::GetRelativePath($rootPath,$path).Replace([string][char]92,'/');@{Path=$relative;Sha256=(Get-FileHash -LiteralPath $path).Hash}})
    MethodNames=$methodNames
    RoutedNames=$routedNames
    RoutePairs=$routePairs
    StateTableActionReferences=$referencedNames
    LoadedVanillaStateActionNames=$vanillaNames
    Checks=$checks.ToArray()
    Passed=(@($checks|Where-Object {-not $_.Pass}).Count -eq 0)
    Meaning='Verifies direct built-in PowerShell state-action routing covers all declared actions and state-table references, and every action used by the loaded vanilla Doom state table. It also verifies unknown names return to generic dispatch and Mobj.SetState retains scriptblock and PSMethod fallback branches. Does not substitute for replay, campaign, or native pacing evidence.'
}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output -Encoding utf8
if(-not $report.Passed){throw "Action dispatch checks failed: $(@($checks|Where-Object {-not $_.Pass}|ForEach-Object Name) -join ', ')"}
"PASS: $($checks.Count) action-dispatch checks; $($methodNames.Count) methods, $($routedNames.Count) routes, $($vanillaNames.Count) loaded state actions. Receipt: $Output"

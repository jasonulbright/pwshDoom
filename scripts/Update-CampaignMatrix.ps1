#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$SmokeReport,[string]$E1M1Route,
    [string]$Output="$PSScriptRoot/../docs/campaign-matrix.md")
$ErrorActionPreference='Stop'
$report=Get-Content -LiteralPath $SmokeReport -Raw | ConvertFrom-Json
if(-not $report.Complete -or $report.FatalError){throw 'The smoke sweep did not finish.'}
$route=$null
if($E1M1Route) {
    $route=Get-Content -LiteralPath $E1M1Route -Raw | ConvertFrom-Json
    if(-not $route.Passed -or $route.WadSha256 -ne $report.WadSha256){throw 'E1M1 route did not pass with the same IWAD.'}
}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$reportRelative=[IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($SmokeReport)).Replace('\','/')
$lines=[Collections.Generic.List[string]]::new()
$stamp=if($report.UpdatedUtc -is [DateTime]){$report.UpdatedUtc.ToUniversalTime().ToString('o')}else{[string]$report.UpdatedUtc}
$lines.Add('# Campaign qualification matrix')
$lines.Add('')
$lines.Add("Updated from the completed smoke report dated $stamp. Release sequence: Ultimate Doom, Doom II, then a MyHouse-based audit. See [roadmap](roadmap.md).")
$lines.Add('')
$lines.Add("**Smoke: $($report.Passed)/$($report.Cases.Count) passed at skill $($report.Skill).** Each case loads the map, runs $($report.RequestedTics) idle simulation tics, and renders two complete 320×200 serial frames from two camera headings. A smoke pass is not a completed level or visual-reference match. Headless stage timings are not gameplay FPS.")
$lines.Add('')
$lines.Add("Source/IWAD hashes and detailed results: [$reportRelative](../$reportRelative).")
$lines.Add('')
if($route) {
    $routeRelative=[IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($E1M1Route)).Replace('\','/')
    $lines.Add("E1M1 has an [input-only completion report](../$routeRelative) with $($route.SimulationCommands) commands. That route ends at intermission; it does not qualify next-level presentation or a whole episode. Other maps still need completion evidence. The route harness targets E1M1/HMP; source-version matching is checked separately in the campaign validation report.")
    $lines.Add('')
}
$lines.Add('| Map | Load / idle simulation / two frames | Input-only completion | Transition / ending |')
$lines.Add('| --- | --- | --- | --- |')
foreach($case in $report.Cases) {
    $smoke=if($case.Passed){'Pass'}else{'FAIL: '+$case.Stage}
    $completion=if($case.Map -eq 'E1M1' -and $route){'Pass, HMP'}else{'Untested'}
    $lines.Add("| $($case.Map) | $smoke | $completion | Untested in terminal host |")
}
$lines.Add('')
$lines.Add('## Current blockers and next work')
$lines.Add('')
$lines.Add('- The terminal host stops at level completion. Implement intermission, next-map asset refresh, carryover, and episode-ending presentation.')
$lines.Add('- Source inspection identified episode-map-8 finale routing and the episode-4 secret-map return as candidate defects. Add isolated behavior reproductions and repair before claiming campaign progression.')
$lines.Add('- Add ordinary-input recording and completion routes for the remaining maps, including normal/secret paths and boss-triggered effects. Keep targeted state fixtures separate from playthrough evidence.')
$lines.Add('- Physical controls, audio, save/load, automap, harder scenes, visual fidelity, other difficulties, and 1080p hardware need their own validation.')
$lines.Add('- Doom II and MyHouse coverage has not started. MyHouse requires a version-pinned package/feature audit before choosing an extension scope.')
$lines.Add('')
$lines.Add('The initial sweep failed E2M7 because an enum conversion rejected extra line-flag bits. The raw failure and synthetic before/after tests remain in results/campaign-smoke-baseline.json and results/line-flags-*.json; the fix preserves the bitfield rather than deleting unknown bits.')
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),[string]::Join("`n",$lines)+"`n",[Text.UTF8Encoding]::new($false))
"Updated campaign matrix: $Output"

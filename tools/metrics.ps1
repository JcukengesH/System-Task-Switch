#requires -Version 5.1
<#
metrics.ps1 - regenerates docs/PROJECT_METRICS.md for the workspace.

DESIGN RULES
- The output file is a GENERATED artifact. The guard anchors on the FIRST
  line: '<!-- GENERATED-FILE' — a hand-written document that merely mentions
  the marker word in prose is NEVER overwritten.
- All filesystem existence checks use -LiteralPath (wildcard characters in
  names like 'report [draft].md' cannot bypass the guard); -OutputPath is
  normalized to an absolute path first.
- Hand-written architecture documentation (docs/ARCHITECTURE.md) is not
  read, referenced for writing, or touched.
- The output document is written UTF-8 with BOM; this script itself stays
  ASCII-only because Windows PowerShell 5.1 misreads BOM-less UTF-8.
- No absolute machine paths and no git commit SUBJECTS are embedded (console
  decoding of non-ASCII git output is unreliable); identifiers only.
- Output is byte-idempotent for identical inputs within the same minute
  (the 'generated:' timestamp is minute-precision).

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\metrics.ps1 [-Top 10] [-OutputPath <file>]
#>
[CmdletBinding()]
param(
	[int]$Top = 10,
	[string]$OutputPath = ''
)

$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $ProjectRoot
if ($OutputPath -eq '') {
	$OutputPath = Join-Path (Join-Path $WorkspaceRoot 'docs') 'PROJECT_METRICS.md'
}

$Marker = 'GENERATED-FILE'

function Rel {
	param([string]$Path)
	$prefix = $ProjectRoot + [System.IO.Path]::DirectorySeparatorChar
	if ($Path.StartsWith($prefix, 'OrdinalIgnoreCase')) {
		$p = $Path.Substring($prefix.Length)
		return $p.Replace('\', '/')
	}
	return $Path.Replace('\', '/')
}

function LineCount {
	param([string]$File)
	return [System.IO.File]::ReadAllLines($File).Count
}

function Bytes {
	param([object]$Item)
	return [long]$Item.Length
}

# ---- refuse to clobber a non-generated file -------------------------------
# Anchor: the FIRST line must be the generator comment (a hand-written file
# merely mentioning GENERATED-FILE in prose must not be overwritten).
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) {
	$existing = [System.IO.File]::ReadAllText($OutputPath, [System.Text.Encoding]::UTF8)
	$firstLine = (($existing -split "`r?`n", 2)[0])
	if ($firstLine -notmatch '^<!--\s*GENERATED-FILE') {
		Write-Output ('REFUSED: target exists and is NOT a generated file (no marker on first line): ' + (Rel $OutputPath))
		Write-Output 'Hand-written documentation is never overwritten. Choose another -OutputPath or remove the file deliberately.'
		exit 1
	}
}

# ---- inventory -------------------------------------------------------------
$all = @(Get-ChildItem $ProjectRoot -Recurse -File | Where-Object {
	($_.FullName -notmatch '\\\.godot\\') -and ($_.FullName -notmatch '\\\.git\\')
})

$sb = New-Object System.Text.StringBuilder
function Say { param([string]$Text) [void]$sb.AppendLine($Text) }

Say ('<!-- ' + $Marker + ': do not edit manually. Regenerate: powershell -NoProfile -ExecutionPolicy Bypass -File tools/metrics.ps1 -->')
Say ''
Say '# PROJECT METRICS - SystemTaskFailure'
Say ''
Say ('- generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
Say ('- generator: tools/metrics.ps1 (Top=' + $Top + ')')

$godotVer = 'UNAVAILABLE'
try {
	$gv = @(& godot --version 2>&1 | ForEach-Object { "$_" })
	$gvv = ($gv | Where-Object { $_ -match '\d+\.\d+\.' } | Select-Object -First 1)
	if ($gvv) { $godotVer = $gvv.Trim() }
} catch { }
Say ('- godot: ' + $godotVer)
Say ('- project files counted (excl. .godot/, .git/): ' + $all.Count)
Say ''

Say '## File inventory by extension'
Say ''
Say '| ext | files | bytes |'
Say '|---|---:|---:|'
$groups = $all | Group-Object { [System.IO.Path]::GetExtension($_.Name).ToLowerInvariant() } | Sort-Object Count -Descending
foreach ($gp in $groups) {
	$sum = [long]0
	foreach ($it in $gp.Group) { $sum += Bytes $it }
	$ext = $gp.Name
	if ($ext -eq '') { $ext = '(none)' }
	Say ('| ' + $ext + ' | ' + $gp.Count + ' | ' + ('{0:N0}' -f $sum) + ' |')
}
Say ''
Say '- note: extensions ".godot"/".gitignore"/".gitattributes" are whole-file names of root config files, NOT the excluded .godot/ and .git/ cache directories.'

# ---- scripts by lines ------------------------------------------------------
Say ('## Largest scripts (top ' + $Top + ' of scripts/**)')
Say ''
Say '| lines | bytes | file | flag |'
Say '|---:|---:|---|---|'
$game = @($all | Where-Object { (Rel $_.FullName) -like 'scripts/*' -and $_.Extension -eq '.gd' })
$gameRows = foreach ($f in $game) {
	$lc = LineCount $f.FullName
	$flag = ''
	if ($lc -gt 1000) { $flag = 'BLOCKER >1000' }
	elseif ($lc -gt 600) { $flag = 'REVIEW >600' }
	elseif ($lc -gt 300) { $flag = 'NOTE >300' }
	[pscustomobject]@{ Lc = $lc; By = $f.Length; Path = (Rel $f.FullName); Flag = $flag }
}
foreach ($r in ($gameRows | Sort-Object Lc -Descending | Select-Object -First $Top)) {
	Say ('| ' + $r.Lc + ' | ' + ('{0:N0}' -f $r.By) + ' | ' + $r.Path + ' | ' + $r.Flag + ' |')
}
Say ''
Say ('## Largest addon scripts (top ' + $Top + ' of addons/**, editor plugin)')
Say ''
Say '| lines | bytes | file |'
Say '|---:|---:|---|'
$addonRows = foreach ($f in @($all | Where-Object { (Rel $_.FullName) -like 'addons/*' -and $_.Extension -eq '.gd' })) {
	[pscustomobject]@{ Lc = (LineCount $f.FullName); By = $f.Length; Path = (Rel $f.FullName) }
}
foreach ($r in ($addonRows | Sort-Object Lc -Descending | Select-Object -First $Top)) {
	Say ('| ' + $r.Lc + ' | ' + ('{0:N0}' -f $r.By) + ' | ' + $r.Path + ' |')
}
Say ''

Say '## Totals'
Say ''
$gameCount = @($gameRows).Count
$addonCount = @($addonRows).Count
$gameLines = (@($gameRows) | Measure-Object -Property Lc -Sum).Sum
$addonLines = (@($addonRows) | Measure-Object -Property Lc -Sum).Sum
$tscn = @($all | Where-Object { $_.Extension -eq '.tscn' })
$tres = @($all | Where-Object { $_.Extension -eq '.tres' })
Say ('- game scripts: ' + $gameCount + ' files, ' + $gameLines + ' lines (thresholds: 300 note / 600 review / 1000 blocker, GODOT_RULES 10.1)')
Say ('- addon scripts (editor plugin, informational): ' + $addonCount + ' files, ' + $addonLines + ' lines')
Say ('- scenes (.tscn): ' + $tscn.Count + '; resources (.tres): ' + $tres.Count)
Say ''

Say '## Project settings (read-only snapshot of project.godot)'
Say ''
$projText = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'project.godot'), [System.Text.Encoding]::UTF8)
$mainScene = 'MISSING'
if ($projText -match '(?m)^run/main_scene="([^"]+)"') { $mainScene = $Matches[1] }
Say ('- main_scene: ' + $mainScene)
$autos = @()
$inAuto = $false
foreach ($l in ($projText -split "`n")) {
	if ($l -match '^\[autoload\]') { $inAuto = $true; continue }
	if ($inAuto -and $l -match '^\[') { break }
	if ($inAuto -and $l -match '^([A-Za-z_][A-Za-z0-9_]*)="?([^"]*)"') { $autos += ('  - ' + $Matches[1] + ' -> ' + $Matches[2]) }
}
Say ('- autoloads: ' + $autos.Count)
foreach ($a in $autos) { Say $a }
$plug = ''
if ($projText -match '(?m)^enabled=PackedStringArray\(([^)]*)\)') { $plug = $Matches[1] }
Say ('- editor plugins enabled: ' + $plug)
Say ''

Say '## Git snapshot'
Say ''
$branch = ''
$head = ''
$por = @()
$stash = @()
$shortstat = ''
try {
	$branch = (git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
	$head = (git -C $ProjectRoot log -1 --format='%h %ad' --date=short 2>$null | Out-String).Trim()
	$por = @(git -C $ProjectRoot status --porcelain -uall 2>$null)
	$stash = @(git -C $ProjectRoot stash list 2>$null)
	$shortstat = (git -C $ProjectRoot diff --shortstat 2>$null | Out-String).Trim()
} catch { }
$mod = @($por | Where-Object { $_ -notmatch '^\?\?' -and $_ -notmatch '^!!' })
$unt = @($por | Where-Object { $_ -match '^\?\?' })
Say ('- branch: ' + $branch)
Say ('- head: ' + $head)
Say ('- tracked dirty (any status incl. MM/AM): ' + $mod.Count + ' | untracked: ' + $unt.Count + ' | stash entries: ' + $stash.Count)
Say ('- diff (working tree vs HEAD): ' + $shortstat)
Say '- untracked files:'
if ($unt.Count -eq 0) { Say '  - (none)' }
foreach ($t in $unt) { Say ('  - ' + ($t.Substring(3).Replace('\', '/'))) }
Say ''

Say '## Notes'
Say ''
Say '- This file is the ONLY location for generated metrics. Hand-written architecture documentation lives in docs/ARCHITECTURE.md and is never modified by the generator.'
Say '- Metrics describe the repo at generation time; regenerate rather than editing manually.'

# ---- write ------------------------------------------------------------------
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -LiteralPath $outDir | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $enc)
Write-Output ('wrote ' + $OutputPath + ' (' + (Get-Item -LiteralPath $OutputPath).Length + ' b)')
exit 0

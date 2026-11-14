#requires -Version 5.1
<#
check.ps1 - headless verification runner for SystemTaskFailure (Godot 4.7).

MODES
  static   : --check-only for every scripts/**/*.gd. A file fails on any real
             "Parse Error" / "SCRIPT ERROR" / compile error, OR on a non-zero
             Godot exit code that the documented autoload artifact does not
             explain (guard against future diagnostic-format changes). The
             ONLY accepted exclusions are documented:
             (a) "Identifier not found: <name>" where <name> comes from the
                 [autoload] section of project.godot (autoloads are not
                 registered in --check-only mode), plus the resulting
                 "Failed to load script ... Compilation failed" line in the
                 same file;
             (b) audio environment chatter: AudioDriver|ALSA|PulseAudio|
                 "still in use at exit".
  headless : --editor --quit (authoritative: full import + compile of all
             connected scripts). Success = exit 0 AND zero unknown error lines.
  runtime  : isolated user:// (APPDATA redirected for child processes only),
             path probe via res://tools/user_path_probe.gd. If the actual
             user dir is not under the isolation root -> RUNTIME IS ABORTED.
             Then --quit-after 2 on the main scene with the same error
             classification as headless. Finally proves the real save was not
             touched, appeared or vanished (SHA256/existence before-after).
  all      : static + headless + runtime.
  selftest : table-driven tests of the error classifier and the isolation
             path comparison. Runs no Godot at all.

PRINCIPLE: unknown errors are never hidden. Every excluded line is echoed
with its reason. The old smoke.sh "grep -Ev ...|Meta" blanket filter is
deliberately NOT ported (selftest pins this).

EXIT CODE = number of failed steps (0 = all green).
NOTE: keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less
UTF-8 as ANSI, which corrupts non-ASCII literals.
#>
[CmdletBinding()]
param(
	[ValidateSet('static', 'headless', 'runtime', 'all', 'selftest')]
	[string]$Mode = 'all'
)

$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ProjectFile = Join-Path $ProjectRoot 'project.godot'
if (-not (Test-Path $ProjectFile)) {
	Write-Output 'FATAL: project.godot not found next to tools/. Run me from <project>/tools/.'
	exit 9
}
$GodotExe = 'godot'

# ---------------------------------------------------------------- helpers ---

function Invoke-Godot {
	param([string[]]$GodotArgs)
	$lines = @(& $GodotExe @GodotArgs 2>&1 | ForEach-Object { "$_" })
	$code = $LASTEXITCODE
	return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}

function Get-AutoloadNames {
	$names = @()
	$inAuto = $false
	foreach ($l in [System.IO.File]::ReadAllLines($ProjectFile)) {
		if ($l -match '^\[autoload\]') { $inAuto = $true; continue }
		if ($inAuto -and $l -match '^\[') { break }
		if ($inAuto -and $l -match '^([A-Za-z_][A-Za-z0-9_]*)=') { $names += $Matches[1] }
	}
	if ($names.Count -eq 0) { $names = @('__none__') }
	return $names
}

function Get-ProjectName {
	foreach ($l in [System.IO.File]::ReadAllLines($ProjectFile)) {
		if ($l -match '^config/name="([^"]+)"') { return $Matches[1] }
	}
	return ''
}

$AutoloadNames = Get-AutoloadNames

# Documented environment noise (AGENTS.md): audio driver chatter at exit.
$EnvNoisePattern = 'still in use at exit|AudioDriver|ALSA|PulseAudio'
# Documented --check-only artifact (verified 2026-11-11 on Godot 4.7.2):
$ArtifactPattern = 'Identifier not found: (' + ($AutoloadNames -join '|') + ')\s*$'

function Is-ErrorLine {
	param([string]$Line)
	return ($Line -match 'ERROR:' -or $Line -match 'Parse Error')
}

# Returns one of: known-env, known-artifact, known-consequence, not-an-error,
# unknown-error. Unknown = fail. Nothing is silently dropped.
function Get-Verdict {
	param(
		[string]$Line,
		[string[]]$Autoloads,
		[bool]$ArtifactSeen
	)
	if (-not (Is-ErrorLine -Line $Line)) { return 'not-an-error' }
	$artifact = 'Identifier not found: (' + ($Autoloads -join '|') + ')\s*$'
	if ($Line -match $EnvNoisePattern) { return 'known-env' }
	if ($Line -match $artifact) { return 'known-artifact' }
	if ($ArtifactSeen -and $Line -match 'Failed to load script.*Compilation failed') { return 'known-consequence' }
	return 'unknown-error'
}

# Isolation comparison: $Actual must live under $IsoRoot and inside app_userdata.
function Test-IsolationPath {
	param([string]$Actual, [string]$IsoRoot)
	if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($IsoRoot)) { return $false }
	try {
		$a = [System.IO.Path]::GetFullPath($Actual)
		$r = [System.IO.Path]::GetFullPath($IsoRoot)
		if (-not $r.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
			$r = $r + [System.IO.Path]::DirectorySeparatorChar
		}
		return ($a.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase) -and $a -match 'app_userdata')
	} catch {
		return $false
	}
}

function Report-Step {
	param([string]$Name, [bool]$Ok, [string]$Detail)
	$tag = 'FAIL'
	if ($Ok) { $tag = 'PASS' }
	Write-Output ("[{0}] {1} - {2}" -f $tag, $Name, $Detail)
}

function Show-UnknownErrors {
	param([string]$Step, [object[]]$Unknown)
	foreach ($u in ($Unknown | Select-Object -First 20)) {
		Write-Output ("  {0} UNKNOWN: {1}" -f $Step, $u)
	}
	if ($Unknown.Count -gt 20) {
		Write-Output ("  {0} UNKNOWN ... and {1} more lines" -f $Step, ($Unknown.Count - 20))
	}
}

# Classifies a captured Godot run. Prints everything, signals status via
# $script:ClassRc (0 ok / 1 failed). Never assign its output to a variable:
# Write-Output lines would be swallowed by the capture.
function Classify-Run {
	param([string]$Step, [object]$Result, [bool]$ArtifactSeen)
	$errLines = @($Result.Lines | Where-Object { Is-ErrorLine -Line $_ })
	$unknown = @()
	$excluded = 0
	foreach ($e in $errLines) {
		$v = Get-Verdict -Line $e -Autoloads $AutoloadNames -ArtifactSeen $ArtifactSeen
		if ($v -eq 'unknown-error') { $unknown += $e }
		else { $excluded++; Write-Output ('  EXCLUDED(' + $v + '): ' + $e) }
	}
	$warn = @($Result.Lines | Where-Object { $_ -match '^\s*WARNING:' } | Select-Object -Unique)
	if ($warn.Count -gt 0) {
		Write-Output ('  ' + $Step + ' warnings (reviewed, not failing):')
		foreach ($w in ($warn | Select-Object -First 10)) { Write-Output ('    ' + $w) }
		if ($warn.Count -gt 10) { Write-Output ('    ... and ' + ($warn.Count - 10) + ' more distinct warnings') }
	}
	if ($Result.ExitCode -ne 0) {
		Write-Output ('  ' + $Step + ' FAILED: exit code ' + $Result.ExitCode)
		Show-UnknownErrors -Step $Step -Unknown $unknown
		$script:ClassRc = 1
		return
	}
	if ($unknown.Count -gt 0) {
		Show-UnknownErrors -Step $Step -Unknown $unknown
		$script:ClassRc = 1
		return
	}
	if ($Result.Lines.Count -eq 0) {
		Write-Output ('  ' + $Step + ' FAILED: empty output from Godot (suspicious)')
		$script:ClassRc = 1
		return
	}
	Report-Step -Name $Step -Ok $true -Detail ('exit=0 error-lines=' + $errLines.Count + ' excluded-known=' + $excluded)
	$script:ClassRc = 0
}

# ------------------------------------------------------------------ modes ---

function Run-Static {
	$dir = Join-Path $ProjectRoot 'scripts'
	$files = @(Get-ChildItem $dir -Recurse -Filter '*.gd' -ErrorAction SilentlyContinue | Sort-Object FullName)
	if ($files.Count -eq 0) {
		Write-Output ('  FAIL static: no *.gd found under ' + $dir + ' (unexpected layout)')
		$script:StepRc = 1
		return
	}
	Write-Output ('static: ' + $files.Count + ' game scripts; autoload allowlist: ' + ($AutoloadNames -join ', '))
	$failed = 0
	$artifacts = 0
	$envExcluded = 0
	foreach ($f in $files) {
		$rel = $f.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
		$r = Invoke-Godot @('--headless', '--path', $ProjectRoot, '--check-only', '--script', ('res://' + $rel))
		$errLines = @($r.Lines | Where-Object { Is-ErrorLine -Line $_ })
		$artifactSeen = (@($errLines | Where-Object { $_ -match $ArtifactPattern }).Count -gt 0)
		if ($artifactSeen) { $artifacts++ }
		$unknown = @()
		foreach ($e in $errLines) {
			$v = Get-Verdict -Line $e -Autoloads $AutoloadNames -ArtifactSeen $artifactSeen
			if ($v -eq 'unknown-error') { $unknown += $e }
			elseif ($v -eq 'known-env') { $envExcluded++; Write-Output ('  EXCLUDED-ENV: ' + $e) }
			elseif ($v -eq 'known-artifact') { Write-Output ('  EXCLUDED-ARTIFACT (check-only, no autoload): ' + $e) }
			elseif ($v -eq 'known-consequence') { Write-Output ('  EXCLUDED-CONSEQUENCE: ' + $e) }
		}
		$fileFailed = $false
		if ($unknown.Count -gt 0) {
			$fileFailed = $true
			Write-Output ('  FAIL static: ' + $rel)
			Show-UnknownErrors -Step 'static' -Unknown $unknown
		}
		# MAJOR-fix (code-review 2026-11-11): a non-zero exit the documented
		# artifact cannot explain is a failure even if no error line matched.
		if ($r.ExitCode -ne 0 -and -not $artifactSeen) {
			if (-not $fileFailed) { Write-Output ('  FAIL static: ' + $rel) }
			$fileFailed = $true
			Write-Output ('  static UNKNOWN: exit code ' + $r.ExitCode + ' without documented autoload artifact; tail:')
			foreach ($tl in ($r.Lines | Select-Object -Last 5)) { Write-Output ('    | ' + $tl) }
		}
		if ($fileFailed) { $failed++ }
	}
	$ok = ($failed -eq 0)
	$detail = ('scanned=' + $files.Count + ' failed=' + $failed + ' known-artifact-files=' + $artifacts + ' env-excluded=' + $envExcluded)
	Report-Step -Name 'static' -Ok $ok -Detail $detail
	if ($ok) { $script:StepRc = 0 } else { $script:StepRc = 1 }
}

function Run-Headless {
	Write-Output 'headless: full import + compile (--editor --quit), authoritative check'
	$r = Invoke-Godot @('--headless', '--path', $ProjectRoot, '--editor', '--quit')
	Classify-Run -Step 'headless' -Result $r -ArtifactSeen $false
	$script:StepRc = $script:ClassRc
}

function Run-Runtime {
	Write-Output 'runtime: user:// isolation with mandatory path verification'
	$guid8 = [guid]::NewGuid().ToString('N').Substring(0, 8)
	$isoRoot = Join-Path $env:TEMP ('godot-user-isolation-' + $guid8)
	New-Item -ItemType Directory -Force -Path $isoRoot | Out-Null
	# Save path derived from project config/name (no hardcode drift).
	# File name itself belongs to the game: main.gd uses user://terminal_settings.cfg.
	$pname = Get-ProjectName
	$realSave = $null
	if ($pname -ne '') {
		$realSave = ('{0}\Godot\app_userdata\{1}\terminal_settings.cfg' -f $env:APPDATA, $pname)
	} else {
		Write-Output '  WARN: config/name not parsed, save-immutability proof disabled'
	}
	$hashBefore = $null
	if ($realSave -and (Test-Path $realSave)) { $hashBefore = (Get-FileHash $realSave -Algorithm SHA256).Hash }
	$appdataOriginal = $env:APPDATA
	$env:APPDATA = $isoRoot
	$resultCode = 1
	try {
		$p = Invoke-Godot @('--headless', '--path', $ProjectRoot, '--script', 'res://tools/user_path_probe.gd')
		$actualLine = @($p.Lines | Where-Object { $_ -match '^USER_DATA_DIR=' }) | Select-Object -First 1
		if ($null -eq $actualLine) {
			Write-Output '  ABORT: probe printed no USER_DATA_DIR (probe output below)'
			foreach ($pl in ($p.Lines | Select-Object -First 8)) { Write-Output ('    ' + $pl) }
			Report-Step -Name 'runtime' -Ok $false -Detail 'probe unusable, runtime aborted'
			$script:StepRc = 2
			return
		}
		$actual = $actualLine.Substring('USER_DATA_DIR='.Length)
		Write-Output ('  isolation root : ' + $isoRoot)
		Write-Output ('  actual user dir: ' + $actual)
		if (-not (Test-IsolationPath -Actual $actual -IsoRoot $isoRoot)) {
			Write-Output '  MISMATCH: actual user:// is NOT under the isolation root'
			Report-Step -Name 'runtime' -Ok $false -Detail 'user:// verification failed, runtime aborted'
			$script:StepRc = 2
			return
		}
		Write-Output '  ISOLATION OK: user:// points into the temp root'
		$g = Invoke-Godot @('--headless', '--path', $ProjectRoot, '--quit-after', '2')
		$allCreated = @(Get-ChildItem $isoRoot -Recurse -File -ErrorAction SilentlyContinue)
		Write-Output ('  runtime wrote ' + $allCreated.Count + ' file(s) inside isolation:')
		foreach ($c in ($allCreated | Select-Object -First 20)) { Write-Output ('    ' + $c.FullName.Substring($isoRoot.Length + 1)) }
		Classify-Run -Step 'runtime' -Result $g -ArtifactSeen $false
		$resultCode = $script:ClassRc
	} finally {
		$env:APPDATA = $appdataOriginal
		$tmpPrefix = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
		$isoFull = [System.IO.Path]::GetFullPath($isoRoot)
		if ($isoFull.StartsWith($tmpPrefix + '\', 'OrdinalIgnoreCase') -and $isoFull -match 'godot-user-isolation-') {
			Remove-Item $isoFull -Recurse -Force -ErrorAction SilentlyContinue
			if (Test-Path $isoFull) {
				Write-Output '  WARN: isolation dir not fully removed (locked files?), left in place'
			}
		} else {
			Write-Output '  WARN: isolation dir failed the removal guard, left in place'
		}
	}
	$hashAfter = $null
	if ($realSave -and (Test-Path $realSave)) { $hashAfter = (Get-FileHash $realSave -Algorithm SHA256).Hash }
	if ($null -eq $realSave) {
		Write-Output '  save proof: SKIPPED (project name unknown)'
	} elseif ($null -eq $hashBefore -and $null -eq $hashAfter) {
		Write-Output '  real save: absent before and after (nothing to protect)'
	} elseif ($null -eq $hashBefore) {
		Write-Output '  CRITICAL: real save APPEARED during isolated runtime'
		if ($resultCode -eq 0) { $resultCode = 1 }
	} elseif ($null -eq $hashAfter) {
		Write-Output '  CRITICAL: real save VANISHED during isolated runtime'
		if ($resultCode -eq 0) { $resultCode = 1 }
	} elseif ($hashBefore -eq $hashAfter) {
		Write-Output ('  PROOF real save untouched: SHA256 ' + $hashBefore.Substring(0, 16) + '... stable')
	} else {
		Write-Output '  CRITICAL: real save CHANGED during isolated runtime!'
		if ($resultCode -eq 0) { $resultCode = 1 }
	}
	if ($resultCode -eq 2) { $script:StepRc = 2 } elseif ($resultCode -ne 0) { $script:StepRc = 1 } else { $script:StepRc = 0 }
}

function Run-SelfTest {
	Write-Output 'selftest: classifier + isolation logic (no Godot runs)'
	$al = @('SFX', 'MCPRuntimeProbe')
	$cases = @(
		@{ Line = 'SCRIPT ERROR: Compile Error: Identifier not found: SFX'; Art = $false; Expect = 'known-artifact' },
		@{ Line = 'SCRIPT ERROR: Compile Error: Identifier not found: MCPRuntimeProbe'; Art = $false; Expect = 'known-artifact' },
		@{ Line = 'ERROR: Failed to load script "res://scripts/main.gd" with error "Compilation failed".'; Art = $true; Expect = 'known-consequence' },
		@{ Line = 'ERROR: Failed to load script "res://scripts/main.gd" with error "Compilation failed".'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'ERROR: Failed to load script "res://scripts/x.gd" with error "Parse error".'; Art = $true; Expect = 'unknown-error' },
		@{ Line = 'SCRIPT ERROR: Compile Error: Identifier not found: SOME_OTHER_THING'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'SCRIPT ERROR: Compile Error: Identifier not found: Meta'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'res://scripts/main.gd:12:1 - Parse Error: Expected end of statement'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'SCRIPT ERROR: Invalid call. Nonexistent function "foo" in base "Node"'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'ERROR: Condition "!is_instance_valid(p)" is true.'; Art = $false; Expect = 'unknown-error' },
		@{ Line = 'ERROR: AudioDriver Dummy: whatever'; Art = $false; Expect = 'known-env' },
		@{ Line = 'ERROR: 2 resources still in use at exit'; Art = $false; Expect = 'known-env' },
		@{ Line = 'Godot Engine v4.7.2.stable - https://godotengine.org'; Art = $false; Expect = 'not-an-error' }
	)
	$failedCases = 0
	$i = 0
	foreach ($c in $cases) {
		$i++
		$got = Get-Verdict -Line $c.Line -Autoloads $al -ArtifactSeen $c.Art
		$okCase = ($got -eq $c.Expect)
		if (-not $okCase) { $failedCases++ }
		$tag = 'ok'
		if (-not $okCase) { $tag = 'BAD' }
		Write-Output ('  case {0,2} [{1}] want={2} got={3}' -f $i, $tag, $c.Expect, $got)
	}
	$isoCases = @(
		@{ A = 'C:\Temp\godot-user-isolation-abcd1234\Godot\app_userdata\SystemTaskFailure'; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $true },
		@{ A = 'C:\temp\GODOT-USER-ISOLATION-abcd1234\godot\app_userdata\SystemTaskFailure'; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $true },
		@{ A = 'C:\Users\someone\AppData\Roaming\Godot\app_userdata\SystemTaskFailure'; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $false },
		@{ A = 'C:\Temp\godot-user-isolation-abcd1234other\app_userdata\X'; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $false },
		@{ A = 'C:\Temp\something-else\Godot\app_userdata\X'; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $false },
		@{ A = ''; R = 'C:\Temp\godot-user-isolation-abcd1234'; Expect = $false }
	)
	foreach ($c in $isoCases) {
		$i++
		$got = Test-IsolationPath -Actual $c.A -IsoRoot $c.R
		$okCase = ($got -eq $c.Expect)
		if (-not $okCase) { $failedCases++ }
		$tag = 'ok'
		if (-not $okCase) { $tag = 'BAD' }
		Write-Output ('  case {0,2} [{1}] isolation expected={2} got={3}' -f $i, $tag, $c.Expect, $got)
	}
	if ($failedCases -eq 0) {
		Report-Step -Name 'selftest' -Ok $true -Detail ('all ' + $i + ' cases behave as designed')
		$script:StepRc = 0
		return
	}
	Report-Step -Name 'selftest' -Ok $false -Detail ($failedCases + ' case(s) wrong')
	$script:StepRc = 1
}

# ------------------------------------------------------------------ main ----

Write-Output ('=== check.ps1 mode=' + $Mode + ' ===')
if ($Mode -ne 'selftest') {
	$ver = Invoke-Godot @('--version')
	$verLine = (@($ver.Lines) -join ' / ')
	if ($ver.ExitCode -ne 0 -or $verLine -notmatch '4\.7\.') {
		Write-Output ('FATAL: godot on PATH is not 4.7: "' + $verLine + '" (exit ' + $ver.ExitCode + ')')
		exit 9
	}
	Write-Output ('godot: ' + $verLine)
	Write-Output ('project: ' + $ProjectRoot)
}

$steps = @($Mode)
if ($Mode -eq 'all') { $steps = @('static', 'headless', 'runtime') }

$failed = 0
foreach ($s in $steps) {
	$script:StepRc = 1
	switch ($s) {
		'static' { Run-Static }
		'headless' { Run-Headless }
		'runtime' { Run-Runtime }
		'selftest' { Run-SelfTest }
	}
	Write-Output ('step ' + $s + ' rc=' + $script:StepRc)
	if ($script:StepRc -ne 0) { $failed++ }
}

Write-Output ('=== result: ' + $(if ($failed -eq 0) { 'ALL GREEN' } else { $failed.ToString() + ' STEP(S) FAILED' }) + ' ===')
exit $failed

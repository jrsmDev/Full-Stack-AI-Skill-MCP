<#
.SYNOPSIS
  Syncs skills from "C:\jrsmDev Workspace\FULL STACK AI SKILL" into a flat
  symlinked root at "$env:USERPROFILE\.dsh\skills" that dsh-skill-filesystem
  can discover at depth 1 (<root>/<name>/SKILL.md).

  Run this script whenever you add a new skill repo. It is also safe to re-run
  at any time — it only adds missing links and removes stale ones.
#>
$ErrorActionPreference = 'Stop'

$SourceBase = 'C:\jrsmDev Workspace\FULL STACK AI SKILL'
$TargetRoot = Join-Path $env:USERPROFILE '.dsh\skills'

if (-not (Test-Path $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    Write-Host "Created $TargetRoot"
}

# Find every directory that directly contains a SKILL.md
$skillDirs = Get-ChildItem $SourceBase -Recurse -Filter 'SKILL.md' -File |
    ForEach-Object { $_.Directory } |
    Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\|\\deprecated\\' }

$linked = 0
$skipped = 0
$existing = @{}

foreach ($dir in $skillDirs) {
    $linkName = $dir.Name
    # Deduplicate: if same skill name from different repos, suffix with parent
    if ($existing.ContainsKey($linkName)) {
        $parent = $dir.Parent.Name
        $linkName = "$linkName--$parent"
    }
    $existing[$linkName] = $true
    $linkPath = Join-Path $TargetRoot $linkName

    if (Test-Path $linkPath) {
        $skipped++
        continue
    }

    # Create directory junction (works without admin on Windows)
    cmd /c mklink /J "`"$linkPath`"" "`"$($dir.FullName)`"" 2>&1 | Out-Null
    Write-Host "  + $linkName -> $($dir.FullName)"
    $linked++
}

# Remove stale links pointing to nonexistent targets
Get-ChildItem $TargetRoot -Directory | ForEach-Object {
    $target = (Get-Item $_.FullName).Target
    if ($target -and -not (Test-Path $target)) {
        Remove-Item $_.FullName -Force
        Write-Host "  - Removed stale: $($_.Name)"
    }
}

Write-Host "`nDone: $linked new, $skipped already linked. Total: $($existing.Count) skills in $TargetRoot"

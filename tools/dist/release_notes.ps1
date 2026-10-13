# The release page text for a tagged player build (German, for players):
# tools/dist/release_notes.md with the placeholders filled and the commit
# subjects since the previous release. Run by .github/workflows/windows-release.yml
# before `gh release create` (needs GH_TOKEN). docs/dev-notes/release-builds.md
param(
	[Parameter(Mandatory = $true)][string]$Version,
	[Parameter(Mandatory = $true)][string]$Tag,
	[Parameter(Mandatory = $true)][string]$Repo,
	[Parameter(Mandatory = $true)][string]$Sha,
	[Parameter(Mandatory = $true)][string]$RunUrl,
	[Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = "Stop"

$prev = (gh release list --repo $Repo --limit 1 --exclude-drafts --exclude-pre-releases --json tagName --jq ".[0].tagName")
if ($LASTEXITCODE -ne 0) { throw "gh release list failed" }
$since = ""
$changes = "- Erste Version auf GitHub Releases."
if ($prev) {
	$since = " seit [$prev](https://github.com/$Repo/compare/$prev...$Tag)"
	$subjects = @(gh api "repos/$Repo/compare/$prev...$Tag" --jq '.commits[].commit.message | split("\n")[0]')
	if ($LASTEXITCODE -ne 0) { throw "gh api compare failed" }
	if ($subjects.Count -gt 0) {
		[array]::Reverse($subjects)  # newest first
		$changes = ($subjects | ForEach-Object { "- $_" }) -join "`n"
	}
}
$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "release_notes.md"))
$text = $text.Replace("{VERSION}", $Version).Replace("{PROTOCOL}", ($Version -split '\.')[1])
$text = $text.Replace("{SHORT_SHA}", $Sha.Substring(0, 7)).Replace("{SHA}", $Sha).Replace("{REPO}", $Repo)
$text = $text.Replace("{RUN_URL}", $RunUrl).Replace("{SINCE}", $since).Replace("{CHANGES}", $changes)
[IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding $false))
Write-Host $text

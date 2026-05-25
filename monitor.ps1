param(
    [string]$Owner = "tiamolucy",
    [string]$Repo = "FlashlightApp-iOS"
)

Write-Host "Triggering build workflow for $Owner/$Repo ..."
gh workflow run build-ipa.yml --repo "$Owner/$Repo"

Start-Sleep -Seconds 15

while ($true) {
    $json = gh run list --workflow=build-ipa.yml --repo "$Owner/$Repo" --limit 1 --json status,conclusion,databaseId --jq '.[0]'
    $run = $json | ConvertFrom-Json

    Write-Host "$(Get-Date -Format 'HH:mm:ss') Status: $($run.status)"

    if ($run.status -eq "completed") {
        Write-Host "Build completed! Conclusion: $($run.conclusion)"
        if ($run.conclusion -eq "success") {
            Write-Host "Downloading IPA..."
            gh run download $run.databaseId --name FlashlightApp-ipa --repo "$Owner/$Repo" --dir ./ipa
            Write-Host "IPA downloaded to ./ipa/"
        }
        break
    }

    Write-Host "Waiting 10 minutes..."
    Start-Sleep -Seconds 600
}

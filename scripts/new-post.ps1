param(
    [Parameter(Mandatory = $true)]
    [string]$Title
)

$slug = $Title.ToLower() -replace '[^a-z0-9\u4e00-\u9fff]+', '-' -replace '^-+|-+$', ''
$file = "content/blog/$slug.md"

if (Test-Path $file) {
    Write-Error "文件已存在: $file"
    exit 1
}

& "C:\Program Files\hugo\hugo.exe" new content "blog/$slug.md"

(Get-Content $file) -replace '^title:.*$', "title: `"$Title`"" -replace '^slug:.*$', "slug: `"$slug`"" | Set-Content $file

Write-Output "Created: $file"
Write-Output ""
Write-Output "Quick start:"
Write-Output "  code $file"
Write-Output "  .\preview.ps1"

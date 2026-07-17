param()

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "Source\ForeignValidationOwner.csproj"
dotnet build $project -c Release --nologo
if ($LASTEXITCODE -ne 0)
{
    throw "Foreign validation owner build failed with exit code $LASTEXITCODE."
}

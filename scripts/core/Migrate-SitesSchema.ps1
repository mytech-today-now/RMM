<#
.SYNOPSIS
    Migrates the Sites table to add new contact and address fields.

.DESCRIPTION
    This script adds new columns to the Sites table and creates the SiteURLs table
    for storing multiple URLs per site.

    Searches for database in standard locations:
    1. ProgramData: C:\ProgramData\myTech.Today\RMM\data\devices.db
    2. Legacy: %USERPROFILE%\myTech.Today\RMM\data\devices.db

.EXAMPLE
    .\Migrate-SitesSchema.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Get database path - check multiple locations
$DatabasePath = $null
$possiblePaths = @(
    "$env:ProgramData\myTech.Today\RMM\data\devices.db",    # Standard installation
    "$env:USERPROFILE\myTech.Today\RMM\data\devices.db",    # Legacy location
    "$env:USERPROFILE\myTech.Today\data\devices.db"         # Old legacy location
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $DatabasePath = $path
        break
    }
}

if (-not $DatabasePath) {
    Write-Error "Database not found. Checked locations:`n  $($possiblePaths -join "`n  ")"
    exit 1
}

Write-Host "Migrating Sites schema at: $DatabasePath" -ForegroundColor Cyan
Write-Host ""

# Import PSSQLite
Import-Module PSSQLite -ErrorAction Stop

# Get existing columns
$existingColumns = Invoke-SqliteQuery -DataSource $DatabasePath -Query "PRAGMA table_info(Sites)" | Select-Object -ExpandProperty name

# New columns to add
$newColumns = @(
    @{ Name = 'MainPhone'; Type = 'TEXT' },
    @{ Name = 'CellPhone'; Type = 'TEXT' },
    @{ Name = 'StreetNumber'; Type = 'TEXT' },
    @{ Name = 'StreetName'; Type = 'TEXT' },
    @{ Name = 'Unit'; Type = 'TEXT' },
    @{ Name = 'Building'; Type = 'TEXT' },
    @{ Name = 'City'; Type = 'TEXT' },
    @{ Name = 'State'; Type = 'TEXT' },
    @{ Name = 'Zip'; Type = 'TEXT' },
    @{ Name = 'Country'; Type = 'TEXT' },
    @{ Name = 'Timezone'; Type = 'TEXT' },
    @{ Name = 'RelayAgent'; Type = 'TEXT' },
    @{ Name = 'ContactName'; Type = 'TEXT' }
)

# Add missing columns
foreach ($col in $newColumns) {
    if ($col.Name -notin $existingColumns) {
        $query = "ALTER TABLE Sites ADD COLUMN $($col.Name) $($col.Type)"
        try {
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $query
            Write-Host "[OK] Added column: $($col.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "[SKIP] Column $($col.Name) may already exist or error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[SKIP] Column $($col.Name) already exists" -ForegroundColor Yellow
    }
}

# Create SiteURLs table if not exists
$createSiteURLs = @"
CREATE TABLE IF NOT EXISTS SiteURLs (
    URLId INTEGER PRIMARY KEY AUTOINCREMENT,
    SiteId TEXT NOT NULL,
    URL TEXT NOT NULL,
    Label TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (SiteId) REFERENCES Sites(SiteId) ON DELETE CASCADE
);
"@

try {
    Invoke-SqliteQuery -DataSource $DatabasePath -Query $createSiteURLs
    Write-Host "[OK] SiteURLs table created/verified" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to create SiteURLs table: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Migration complete!" -ForegroundColor Green


<#
.SYNOPSIS
    Sweep Active Directory for secrets left in user attributes.

.DESCRIPTION
    You cannot reliably detect an attacker *reading* a password out of a
    description field - the LDAP query looks like any other. So detect the
    exposure instead: enumerate the attributes an attacker would read and flag
    anything that looks like a credential. Run it on a schedule; if this finds
    something, an attacker's `nxc ... -M get-desc-users` would have too.

    Read-only. Requires the ActiveDirectory module (RSAT) and read access to
    the directory - no privileged rights needed, which is the whole point.

.EXAMPLE
    .\find-secrets-in-attributes.ps1
    .\find-secrets-in-attributes.ps1 -Attributes description,info,comment -SearchBase 'OU=LabUsers,DC=lab,DC=local'
#>
[CmdletBinding()]
param(
    [string[]]$Attributes = @('description','info','comment','wWWHomePage'),
    [string]$SearchBase,
    # Words that suggest a credential was written in clear text.
    [string]$Pattern = '(?i)(pass|pwd|pw\s*[:=]|cred|secret|login\s*[:=])'
)

Import-Module ActiveDirectory -ErrorAction Stop

$getParams = @{ Filter = '*'; Properties = $Attributes }
if ($SearchBase) { $getParams['SearchBase'] = $SearchBase }

$hits = foreach ($u in Get-ADUser @getParams) {
    foreach ($attr in $Attributes) {
        $val = $u.$attr
        if ($val -and ($val -match $Pattern)) {
            [pscustomobject]@{
                SamAccountName = $u.SamAccountName
                Attribute      = $attr
                Value          = $val
            }
        }
    }
}

if ($hits) {
    Write-Warning ("Possible secrets exposed in directory attributes: {0}" -f $hits.Count)
    $hits | Format-Table -AutoSize
    exit 2   # non-zero so a scheduled task / CI job flags it
} else {
    Write-Host 'No credential-like strings found in the swept attributes.'
    exit 0
}

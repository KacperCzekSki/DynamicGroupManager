<#
.SYNOPSIS
Aktualizuje dynamiczną grupę w Active Directory.
.USE
powershell.exe -ExecutionPolicy Bypass -File "Update-ADGroup.ps1" -GroupName "NazwaGrupy" -OU "OU=Uzytkownicy,DC=dip,DC=local" -IncludeSubOUs -RemoveNonMatching -KeepManual
#>

param(
    [Parameter(Mandatory)]
    [string]$GroupName,

    [Parameter(Mandatory)]
    [string]$OU,

    [switch]$IncludeSubOUs,
    [switch]$RemoveNonMatching,
    [switch]$KeepManual
)

# Włącz debug i kontynuację błędów
$ErrorActionPreference = "Continue"

# Import modułu ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error ("Nie udało się załadować modułu ActiveDirectory: {0}" -f $_.Exception.Message)
    exit 1
}

Write-Output "[$(Get-Date)] Aktualizacja grupy: $GroupName z OU: $OU"
Write-Output "Opcje: IncludeSubOUs=$IncludeSubOUs, RemoveNonMatching=$RemoveNonMatching, KeepManual=$KeepManual"

# Ustawienie zakresu wyszukiwania
$SearchScope = if ($IncludeSubOUs) { "Subtree" } else { "OneLevel" }

# Pobranie użytkowników z OU (i opcjonalnie pod-OU)
try {
    $Users = Get-ADUser -SearchBase $OU -SearchScope $SearchScope -Filter * | Select-Object -ExpandProperty DistinguishedName
} catch {
    Write-Error ("Błąd pobierania użytkowników z OU: {0}" -f $_.Exception.Message)
    exit 1
}

if ($Users.Count -eq 0) {
    Write-Output "Brak użytkowników w OU: $OU"
    exit 0
}

Write-Output ("Znaleziono {0} użytkowników w OU" -f $Users.Count)

# Pobranie obecnych członków grupy
try {
    $CurrentMembers = (Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DistinguishedName)
} catch {
    Write-Warning ("Błąd pobierania członków grupy: {0}" -f $_.Exception.Message)
    $CurrentMembers = @()
}

# Dodanie brakujących użytkowników
$ToAdd = $Users | Where-Object { $_ -notin $CurrentMembers }
foreach ($user in $ToAdd) {
    try {
        Write-Output ("Dodaję użytkownika {0} do grupy {1}" -f $user, $GroupName)
        Add-ADGroupMember -Identity $GroupName -Members $user -ErrorAction Stop
        # Oznaczenie użytkownika jako automatycznie dodanego
        Set-ADUser -Identity $user -Add @{extensionAttribute1="DynamicGroup"} -ErrorAction SilentlyContinue
    } catch {
        Write-Warning ("Nie udało się dodać użytkownika {0}: {1}" -f $user, $_.Exception.Message)
    }
}

# Usuwanie użytkowników niepasujących
if ($RemoveNonMatching) {
    $ToRemove = $CurrentMembers | Where-Object {
        ($_ -notin $Users) -and (-not $KeepManual -or ((Get-ADUser $_ -Properties extensionAttribute1).extensionAttribute1 -eq "DynamicGroup"))
    }

    foreach ($user in $ToRemove) {
        try {
            Write-Output ("Usuwam użytkownika {0} z grupy {1}" -f $user, $GroupName)
            Remove-ADGroupMember -Identity $GroupName -Members $user -Confirm:$false -ErrorAction Stop
        } catch {
            Write-Warning ("Nie udało się usunąć użytkownika {0}: {1}" -f $user, $_.Exception.Message)
        }
    }
}

Write-Output "Aktualizacja grupy '$GroupName' zakończona pomyślnie."

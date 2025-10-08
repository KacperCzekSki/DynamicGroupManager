param(
    [Parameter(Mandatory)]
    [string]$GroupName,

    [Parameter(Mandatory)]
    [string]$OU
)

Import-Module ActiveDirectory

Write-Output "[$(Get-Date)] Aktualizacja grupy: $GroupName z OU: $OU"

# Pobierz użytkowników z OU
$Users = Get-ADUser -SearchBase $OU -Filter * | Select-Object -ExpandProperty DistinguishedName

if ($Users.Count -eq 0) {
    Write-Output "Brak użytkowników w OU: $OU"
    exit
}

# Pobierz aktualnych członków
$CurrentMembers = (Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DistinguishedName) 2>$null

# Dodaj brakujących
$ToAdd = $Users | Where-Object { $_ -notin $CurrentMembers }
if ($ToAdd) {
    Add-ADGroupMember -Identity $GroupName -Members $ToAdd -ErrorAction SilentlyContinue
    Write-Output "Dodano: $($ToAdd.Count) użytkowników"
}

# Usuń tych, których już nie ma
$ToRemove = $CurrentMembers | Where-Object { $_ -notin $Users }
if ($ToRemove) {
    Remove-ADGroupMember -Identity $GroupName -Members $ToRemove -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "Usunięto: $($ToRemove.Count) użytkowników"
}

Write-Output "Aktualizacja zakończona pomyślnie."
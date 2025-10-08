# ================================
# DynamicGroupManager.ps1
# GUI do tworzenia dynamicznych grup AD
# ================================

Add-Type -AssemblyName PresentationFramework
$ErrorActionPreference = "Stop"

# Ścieżki
$BasePath = "C:\Scripts\DynamicGroups"
$ConfigFile = Join-Path $BasePath "Groups.json"
$UpdateScript = Join-Path $BasePath "Update-ADGroup.ps1"

# Tworzenie folderu i pliku konfiguracyjnego
if (!(Test-Path $BasePath)) { New-Item -ItemType Directory -Path $BasePath | Out-Null }
if (!(Test-Path $ConfigFile)) { @() | ConvertTo-Json | Out-File $ConfigFile }

# Wczytaj istniejące grupy
function Load-Groups {
    if (Test-Path $ConfigFile) {
        $json = Get-Content $ConfigFile -Raw
        if ($json -and $json -ne "") {
            $data = $json | ConvertFrom-Json
            if ($data -isnot [System.Collections.IEnumerable]) {
                return @($data)
            }
            return $data
        }
    }
    return @()
}


function Save-Groups($groups) {
    $groups | ConvertTo-Json -Depth 5 | Out-File $ConfigFile
}

# Tworzenie zadania w Task Scheduler
function Create-Task($Group) {
    $GroupName = $Group.GroupName
    $OU = $Group.OU
    $Schedule = $Group.Schedule
    $IncludeSubOUs = $Group.IncludeSubOUs
    $RemoveNonMatching = $Group.RemoveNonMatching
    $KeepManual = $Group.KeepManual

    $TaskName = "DynamicGroup_$GroupName"

    # Usuń stare zadanie, jeśli istnieje
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Harmonogram
    switch ($Schedule) {
        "Hourly" {
            $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
                -RepetitionInterval (New-TimeSpan -Hours 1) `
                -RepetitionDuration (New-TimeSpan -Days 3650)
        }
        "Daily" {
            $Trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
        }
        default {
            $Trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
        }
    }

    # Argumenty do skryptu
    $args = "-GroupName `"$GroupName`" -OU `"$OU`""
    if ($IncludeSubOUs) { $args += " -IncludeSubOUs" }
    if ($RemoveNonMatching) { $args += " -RemoveNonMatching" }
    if ($KeepManual) { $args += " -KeepManual" }

    $ActionObj = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$UpdateScript`" $args"
    Register-ScheduledTask -Action $ActionObj -Trigger $Trigger -TaskName $TaskName -Description "Dynamic Group: $GroupName" -User "SYSTEM" -RunLevel Highest | Out-Null
}

# GUI XAML
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dynamic Group Manager" Height="450" Width="650" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <Label Content="Nazwa grupy:" Width="100"/>
            <TextBox x:Name="txtGroup" Width="200"/>
            <Label Content="OU:" Width="40" Margin="10,0,0,0"/>
            <TextBox x:Name="txtOU" Width="200"/>
        </StackPanel>

        <StackPanel Orientation="Horizontal" Grid.Row="1" Margin="0,0,0,10">
            <Label Content="Harmonogram:" Width="100"/>
            <ComboBox x:Name="cmbSchedule" Width="200">
                <ComboBoxItem Content="Hourly"/>
                <ComboBoxItem Content="Daily" IsSelected="True"/>
            </ComboBox>

            <CheckBox x:Name="chkIncludeSubOUs" Content="Include Sub-OUs" Margin="20,0,0,0"/>
            <CheckBox x:Name="chkRemoveNonMatching" Content="Usuń użytkowników niepasujących" Margin="20,0,0,0"/>
            <CheckBox x:Name="chkKeepManual" Content="Nie usuwać użytkowników ręcznie dodanych" Margin="20,0,0,0"/>

            <Button x:Name="btnAdd" Content="Dodaj grupę" Width="120" Margin="20,0,0,0"/>
        </StackPanel>

        <DataGrid x:Name="dgGroups" Grid.Row="2" Margin="0,10,0,10" AutoGenerateColumns="False" Height="220">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Grupa" Binding="{Binding GroupName}" Width="*"/>
                <DataGridTextColumn Header="OU" Binding="{Binding OU}" Width="2*"/>
                <DataGridTextColumn Header="Harmonogram" Binding="{Binding Schedule}" Width="*"/>
                <DataGridCheckBoxColumn Header="Sub-OUs" Binding="{Binding IncludeSubOUs}" Width="*"/>
                <DataGridCheckBoxColumn Header="Usuń niepasujących" Binding="{Binding RemoveNonMatching}" Width="*"/>
                <DataGridCheckBoxColumn Header="Nie usuwać ręcznie" Binding="{Binding KeepManual}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>

        <Button x:Name="btnRemove" Grid.Row="3" VerticalAlignment="Bottom" HorizontalAlignment="Right" Content="Usuń wybraną" Width="120"/>
    </Grid>
</Window>
"@

# Tworzenie GUI
$reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

$txtGroup = $Window.FindName("txtGroup")
$txtOU = $Window.FindName("txtOU")
$cmbSchedule = $Window.FindName("cmbSchedule")
$chkIncludeSubOUs = $Window.FindName("chkIncludeSubOUs")
$chkRemoveNonMatching = $Window.FindName("chkRemoveNonMatching")
$chkKeepManual = $Window.FindName("chkKeepManual")
$btnAdd = $Window.FindName("btnAdd")
$btnRemove = $Window.FindName("btnRemove")
$dgGroups = $Window.FindName("dgGroups")

# Załaduj grupy
$Global:Groups = @(Load-Groups)
$dgGroups.ItemsSource = @($Global:Groups)

# Dodaj grupę
$btnAdd.Add_Click({
    $GroupName = $txtGroup.Text.Trim()
    $OU = $txtOU.Text.Trim()
    $Schedule = $cmbSchedule.Text
    $IncludeSubOUs = $chkIncludeSubOUs.IsChecked
    $RemoveNonMatching = $chkRemoveNonMatching.IsChecked
    $KeepManual = $chkKeepManual.IsChecked

    if ($GroupName -eq "" -or $OU -eq "") {
        [System.Windows.MessageBox]::Show("Podaj nazwę grupy i ścieżkę OU.")
        return
    }

    $newGroup = [PSCustomObject]@{
        GroupName = $GroupName
        OU = $OU
        Schedule = $Schedule
        IncludeSubOUs = $IncludeSubOUs
        RemoveNonMatching = $RemoveNonMatching
        KeepManual = $KeepManual
    }

    $Global:Groups += $newGroup
    Save-Groups $Global:Groups
    Create-Task $newGroup

    $dgGroups.ItemsSource = $null
    $dgGroups.ItemsSource = @($Global:Groups)

    $txtGroup.Text = ""
    $txtOU.Text = ""
    $chkIncludeSubOUs.IsChecked = $false
    $chkRemoveNonMatching.IsChecked = $false
    $chkKeepManual.IsChecked = $false
})

# Usuń grupę
$btnRemove.Add_Click({
    $selected = $dgGroups.SelectedItem
    if ($null -eq $selected) { return }

    $TaskName = "DynamicGroup_$($selected.GroupName)"
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $Global:Groups = $Global:Groups | Where-Object { $_.GroupName -ne $selected.GroupName }
    Save-Groups $Global:Groups
    $dgGroups.ItemsSource = $null
    $dgGroups.ItemsSource = @($Global:Groups)
})

$Window.ShowDialog() | Out-Null

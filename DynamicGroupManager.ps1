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
$Global:Groups = @()
function Load-Groups {
    $taskList = Get-ScheduledTask | Where-Object { $_.TaskName -like "DynamicGroup_*" } | ForEach-Object {
        $parts = $_.TaskName -split "_", 2
        if ($parts.Count -eq 2) {
            [PSCustomObject]@{
                GroupName = $parts[1]
                OU = ($_.Actions[0].Arguments -split '-OU "', 2)[1] -replace '"', ''
                Schedule = if ($_.Triggers[0].Repetition.Interval -eq 'PT1H') { 'Hourly' } else { 'Daily' }
            }
        }
    }
    $Global:Groups = @($taskList) # <- wymuszenie tablicy, nawet jeśli jest 1 element
    $dgGroups.ItemsSource = $Global:Groups
}


function Save-Groups($groups) {
    $groups | ConvertTo-Json -Depth 5 | Out-File $ConfigFile
}

# Tworzenie zadania w Task Scheduler
function Create-Task($GroupName, $OU, $Schedule) {
    $Action = "powershell.exe -ExecutionPolicy Bypass -File `"$UpdateScript`" -GroupName `"$GroupName`" -OU `"$OU`""
    $TaskName = "DynamicGroup_$GroupName"

    # Usuń stare zadanie, jeśli istnieje
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    switch ($Schedule) {
        "Hourly" {
            # Uruchamiaj co godzinę, bez "nieskończonego" czasu trwania
            $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
                -RepetitionInterval (New-TimeSpan -Hours 1) `
                -RepetitionDuration (New-TimeSpan -Days 3650)  # 10 lat
        }
        "Daily" {
            $Trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
        }
        default {
            $Trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
        }
    }

    $ActionObj = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$UpdateScript`" -GroupName `"$GroupName`" -OU `"$OU`""
    Register-ScheduledTask -Action $ActionObj -Trigger $Trigger -TaskName $TaskName -Description "Dynamic Group: $GroupName" -User "SYSTEM" -RunLevel Highest | Out-Null
}


# GUI XAML
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dynamic Group Manager" Height="400" Width="600" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
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

        <StackPanel Orientation="Horizontal" Grid.Row="1">
            <Label Content="Harmonogram:" Width="100"/>
            <ComboBox x:Name="cmbSchedule" Width="200">
                <ComboBoxItem Content="Hourly"/>
                <ComboBoxItem Content="Daily" IsSelected="True"/>
            </ComboBox>
            <Button x:Name="btnAdd" Content="Dodaj grupę" Width="120" Margin="20,0,0,0"/>
        </StackPanel>

        <DataGrid x:Name="dgGroups" Grid.Row="2" Margin="0,10,0,40" AutoGenerateColumns="False" Height="200">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Grupa" Binding="{Binding GroupName}" Width="*"/>
                <DataGridTextColumn Header="OU" Binding="{Binding OU}" Width="2*"/>
                <DataGridTextColumn Header="Harmonogram" Binding="{Binding Schedule}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>

        <Button x:Name="btnRemove" Grid.Row="2" VerticalAlignment="Bottom" HorizontalAlignment="Right" Content="Usuń wybraną" Width="120"/>
    </Grid>
</Window>
"@


# Tworzenie GUI
$reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

$txtGroup = $Window.FindName("txtGroup")
$txtOU = $Window.FindName("txtOU")
$cmbSchedule = $Window.FindName("cmbSchedule")
$btnAdd = $Window.FindName("btnAdd")
$btnRemove = $Window.FindName("btnRemove")
$dgGroups = $Window.FindName("dgGroups")

# Załaduj grupy
$Global:Groups = @(Load-Groups)
$dgGroups.ItemsSource = $Global:Groups

# Dodaj grupę
$btnAdd.Add_Click({
    $GroupName = $txtGroup.Text.Trim()
    $OU = $txtOU.Text.Trim()
    $Schedule = $cmbSchedule.Text

    if ($GroupName -eq "" -or $OU -eq "") {
        [System.Windows.MessageBox]::Show("Podaj nazwę grupy i ścieżkę OU.")
        return
    }

    $newGroup = [PSCustomObject]@{
        GroupName = $GroupName
        OU         = $OU
        Schedule   = $Schedule
    }

    $Global:Groups += $newGroup
    Save-Groups $Global:Groups
    Create-Task $GroupName $OU $Schedule

    $dgGroups.ItemsSource = $null
    $dgGroups.ItemsSource = $Global:Groups

    $txtGroup.Text = ""
    $txtOU.Text = ""
})

# Usuń grup
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
    $dgGroups.ItemsSource = $Global:Groups
})

$Window.ShowDialog() | Out-Null
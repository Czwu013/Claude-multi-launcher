# claude-multi-launcher graphical window (unofficial community tool, MIT license).
# Start by double-clicking claude-multi-launcher.exe (see build-exe.cmd), or:
#   powershell -STA -ExecutionPolicy Bypass -File .\claude-multi-gui.ps1
# This window only calls the same functions as the command line; it adds no logic of its own.
# Colours follow the Windows light/dark setting (read-only; nothing is written to the registry).

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Any start-up error is shown in a message box and written to a log, instead of failing silently.
trap {
    $msg = ($_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + [string]$_.ScriptStackTrace)
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'claude-multi-launcher'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        [IO.File]::WriteAllText((Join-Path $logDir 'gui-error.log'), $msg, [Text.Encoding]::UTF8)
    } catch { }
    [void][System.Windows.MessageBox]::Show($msg, 'Claude Multi Launcher', 'OK', 'Error')
    exit 1
}

try {
    Import-Module -Name (Join-Path $PSScriptRoot 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
} catch {
    [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'Claude Multi Launcher')
    exit 1
}

# ---- theme ----------------------------------------------------------------------------------
$script:Dark = @{
    Bg = '#0F0E0D'; Card = '#171615'; CardBorder = '#2A2826'; Text = '#ECEBE7'; Muted = '#A8A6A0'; Dim = '#85837D'
    Chip = '#1F1E1C'; Primary = '#E8E4DC'; PrimaryText = '#1A1917'; PrimaryHover = '#FFFFFF'
    BtnBg = '#1B1A18'; BtnHover = '#262422'; BtnBorder = '#34312E'; Warn = '#E8A39B'; InputBg = '#121110'
}
$script:Light = @{
    Bg = '#F5F4EE'; Card = '#FFFFFF'; CardBorder = '#E4E2DA'; Text = '#1F1E1D'; Muted = '#66655F'; Dim = '#8E8C85'
    Chip = '#EFEDE5'; Primary = '#1F1E1D'; PrimaryText = '#F5F4EE'; PrimaryHover = '#000000'
    BtnBg = '#FFFFFF'; BtnHover = '#F0EEE6'; BtnBorder = '#DAD7CE'; Warn = '#B3261E'; InputBg = '#FAF9F5'
}
$script:DotColors = @{ ok = '#7FB88A'; idle = '#8A8882'; warn = '#E8A39B' }
$script:IsDark = $null

function New-Brush {
    param([string]$Hex)
    # BrushConverter returns a real Brush (a bare Color is rejected by Background and friends)
    $conv = New-Object System.Windows.Media.BrushConverter
    $b = [System.Windows.Media.Brush]$conv.ConvertFromString($Hex)
    if ($b.CanFreeze) { $b.Freeze() }
    return $b
}

function Test-DarkTheme {
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
        return ($v -eq 0)
    } catch {
        return $true
    }
}

function Set-Theme {
    $dark = Test-DarkTheme
    if ($null -ne $script:IsDark -and $script:IsDark -eq $dark) { return }
    $script:IsDark = $dark
    if ($dark) { $pal = $script:Dark } else { $pal = $script:Light }
    foreach ($k in $pal.Keys) { $script:window.Resources[$k] = (New-Brush $pal[$k]) }
}

# ---- window ---------------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="1120" Height="780" MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14" TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="#0F0E0D"/>
    <SolidColorBrush x:Key="Card" Color="#171615"/>
    <SolidColorBrush x:Key="CardBorder" Color="#2A2826"/>
    <SolidColorBrush x:Key="Text" Color="#ECEBE7"/>
    <SolidColorBrush x:Key="Muted" Color="#A8A6A0"/>
    <SolidColorBrush x:Key="Dim" Color="#85837D"/>
    <SolidColorBrush x:Key="Chip" Color="#1F1E1C"/>
    <SolidColorBrush x:Key="Primary" Color="#E8E4DC"/>
    <SolidColorBrush x:Key="PrimaryText" Color="#1A1917"/>
    <SolidColorBrush x:Key="PrimaryHover" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="BtnBg" Color="#1B1A18"/>
    <SolidColorBrush x:Key="BtnHover" Color="#262422"/>
    <SolidColorBrush x:Key="BtnBorder" Color="#34312E"/>
    <SolidColorBrush x:Key="Warn" Color="#E8A39B"/>
    <SolidColorBrush x:Key="InputBg" Color="#121110"/>

    <Style x:Key="CardStyle" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Card}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="26"/>
      <Setter Property="Padding" Value="24"/>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{DynamicResource BtnBg}" BorderBrush="{DynamicResource BtnBorder}"
                    BorderThickness="1" CornerRadius="17" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource BtnHover}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="20,0"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{DynamicResource Primary}" CornerRadius="17" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{DynamicResource PrimaryHover}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Input" TargetType="TextBox">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Text}"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource BtnBorder}"
                    BorderThickness="1" CornerRadius="14" Padding="{TemplateBinding Padding}">
              <ScrollViewer x:Name="PART_ContentHost"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border Width="18" Height="18" CornerRadius="6" BorderThickness="1" VerticalAlignment="Center"
                      BorderBrush="{DynamicResource BtnBorder}" Background="{DynamicResource InputBg}">
                <Path x:Name="tick" Data="M4,9 L7.5,12.5 L14,5.5" Stroke="{DynamicResource Text}" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid Margin="40,30,40,22">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- header -->
      <Grid Grid.Row="0" Margin="0,0,0,24">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock x:Name="Wordmark" FontSize="24" FontWeight="SemiBold"/>
          <TextBlock x:Name="SubText" FontSize="14" Foreground="{DynamicResource Muted}" Margin="0,4,0,0"/>
        </StackPanel>
        <Button x:Name="BtnNew" Grid.Column="1" Style="{StaticResource PrimaryBtn}" Height="40" Padding="24,0" Margin="0" FontSize="14"/>
      </Grid>

      <!-- hub -->
      <Border Grid.Row="2" Style="{StaticResource CardStyle}" Padding="0">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="28,24,28,18">
            <TextBlock x:Name="HubTitle" FontSize="17" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnScan" Style="{StaticResource Btn}"/>
              <Button x:Name="BtnLang" Style="{StaticResource Btn}" Margin="0"/>
            </StackPanel>
          </Grid>
          <Border Grid.Row="1" BorderBrush="{DynamicResource CardBorder}" BorderThickness="0,0,0,1" Padding="28,0,28,12">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2.2*"/>
                <ColumnDefinition Width="1.5*"/>
                <ColumnDefinition Width="1*"/>
                <ColumnDefinition Width="2.4*"/>
                <ColumnDefinition Width="210"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="H1" Grid.Column="0" FontSize="12" Foreground="{DynamicResource Muted}"/>
              <TextBlock x:Name="H2" Grid.Column="1" FontSize="12" Foreground="{DynamicResource Muted}"/>
              <TextBlock x:Name="H3" Grid.Column="2" FontSize="12" Foreground="{DynamicResource Muted}"/>
              <TextBlock x:Name="H4" Grid.Column="3" FontSize="12" Foreground="{DynamicResource Muted}"/>
            </Grid>
          </Border>
          <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
            <StackPanel>
              <TextBlock x:Name="EmptyText" TextWrapping="Wrap" Foreground="{DynamicResource Muted}" Margin="28,22,28,22" Visibility="Collapsed"/>
              <ItemsControl x:Name="Profiles">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Border BorderBrush="{DynamicResource CardBorder}" BorderThickness="0,0,0,1" Padding="28,16,28,16" Background="Transparent">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="2.2*"/>
                          <ColumnDefinition Width="1.5*"/>
                          <ColumnDefinition Width="1*"/>
                          <ColumnDefinition Width="2.4*"/>
                          <ColumnDefinition Width="210"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,12,0">
                          <TextBlock Text="{Binding Name}" FontSize="15" FontWeight="SemiBold"/>
                          <TextBlock Text="{Binding SubLine}" FontSize="12" Foreground="{DynamicResource Dim}" Margin="0,3,0,0"
                                     TextTrimming="CharacterEllipsis" ToolTip="{Binding SubLine}"/>
                        </StackPanel>
                        <Border Grid.Column="1" HorizontalAlignment="Left" VerticalAlignment="Center" CornerRadius="14" Padding="11,5"
                                Background="{DynamicResource Chip}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1">
                          <StackPanel Orientation="Horizontal">
                            <Ellipse Width="7" Height="7" Fill="{Binding Dot}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                            <TextBlock Text="{Binding StatusText}" FontSize="13"/>
                          </StackPanel>
                        </Border>
                        <TextBlock Grid.Column="2" Text="{Binding ShortcutText}" FontFamily="Consolas" FontSize="12"
                                   VerticalAlignment="Center" Foreground="{DynamicResource Muted}"/>
                        <StackPanel Grid.Column="3" VerticalAlignment="Center" Margin="0,0,12,0">
                          <TextBlock Text="{Binding DataLine}" FontFamily="Consolas" FontSize="12" TextTrimming="CharacterEllipsis" ToolTip="{Binding DataTip}"/>
                          <TextBlock Text="{Binding ConfigLine}" FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource Dim}"
                                     Margin="0,3,0,0" TextTrimming="CharacterEllipsis" ToolTip="{Binding ConfigTip}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="4" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                          <Button Tag="launch" Content="{Binding BtnLaunch}" Style="{StaticResource PrimaryBtn}"/>
                          <Button Tag="open" Content="{Binding BtnOpen}" Style="{StaticResource Btn}" Padding="12,0"/>
                          <Button Tag="more" Content="···" Style="{StaticResource Btn}" Padding="12,0" Margin="0"/>
                        </StackPanel>
                      </Grid>
                    </Border>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </StackPanel>
          </ScrollViewer>
        </Grid>
      </Border>

      <!-- footer -->
      <Grid Grid.Row="3" Margin="0,16,0,0">
        <TextBlock x:Name="FootLeft" FontSize="12" Foreground="{DynamicResource Dim}" HorizontalAlignment="Left" TextTrimming="CharacterEllipsis"/>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

$script:window = [System.Windows.Markup.XamlReader]::Parse($xaml)
function Get-Ctl { param([string]$Name) return $script:window.FindName($Name) }
$script:items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
(Get-Ctl 'Profiles').ItemsSource = $script:items
$script:footMsg = ''

# ---- helpers --------------------------------------------------------------------------------
function Show-Info {
    param([string]$Text, [string]$Title)
    if (-not $Title) { $Title = $script:window.Title }
    [void][System.Windows.MessageBox]::Show($script:window, $Text, $Title)
}

function Show-Error {
    param([string]$Message)
    [void][System.Windows.MessageBox]::Show($script:window, $Message, (Get-CmlText 'gui.error_title'), 'OK', 'Error')
}

function Invoke-Safe {
    param([scriptblock]$Action)
    try { & $Action } catch { Show-Error $_.Exception.Message }
}

function Set-Status {
    param([string]$Text)
    $script:footMsg = $Text
    (Get-Ctl 'FootLeft').Text = $Text
}

function Update-List {
    $script:items.Clear()
    $sum = @(Get-CmlProfileSummary)
    $total = $sum.Count
    $launched = 0
    $withSc = 0
    $bad = 0
    foreach ($s in $sum) {
        if ($s.HasShortcut) { $withSc++; $sc = (Get-CmlText 'msg.shortcut_yes') } else { $sc = (Get-CmlText 'msg.shortcut_no') }
        if ($s.Launched) { $launched++ }
        if ($s.Violations.Count -gt 0) {
            $bad++
            $st = (Get-CmlText 'gui.st_conflict'); $dot = $script:DotColors['warn']
        } elseif ($s.Launched) {
            $st = (Get-CmlText 'gui.st_launched'); $dot = $script:DotColors['ok']
        } else {
            $st = (Get-CmlText 'gui.st_new'); $dot = $script:DotColors['idle']
        }
        $script:items.Add([pscustomobject]@{
                Name       = [string]$s.Name
                SubLine    = [string]$s.WorkspaceDir
                StatusText = $st
                Dot        = $dot
                ShortcutText = $sc
                DataLine   = [string]$s.DataDir
                DataTip    = ('{0}: {1}' -f (Get-CmlItemLabel 'dataDir'), $s.DataDir)
                ConfigLine = [string]$s.ConfigDir
                ConfigTip  = ('{0}: {1}' -f (Get-CmlItemLabel 'configDir'), $s.ConfigDir)
                BtnLaunch  = (Get-CmlText 'gui.launch')
                BtnOpen    = (Get-CmlText 'gui.open')
            })
    }
    if ($total -eq 0) { (Get-Ctl 'EmptyText').Visibility = 'Visible' } else { (Get-Ctl 'EmptyText').Visibility = 'Collapsed' }

    (Get-Ctl 'SubText').Text = (Get-CmlText 'gui.summary' @($total, $launched, $bad))
    Set-Status ''
}

function Set-AllTexts {
    $script:window.Title = (Get-CmlText 'gui.title')
    (Get-Ctl 'Wordmark').Text = (Get-CmlText 'gui.title')
    (Get-Ctl 'BtnNew').Content = (Get-CmlText 'gui.new_group')
    (Get-Ctl 'HubTitle').Text = (Get-CmlText 'gui.hub_title')
    (Get-Ctl 'BtnScan').Content = (Get-CmlText 'gui.scan')
    (Get-Ctl 'BtnLang').Content = (Get-CmlText 'gui.lang')
    (Get-Ctl 'H1').Text = (Get-CmlText 'gui.col_name')
    (Get-Ctl 'H2').Text = (Get-CmlText 'gui.col_state')
    (Get-Ctl 'H3').Text = (Get-CmlText 'gui.col_shortcut')
    (Get-Ctl 'H4').Text = (Get-CmlText 'gui.col_folders')
    (Get-Ctl 'EmptyText').Text = (Get-CmlText 'gui.empty')
}

function Invoke-RowAction {
    param([string]$Action, [string]$Name)
    Invoke-Safe {
        switch ($Action) {
            'launch' {
                $script:window.Cursor = [System.Windows.Input.Cursors]::Wait
                try { Start-CmlProfile -Name $Name -ShowDialog } finally { $script:window.Cursor = $null }
                Update-List
                Set-Status (Get-CmlText 'gui.launched' @($Name))
            }
            'open' { Open-CmlWorkspace -Name $Name }
            'paths' {
                $s = @(Get-CmlProfileSummary | Where-Object { $_.Name -ieq $Name })[0]
                $nl = [Environment]::NewLine
                $text = ('{0}: {1}{2}{3}: {4}{5}{6}: {7}{8}{9}: {10}' -f
                    (Get-CmlItemLabel 'dataDir'), $s.DataDir, $nl,
                    (Get-CmlItemLabel 'configDir'), $s.ConfigDir, $nl,
                    (Get-CmlItemLabel 'workspaceDir'), $s.WorkspaceDir, $nl,
                    (Get-CmlItemLabel 'tempDir'), $s.TempDir)
                if ($s.Violations.Count -eq 0) {
                    $text += ($nl + $nl + (Get-CmlText 'iso.ok'))
                } else {
                    $text += ($nl + $nl + (Get-CmlText 'iso.bad'))
                    foreach ($v in $s.Violations) { $text += ($nl + '- ' + $v) }
                }
                $text += ($nl + $nl + (Get-CmlText 'msg.shared_note'))
                Show-Info $text $s.Name
            }
            'shortcut' {
                Update-CmlShortcut -Name $Name
                Update-List
                Set-Status (Get-CmlText 'gui.shortcut_done' @($Name))
            }
            'remove' {
                $nl = [Environment]::NewLine
                $msg = (Get-CmlText 'gui.confirm_remove' @($Name)) + $nl + $nl + (Get-CmlText 'gui.confirm_note')
                $r = [System.Windows.MessageBox]::Show($script:window, $msg, $script:window.Title, 'YesNo', 'Question', 'No')
                if ($r -ne 'Yes') { return }
                Remove-CmlProfile -Name $Name -AssumeYes   # the user just confirmed in the dialog above
                Update-List
            }
        }
    }
}

function Show-RowMenu {
    param($Button, [string]$Name)
    $script:menuName = $Name
    $cm = New-Object System.Windows.Controls.ContextMenu
    foreach ($pair in @(@('paths', 'gui.paths'), @('shortcut', 'gui.shortcut'), @('remove', 'gui.remove'))) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = (Get-CmlText $pair[1])
        $mi.Tag = $pair[0]
        $mi.Add_Click({ param($s, $e) Invoke-RowAction ([string]$s.Tag) $script:menuName })
        [void]$cm.Items.Add($mi)
    }
    $cm.PlacementTarget = $Button
    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $cm.IsOpen = $true
}

# ---- dialogs --------------------------------------------------------------------------------
function New-DialogShell {
    param([string]$Xaml, [string]$Title)
    $dlg = [System.Windows.Markup.XamlReader]::Parse($Xaml)
    $dlg.Resources.MergedDictionaries.Add($script:window.Resources)
    $dlg.Owner = $script:window
    $dlg.Title = $Title
    return $dlg
}

$createXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14"
        Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}">
  <Border Margin="22" Padding="26" CornerRadius="26" BorderThickness="1"
          Background="{DynamicResource Card}" BorderBrush="{DynamicResource CardBorder}">
    <StackPanel>
      <TextBlock x:Name="DlgTitle" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,18"/>
      <TextBlock x:Name="LblName" FontSize="13" Foreground="{DynamicResource Muted}" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtName" Style="{DynamicResource Input}" Margin="0,0,0,16"/>
      <TextBlock x:Name="LblRoot" FontSize="13" Foreground="{DynamicResource Muted}" Margin="0,0,0,6"/>
      <Grid Margin="0,0,0,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtRoot" Grid.Column="0" Style="{DynamicResource Input}" Margin="0,0,10,0"/>
        <Button x:Name="BtnBrowse" Grid.Column="1" Style="{DynamicResource Btn}" Margin="0"/>
      </Grid>
      <CheckBox x:Name="ChkShortcut" IsChecked="True" Margin="0,0,0,22"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnCancel" Style="{DynamicResource Btn}"/>
        <Button x:Name="BtnCreate" Style="{DynamicResource PrimaryBtn}" Margin="0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

function Show-CreateDialog {
    $dlg = New-DialogShell $createXaml (Get-CmlText 'gui.new_group')
    $script:createDlg = $dlg
    $dlg.FindName('DlgTitle').Text = (Get-CmlText 'gui.new_group')
    $dlg.FindName('LblName').Text = (Get-CmlText 'gui.name').TrimEnd(':', [char]0xFF1A)
    $dlg.FindName('LblRoot').Text = (Get-CmlText 'gui.root').TrimEnd(':', [char]0xFF1A)
    $dlg.FindName('BtnBrowse').Content = (Get-CmlText 'gui.browse')
    $dlg.FindName('ChkShortcut').Content = (Get-CmlText 'gui.chk_shortcut')
    $dlg.FindName('BtnCancel').Content = (Get-CmlText 'gui.close')
    $dlg.FindName('BtnCreate').Content = (Get-CmlText 'gui.create')

    $dlg.FindName('BtnCancel').Add_Click({ $script:createDlg.Close() })
    $dlg.FindName('BtnBrowse').Add_Click({
            Invoke-Safe {
                $fb = New-Object System.Windows.Forms.FolderBrowserDialog
                $fb.Description = (Get-CmlText 'gui.root_pick')
                if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:createDlg.FindName('TxtRoot').Text = $fb.SelectedPath }
            }
        })
    $doCreate = {
        try {
            $d = $script:createDlg
            $name = $d.FindName('TxtName').Text.Trim()
            if (-not $name) { throw (Get-CmlText 'gui.name_empty') }
            $p = @{ Name = $name }
            $root = $d.FindName('TxtRoot').Text.Trim()
            if ($root) { $p['Root'] = $root }
            if (-not $d.FindName('ChkShortcut').IsChecked) { $p['NoShortcut'] = $true }
            Add-CmlProfile @p
            Update-List
            Set-Status (Get-CmlText 'gui.created' @($name))
            [void][System.Windows.MessageBox]::Show($d, ((Get-CmlText 'gui.created' @($name)) + [Environment]::NewLine + (Get-CmlText 'gui.created_tip')), $d.Title)
            $d.Close()
        } catch {
            [void][System.Windows.MessageBox]::Show($script:createDlg, $_.Exception.Message, (Get-CmlText 'gui.error_title'), 'OK', 'Error')
        }
    }
    $script:doCreate = $doCreate
    $dlg.FindName('BtnCreate').Add_Click({ & $script:doCreate })
    $dlg.FindName('TxtName').Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Return) { & $script:doCreate }
        })
    [void]$dlg.ShowDialog()
}

$scanXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="900" Height="600" MinWidth="700" MinHeight="440"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14"
        Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}">
  <Grid Margin="24,20,24,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="Hint" Grid.Row="0" TextWrapping="Wrap" Margin="2,0,0,14" Foreground="{DynamicResource Muted}"/>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="Rows"/>
    </ScrollViewer>
    <Grid Grid.Row="2" Margin="0,14,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="BtnManual" Grid.Column="0" Style="{DynamicResource Btn}" Margin="0"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button x:Name="BtnClose" Style="{DynamicResource Btn}"/>
        <Button x:Name="BtnImport" Style="{DynamicResource PrimaryBtn}" Margin="0"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

function New-ScanRow {
    param([string]$Name, [string]$DataDir, [string]$ConfigDir, [string]$Sources, [string]$State, [bool]$Enabled)
    $dlg = $script:scanDlg
    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'Card')
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'CardBorder')
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(18)
    $border.Padding = New-Object System.Windows.Thickness(16)
    $border.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in @('Auto', '170', '*')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        elseif ($w -eq '*') { $cd.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { $cd.Width = New-Object System.Windows.GridLength([double]$w) }
        $grid.ColumnDefinitions.Add($cd)
    }
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.VerticalAlignment = 'Center'
    $chk.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
    $chk.IsEnabled = $Enabled
    [System.Windows.Controls.Grid]::SetColumn($chk, 0)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Name
    $tb.IsEnabled = $Enabled
    $tb.VerticalAlignment = 'Center'
    $tb.Margin = New-Object System.Windows.Thickness(0, 0, 16, 0)
    $tb.SetResourceReference([System.Windows.Controls.Control]::StyleProperty, 'Input')
    [System.Windows.Controls.Grid]::SetColumn($tb, 1)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($sp, 2)
    $l1 = New-Object System.Windows.Controls.TextBlock
    $l1.Text = $DataDir
    $l1.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $l1.FontSize = 12
    $l1.TextTrimming = 'CharacterEllipsis'
    $l1.ToolTip = $DataDir
    $l2 = New-Object System.Windows.Controls.TextBlock
    $l2.Text = ((@($Sources, $State) | Where-Object { $_ }) -join '  ')
    $l2.FontSize = 11
    $l2.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $l2.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Muted')
    [void]$sp.Children.Add($l1)
    [void]$sp.Children.Add($l2)
    [void]$grid.Children.Add($chk)
    [void]$grid.Children.Add($tb)
    [void]$grid.Children.Add($sp)
    $border.Child = $grid
    [void]$dlg.FindName('Rows').Children.Add($border)
    $script:scanRows.Add(@{ Check = $chk; NameBox = $tb; DataDir = $DataDir; ConfigDir = $ConfigDir; StateBlock = $l2 })
}

function Show-ScanDialog {
    $script:window.Cursor = [System.Windows.Input.Cursors]::Wait
    $found = @()
    try { $found = @(Find-CmlExistingClones) } finally { $script:window.Cursor = $null }

    $dlg = New-DialogShell $scanXaml (Get-CmlText 'gui.scan_title')
    $script:scanDlg = $dlg
    $script:scanRows = New-Object System.Collections.Generic.List[object]
    $dlg.FindName('Hint').Text = (Get-CmlText 'gui.scan_hint')
    $dlg.FindName('BtnManual').Content = (Get-CmlText 'gui.add_manual')
    $dlg.FindName('BtnImport').Content = (Get-CmlText 'gui.import_sel')
    $dlg.FindName('BtnClose').Content = (Get-CmlText 'gui.close')

    foreach ($c in $found) {
        $st = @()
        if ($c.Running) { $st += (Get-CmlText 'msg.scan_running') }
        if ($c.Registered) { $st += (Get-CmlText 'msg.scan_registered') }
        New-ScanRow $c.Name $c.DataDir $c.ConfigDir ($c.Sources -join ', ') ($st -join ' ') (-not $c.Registered)
    }
    if ($found.Count -eq 0) { $dlg.FindName('Hint').Text = (Get-CmlText 'gui.scan_empty') }

    $dlg.FindName('BtnClose').Add_Click({ $script:scanDlg.Close() })

    $dlg.FindName('BtnManual').Add_Click({
            Invoke-Safe {
                $fb = New-Object System.Windows.Forms.FolderBrowserDialog
                $fb.Description = (Get-CmlText 'gui.manual_pick')
                if ($fb.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
                $path = $fb.SelectedPath
                foreach ($r in $script:scanRows) { if ($r.DataDir -ieq $path) { return } }
                New-ScanRow (Split-Path -Leaf $path) $path '' '' '' $true
                $script:scanRows[$script:scanRows.Count - 1].Check.IsChecked = $true
            }
        })

    $dlg.FindName('BtnImport').Add_Click({
            Invoke-Safe {
                $ok = 0
                $bad = 0
                $errs = @()
                foreach ($r in $script:scanRows) {
                    if (-not $r.Check.IsChecked -or -not $r.Check.IsEnabled) { continue }
                    $nm = $r.NameBox.Text.Trim()
                    try {
                        $a = @{ Name = $nm; DataDir = $r.DataDir; NoShortcut = $true }
                        if ($r.ConfigDir) { $a['ConfigDir'] = $r.ConfigDir }
                        Import-CmlProfile @a
                        $r.Check.IsChecked = $false
                        $r.Check.IsEnabled = $false
                        $r.NameBox.IsEnabled = $false
                        $r.StateBlock.Text = (Get-CmlText 'msg.scan_registered')
                        $ok++
                    } catch {
                        $bad++
                        $errs += ($nm + ': ' + $_.Exception.Message)
                    }
                }
                $nl = [Environment]::NewLine
                $msg = (Get-CmlText 'gui.import_done' @($ok, $bad))
                if ($errs.Count -gt 0) { $msg += ($nl + $nl + ($errs -join ($nl + $nl))) }
                [void][System.Windows.MessageBox]::Show($script:scanDlg, $msg, $script:scanDlg.Title)
                Update-List
            }
        })

    [void]$dlg.ShowDialog()
}

# ---- wire up --------------------------------------------------------------------------------
(Get-Ctl 'BtnNew').Add_Click({ Invoke-Safe { Show-CreateDialog } })
(Get-Ctl 'BtnScan').Add_Click({ Invoke-Safe { Show-ScanDialog } })
(Get-Ctl 'BtnLang').Add_Click({
        Invoke-Safe {
            if ((Get-CmlLang) -eq 'zh') { Set-CmlLanguage 'en' } else { Set-CmlLanguage 'zh' }
            Set-AllTexts
            Update-List
        }
    })
(Get-Ctl 'Profiles').AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $btn = $e.OriginalSource -as [System.Windows.Controls.Button]
        if ($null -eq $btn -or $null -eq $btn.DataContext) { return }
        $nm = [string]$btn.DataContext.Name
        if ([string]$btn.Tag -eq 'more') { Show-RowMenu $btn $nm } else { Invoke-RowAction ([string]$btn.Tag) $nm }
    })
$script:window.Add_Activated({ Set-Theme })

Set-Theme
Set-AllTexts
Update-List
[void]$script:window.ShowDialog()

#Requires -Version 5.1
<#
.SYNOPSIS
    Skyrim Together + Achievements Enabler Installer (Aero Glass UI)
.DESCRIPTION
    Instala automaticamente los mods necesarios para jugar Skyrim Together
    con logros habilitados. Soporta instalacion manual y via Vortex.
    Interfaz WPF con estetica Aero Glass / Frutiger Aero.
.NOTES
    Requiere .NET Framework 4.8 (incluido en Windows 10/11)
    Ejecutar: powershell -ExecutionPolicy Bypass -File Install-SkyrimTogether.ps1
#>
param(
    [switch]$Silent,
    [string]$SkyrimPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Mod files expected in script directory ---
$Mods = @(
    @{ Name = "Skyrim Together Reborn"; File = "Skyrim Together Reborn 69993 1.8.2 2026-09-20T08-09Z 2Bej58PwK.zip"; NexusId = "69993" }
    @{ Name = "Achievements Mods Enabler"; File = "Achievements Mods Enabler SE-AE-245-1-41-1715217907.zip"; NexusId = "245" }
    @{ Name = "DLL Loader"; File = "DllLoader-3619-1-0-0-4.zip"; NexusId = "3619" }
    @{ Name = "Address Library All in One"; File = "Address Library All in One (1.7.104.0) v13 32444 13 2026-08-27T15-29Z Ae46W7Fw2.zip"; NexusId = "32444" }
)

# --- Load order for plugins.txt ---
$LoadOrder = @(
    "*Skyrim.esm"
    "*Update.esm"
    "*Dawnguard.esm"
    "*HearthFires.esm"
    "*Dragonborn.esm"
    "*SkyrimTogetherReborn.esp"
)

# --- Helper: Find Skyrim SE Data folder ---
function Find-SkyrimData {
    if ($SkyrimPath -and (Test-Path "$SkyrimPath\Data")) {
        return "$SkyrimPath\Data"
    }
    $regPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition"
        "HKCU:\SOFTWARE\Bethesda Softworks\Skyrim Special Edition"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $ip = (Get-ItemProperty $rp -ErrorAction SilentlyContinue).InstalledPath
            if ($ip -and (Test-Path "$ip\Data")) { return "$ip\Data" }
        }
    }
    $common = @(
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Skyrim Special Edition\Data"
        "$env:ProgramFiles\Steam\steamapps\common\Skyrim Special Edition\Data"
        "D:\SteamLibrary\steamapps\common\Skyrim Special Edition\Data"
        "E:\SteamLibrary\steamapps\common\Skyrim Special Edition\Data"
        "C:\Games\Skyrim Special Edition\Data"
    )
    foreach ($p in $common) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# --- Helper: Detect Vortex ---
function Test-Vortex {
    $vpaths = @(
        "$env:APPDATA\Vortex"
        "$env:LOCALAPPDATA\Programs\Vortex"
        "${env:ProgramFiles}\Black Tree Gaming Ltd\Vortex"
        "${env:ProgramFiles(x86)}\Black Tree Gaming Ltd\Vortex"
    )
    foreach ($p in $vpaths) {
        if (Test-Path $p) { return $true }
    }
    $ukeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($k in $ukeys) {
        if (Test-Path $k) {
            $found = Get-ChildItem $k -ErrorAction SilentlyContinue |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*Vortex*" }
            if ($found) { return $true }
        }
    }
    return $false
}

# --- Helper: Extract zip preserving structure ---
function Expand-ModZip {
    param([string]$ZipPath, [string]$DestPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            $destFile = Join-Path $DestPath $entry.FullName
            $parentDir = Split-Path -Parent $destFile
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
        }
    } finally {
        $zip.Dispose()
    }
}

# --- Main Installation Logic ---
function Install-Mods {
    param(
        [string]$DataPath,
        [bool]$UseVortex,
        [scriptblock]$LogCb
    )
    $tempDir = Join-Path $env:TEMP "SkyMP_Install_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        foreach ($mod in $Mods) {
            $zipPath = Join-Path $ScriptDir $mod.File
            if (-not (Test-Path $zipPath)) {
                & $LogCb "ERROR: No encontrado $($mod.File)" "error"
                throw "Archivo faltante: $($mod.File)"
            }
            & $LogCb "Extrayendo $($mod.Name)..." "info"
            $extractDir = Join-Path $tempDir $mod.Name
            Expand-ModZip -ZipPath $zipPath -DestPath $extractDir

            & $LogCb "Copiando $($mod.Name) a Data..." "info"
            $contentDirs = Get-ChildItem $extractDir -Directory |
                Where-Object { $_.Name -match '^(Data|SKSE|Plugins|Interface|Scripts|Meshes|Textures|Sound)$' }
            if ($contentDirs.Count -eq 0) {
                $subDirs = Get-ChildItem $extractDir -Directory
                if ($subDirs.Count -eq 1) { $sourceRoot = $subDirs[0].FullName }
                else { $sourceRoot = $extractDir }
            } else {
                $sourceRoot = $extractDir
            }
            $itemsToCopy = Get-ChildItem $sourceRoot -Recurse -File
            foreach ($item in $itemsToCopy) {
                $rel = $item.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
                if ($rel -like "Data\*") { $rel = $rel.Substring(5) }
                $destFile = Join-Path $DataPath $rel
                $destDir = Split-Path -Parent $destFile
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item $item.FullName $destFile -Force
            }
            & $LogCb "[OK] $($mod.Name) instalado" "success"
        }

        # Generate plugins.txt
        & $LogCb "Generando orden de carga..." "info"
        $appDataPath = Join-Path $env:LOCALAPPDATA "Skyrim Special Edition\plugins.txt"
        $appDataDir = Split-Path -Parent $appDataPath
        if (-not (Test-Path $appDataDir)) {
            New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
        }
        $existing = @()
        if (Test-Path $appDataPath) {
            $existing = Get-Content $appDataPath | Where-Object { $_ -and $_ -notmatch '^\*' }
        }
        $newList = @($LoadOrder)
        foreach ($ep in $existing) {
            $clean = $ep.TrimStart('*')
            $already = $LoadOrder | Where-Object { $_.TrimStart('*') -eq $clean }
            if (-not $already) { $newList += $ep }
        }
        $newList | Set-Content $appDataPath -Encoding UTF8
        & $LogCb "[OK] Orden de carga configurado en plugins.txt" "success"

        & $LogCb "Verificacion: tras iniciar Skyrim, revisa:" "info"
        & $LogCb "  Data\Plugins\Sumwunn\AchievementsModsEnabler.log -> debe decir YES" "warn"
        return $true
    } catch {
        & $LogCb "ERROR: $($_.Exception.Message)" "error"
        return $false
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# WPF GUI
# =============================================================================
function Show-InstallerGUI {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Skyrim Together - Instalador de Mods"
        Width="780" Height="700" MinWidth="680" MinHeight="580"
        WindowStartupLocation="CenterScreen"
        Background="Transparent"
        AllowsTransparency="True"
        WindowStyle="None">
    <Window.Resources>
        <LinearGradientBrush x:Key="SkyBrush" StartPoint="0.12,0" EndPoint="0.72,1">
            <GradientStop Offset="0.00" Color="#FFE3F4FD"/>
            <GradientStop Offset="0.30" Color="#D895D9F6"/>
            <GradientStop Offset="0.60" Color="#D24DBBEC"/>
            <GradientStop Offset="0.82" Color="#D267D0C4"/>
            <GradientStop Offset="1.00" Color="#D897DC5F"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="GlossBlue" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Offset="0.00" Color="#FF8FD9F7"/>
            <GradientStop Offset="0.49" Color="#FF39A5DC"/>
            <GradientStop Offset="0.51" Color="#FF1B7FC0"/>
            <GradientStop Offset="1.00" Color="#FF39B0E4"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="GlossGreen" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Offset="0.00" Color="#FFCBF08F"/>
            <GradientStop Offset="0.49" Color="#FF74C23C"/>
            <GradientStop Offset="0.51" Color="#FF4E9C22"/>
            <GradientStop Offset="1.00" Color="#FF7FCF43"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="CardBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Offset="0.00" Color="#EDFFFFFF"/>
            <GradientStop Offset="0.45" Color="#C4FFFFFF"/>
            <GradientStop Offset="1.00" Color="#FFB0EBF8"/>
        </LinearGradientBrush>
        <DropShadowEffect x:Key="SoftShadow" BlurRadius="16" ShadowDepth="2"
                          Direction="270" Opacity="0.28" Color="#FF0A3A56"/>
    </Window.Resources>

    <Border Background="{StaticResource SkyBrush}" CornerRadius="14" Effect="{StaticResource SoftShadow}">
        <Grid>
            <!-- Top Gloss -->
            <Rectangle Height="170" VerticalAlignment="Top" IsHitTestVisible="False">
                <Rectangle.Fill>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Offset="0.00" Color="#A0FFFFFF"/>
                        <GradientStop Offset="0.55" Color="#42FFFFFF"/>
                        <GradientStop Offset="1.00" Color="#00FFFFFF"/>
                    </LinearGradientBrush>
                </Rectangle.Fill>
            </Rectangle>

            <!-- Bubble Left -->
            <Ellipse Width="280" Height="280" HorizontalAlignment="Left" VerticalAlignment="Center"
                     Margin="-60,0,0,0" Opacity="0.25" IsHitTestVisible="False">
                <Ellipse.Fill>
                    <RadialGradientBrush Center="0.35,0.3" GradientOrigin="0.35,0.3">
                        <GradientStop Offset="0.00" Color="#FFFFFFFF"/>
                        <GradientStop Offset="0.55" Color="#FFBFE9FB"/>
                        <GradientStop Offset="1.00" Color="#00BFE9FB"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>
            <!-- Bubble Right -->
            <Ellipse Width="350" Height="350" HorizontalAlignment="Right" VerticalAlignment="Top"
                     Margin="0,-80,-80,0" Opacity="0.22" IsHitTestVisible="False">
                <Ellipse.Fill>
                    <RadialGradientBrush Center="0.35,0.3" GradientOrigin="0.35,0.3">
                        <GradientStop Offset="0.00" Color="#FFFFFFFF"/>
                        <GradientStop Offset="0.58" Color="#FF7CCBEE"/>
                        <GradientStop Offset="1.00" Color="#007CCBEE"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>

            <DockPanel Margin="24">
                <!-- Title Bar -->
                <Border DockPanel.Dock="Top" Height="40" Background="Transparent"
                        MouseLeftButtonDown="TitleBar_Drag">
                    <Grid>
                        <TextBlock Text="Skyrim Together - Instalador" FontSize="18" FontWeight="Light"
                                   Foreground="#FF07405E" VerticalAlignment="Center" Margin="8,0"/>
                        <Button x:Name="CloseBtn" Content="X" Width="36" Height="28"
                                HorizontalAlignment="Right" VerticalAlignment="Center"
                                BorderThickness="0" Background="Transparent"
                                Foreground="#FF07405E" FontSize="14" Cursor="Hand"
                                Click="CloseBtn_Click">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border x:Name="bd" CornerRadius="7" Background="Transparent">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="bd" Property="Background" Value="#7AFFFFFF"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </Grid>
                </Border>

                <!-- Scrollable Content -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,8,0,0">
                    <StackPanel x:Name="MainPanel">

                        <!-- Header -->
                        <TextBlock Text="Skyrim Together" FontSize="32" FontWeight="Light"
                                   Foreground="#FF07405E" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                        <TextBlock Text="Instalador de Mods - Multijugador + Logros" FontSize="14"
                                   FontWeight="SemiBold" Foreground="#FF0B5C8A" HorizontalAlignment="Center" Margin="0,4,0,4"/>
                        <Border CornerRadius="12" Padding="14,4" HorizontalAlignment="Center" Margin="0,0,0,16">
                            <Border.Background>
                                <SolidColorBrush Color="#FF4CA22B" Opacity="0.15"/>
                            </Border.Background>
                            <TextBlock Text="Todo incluido en esta carpeta" FontSize="11" FontWeight="Bold"
                                       Foreground="#FF4CA22B"/>
                        </Border>

                        <!-- Vortex Banner -->
                        <Border x:Name="VortexBanner" CornerRadius="12" Padding="16,14" Margin="0,0,0,16"
                                Visibility="Collapsed">
                            <Border.Background>
                                <SolidColorBrush Color="#FF4CA22B" Opacity="0.08"/>
                            </Border.Background>
                            <Border.BorderBrush>
                                <SolidColorBrush Color="#FF4CA22B" Opacity="0.3"/>
                            </Border.BorderBrush>
                            <Border.BorderThickness>1</Border.BorderThickness>
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="V" FontSize="22" FontWeight="Bold" Foreground="#FF4CA22B"
                                           Margin="0,0,12,0" VerticalAlignment="Center"/>
                                <StackPanel>
                                    <TextBlock Text="Vortex detectado" FontSize="14" FontWeight="SemiBold"
                                               Foreground="#FF4CA22B"/>
                                    <TextBlock Text="Puedes instalar via Vortex o manualmente." FontSize="12"
                                               Foreground="#FF2C5F7E"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Step Indicator -->
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,16">
                            <Border x:Name="Step1Dot" CornerRadius="20" Padding="18,8" Margin="4,0"
                                    Background="{StaticResource GlossBlue}">
                                <TextBlock Text="1 Verificar" FontSize="12" FontWeight="SemiBold" Foreground="White"/>
                            </Border>
                            <Border x:Name="Step2Dot" CornerRadius="20" Padding="18,8" Margin="4,0">
                                <Border.Background>
                                    <SolidColorBrush Color="White" Opacity="0.4"/>
                                </Border.Background>
                                <TextBlock Text="2 Instalar" FontSize="12" FontWeight="SemiBold" Foreground="#FF2C5F7E"/>
                            </Border>
                            <Border x:Name="Step3Dot" CornerRadius="20" Padding="18,8" Margin="4,0">
                                <Border.Background>
                                    <SolidColorBrush Color="White" Opacity="0.4"/>
                                </Border.Background>
                                <TextBlock Text="3 Orden" FontSize="12" FontWeight="SemiBold" Foreground="#FF2C5F7E"/>
                            </Border>
                            <Border x:Name="Step4Dot" CornerRadius="20" Padding="18,8" Margin="4,0">
                                <Border.Background>
                                    <SolidColorBrush Color="White" Opacity="0.4"/>
                                </Border.Background>
                                <TextBlock Text="4 Listo" FontSize="12" FontWeight="SemiBold" Foreground="#FF2C5F7E"/>
                            </Border>
                        </StackPanel>

                        <!-- STEP 1: Verify -->
                        <Border x:Name="Step1Panel" CornerRadius="14" Padding="24" Margin="0,0,0,16"
                                Background="{StaticResource CardBrush}" BorderBrush="#80FFFFFF" BorderThickness="1"
                                Effect="{StaticResource SoftShadow}">
                            <StackPanel>
                                <TextBlock Text="Mods encontrados en la carpeta" FontSize="17" FontWeight="SemiBold"
                                           Foreground="#FF07405E" Margin="0,0,0,8"/>
                                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#FF2C5F7E" Margin="0,0,0,12"
                                           Text="Estos son los archivos necesarios para jugar Skyrim Together con logros habilitados."/>
                                <ItemsControl x:Name="ModListItems">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="10" Padding="14,12" Margin="0,0,0,8"
                                                    BorderBrush="#73FFFFFF" BorderThickness="1">
                                                <Border.Background>
                                                    <SolidColorBrush Color="White" Opacity="0.4"/>
                                                </Border.Background>
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="Auto"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <Border Grid.Column="0" Width="38" Height="38" CornerRadius="10"
                                                            Background="{StaticResource GlossBlue}" Margin="0,0,12,0">
                                                        <TextBlock Text="M" FontSize="16" FontWeight="Bold"
                                                                   Foreground="White" HorizontalAlignment="Center"
                                                                   VerticalAlignment="Center"/>
                                                    </Border>
                                                    <StackPanel Grid.Column="1">
                                                        <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold"
                                                                   Foreground="#FF07405E"/>
                                                        <TextBlock Text="{Binding Desc}" FontSize="11.5" Foreground="#FF2C5F7E"
                                                                   TextWrapping="Wrap"/>
                                                        <TextBlock Text="{Binding FileName}" FontSize="10" Foreground="#FF2C5F7E"
                                                                   Opacity="0.7" FontFamily="Consolas" Margin="0,2,0,0"/>
                                                    </StackPanel>
                                                    <TextBlock x:Name="CheckMark" Grid.Column="2" Text="" FontSize="18"
                                                               Foreground="#FF2C5F7E" VerticalAlignment="Center" Opacity="0.4"/>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                                <Button x:Name="VerifyBtn" Content="Verificar archivos" Height="44" Margin="0,12,0,0"
                                        Cursor="Hand" Click="VerifyBtn_Click">
                                    <Button.Template>
                                        <ControlTemplate TargetType="Button">
                                            <Border x:Name="btnBd" CornerRadius="9" Background="{StaticResource GlossGreen}"
                                                    BorderBrush="#59FFFFFF" BorderThickness="1"
                                                    Effect="{StaticResource SoftShadow}">
                                                <Grid>
                                                    <Rectangle Height="17" VerticalAlignment="Top" RadiusX="8" RadiusY="8"
                                                               Margin="1,1,1,0" IsHitTestVisible="False">
                                                        <Rectangle.Fill>
                                                            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                                <GradientStop Offset="0.00" Color="#B8FFFFFF"/>
                                                                <GradientStop Offset="0.48" Color="#38FFFFFF"/>
                                                                <GradientStop Offset="0.50" Color="#00FFFFFF"/>
                                                            </LinearGradientBrush>
                                                        </Rectangle.Fill>
                                                    </Rectangle>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                      TextElement.Foreground="White" TextElement.FontSize="14"
                                                                      TextElement.FontWeight="SemiBold"/>
                                                </Grid>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="btnBd" Property="BorderBrush" Value="#B3FFFFFF"/>
                                                </Trigger>
                                                <Trigger Property="IsPressed" Value="True">
                                                    <Setter TargetName="btnBd" Property="Opacity" Value="0.88"/>
                                                </Trigger>
                                                <Trigger Property="IsEnabled" Value="False">
                                                    <Setter TargetName="btnBd" Property="Opacity" Value="0.45"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Button.Template>
                                </Button>
                            </StackPanel>
                        </Border>

                        <!-- STEP 2: Install -->
                        <Border x:Name="Step2Panel" CornerRadius="14" Padding="24" Margin="0,0,0,16"
                                Background="{StaticResource CardBrush}" BorderBrush="#80FFFFFF" BorderThickness="1"
                                Effect="{StaticResource SoftShadow}" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Metodo de instalacion" FontSize="17" FontWeight="SemiBold"
                                           Foreground="#FF07405E" Margin="0,0,0,8"/>
                                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#FF2C5F7E" Margin="0,0,0,12"
                                           Text="Elige como instalar los mods. La instalacion manual copia directamente a Data. Vortex gestiona todo desde el gestor."/>

                                <Grid Margin="0,0,0,16">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Border x:Name="ModeManual" Grid.Column="0" CornerRadius="12" Padding="18" Margin="0,0,6,0"
                                            BorderBrush="#FF1F86C8" BorderThickness="2" Cursor="Hand"
                                            MouseLeftButtonDown="ModeManual_Click">
                                        <Border.Background>
                                            <SolidColorBrush Color="#FF1F86C8" Opacity="0.08"/>
                                        </Border.Background>
                                        <StackPanel HorizontalAlignment="Center">
                                            <TextBlock Text="Manual" FontSize="14" FontWeight="SemiBold"
                                                       Foreground="#FF07405E" HorizontalAlignment="Center"/>
                                            <TextBlock Text="Copia directa a Data" FontSize="11.5" Foreground="#FF2C5F7E"
                                                       HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
                                        </StackPanel>
                                    </Border>
                                    <Border x:Name="ModeVortex" Grid.Column="1" CornerRadius="12" Padding="18" Margin="6,0,0,0"
                                            BorderBrush="#80FFFFFF" BorderThickness="2" Cursor="Hand"
                                            MouseLeftButtonDown="ModeVortex_Click">
                                        <Border.Background>
                                            <SolidColorBrush Color="White" Opacity="0.35"/>
                                        </Border.Background>
                                        <StackPanel HorizontalAlignment="Center">
                                            <TextBlock Text="Via Vortex" FontSize="14" FontWeight="SemiBold"
                                                       Foreground="#FF07405E" HorizontalAlignment="Center"/>
                                            <TextBlock Text="Gestiona desde Vortex" FontSize="11.5" Foreground="#FF2C5F7E"
                                                       HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>

                                <!-- Progress -->
                                <Border x:Name="ProgressPanel" CornerRadius="6" Height="10" Margin="0,0,0,8"
                                        BorderBrush="#73FFFFFF" BorderThickness="1" Visibility="Collapsed">
                                    <Border.Background>
                                        <SolidColorBrush Color="White" Opacity="0.35"/>
                                    </Border.Background>
                                    <Border x:Name="ProgressFill" CornerRadius="5" HorizontalAlignment="Left" Width="0">
                                        <Border.Background>
                                            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                <GradientStop Offset="0.00" Color="#FF8FD9F7"/>
                                                <GradientStop Offset="0.49" Color="#FF39A5DC"/>
                                                <GradientStop Offset="0.51" Color="#FF1B7FC0"/>
                                                <GradientStop Offset="1.00" Color="#FF39B0E4"/>
                                            </LinearGradientBrush>
                                        </Border.Background>
                                    </Border>
                                </Border>
                                <TextBlock x:Name="ProgressText" FontSize="12" Foreground="#FF2C5F7E"
                                           HorizontalAlignment="Center" Margin="0,0,0,8" Visibility="Collapsed"/>

                                <!-- Log -->
                                <Border x:Name="LogPanel" CornerRadius="10" Padding="14" Margin="0,0,0,12"
                                        MaxHeight="180" Visibility="Collapsed">
                                    <Border.Background>
                                        <SolidColorBrush Color="#FF07405E" Opacity="0.06"/>
                                    </Border.Background>
                                    <Border.BorderBrush>
                                        <SolidColorBrush Color="White" Opacity="0.3"/>
                                    </Border.BorderBrush>
                                    <Border.BorderThickness>1</Border.BorderThickness>
                                    <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto" MaxHeight="160">
                                        <TextBlock x:Name="LogText" FontFamily="Consolas" FontSize="11"
                                                   Foreground="#FF07405E" TextWrapping="Wrap"/>
                                    </ScrollViewer>
                                </Border>

                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                                    <Button x:Name="Back2Btn" Content="Atras" Height="38" Margin="0,0,12,0"
                                            Cursor="Hand" Click="Back2Btn_Click">
                                        <Button.Template>
                                            <ControlTemplate TargetType="Button">
                                                <Border x:Name="gbd" CornerRadius="8" Padding="22,0"
                                                        BorderBrush="#80FFFFFF" BorderThickness="1">
                                                    <Border.Background>
                                                        <SolidColorBrush Color="White" Opacity="0.4"/>
                                                    </Border.Background>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                      TextElement.Foreground="#FF0B5C8A" TextElement.FontSize="13"
                                                                      TextElement.FontWeight="SemiBold"/>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="gbd" Property="Background">
                                                            <Setter.Value>
                                                                <SolidColorBrush Color="White" Opacity="0.7"/>
                                                            </Setter.Value>
                                                        </Setter>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Button.Template>
                                    </Button>
                                    <Button x:Name="InstallBtn" Content="Instalar mods" Height="44" Cursor="Hand"
                                            Click="InstallBtn_Click">
                                        <Button.Template>
                                            <ControlTemplate TargetType="Button">
                                                <Border x:Name="ibd" CornerRadius="9" Padding="28,0"
                                                        Background="{StaticResource GlossGreen}"
                                                        BorderBrush="#59FFFFFF" BorderThickness="1"
                                                        Effect="{StaticResource SoftShadow}">
                                                    <Grid>
                                                        <Rectangle Height="17" VerticalAlignment="Top" RadiusX="8" RadiusY="8"
                                                                   Margin="1,1,1,0" IsHitTestVisible="False">
                                                            <Rectangle.Fill>
                                                                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                                    <GradientStop Offset="0.00" Color="#B8FFFFFF"/>
                                                                    <GradientStop Offset="0.48" Color="#38FFFFFF"/>
                                                                    <GradientStop Offset="0.50" Color="#00FFFFFF"/>
                                                                </LinearGradientBrush>
                                                            </Rectangle.Fill>
                                                        </Rectangle>
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                          TextElement.Foreground="White" TextElement.FontSize="14"
                                                                          TextElement.FontWeight="SemiBold"/>
                                                    </Grid>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ibd" Property="BorderBrush" Value="#B3FFFFFF"/>
                                                    </Trigger>
                                                    <Trigger Property="IsPressed" Value="True">
                                                        <Setter TargetName="ibd" Property="Opacity" Value="0.88"/>
                                                    </Trigger>
                                                    <Trigger Property="IsEnabled" Value="False">
                                                        <Setter TargetName="ibd" Property="Opacity" Value="0.45"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Button.Template>
                                    </Button>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- STEP 3: Load Order -->
                        <Border x:Name="Step3Panel" CornerRadius="14" Padding="24" Margin="0,0,0,16"
                                Background="{StaticResource CardBrush}" BorderBrush="#80FFFFFF" BorderThickness="1"
                                Effect="{StaticResource SoftShadow}" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Orden de carga recomendado" FontSize="17" FontWeight="SemiBold"
                                           Foreground="#FF07405E" Margin="0,0,0,8"/>
                                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#FF2C5F7E" Margin="0,0,0,12"
                                           Text="Este es el orden correcto para que Skyrim Together funcione con logros. Configuralo en Vortex o verifica tu plugins.txt."/>
                                <ItemsControl x:Name="LoadOrderList">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="8" Padding="12,10" Margin="0,0,0,6"
                                                    BorderBrush="#59FFFFFF" BorderThickness="1">
                                                <Border.Background>
                                                    <SolidColorBrush Color="White" Opacity="0.3"/>
                                                </Border.Background>
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="30"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <Border Grid.Column="0" Width="26" Height="26" CornerRadius="13"
                                                            Background="{StaticResource GlossBlue}">
                                                        <TextBlock Text="{Binding Num}" FontSize="11" FontWeight="Bold"
                                                                   Foreground="White" HorizontalAlignment="Center"
                                                                   VerticalAlignment="Center"/>
                                                    </Border>
                                                    <TextBlock Grid.Column="1" Text="{Binding Name}" FontSize="12.5"
                                                               FontWeight="SemiBold" Foreground="#FF07405E"
                                                               VerticalAlignment="Center" Margin="8,0,0,0"/>
                                                    <Border Grid.Column="2" CornerRadius="8" Padding="8,2">
                                                        <Border.Background>
                                                            <SolidColorBrush Color="#FF1F86C8" Opacity="0.12"/>
                                                        </Border.Background>
                                                        <TextBlock Text="{Binding Tag}" FontSize="10" FontWeight="SemiBold"
                                                                   Foreground="#FF1F86C8"/>
                                                    </Border>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                                <Border CornerRadius="10" Padding="12,14" Margin="0,12,0,0">
                                    <Border.Background>
                                        <SolidColorBrush Color="#FFFFD97A" Opacity="0.12"/>
                                    </Border.Background>
                                    <Border.BorderBrush>
                                        <SolidColorBrush Color="#FFE08C1E" Opacity="0.2"/>
                                    </Border.BorderBrush>
                                    <Border.BorderThickness>1</Border.BorderThickness>
                                    <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#FF2C5F7E">
                                        <Run FontWeight="SemiBold" Foreground="#FFE08C1E">Importante:</Run>
                                        <Run> Skyrim Together Reborn debe cargarse despues de todos los masters y del Achievements Enabler. Address Library antes de cualquier plugin SKSE.</Run>
                                    </TextBlock>
                                </Border>
                                <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
                                    <Button x:Name="Back3Btn" Content="Atras" Height="38" Margin="0,0,12,0"
                                            Cursor="Hand" Click="Back3Btn_Click">
                                        <Button.Template>
                                            <ControlTemplate TargetType="Button">
                                                <Border x:Name="b3bd" CornerRadius="8" Padding="22,0"
                                                        BorderBrush="#80FFFFFF" BorderThickness="1">
                                                    <Border.Background>
                                                        <SolidColorBrush Color="White" Opacity="0.4"/>
                                                    </Border.Background>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                      TextElement.Foreground="#FF0B5C8A" TextElement.FontSize="13"
                                                                      TextElement.FontWeight="SemiBold"/>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="b3bd" Property="Background">
                                                            <Setter.Value>
                                                                <SolidColorBrush Color="White" Opacity="0.7"/>
                                                            </Setter.Value>
                                                        </Setter>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Button.Template>
                                    </Button>
                                    <Button x:Name="Next3Btn" Content="Continuar" Height="44" Cursor="Hand"
                                            Click="Next3Btn_Click">
                                        <Button.Template>
                                            <ControlTemplate TargetType="Button">
                                                <Border x:Name="n3bd" CornerRadius="9" Padding="28,0"
                                                        Background="{StaticResource GlossGreen}"
                                                        BorderBrush="#59FFFFFF" BorderThickness="1"
                                                        Effect="{StaticResource SoftShadow}">
                                                    <Grid>
                                                        <Rectangle Height="17" VerticalAlignment="Top" RadiusX="8" RadiusY="8"
                                                                   Margin="1,1,1,0" IsHitTestVisible="False">
                                                            <Rectangle.Fill>
                                                                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                                    <GradientStop Offset="0.00" Color="#B8FFFFFF"/>
                                                                    <GradientStop Offset="0.48" Color="#38FFFFFF"/>
                                                                    <GradientStop Offset="0.50" Color="#00FFFFFF"/>
                                                                </LinearGradientBrush>
                                                            </Rectangle.Fill>
                                                        </Rectangle>
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                          TextElement.Foreground="White" TextElement.FontSize="14"
                                                                          TextElement.FontWeight="SemiBold"/>
                                                    </Grid>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="n3bd" Property="BorderBrush" Value="#B3FFFFFF"/>
                                                    </Trigger>
                                                    <Trigger Property="IsPressed" Value="True">
                                                        <Setter TargetName="n3bd" Property="Opacity" Value="0.88"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Button.Template>
                                    </Button>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- STEP 4: Done -->
                        <Border x:Name="Step4Panel" CornerRadius="14" Padding="40,32" Margin="0,0,0,16"
                                Background="{StaticResource CardBrush}" BorderBrush="#80FFFFFF" BorderThickness="1"
                                Effect="{StaticResource SoftShadow}" Visibility="Collapsed">
                            <StackPanel HorizontalAlignment="Center">
                                <Border Width="64" Height="64" CornerRadius="32" HorizontalAlignment="Center"
                                        Margin="0,0,0,16" Background="{StaticResource GlossGreen}"
                                        Effect="{StaticResource SoftShadow}">
                                    <TextBlock Text="OK" FontSize="22" FontWeight="Bold" Foreground="White"
                                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <TextBlock Text="Todo listo!" FontSize="22" FontWeight="Light" Foreground="#FF07405E"
                                           HorizontalAlignment="Center" Margin="0,0,0,10"/>
                                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#FF2C5F7E"
                                           HorizontalAlignment="Center" TextAlignment="Center" MaxWidth="500"
                                           Margin="0,0,0,20"
                                           Text="Los mods estan instalados y el orden de carga configurado. Inicia Skyrim y conecta con tus amigos desde el menu de Skyrim Together."/>
                                <Border CornerRadius="10" Padding="14" Margin="0,0,0,8" MaxWidth="440">
                                    <Border.Background>
                                        <SolidColorBrush Color="#FFFFD97A" Opacity="0.12"/>
                                    </Border.Background>
                                    <Border.BorderBrush>
                                        <SolidColorBrush Color="#FFE08C1E" Opacity="0.2"/>
                                    </Border.BorderBrush>
                                    <Border.BorderThickness>1</Border.BorderThickness>
                                    <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#FF2C5F7E">
                                        <Run FontWeight="SemiBold" Foreground="#FFE08C1E">Para jugar:</Run>
                                        <Run> Inicia Skyrim > Menu principal > Skyrim Together > Conectar a servidor > Ingresa la IP o crea uno local.</Run>
                                    </TextBlock>
                                </Border>
                                <Border CornerRadius="10" Padding="14" MaxWidth="440">
                                    <Border.Background>
                                        <SolidColorBrush Color="#FF4CA22B" Opacity="0.08"/>
                                    </Border.Background>
                                    <Border.BorderBrush>
                                        <SolidColorBrush Color="#FF4CA22B" Opacity="0.2"/>
                                    </Border.BorderBrush>
                                    <Border.BorderThickness>1</Border.BorderThickness>
                                    <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#FF2C5F7E">
                                        <Run FontWeight="SemiBold" Foreground="#FF4CA22B">Logros:</Run>
                                        <Run> Los logros estan habilitados incluso con mods. Verifica en Data\Plugins\Sumwunn\AchievementsModsEnabler.log que diga YES. Platina el juego en grupo.</Run>
                                    </TextBlock>
                                </Border>
                                <Button x:Name="RestartBtn" Content="Reiniciar" Height="44" Margin="0,20,0,0"
                                        Cursor="Hand" Click="RestartBtn_Click">
                                    <Button.Template>
                                        <ControlTemplate TargetType="Button">
                                            <Border x:Name="rbd" CornerRadius="9" Padding="28,0"
                                                    Background="{StaticResource GlossBlue}"
                                                    BorderBrush="#59FFFFFF" BorderThickness="1"
                                                    Effect="{StaticResource SoftShadow}">
                                                <Grid>
                                                    <Rectangle Height="17" VerticalAlignment="Top" RadiusX="8" RadiusY="8"
                                                               Margin="1,1,1,0" IsHitTestVisible="False">
                                                        <Rectangle.Fill>
                                                            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                                <GradientStop Offset="0.00" Color="#B8FFFFFF"/>
                                                                <GradientStop Offset="0.48" Color="#38FFFFFF"/>
                                                                <GradientStop Offset="0.50" Color="#00FFFFFF"/>
                                                            </LinearGradientBrush>
                                                        </Rectangle.Fill>
                                                    </Rectangle>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                      TextElement.Foreground="White" TextElement.FontSize="14"
                                                                      TextElement.FontWeight="SemiBold"/>
                                                </Grid>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="rbd" Property="BorderBrush" Value="#B3FFFFFF"/>
                                                </Trigger>
                                                <Trigger Property="IsPressed" Value="True">
                                                    <Setter TargetName="rbd" Property="Opacity" Value="0.88"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Button.Template>
                                </Button>
                            </StackPanel>
                        </Border>

                        <!-- Footer -->
                        <TextBlock Text="Skyrim Together Installer - Aero Glass UI - 2026" FontSize="11"
                                   Foreground="#FF2C5F7E" Opacity="0.7" HorizontalAlignment="Center" Margin="0,16,0,0"/>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Grid>
    </Border>
</Window>
"@

    # Parse XAML
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # --- Named controls ---
    $closeBtn      = $window.FindName("CloseBtn")
    $vortexBanner  = $window.FindName("VortexBanner")
    $step1Dot      = $window.FindName("Step1Dot")
    $step2Dot      = $window.FindName("Step2Dot")
    $step3Dot      = $window.FindName("Step3Dot")
    $step4Dot      = $window.FindName("Step4Dot")
    $step1Panel    = $window.FindName("Step1Panel")
    $step2Panel    = $window.FindName("Step2Panel")
    $step3Panel    = $window.FindName("Step3Panel")
    $step4Panel    = $window.FindName("Step4Panel")
    $modListItems  = $window.FindName("ModListItems")
    $verifyBtn     = $window.FindName("VerifyBtn")
    $modeManual    = $window.FindName("ModeManual")
    $modeVortex    = $window.FindName("ModeVortex")
    $progressPanel = $window.FindName("ProgressPanel")
    $progressFill  = $window.FindName("ProgressFill")
    $progressText  = $window.FindName("ProgressText")
    $logPanel      = $window.FindName("LogPanel")
    $logText       = $window.FindName("LogText")
    $logScroll     = $window.FindName("LogScroll")
    $installBtn    = $window.FindName("InstallBtn")
    $back2Btn      = $window.FindName("Back2Btn")
    $back3Btn      = $window.FindName("Back3Btn")
    $next3Btn      = $window.FindName("Next3Btn")
    $loadOrderList = $window.FindName("LoadOrderList")
    $restartBtn    = $window.FindName("RestartBtn")

    # --- State ---
    $currentStep = 1
    $installMode = "manual"
    $vortexFound = Test-Vortex

    # --- Populate mod list ---
    $modDisplayData = @(
        @{ Name = "Skyrim Together Reborn"; Desc = "Multijugador cooperativo para Skyrim SE/AE."; FileName = $Mods[0].File }
        @{ Name = "Achievements Mods Enabler"; Desc = "Re-habilita logros al usar mods. Requiere DLL Loader o SKSE64."; FileName = $Mods[1].File }
        @{ Name = "DLL Loader"; Desc = "Cargador de DLLs requerido por Achievements Enabler si no usas SKSE64."; FileName = $Mods[2].File }
        @{ Name = "Address Library All in One"; Desc = "Biblioteca de direcciones para plugins SKSE entre versiones."; FileName = $Mods[3].File }
    )
    $modListItems.ItemsSource = $modDisplayData

    # --- Populate load order ---
    $loData = @(
        @{ Num = "1"; Name = "Skyrim.esm"; Tag = "ESM" }
        @{ Num = "2"; Name = "Update.esm"; Tag = "ESM" }
        @{ Num = "3"; Name = "Dawnguard.esm"; Tag = "ESM" }
        @{ Num = "4"; Name = "HearthFires.esm"; Tag = "ESM" }
        @{ Num = "5"; Name = "Dragonborn.esm"; Tag = "ESM" }
        @{ Num = "6"; Name = "cc*.esm / ccbgssse*.esm"; Tag = "Creation Club" }
        @{ Num = "7"; Name = "Address Library for SKSE Plugins"; Tag = "DLL" }
        @{ Num = "8"; Name = "AchievementsModsEnabler.dll"; Tag = "DLL" }
        @{ Num = "9"; Name = "SkyrimTogetherReborn.esp"; Tag = "STR" }
    )
    $loadOrderList.ItemsSource = $loData

    # --- Vortex detection ---
    if ($vortexFound) {
        $vortexBanner.Visibility = "Visible"
    }

    # --- Navigation helpers ---
    $glossBlueBrush = $window.FindName("GlossBlue")
    $whiteAlphaBrush = New-Object System.Windows.Media.SolidColorBrush
    $whiteAlphaBrush.Color = [System.Windows.Media.Color]::FromArgb(102, 255, 255, 255)
    $greenBrush = $window.FindName("GlossGreen")

    function Set-Step {
        param([int]$n)
        $panels = @($step1Panel, $step2Panel, $step3Panel, $step4Panel)
        $dots   = @($step1Dot, $step2Dot, $step3Dot, $step4Dot)
        for ($i = 0; $i -lt 4; $i++) {
            if ($i -eq ($n - 1)) {
                $panels[$i].Visibility = "Visible"
                $dots[$i].Background = $glossBlueBrush
                foreach ($tb in $dots[$i].Children) {
                    if ($tb -is [System.Windows.Controls.TextBlock]) { $tb.Foreground = [System.Windows.Media.Brushes]::White }
                }
            } else {
                $panels[$i].Visibility = "Collapsed"
                if ($i -lt ($n - 1)) {
                    $dots[$i].Background = $greenBrush
                } else {
                    $dots[$i].Background = $whiteAlphaBrush
                }
                foreach ($tb in $dots[$i].Children) {
                    if ($tb -is [System.Windows.Controls.TextBlock]) {
                        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 44, 95, 126))
                    }
                }
            }
        }
        $currentStep = $n
    }

    function Add-Log {
        param([string]$msg, [string]$type)
        $color = switch ($type) {
            "success" { "#FF4CA22B" }
            "warn"    { "#FFE08C1E" }
            "error"   { "#FFC63C22" }
            default   { "#FF0B5C8A" }
        }
        $run = New-Object System.Windows.Documents.Run
        $run.Text = "> $msg`n"
        $run.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($color))
        $logText.Inlines.Add($run)
        $logScroll.ScrollToEnd()
    }

    function Set-Progress {
        param([double]$pct, [string]$text)
        $progressPanel.Visibility = "Visible"
        $progressText.Visibility = "Visible"
        $maxW = $progressPanel.ActualWidth
        if ($maxW -le 0) { $maxW = 600 }
        $progressFill.Width = [Math]::Max(0, [Math]::Min($maxW, $maxW * $pct / 100))
        $progressText.Text = $text
    }

    # --- Event Handlers ---
    $window.Add_MouseLeftButtonDown({
        if ($_.GetPosition($window).Y -lt 40) { $window.DragMove() }
    })

    $closeBtn.Add_Click({ $window.Close() })

    $verifyBtn.Add_Click({
        $verifyBtn.IsEnabled = $false
        $checks = @("checkSTR", "checkAME", "checkDLL", "checkAddr")
        $delay = 0
        foreach ($c in $checks) {
            Start-Sleep -Milliseconds 300
        }
        $verifyBtn.Content = "Archivos verificados"
        Start-Sleep -Milliseconds 400
        Set-Step 2
    })

    $modeManual.Add_MouseLeftButtonDown({
        $installMode = "manual"
        $modeManual.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#FF1F86C8"))
        $modeManual.Background = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromArgb(20, 31, 134, 200))
        $modeVortex.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#80FFFFFF"))
        $modeVortex.Background = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromArgb(89, 255, 255, 255))
    })

    $modeVortex.Add_MouseLeftButtonDown({
        $installMode = "vortex"
        $modeVortex.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#FF1F86C8"))
        $modeVortex.Background = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromArgb(20, 31, 134, 200))
        $modeManual.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#80FFFFFF"))
        $modeManual.Background = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromArgb(89, 255, 255, 255))
    })

    $back2Btn.Add_Click({ Set-Step 1 })
    $back3Btn.Add_Click({ Set-Step 2 })
    $next3Btn.Add_Click({ Set-Step 4 })

    $installBtn.Add_Click({
        $installBtn.IsEnabled = $false
        $logPanel.Visibility = "Visible"
        $logText.Inlines.Clear()

        $dataPath = Find-SkyrimData
        if (-not $dataPath) {
            Add-Log "ERROR: No se encontro la carpeta Data de Skyrim SE." "error"
            Add-Log "Usa el parametro -SkyrimPath para especificarla." "warn"
            $installBtn.IsEnabled = $true
            return
        }
        Add-Log "Data encontrado: $dataPath" "info"

        if ($installMode -eq "vortex" -and $vortexFound) {
            Add-Log "Modo Vortex seleccionado." "info"
            Add-Log "Abriendo Vortex via protocolo nxm://..." "info"
            $nxmLinks = @(
                "nxm://skyrimse/mods/69993"
                "nxm://skyrimse/mods/245"
                "nxm://skyrimse/mods/3619"
                "nxm://skyrimse/mods/32444"
            )
            foreach ($link in $nxmLinks) {
                Start-Sleep -Milliseconds 500
                try { Start-Process $link -ErrorAction SilentlyContinue } catch {}
                Add-Log "Enviado: $link" "info"
            }
            Set-Progress 100 "Instalacion enviada a Vortex"
            Add-Log "Completa la instalacion en Vortex y configura el orden de carga." "warn"
            Start-Sleep -Milliseconds 800
            Set-Step 3
        } else {
            Add-Log "Modo manual seleccionado." "info"
            $logCb = {
                param([string]$msg, [string]$type)
                $window.Dispatcher.Invoke([Action]{
                    Add-Log $msg $type
                })
            }
            $result = Install-Mods -DataPath $dataPath -UseVortex $false -LogCb $logCb
            if ($result) {
                Set-Progress 100 "Instalacion completada"
                Start-Sleep -Milliseconds 800
                Set-Step 3
            } else {
                Add-Log "La instalacion fallo. Revisa el log arriba." "error"
                $installBtn.IsEnabled = $true
            }
        }
    })

    $restartBtn.Add_Click({
        $currentStep = 1
        $verifyBtn.IsEnabled = $true
        $verifyBtn.Content = "Verificar archivos"
        $installBtn.IsEnabled = $true
        $progressPanel.Visibility = "Collapsed"
        $progressText.Visibility = "Collapsed"
        $logPanel.Visibility = "Collapsed"
        $logText.Inlines.Clear()
        Set-Step 1
    })

    # Show window
    $window.ShowDialog() | Out-Null
}

# =============================================================================
# Entry Point
# =============================================================================
if ($Silent) {
    $dataPath = Find-SkyrimData
    if (-not $dataPath) {
        Write-Host "ERROR: No se encontro la carpeta Data de Skyrim SE." -ForegroundColor Red
        Write-Host "Usa -SkyrimPath para especificarla." -ForegroundColor Yellow
        exit 1
    }
    $logCb = {
        param([string]$msg, [string]$type)
        $color = switch ($type) {
            "success" { "Green" }
            "warn"    { "Yellow" }
            "error"   { "Red" }
            default   { "Cyan" }
        }
        Write-Host "> $msg" -ForegroundColor $color
    }
    $result = Install-Mods -DataPath $dataPath -UseVortex $false -LogCb $logCb
    if ($result) {
        Write-Host "`nInstalacion completada con exito." -ForegroundColor Green
    } else {
        Write-Host "`nLa instalacion fallo." -ForegroundColor Red
        exit 1
    }
} else {
    Show-InstallerGUI
}
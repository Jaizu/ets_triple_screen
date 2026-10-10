@echo off
rem ============================================================
rem  ETS2 Triple Monitor Configurator
rem  Double-click this file. It launches the GUI embedded below
rem  using the PowerShell that ships with Windows (no installs).
rem ============================================================
powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$p='%~f0'; $c=[IO.File]::ReadAllText($p); $i=$c.IndexOf('#PS'+'_START'); Invoke-Expression $c.Substring($i)"
exit /b
#PS_START
$ErrorActionPreference = 'Stop'

try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ci  = [System.Globalization.CultureInfo]::InvariantCulture
$deg = [string][char]176
$Entries = @{}
$Labels  = @{}

# ============================================================
# UTILITIES
# ============================================================

function F6($x) { return ([double]$x).ToString('F6', $ci) }
function F3($x) { return ([double]$x).ToString('F3', $ci) }
function F2($x) { return ([double]$x).ToString('F2', $ci) }

function Show-Error($msg) {
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Error', 'OK', 'Error')
}

function Get-Num($key) {
    $t = $Entries[$key].Text.Trim().Replace(',', '.')
    $v = 0.0
    if (-not [double]::TryParse($t, [System.Globalization.NumberStyles]::Float, $ci, [ref]$v)) {
        throw ($Labels[$key] + ' must be a valid number.')
    }
    return $v
}

function Get-Fov($size, $dist) {
    return 2.0 * [Math]::Atan(($size / 2.0) / $dist) * 180.0 / [Math]::PI
}

# Angular correction produced by the bezel (degrees)
function Get-BezelAngle($w, $d, $b) {
    if ($b -le 0 -or $w -le 0 -or $d -le 0) { return 0.0 }
    $a0 = [Math]::Atan(($w / 2.0) / $d)
    $a1 = [Math]::Atan((($w + $b) / 2.0) / $d)
    return ($a1 - $a0) * 180.0 / [Math]::PI
}

# ============================================================
# SII FILE GENERATION
# ============================================================

function Get-MonitorBlock($d, $name, $nx, $heading, $hrel, $vrel) {
    $pitch = F6 $d.pitch
    $roll  = F6 $d.roll
    $cx = F6 $d.camera_x
    $cy = F6 $d.camera_y
    $cz = F6 $d.camera_z
    $fh = F6 $d.fov_h
    $fv = F6 $d.fov_v
    $fx = F6 $d.frustum_x
    $fy = F6 $d.frustum_y
    $fw = F6 $d.frustum_w
    $fht = F6 $d.frustum_h
    $hd = F6 $heading
    $hr = F6 $hrel
    $vr = F6 $vrel
    $ri = $d.render_interior
    $re = $d.render_exterior

    return @"
monitor_config : _nameless.$name {
 name: $name

 normalized_x: $nx
 normalized_y: 0.000000
 normalized_width: 0.333333
 normalized_height: 1.000000

 heading_offset: $hd
 pitch_offset: $pitch
 roll_offset: $roll

 camera_space_offset: ($cx, $cy, $cz)

 horizontal_fov_relative_offset: $hr
 vertical_fov_relative_offset: $vr

 horizontal_fov_override: $fh
 vertical_fov_override: $fv

 frustum_subrect_x: $fx
 frustum_subrect_y: $fy
 frustum_subrect_width: $fw
 frustum_subrect_height: $fht

 render_interior: $ri
 render_exterior: $re
}
"@
}

function New-Sii($d) {
    # The bezel is added to the physical angle.
    $left  = $d.angle + $d.bezel_angle
    $right = -$left

    $center = Get-MonitorBlock $d 'center' '0.333333' 0.0 $d.center_h_rel $d.center_v_rel
    $lft    = Get-MonitorBlock $d 'left'   '0.000000' $left $d.left_h_rel $d.left_v_rel
    $rgt    = Get-MonitorBlock $d 'right'  '0.666667' $right $d.right_h_rel $d.right_v_rel

    return @"
SiiNunit
{
multimon_config : _nameless.0 {
 normalized_ui_x: 0.333333
 normalized_ui_width: 0.333333

 monitors: 3
 monitors[0]: _nameless.center
 monitors[1]: _nameless.left
 monitors[2]: _nameless.right
}

$center
$lft
$rgt
}
"@
}

# ============================================================
# GUI HELPERS
# ============================================================

function Add-Section($parent, $text, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(15, $y)
    $parent.Controls.Add($l)
}

function Add-Note($parent, $text, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.AutoSize = $true
    $l.MaximumSize = New-Object System.Drawing.Size(630, 0)
    $l.Location = New-Object System.Drawing.Point(15, $y)
    $parent.Controls.Add($l)
}

function Add-Check($parent, $text, $x, $y, $checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text
    $c.AutoSize = $true
    $c.Checked = $checked
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $parent.Controls.Add($c)
    return $c
}

# fields: array of @(key, label, default)
function Add-Grid($parent, $fields, $cols, $startY) {
    $i = 0
    $colW = [int](640 / $cols)
    foreach ($f in $fields) {
        $col = $i % $cols
        $row = [int][Math]::Floor($i / $cols)
        $x = 15 + $col * $colW
        $y = $startY + $row * 52

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $f[1]
        $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point($x, $y)
        $parent.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Text = $f[2]
        $tb.Location = New-Object System.Drawing.Point($x, ($y + 20))
        $tb.Width = $colW - 25
        $parent.Controls.Add($tb)

        $Entries[$f[0]] = $tb
        $Labels[$f[0]]  = $f[1]
        $i++
    }
}

function Show-Text($title, $text) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $title
    $f.StartPosition = 'CenterParent'
    $f.ClientSize = New-Object System.Drawing.Size(440, 600)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = 'Vertical'
    $tb.Font = New-Object System.Drawing.Font('Consolas', 10)
    $tb.Dock = 'Fill'
    $tb.Text = $text
    $f.Controls.Add($tb)
    $f.Add_Shown({ $tb.Select(0, 0) })
    [void]$f.ShowDialog($form)
    $f.Dispose()
}

# ============================================================
# MAIN WINDOW
# ============================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = 'ETS2 Triple Monitor Configurator'
$form.ClientSize = New-Object System.Drawing.Size(700, 650)
$form.MinimumSize = New-Object System.Drawing.Size(716, 690)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size = New-Object System.Drawing.Size(680, 580)
$tabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($tabs)

# ---------------- Screens ----------------
$tabScreens = New-Object System.Windows.Forms.TabPage
$tabScreens.Text = 'Screens'
$tabs.TabPages.Add($tabScreens)

Add-Section $tabScreens 'Physical dimensions' 15
Add-Grid $tabScreens @(
    @('width',    'Visible monitor width (mm)',            '700'),
    @('height',   'Visible monitor height (mm)',           '395'),
    @('bezel',    'Total bezel between two monitors (mm)', '15'),
    @('distance', 'Eyes -> screen distance (mm)',          '700')
) 2 45

Add-Section $tabScreens 'Side monitor angle' 170
Add-Grid $tabScreens @(
    ,@('angle', 'Physical angle of each side monitor (degrees)', '54.0')
) 2 200
Add-Note $tabScreens ("Example: 54$deg means the left monitor is rotated +54$deg and the right one -54$deg relative to the center monitor.") 262

# ---------------- Camera ----------------
$tabCamera = New-Object System.Windows.Forms.TabPage
$tabCamera.Text = 'Camera'
$tabs.TabPages.Add($tabCamera)

Add-Section $tabCamera 'Camera Space Offset' 15
Add-Note $tabCamera 'Camera offset. Z moves the camera closer to / farther from the game''s reference point.' 42
Add-Grid $tabCamera @(
    @('camera_x', 'X - lateral (m)',    '0.0'),
    @('camera_y', 'Y - vertical (m)',   '0.0'),
    @('camera_z', 'Z - depth (m)',      '0.0')
) 3 80

Add-Section $tabCamera 'Orientation' 160
Add-Grid $tabCamera @(
    @('pitch', ("Pitch ($deg)"), '0.0'),
    @('roll',  ("Roll ($deg)"),  '0.0')
) 2 190

# ---------------- FOV ----------------
$tabFov = New-Object System.Windows.Forms.TabPage
$tabFov.Text = 'FOV'
$tabs.TabPages.Add($tabFov)

Add-Section $tabFov 'Field of view' 15
$chkAuto = Add-Check $tabFov 'Calculate FOV automatically from monitor size and distance' 15 42 $true
Add-Grid $tabFov @(
    @('fov_h', ("Horizontal FOV per monitor ($deg)"), '53.13'),
    @('fov_v', ("Vertical FOV per monitor ($deg)"),   '31.36')
) 2 75

Add-Section $tabFov 'Relative FOV offsets' 170
Add-Note $tabFov 'These should normally stay at 0. They allow an individual compensation per monitor.' 197
Add-Grid $tabFov @(
    @('center_h_rel', 'Center H', '0.0'),
    @('left_h_rel',   'Left H',   '0.0'),
    @('right_h_rel',  'Right H',  '0.0'),
    @('center_v_rel', 'Center V', '0.0'),
    @('left_v_rel',   'Left V',   '0.0'),
    @('right_v_rel',  'Right V',  '0.0')
) 3 235

$toggleFov = {
    foreach ($k in 'fov_h', 'fov_v') { $Entries[$k].Enabled = -not $chkAuto.Checked }
}
$chkAuto.Add_CheckedChanged($toggleFov)
& $toggleFov

# ---------------- Advanced ----------------
$tabAdv = New-Object System.Windows.Forms.TabPage
$tabAdv.Text = 'Advanced'
$tabs.TabPages.Add($tabAdv)

Add-Section $tabAdv 'Render' 15
$chkInt = Add-Check $tabAdv 'Render interior' 15 42 $true
$chkExt = Add-Check $tabAdv 'Render exterior' 15 68 $true

Add-Section $tabAdv 'Frustum Subrect' 110
Add-Note $tabAdv 'For a normal triple-monitor setup use X=0, Y=0, Width=1 and Height=1.' 137
Add-Grid $tabAdv @(
    @('frustum_x', 'X',      '0.0'),
    @('frustum_y', 'Y',      '0.0'),
    @('frustum_w', 'Width',  '1.0'),
    @('frustum_h', 'Height', '1.0')
) 2 170

# ============================================================
# READ + VALIDATE
# ============================================================

function Get-Data {
    $d = @{}
    $d.width    = Get-Num 'width'
    $d.height   = Get-Num 'height'
    $d.bezel    = Get-Num 'bezel'
    $d.distance = Get-Num 'distance'
    $d.angle    = Get-Num 'angle'

    if ($d.width    -le 0) { throw 'The width must be greater than 0.' }
    if ($d.height   -le 0) { throw 'The height must be greater than 0.' }
    if ($d.distance -le 0) { throw 'The distance must be greater than 0.' }
    if ($d.bezel    -lt 0) { throw 'The bezel cannot be negative.' }
    if ($d.angle -le 0 -or $d.angle -ge 90) { throw 'The angle must be between 0 and 90 degrees.' }

    $d.bezel_angle = Get-BezelAngle $d.width $d.distance $d.bezel

    if ($chkAuto.Checked) {
        $d.fov_h = Get-Fov $d.width  $d.distance
        $d.fov_v = Get-Fov $d.height $d.distance
    } else {
        $d.fov_h = Get-Num 'fov_h'
        $d.fov_v = Get-Num 'fov_v'
    }

    foreach ($k in 'camera_x','camera_y','camera_z','pitch','roll',
                   'center_h_rel','left_h_rel','right_h_rel',
                   'center_v_rel','left_v_rel','right_v_rel',
                   'frustum_x','frustum_y','frustum_w','frustum_h') {
        $d[$k] = Get-Num $k
    }

    $d.render_interior = if ($chkInt.Checked) { 'true' } else { 'false' }
    $d.render_exterior = if ($chkExt.Checked) { 'true' } else { 'false' }
    return $d
}

# ============================================================
# ACTIONS
# ============================================================

function Line($label, $value, $unit) {
    return ($label.PadRight(22) + $value.PadLeft(10) + $unit)
}

function Do-Preview {
    $d = Get-Data
    $left  = $d.angle + $d.bezel_angle
    $right = -$left

    $lines = @(
        'GEOMETRY',
        '----------------------------',
        (Line 'Physical angle:'    (F3 $d.angle)       " $deg"),
        (Line 'Bezel correction:'  (F3 $d.bezel_angle) " $deg"),
        (Line 'Left heading:'      ('+' + (F3 $left))  " $deg"),
        (Line 'Center heading:'    '0.000'             " $deg"),
        (Line 'Right heading:'     (F3 $right)         " $deg"),
        '',
        'FOV',
        '----------------------------',
        (Line 'Horizontal:'        (F3 $d.fov_h)       " $deg"),
        (Line 'Vertical:'          (F3 $d.fov_v)       " $deg"),
        '',
        'CAMERA',
        '----------------------------',
        (Line 'X:'     (F3 $d.camera_x) ' m'),
        (Line 'Y:'     (F3 $d.camera_y) ' m'),
        (Line 'Z:'     (F3 $d.camera_z) ' m'),
        (Line 'Pitch:' (F3 $d.pitch)    " $deg"),
        (Line 'Roll:'  (F3 $d.roll)     " $deg"),
        '',
        'FRUSTUM',
        '----------------------------',
        (Line 'X:'      (F3 $d.frustum_x) ''),
        (Line 'Y:'      (F3 $d.frustum_y) ''),
        (Line 'Width:'  (F3 $d.frustum_w) ''),
        (Line 'Height:' (F3 $d.frustum_h) '')
    )
    Show-Text 'Preview' ($lines -join "`r`n")
}

function Do-Generate {
    $d = Get-Data
    $content = New-Sii $d

    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Save ETS2 configuration'
    $dlg.Filter = 'SII files (*.sii)|*.sii|All files (*.*)|*.*'
    $dlg.FileName = 'multimon_config.sii'
    $dlg.DefaultExt = 'sii'
    $ets = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Euro Truck Simulator 2'
    if (Test-Path $ets) { $dlg.InitialDirectory = $ets }

    if ($dlg.ShowDialog() -ne 'OK') { return }

    [IO.File]::WriteAllText($dlg.FileName, $content, (New-Object System.Text.UTF8Encoding($false)))

    $left  = $d.angle + $d.bezel_angle
    $right = -$left
    $msg = "File generated successfully.`r`n`r`n" +
           "Horizontal FOV: $(F2 $d.fov_h)$deg`r`n" +
           "Vertical FOV: $(F2 $d.fov_v)$deg`r`n`r`n" +
           "Left heading: +$(F2 $left)$deg`r`n" +
           "Right heading: $(F2 $right)$deg`r`n`r`n" +
           "File:`r`n$($dlg.FileName)"
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Configuration generated', 'OK', 'Information')
}

# ============================================================
# BUTTONS
# ============================================================

$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text = 'Preview calculations'
$btnPreview.Size = New-Object System.Drawing.Size(180, 34)
$btnPreview.Location = New-Object System.Drawing.Point(10, 603)
$btnPreview.Anchor = 'Bottom,Left'
$btnPreview.Add_Click({
    try { Do-Preview } catch { Show-Error $_.Exception.Message }
})
$form.Controls.Add($btnPreview)

$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Text = 'Generate multimon_config.sii'
$btnGen.Size = New-Object System.Drawing.Size(220, 34)
$btnGen.Location = New-Object System.Drawing.Point(470, 603)
$btnGen.Anchor = 'Bottom,Right'
$btnGen.Add_Click({
    try { Do-Generate } catch { Show-Error $_.Exception.Message }
})
$form.Controls.Add($btnGen)

[void]$form.ShowDialog()

} catch {
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Fatal error', 'OK', 'Error')
}

Import-Module (Join-Path (Join-Path $PSScriptRoot "..") "Couven92.PowerShell.MathUtils")
Import-Module (Join-Path (Join-Path $PSScriptRoot "..") "Couven92.PowerShell.Bresenham")

$MaxRadiansLatitude = [Math]::Atan([Math]::Sinh([Math]::PI))
$MinRadiansLatitude = -$MaxRadiansLatitude

$MaxDegreesLatitude = Convert-RadiansToDegrees $MaxRadiansLatitude
$MinDegreesLatitude = Convert-RadiansToDegrees $MinRadiansLatitude

function Get-MapTileName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [Alias("Z")]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [Alias("X")]
        [int]$TileX,
        [Parameter(Mandatory=$true, Position=2, ValueFromPipelineByPropertyName=$true)]
        [Alias("Y")]
        [int]$TileY
    )
    begin {
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    }
    process {
        $x = $TileX.ToString($invariant)
        $y = $TileY.ToString($invariant)
        $z = $ZoomLevel.ToString($invariant)
        "z$z-y$y-x$x"
    }
}
Export-ModuleMember -Function Get-MapTileName

function Add-MapTileNameMember {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [PSCustomObject]$TileReference
    )
    process {
        $name = $TileReference | Get-MapTileName
        $TileReference | Add-Member @{ TileName = $name }
    }
}
Export-ModuleMember -Function Add-MapTileNameMember

function Get-MapTileFromPoint {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(-180, +180)]
        [double]$DegreesLongitude,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
            if ($_ -lt $MinDegreesLatitude) {
                throw "Cannot validate argument on parameter 'DegreesLatitude'. The $_ argument is less than the minimum allowed range of $MinDegreesLatitude. Supply an argument that is greater than or equal to $MinDegreesLatitude and then try the command again."
            } elseif ($_ -gt $MaxDegreesLatitude) {
                throw "Cannot validate argument on parameter 'DegreesLatitude'. The $_ argument is greater than the maximum allowed range of $MaxDegreesLatitude. Supply an argument that is less than or equal to $MaxDegreesLatitude and then try the command again."
            } else {
                $true
            }
        })]
        [double]$DegreesLatitude,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(-[Math]::PI, +[Math]::PI)]
        [double]$RadiansLongitude,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
            if ($_ -lt $MinRadiansLatitude) {
                throw "Cannot validate argument on parameter 'RadiansLatitude'. The $_ argument is less than the minimum allowed range of $MinRadiansLatitude. Supply an argument that is greater than or equal to $MinRadiansLatitude and then try the command again."
            } elseif ($_ -gt $MaxRadiansLatitude) {
                throw "Cannot validate argument on parameter 'RadiansLatitude'. The $_ argument is greater than the maximum allowed range of $MaxRadiansLatitude. Supply an argument that is less than or equal to $MaxRadiansLatitude and then try the command again."
            } else {
                $true
            }
        })]
        [double]$RadiansLatitude
    )
    begin {
        if ($ZoomLevel) {
            [double]$PreZoomLevel = $ZoomLevel
            [double]$Pre2PowZoom = [Math]::Pow(2, $PreZoomLevel)
        }
    }
    process {
        if (-not $RadiansLatitude) {
            $RadiansLatitude = Convert-DegreesToRadians $DegreesLatitude -ErrorAction Stop
        }
        if (-not $DegreesLongitude) {
            $DegreesLongitude = Convert-RadiansToDegrees $RadiansLongitude -ErrorAction Stop
        }
        if ($PreZoomLevel -eq $ZoomLevel) {
            [double]$ConstN = $Pre2PowZoom
        } else {
            [double]$ConstN = [Math]::Pow(2, $ZoomLevel)
        }

        $xtile = [Math]::Floor(($DegreesLongitude + 180.0) / 360.0 * $ConstN)
        $ytile = ([Math]::Floor((1.0 - [Math]::Log([Math]::Tan($RadiansLatitude) + (1.0 / [Math]::Cos($RadiansLatitude))) / [Math]::PI) / 2.0 * $ConstN))

        [PSCustomObject]@{
            ZoomLevel = $ZoomLevel
            TileX = $xtile
            TileY = $ytile
            TileName = Get-MapTileName -ZoomLevel $ZoomLevel -TileX $xtile -TileY $ytile
        }
    }
}
Export-ModuleMember -Function Get-MapTileFromPoint

function Add-MapTileMembers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [PSCustomObject]$Point
    )
    process {
        $tile = $Point | Get-MapTileFromPoint -ZoomLevel $ZoomLevel
        $Point | Add-Member @{
            ZoomLevel = $tile.ZoomLevel
            TileX = $tile.TileX
            TileY = $tile.TileY
            TileName = $tile.TileName
        }
    }
}
Export-ModuleMember -Function Add-MapTileMembers

function Get-MapTilesAlongPath {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [PSCustomObject[]]$Coordinates,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$UsedCoordinates
    )

    begin {
        if (-not $UsedCoordinates) {
            $UsedCoordinates = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
        }
        $bresenhamPaths = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        $bresenhamPaths.Clear()
        $isFirst = $true
        foreach ($item in $Coordinates) {
            $currentTile = $item | Get-MapTileFromPoint `
                -ZoomLevel $ZoomLevel -ErrorAction Stop
            if ($isFirst -eq $true) {
                $previousTile = $currentTile
                $isFirst = $false
                continue
            }
            $bresenhamPaths.Add([PSCustomObject]@{
                X0 = $previousTile["TileX"]
                Y0 = $previousTile["TileY"]
                X1 = $currentTile["TileX"]
                Y1 = $currentTile["TileY"]
            }) | Out-Null
            $previousTile = $currentTile
        }
        $bresenhamTiles = $bresenhamPaths.ToArray() | Get-BresenhamLineCoordinates `
            -UsedCoordinates $UsedCoordinates
        foreach ($item in $bresenhamTiles) {
            [PSCustomObject]@{
                ZoomLevel = $ZoomLevel
                TileX = $item.X
                TileY = $item.Y
                TileName = Get-MapTileName -ZoomLevel $ZoomLevel `
                    -TileX $item.X -TileY $item.Y
            }
        }
    }
}
Export-ModuleMember -Function Get-MapTilesAlongPath

function Get-MapTilesAdjacent {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [Alias("Z")]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [Alias("X")]
        [int]$TileX,
        [Parameter(Mandatory=$true, Position=2, ValueFromPipelineByPropertyName=$true)]
        [Alias("Y")]
        [int]$TileY,
        [Parameter(Mandatory=$true, Position=3, ValueFromPipelineByPropertyName=$true)]
        [Alias("Name")]
        [int]$TileName,
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$TileRadius = 0,
        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$UsedCoordinates
    )

    begin {
        if (-not $UsedCoordinates) {
            $UsedCoordinates = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
        }
    }

    process {
        if ($TileRadius -lt 1) {
            if ($UsedCoordinates.Add($TileName)) {
                $MapTile
            }
            return
        }
        $xCenter = $TileX
        $yCenter = $TileY
        $xMax = $xCenter + $TileRadius
        $yMax = $yCenter + $TileRadius
        for ($x = $xCenter - ($TileRadius - 1); $x -le $xMax; $x++) {
            for ($y = $yCenter - ($TileRadius - 1); $y -le $yMax; $y++) {
                if (($x -eq $xCenter) -and ($y -eq $yCenter)) {
                    if ($UsedCoordinates.Add($TileName)) {
                        $MapTile
                    }
                    continue
                }
                $name = Get-MapTileName -ZoomLevel $ZoomLevel -TileX $x -TileY $y
                if ($UsedCoordinates.Add($name)) {
                    [PSCustomObject]@{
                        ZoomLevel = $ZoomLevel
                        TileX = $x
                        TileY = $y
                        TileName = $name
                    }
                }
            }
        }
    }
}
Export-ModuleMember -Function Get-MapTilesAdjacent

function Get-MapTileJoinedName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateRange(0, 22)]
        [Alias("Z")]
        [int]$ZoomLevel,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [Alias("X")]
        [int]$TileX,
        [Parameter(Mandatory=$true, Position=2, ValueFromPipelineByPropertyName=$true)]
        [Alias("Y")]
        [int]$TileY,
        [Parameter(Mandatory=$true, Position=3, ValueFromPipelineByPropertyName=$true)]
        [Alias("Width")][Alias("W")]
        [int]$TileWidth,
        [Parameter(Mandatory=$true, Position=4, ValueFromPipelineByPropertyName=$true)]
        [Alias("Height")][Alias("H")]
        [int]$TileHeight
    )
    begin {
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    }
    process {
        $n = Get-MapTileName -ZoomLevel $ZoomLevel -TileX $TileX -TileY $TileY `
            -ErrorAction Stop
        $w = $TileWidth.ToString($invariant)
        $h = $TileHeight.ToString($invariant)
        "$n-w$w-h$h"
    }
}
Export-ModuleMember -Function Get-MapTileJoinedName

function Get-MapTilesJoined {
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [PSCustomObject[]]$MapTiles,
        [Parameter(Position=1)]
        [ValidateScript({
            if ($_ -lt 0) {
                throw "Cannot validate argument on parameter 'TileRadius'. The $_ argument is less than the minimum allowed range of 0. Supply an argument that is greater than or equal to 0 and then try the command again."
            }
            $true
        })]
        [int]$TileRadius = 0
    )
    $available = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new(
        $MapTiles.Count,
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($item in $MapTiles) {
        $available.Add($item.TileName, $item) | Out-Null
    }
    $usedCoordinates = [System.Collections.Generic.HashSet[string]]::new(
        $available.Count,
        [System.StringComparer]::OrdinalIgnoreCase
    )
    if ($TileRadius -lt 1) {
        $TileRadius = 1
    }
    $diameter = $TileRadius * 2
    $lineTileNames = [System.Collections.Generic.List[string]]::new($diameter)
    $singleTiles = [PSCustomObject[,]]::new($diameter, $diameter)
    foreach ($item in $MapTiles) {
        if ($usedCoordinates.Contains($item.TileName)) {
            continue
        }
        $xExhausted = $false
        $yExhausted = $false
        $usedCoordinates.Add($item.TileName) | Out-Null
        $singleTiles[0, 0] = $item
        $width = 1
        $height = 1
        for ($extent = 1; $extent -lt $diameter; $extent++) {
            $xExtent = $item.TileX + $extent
            $yExtent = $item.TileY + $extent
            if (-not $xExhausted) {
                $x = $xExtent
                $lineTileNames.Clear()
                for ($offset = 0; $offset -lt $height; $offset++) {
                    $y = $Item.TileY + $offset
                    $name = Get-MapTileName -ZoomLevel $Item.ZoomLevel `
                        -TileX $x -TileY $y
                    if ((-not $available.ContainsKey($name)) -or ($usedCoordinates.Contains($name))) {
                        $xExhausted = $true
                        break
                    }
                    $singleTiles[$extent, $offset] = $available[$name]
                    $lineTileNames.Add($name) | Out-Null
                }
                if (-not $xExhausted) {
                    $width++
                    $usedCoordinates.UnionWith($lineTileNames) | Out-Null
                }
            }
            if (-not $yExhausted) {
                $y = $yExtent
                $lineTileNames.Clear()
                for ($offset = 0; $offset -lt $width; $offset++) {
                    $x = $item.TileX + $offset
                    $name = Get-MapTileName -ZoomLevel $Item.ZoomLevel `
                        -TileX $x -TileY $y
                    if ((-not $available.ContainsKey($name)) -or ($usedCoordinates.Contains($name))) {
                        $yExhausted = $true
                        break
                    }
                    $singleTiles[$offset, $extent] = $available[$name]
                    $lineTileNames.Add($name) | Out-Null
                }
                if (-not $yExhausted) {
                    $height++
                    $usedCoordinates.UnionWith($lineTileNames) | Out-Null
                }
            }
        }
        $joinTiles = [PSCustomObject[,]]::new($width, $height)
        for ($x = 0; $x -lt $width; $x++) {
            for ($y = 0; $y -lt $height; $y++) {
                $joinTiles[$x, $y] = $singleTiles[$x, $y]
            }
        }
        $name = $joinTiles[0, 0] | Get-MapTileJoinedName `
            -TileWidth $width -TileHeight $height
        [PSCustomObject]@{
            TileName = $name
            TileWidth = $width
            TileHeight = $height
            Tiles = $joinTiles
            TileX = $joinTiles[0, 0].TileX
            TileY = $joinTiles[0, 0].TileY
            ZoomLevel = $joinTiles[0, 0].ZoomLevel
        }
    }
}
Export-ModuleMember -Function Get-MapTilesJoined
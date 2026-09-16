Add-Type -AssemblyName System.Drawing

$inFile = "gordito.png"
$outFile = "gordito.tga"
$targetWidth = 32
$targetHeight = 32

$img = [System.Drawing.Image]::FromFile($inFile)
$bmp = New-Object System.Drawing.Bitmap($img, $targetWidth, $targetHeight)

$fs = New-Object System.IO.FileStream($outFile, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)

# TGA Header (18 bytes)
$bw.Write([byte]0)   # ID length
$bw.Write([byte]0)   # Color map type
$bw.Write([byte]2)   # Image type (Uncompressed true-color)
$bw.Write([byte]0)   # Color map spec (5 bytes)
$bw.Write([byte]0)
$bw.Write([byte]0)
$bw.Write([byte]0)
$bw.Write([byte]0)
$bw.Write([UInt16]0) # X origin
$bw.Write([UInt16]0) # Y origin
$bw.Write([UInt16]$targetWidth)  # Width
$bw.Write([UInt16]$targetHeight) # Height
$bw.Write([byte]32)  # Pixel depth
$bw.Write([byte]0x28) # Image descriptor (top-left origin, 8 bits alpha)

# Pixel data (BGRA)
for ($y = 0; $y -lt $targetHeight; $y++) {
    for ($x = 0; $x -lt $targetWidth; $x++) {
        $pixel = $bmp.GetPixel($x, $y)
        $bw.Write([byte]$pixel.B)
        $bw.Write([byte]$pixel.G)
        $bw.Write([byte]$pixel.R)
        $bw.Write([byte]$pixel.A)
    }
}

$bw.Close()
$fs.Close()
$bmp.Dispose()
$img.Dispose()

Write-Host "Converted successfully to $outFile"

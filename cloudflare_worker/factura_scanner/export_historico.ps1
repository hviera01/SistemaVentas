$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data

$cutoff = "2026-07-17 22:23:35.328"
$connStr = "Server=localhost\SQLEXPRESS;Database=DB_SUPERCOLOR;Integrated Security=True;TrustServerCertificate=True;"
$outPath = Join-Path $PSScriptRoot "data_historico.sql"

function Esc([string]$s) {
    if ($null -eq $s) { return "" }
    return $s.Replace("'", "''")
}
function SqlStr($val) {
    if ($null -eq $val -or $val -eq [DBNull]::Value) { return "NULL" }
    return "'" + (Esc([string]$val)) + "'"
}
function SqlNum($val) {
    if ($null -eq $val -or $val -eq [DBNull]::Value) { return "NULL" }
    return ([string]$val).Replace(",", ".")
}
function SqlDate($val) {
    if ($null -eq $val -or $val -eq [DBNull]::Value) { return "NULL" }
    $dt = [datetime]$val
    return "'" + $dt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + "'"
}

$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
$conn.Open()

$lines = New-Object System.Collections.Generic.List[string]

# VENTA
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT IdVenta, TipoDocumento, NumeroDocumento, DocumentoCliente, NombreCliente, MontoPago, MontoCambio, MontoTotal, FechaRegistro, MetodoPago, Estado, Impuesto, Condicion, FechaVencimiento, SaldoPendiente FROM VENTA WHERE FechaRegistro <= @cutoff ORDER BY IdVenta"
$cmd.Parameters.AddWithValue("@cutoff", $cutoff) | Out-Null
$reader = $cmd.ExecuteReader()
$ventaIds = New-Object System.Collections.Generic.List[string]
while ($reader.Read()) {
    $idVenta = $reader["IdVenta"]
    $ventaIds.Add([string]$idVenta)
    $vals = @(
        (SqlNum $idVenta),
        (SqlStr $reader["TipoDocumento"]),
        (SqlStr $reader["NumeroDocumento"]),
        (SqlStr $reader["DocumentoCliente"]),
        (SqlStr $reader["NombreCliente"]),
        (SqlNum $reader["MontoPago"]),
        (SqlNum $reader["MontoCambio"]),
        (SqlNum $reader["MontoTotal"]),
        (SqlDate $reader["FechaRegistro"]),
        (SqlStr $reader["MetodoPago"]),
        (SqlStr $reader["Estado"]),
        (SqlNum $reader["Impuesto"]),
        (SqlStr $reader["Condicion"]),
        (SqlDate $reader["FechaVencimiento"]),
        (SqlNum $reader["SaldoPendiente"])
    ) -join ","
    $lines.Add("INSERT INTO ventas VALUES ($vals);")
}
$reader.Close()
Write-Host "Ventas exportadas: $($ventaIds.Count)"

# DETALLE_VENTA (solo de las ventas ya filtradas)
$cmd2 = $conn.CreateCommand()
$cmd2.CommandText = "SELECT D.IdDetalleVenta, D.IdVenta, D.IdProducto, D.NombreProducto, D.PrecioVenta, D.Cantidad, D.SubTotal, D.FechaRegistro, D.Estado, D.PrecioCompraUsado FROM DETALLE_VENTA D INNER JOIN VENTA V ON V.IdVenta = D.IdVenta WHERE V.FechaRegistro <= @cutoff ORDER BY D.IdDetalleVenta"
$cmd2.Parameters.AddWithValue("@cutoff", $cutoff) | Out-Null
$reader2 = $cmd2.ExecuteReader()
$detalleCount = 0
while ($reader2.Read()) {
    $vals = @(
        (SqlNum $reader2["IdDetalleVenta"]),
        (SqlNum $reader2["IdVenta"]),
        (SqlNum $reader2["IdProducto"]),
        (SqlStr $reader2["NombreProducto"]),
        (SqlNum $reader2["PrecioVenta"]),
        (SqlNum $reader2["Cantidad"]),
        (SqlNum $reader2["SubTotal"]),
        (SqlDate $reader2["FechaRegistro"]),
        (SqlStr $reader2["Estado"]),
        (SqlNum $reader2["PrecioCompraUsado"])
    ) -join ","
    $lines.Add("INSERT INTO detalle_venta VALUES ($vals);")
    $detalleCount++
}
$reader2.Close()
Write-Host "Detalle exportado: $detalleCount"

$conn.Close()

[System.IO.File]::WriteAllLines($outPath, $lines)
Write-Host "Archivo generado: $outPath"

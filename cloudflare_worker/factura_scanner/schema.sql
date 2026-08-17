CREATE TABLE ventas (
  id_venta INTEGER PRIMARY KEY,
  tipo_documento TEXT,
  numero_documento TEXT,
  documento_cliente TEXT,
  nombre_cliente TEXT,
  monto_pago REAL,
  monto_cambio REAL,
  monto_total REAL,
  fecha_registro TEXT,
  metodo_pago TEXT,
  estado TEXT,
  impuesto REAL,
  condicion TEXT,
  fecha_vencimiento TEXT,
  saldo_pendiente REAL
);
CREATE INDEX idx_ventas_fecha ON ventas(fecha_registro);
CREATE INDEX idx_ventas_numero ON ventas(numero_documento);

CREATE TABLE detalle_venta (
  id_detalle_venta INTEGER PRIMARY KEY,
  id_venta INTEGER,
  id_producto INTEGER,
  nombre_producto TEXT,
  precio_venta REAL,
  cantidad REAL,
  subtotal REAL,
  fecha_registro TEXT,
  estado TEXT,
  precio_compra_usado REAL
);
CREATE INDEX idx_detalle_id_venta ON detalle_venta(id_venta);

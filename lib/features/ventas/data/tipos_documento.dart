/// Clave interna (guardada en `venta.tipoDocumento` en Firestore) -> etiqueta
/// legible, de los tipos de documento que puede generar una venta.
const tiposDocumento = {
  'Factura': 'Factura',
  'Boleta': 'Boleta',
  'Cotizacion': 'Cotización',
  'VentaSinFacturar': 'Venta Sin Facturar',
};

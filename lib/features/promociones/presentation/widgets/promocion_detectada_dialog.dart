import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/promocion_model.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Diálogo interactivo que se muestra al agregar (o al ajustar la cantidad
/// de) un producto que cumple una promoción vigente y aplicable a la
/// condición/método de pago de la venta en curso. El cajero decide si se
/// aplica o no — si rechaza, el producto sigue a precio normal.
class PromocionDetectadaDialog extends StatelessWidget {
  final PromocionModel promocion;
  // Contexto adicional para explicar la oferta en combo/regalo: precio
  // normal por unidad del producto base (con ISV), para mostrar cuánto se
  // ahorra. Para comboMultiproducto es el total normal (con ISV) de los
  // productos del combo ya en el carrito.
  final double? precioUnitarioBase;

  const PromocionDetectadaDialog({super.key, required this.promocion, this.precioUnitarioBase});

  String get _titulo {
    switch (promocion.tipo) {
      case TipoPromocion.porcentaje:
        return '¡Este producto tiene descuento!';
      case TipoPromocion.precioFijo:
        return '¡Este producto tiene precio especial!';
      case TipoPromocion.comboCantidad:
      case TipoPromocion.comboMultiproducto:
        return '¡Aplica para un combo!';
      case TipoPromocion.regalo:
        return '¡Aplica para un regalo!';
    }
  }

  String get _detalle {
    switch (promocion.tipo) {
      case TipoPromocion.porcentaje:
        return 'Se aplica ${promocion.valor.toStringAsFixed(promocion.valor == promocion.valor.roundToDouble() ? 0 : 1)}% de descuento por la promoción "${promocion.nombre}".';
      case TipoPromocion.precioFijo:
        return 'El precio especial es ${formatearMoneda(promocion.valor)} por la promoción "${promocion.nombre}".';
      case TipoPromocion.comboCantidad:
        final ahorro = precioUnitarioBase == null ? null : (precioUnitarioBase! * promocion.cantidadRequerida) - promocion.precioCombo;
        return 'Llevando ${promocion.cantidadRequerida} unidades de "${promocion.nombreProductoBase}", el total baja a ${formatearMoneda(promocion.precioCombo)}'
            '${ahorro != null && ahorro > 0 ? ' (ahorro de ${formatearMoneda(ahorro)})' : ''} por la promoción "${promocion.nombre}".';
      case TipoPromocion.comboMultiproducto:
        final ahorro = precioUnitarioBase == null ? null : precioUnitarioBase! - promocion.precioCombo;
        return 'Ya tenés en el carrito los ${promocion.nombresProductosCombo.length} productos del combo "${promocion.nombre}" (${promocion.nombresProductosCombo.join(', ')}). El paquete completo se paga ${formatearMoneda(promocion.precioCombo)}'
            '${ahorro != null && ahorro > 0 ? ' (ahorro de ${formatearMoneda(ahorro)})' : ''}.';
      case TipoPromocion.regalo:
        final productos = promocion.nombresProductosRegalo.join(', ');
        return 'Llevando ${promocion.cantidadRequerida} unidades de "${promocion.nombreProductoBase}", se regalan ${promocion.cantidadRegalo} unidades de cada uno de: $productos, por la promoción "${promocion.nombre}".';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.celebration_outlined, color: Color(0xFFC62828)),
          const SizedBox(width: 10),
          Expanded(child: Text(_titulo, style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700))),
        ],
      ),
      content: Text(_detalle, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF4B4F58))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('No, precio normal', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Sí, aplicar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

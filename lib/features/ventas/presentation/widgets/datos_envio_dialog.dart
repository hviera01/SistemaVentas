import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lo que arma el diálogo -pedido explícito del dueño: "un modal de cuando
/// es envío... datos de envío y la opción de si imprimir guía de envío"-.
/// [imprimir] solo aplica al usarse desde Registrar Venta (si se marca,
/// además de guardar los datos se imprime la guía apenas se confirme la
/// venta); reimprimir/generar desde Detalle Venta ignora ese campo -ahí el
/// botón que abre este diálogo ya deja claro que la intención es imprimir-.
class DatosEnvioResultado {
  final String nombre;
  final String direccion;
  final String telefono;
  final bool imprimir;
  const DatosEnvioResultado({required this.nombre, required this.direccion, required this.telefono, required this.imprimir});
}

class DatosEnvioDialog extends StatefulWidget {
  final String nombreInicial;
  final String direccionInicial;
  final String telefonoInicial;
  // false desde Detalle Venta (ya se sabe que se va a imprimir; el checkbox
  // ahí no aporta nada, ver arriba) -true (default) desde Registrar Venta.
  final bool mostrarOpcionImprimir;

  const DatosEnvioDialog({
    super.key,
    this.nombreInicial = '',
    this.direccionInicial = '',
    this.telefonoInicial = '',
    this.mostrarOpcionImprimir = true,
  });

  @override
  State<DatosEnvioDialog> createState() => _DatosEnvioDialogState();
}

class _DatosEnvioDialogState extends State<DatosEnvioDialog> {
  late final _ctrlNombre = TextEditingController(text: widget.nombreInicial);
  late final _ctrlDireccion = TextEditingController(text: widget.direccionInicial);
  late final _ctrlTelefono = TextEditingController(text: widget.telefonoInicial);
  bool _imprimir = true;

  @override
  void dispose() {
    _ctrlNombre.dispose();
    _ctrlDireccion.dispose();
    _ctrlTelefono.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (_ctrlNombre.text.trim().isEmpty || _ctrlDireccion.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre y dirección son obligatorios para el envío')));
      return;
    }
    Navigator.pop(
      context,
      DatosEnvioResultado(
        nombre: _ctrlNombre.text.trim(),
        direccion: _ctrlDireccion.text.trim(),
        telefono: _ctrlTelefono.text.trim(),
        imprimir: widget.mostrarOpcionImprimir ? _imprimir : true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 480 ? tamano.width - 32 : 420.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: Color(0xFF1565C0)),
                const SizedBox(width: 10),
                Expanded(child: Text('Datos de envío', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Se prellenan del cliente si tenía -podés cambiarlos si el envío es para otra persona/dirección.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            _campo('Nombre de quien recibe', _ctrlNombre, icono: Icons.person_outline),
            const SizedBox(height: 10),
            _campo('Dirección', _ctrlDireccion, icono: Icons.place_outlined, lineas: 3),
            const SizedBox(height: 10),
            _campo('Teléfono', _ctrlTelefono, icono: Icons.phone_outlined, teclado: TextInputType.phone),
            if (widget.mostrarOpcionImprimir) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _imprimir = !_imprimir),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(value: _imprimir, onChanged: (v) => setState(() => _imprimir = v ?? true), activeColor: const Color(0xFF1565C0)),
                      Expanded(child: Text('Imprimir guía de envío al confirmar la venta', style: GoogleFonts.poppins(fontSize: 12.5))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirmar,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Guardar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController controller, {required IconData icono, int lineas = 1, TextInputType? teclado}) {
    return TextField(
      controller: controller,
      maxLines: lineas,
      keyboardType: teclado,
      style: GoogleFonts.poppins(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: etiqueta,
        labelStyle: GoogleFonts.poppins(fontSize: 12.5),
        prefixIcon: Icon(icono, size: 19),
        filled: true,
        fillColor: const Color(0xFFF2F3F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/negocio/providers/negocio_provider.dart';
import '../../features/ventas/presentation/widgets/teclado_numerico_dialog.dart';
import '../utils/tablet_utils.dart';
import 'teclado_texto_dialog.dart';

/// Envuelve un campo de texto (TextField/TextFormField) para que, en tablet
/// y solo si está prendido en Negocio > Teclado en pantalla (ver
/// NegocioModel.tecladoCompactoTablet), tocarlo abra un teclado propio y
/// chico -TecladoNumericoDialog o TecladoTextoDialog según [numerico]- en
/// vez del teclado nativo del sistema. En cualquier otro caso (celular, PC,
/// o el ajuste apagado) no hace nada: devuelve [child] tal cual, sin envolver
/// nada -por eso no hace falta que el árbol de arriba sea un ConsumerWidget,
/// el propio Consumer de acá adentro se encarga de leer Negocio-.
///
/// [controller] es el mismo TextEditingController que ya usa [child]: al
/// confirmar el teclado propio, se le asigna el texto nuevo directo
/// (dispara igual el onChanged del campo, porque TextField/EditableText
/// escuchan al controller, no solo al tipeo real).
class CampoTecladoCompacto extends StatelessWidget {
  final TextEditingController controller;
  final Widget child;
  final bool numerico;
  final String? titulo;

  const CampoTecladoCompacto({super.key, required this.controller, required this.child, this.numerico = false, this.titulo});

  Future<void> _abrir(BuildContext context) async {
    final resultado = numerico
        ? await showDialog<String>(context: context, builder: (_) => TecladoNumericoDialog(titulo: titulo ?? 'Valor', valorInicial: controller.text))
        : await showDialog<String>(context: context, builder: (_) => TecladoTextoDialog(titulo: titulo ?? 'Escribir', valorInicial: controller.text));
    if (resultado != null) controller.text = resultado;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final negocio = ref.watch(negocioStreamProvider).value;
        final activo = (negocio?.tecladoCompactoTablet ?? false) && esTabletTactil(context);
        if (!activo) return child;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _abrir(context),
          child: AbsorbPointer(child: child),
        );
      },
    );
  }
}
